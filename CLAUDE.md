# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

BrighterArc 是台灣立法院行政院答復資料的自動化處理與查詢系統。專案使用 Bash shell scripts 實作，提供完整的資料抓取、向量化、儲存與查詢功能。

### 核心功能

- **自動抓取**：從立法院開放資料平台抓取行政院答復資料
- **Embedding 計算**：使用 OpenAI text-embedding-3-small 產生 1536 維向量
- **向量儲存**：批次上傳到 Qdrant 向量資料庫
- **語意搜尋**：提供自然語言查詢功能
- **資料分發**：透過 GitHub Releases 分發預計算的 embeddings

## Architecture

### 系統架構

```
每日自動化流程（GitHub Actions，每天台北時間 2:30）:
┌─────────────────────────────────────┐
│ fetch_legislative_data.sh           │
│   - 立法院 OpenData API             │
│   - OpenAI Embeddings API           │
│   - 存入 data/daily/YYYY-MM-DD.jsonl│
└─────────────────────────────────────┘
              ↓
┌─────────────────────────────────────┐
│ update_legislative_qdrant.sh        │
│   - 讀取 JSONL 檔案                 │
│   - 批次上傳到 Qdrant               │
└─────────────────────────────────────┘
              ↓
┌─────────────────────────────────────┐
│ build_legislative_release.sh        │
│   - 合併當月所有資料                │
│   - 去重 + 壓縮                     │
│   - 更新 GitHub Release             │
└─────────────────────────────────────┘

使用者工作流程:
GitHub Release → 下載 → update_legislative_qdrant.sh → Qdrant → query_legislative_data.sh
```

### Module System

所有模組位於 `lib/` 目錄，採用 source 載入方式。每個模組都有防重複載入機制：

```bash
if [[ -n "${MODULE_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
MODULE_SH_LOADED=1
```

### Module Dependencies

```
core.sh (獨立，被所有其他模組依賴)
  ├── args.sh (獨立)
  ├── openai.sh → core.sh
  ├── legislative.sh → core.sh
  └── qdrant.sh → core.sh
```

## Core Modules

專案使用 5 個核心 lib 模組：

### lib/core.sh

核心工具函式庫，提供跨平台指令檢查與檔案驗證。

**主要函式**：

- `require_cmd <cmd>` - 檢查必要指令是否存在
  - 自動偵測作業系統（macOS/Linux）
  - 提供各發行版的安裝指引（Ubuntu, Debian, Arch, Alpine, CentOS, RHEL, Fedora）
  - 失敗時返回非零值並輸出錯誤訊息

- `require_dep <path>` - 驗證必要檔案存在
  - 支援相對路徑和絕對路徑
  - 失敗時返回非零值並輸出錯誤訊息

**使用範例**：
```bash
source "${SCRIPT_DIR}/lib/core.sh"
require_cmd curl jq || exit 1
```

### lib/args.sh

命令列參數解析模組，提供統一的參數處理介面。

**主要函式**：

- `parse_args "$@"` - 解析命令列參數
  - 支援 `--key value` 格式
  - 支援 `--key=value` 格式
  - 支援 `--flag` 布林旗標
  - 解析結果儲存為 `ARG_*` 全域變數（例如 `--limit 10` → `ARG_limit=10`）

- `arg_required <key> <var_name> <desc>` - 驗證必填參數
  - 檢查參數是否提供
  - 失敗時顯示錯誤訊息並退出
  - 將值賦值給指定變數名

- `arg_optional <key> <var_name> <default>` - 處理選填參數
  - 如果參數未提供，使用預設值
  - 將值賦值給指定變數名

**使用範例**：
```bash
source "${SCRIPT_DIR}/lib/args.sh"
parse_args "$@"
arg_required query QUERY_TEXT "查詢文字"
arg_optional limit RESULT_LIMIT "10"
```

### lib/openai.sh

OpenAI Embeddings API 整合模組。

**主要函式**：

- `openai_init_env` - 初始化 OpenAI API 環境
  - 檢查 `OPENAI_API_KEY` 環境變數
  - 驗證必要指令（curl, jq）
  - 返回 0 表示成功，非零表示失敗

- `openai_create_embedding <model> <text>` - 產生單一文字的 embedding
  - 參數 1: 模型名稱（例如 "text-embedding-3-small"）
  - 參數 2: 要嵌入的文字
  - 輸出: JSON array of floats（向量）
  - 使用 POST /v1/embeddings API

**環境變數**：
- `OPENAI_API_KEY` - OpenAI API 金鑰（必須）
- `OPENAI_BASE_URL` - API base URL（選填，預設：https://api.openai.com/v1）

**使用範例**：
```bash
source "${SCRIPT_DIR}/lib/openai.sh"
openai_init_env || exit 1
embedding="$(openai_create_embedding "text-embedding-3-small" "測試文字")"
```

### lib/legislative.sh

立法院開放資料 API 整合模組。

**主要函式**：

- `legislative_init_env` - 初始化環境
  - 設定 API base URL
  - 檢查必要指令（curl, jq）

- `legislative_fetch_replies <term> <sessionPeriod> <sessionTimes> <limit> <format>` - 抓取答復資料
  - 支援依會期篩選
  - format: "json" 或 "jsonl"
  - 返回資料包含 term, sessionPeriod, sessionTimes, eyNumber, lyNumber, subject, content, docUrl

- `legislative_fetch_latest_replies <limit> <format>` - 抓取最新 N 筆資料
  - 自動抓取所有會期的最新資料
  - 預設 limit=100

- `legislative_generate_point_id <term> <sessionPeriod> <sessionTimes> <eyNumber> <lyNumber>` - 產生唯一 UUID
  - 使用 MD5 hash 轉換為 UUID 格式
  - 格式: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

**API 端點**：https://data.ly.gov.tw/odw/ID2Action.action

**環境變數**：
- `LEGISLATIVE_API_BASE` - API base URL（選填，預設：https://data.ly.gov.tw/odw）

**使用範例**：
```bash
source "${SCRIPT_DIR}/lib/legislative.sh"
legislative_init_env || exit 1
data="$(legislative_fetch_latest_replies 100 "json")"
```

### lib/qdrant.sh

Qdrant 向量資料庫操作模組，包含完整的 CRUD 操作與網路重試機制。

**主要函式**：

- `qdrant_init_env` - 初始化 Qdrant 連接
  - 檢查 `QDRANT_URL` 環境變數
  - 檢查 `QDRANT_API_KEY`（Qdrant Cloud 需要）
  - 驗證必要指令（curl, jq）

- `qdrant_create_collection <name> <vector_size> <distance>` - 建立 collection
  - name: collection 名稱
  - vector_size: 向量維度（例如 1536）
  - distance: Cosine, Euclid, 或 Dot（預設 Cosine）

- `qdrant_collection_exists <name>` - 檢查 collection 是否存在
  - 返回 0 表示存在，1 表示不存在

- `qdrant_upsert_point <collection> <point_id> <vector_json> <payload_json>` - 插入或更新單一 point
  - 包含網路重試機制（最多 3 次，0.5 秒延遲）
  - HTTP 錯誤不重試，只重試網路錯誤

- `qdrant_upsert_points_batch <collection> <points_json>` - 批次插入或更新 points
  - points_json: JSON array，格式 `[{"id":"...","vector":[...],"payload":{...}}]`
  - 適合大量資料上傳

- `qdrant_point_exists <collection> <point_id>` - 檢查 point 是否存在
  - 包含網路重試機制
  - 返回 0 表示存在，1 表示不存在

- `qdrant_search <collection> <vector_json> <limit>` - 向量相似度搜尋
  - vector_json: query vector（JSON array）
  - limit: 回傳結果數量
  - 輸出完整 JSON 結果（包含 id, score, payload）

**環境變數**：
- `QDRANT_URL` - Qdrant 伺服器 URL（預設：http://localhost:6333）
- `QDRANT_API_KEY` - Qdrant API key（Qdrant Cloud 需要）

**使用範例**：
```bash
source "${SCRIPT_DIR}/lib/qdrant.sh"
qdrant_init_env || exit 1
qdrant_create_collection "my_collection" 1536 "Cosine"
```

## Core Scripts

專案包含 4 個核心腳本，實作完整的資料處理流程。

### fetch_legislative_data.sh

抓取立法院資料並計算 embeddings，儲存為 JSONL 格式。

**用途**：每日自動抓取最新資料，計算 embeddings，並儲存到本地。

**參數**：
```bash
--date YYYY-MM-DD      # 指定日期（預設：今天）
--limit N              # 抓取筆數（預設：100）
--output FILE          # 輸出檔案（預設：data/daily/YYYY-MM-DD.jsonl）
--model MODEL          # Embedding 模型（預設：text-embedding-3-small）
```

**輸出格式**：JSONL（每行一個 JSON 物件）
```json
{"id":"uuid","vector":[0.1,0.2,...],"payload":{"term":"10","subject":"...","content":"...",...}}
```

**特性**：
- 自動處理長文件分塊（>4000 字元）
- 分塊重疊 500 字元確保語意連貫
- 每個分塊產生獨立 UUID（基於 base_id + chunk_index）
- 避免 OpenAI API rate limit（分塊之間 sleep 0.5 秒）
- 顯示處理進度與統計資訊

**執行範例**：
```bash
./fetch_legislative_data.sh --limit 100
# 輸出: data/daily/2026-01-12.jsonl
```

**環境變數**：
- `OPENAI_API_KEY` - 必須設定

### update_legislative_qdrant.sh

讀取 JSONL 檔案並批次上傳到 Qdrant。

**用途**：將本地 JSONL 檔案（每日資料或 Release 檔案）上傳到 Qdrant。

**參數**：
```bash
--input FILE           # 輸入檔案（必填，支援 .jsonl 和 .jsonl.gz）
--collection NAME      # Collection 名稱（預設：legislative_replies）
--batch-size N         # 批次大小（預設：100）
--skip-existing        # 跳過已存在的 points（flag）
```

**特性**：
- 自動解壓縮 .gz 檔案
- 自動偵測 vector_size（從第一筆資料）
- 自動建立 collection（如不存在）
- 批次上傳提升效能
- 顯示上傳進度與統計資訊
- 支援跳過已存在的 points（避免重複計算）

**執行範例**：
```bash
# 上傳今天的資料
./update_legislative_qdrant.sh --input data/daily/2026-01-12.jsonl

# 上傳 Release 檔案
./update_legislative_qdrant.sh --input legislative_202601.jsonl.gz

# 跳過已存在的資料
./update_legislative_qdrant.sh --input data.jsonl --skip-existing
```

**環境變數**：
- `QDRANT_URL` - 必須設定
- `QDRANT_API_KEY` - Qdrant Cloud 需要

### build_legislative_release.sh

建立或更新月度 GitHub Release。

**用途**：合併每日資料，去重，壓縮，並更新 GitHub Release。

**參數**：
```bash
--input FILE           # 今日資料檔案（預設：data/daily/今天.jsonl）
--month YYYYMM         # 指定月份（預設：當前月份）
```

**Release 格式**：
- Tag: `data-v202601`, `data-v202602`, ...
- File: `legislative_202601.jsonl.gz`, `legislative_202602.jsonl.gz`, ...
- 描述: 包含統計資訊（總 points、檔案大小、最後更新時間）

**處理流程**：
1. 判斷當前月份（YYYYMM）
2. 下載現有月度 Release（如存在）
3. 解壓縮現有資料
4. 合併今天的資料
5. 去重（使用 jq：`group_by(.id) | map(max_by(.payload.updated // ""))`)
6. 壓縮（gzip）
7. 更新或建立 GitHub Release（使用 gh CLI）

**Release 策略**：
- 每月一個 Release
- 每天更新同一個月份的 Release
- 新月份開始時建立新 Release，舊月份凍結

**執行範例**：
```bash
./build_legislative_release.sh
# 自動處理當月 Release
```

**環境變數**：
- `GITHUB_TOKEN` - 必須設定（GitHub Actions 自動提供）

### query_legislative_data.sh

語意搜尋查詢工具。

**用途**：將自然語言查詢轉為 embedding，在 Qdrant 中搜尋最相似的文件。

**參數**：
```bash
--query "文字"         # 查詢文字（必填）
--limit N              # 回傳結果數（預設：10）
--collection NAME      # Collection 名稱（預設：legislative_replies）
--format text|json     # 輸出格式（預設：text）
--model MODEL          # Embedding 模型（預設：text-embedding-3-small）
```

**輸出格式**：

**text 格式**（友善閱讀）：
```
===========================================
查詢：原住民政策
相似度搜尋結果（Top 5）
===========================================

1. [相似度: 0.8921] 第 10 屆第 1 會期
   會議次數: 5
   行政院文號: 院總第1234號
   立法院文號: 委員提案第5678號

   主題: 關於原住民族土地權利保障

   內容:
   行政院茲就立法院審議...

   網址: https://lci.ly.gov.tw/...

-------------------------------------------
```

**json 格式**（機器處理）：
```json
[
  {
    "score": 0.8921,
    "id": "uuid",
    "payload": {...}
  }
]
```

**執行範例**：
```bash
# 基本查詢
./query_legislative_data.sh --query "原住民政策" --limit 5

# JSON 格式輸出（用於程式整合）
./query_legislative_data.sh --query "環境保護" --format json
```

**環境變數**：
- `OPENAI_API_KEY` - 必須設定
- `QDRANT_URL` - 必須設定
- `QDRANT_API_KEY` - Qdrant Cloud 需要

## Data Structure

### Directory Structure

```
data/
├── daily/                     # 每日資料（提交到 Git）
│   ├── .gitkeep
│   ├── 2026-01-12.jsonl
│   ├── 2026-01-13.jsonl
│   └── ...
│
└── monthly/                   # 月度累積（Git 忽略，透過 Release 分發）
    ├── .gitkeep
    └── legislative_202601.jsonl  # 本地建立，用於 Release
```

### JSONL Format

每一行是一個完整的 JSON 物件，包含 id, vector, payload：

```json
{
  "id": "abc-123-def-456",
  "vector": [0.1, 0.2, 0.3, ..., 0.9],
  "payload": {
    "term": "10",
    "sessionPeriod": "1",
    "sessionTimes": "5",
    "eyNumber": "院總第1234號",
    "lyNumber": "委員提案第5678號",
    "subject": "關於原住民族土地權利保障之質詢",
    "content": "行政院茲就立法院...",
    "docUrl": "https://lci.ly.gov.tw/...",
    "baseId": "abc-123-def-456",
    "isChunked": false,
    "chunkIndex": null,
    "totalChunks": null,
    "chunkText": "主題加上內容的完整文字"
  }
}
```

**payload 欄位說明**：
- `term`, `sessionPeriod`, `sessionTimes`: 會期資訊
- `eyNumber`, `lyNumber`: 行政院與立法院公文編號
- `subject`: 主旨
- `content`: 答復內容
- `docUrl`: 原始文件連結
- `baseId`: 原始文件的 ID（分塊時不變）
- `isChunked`: 是否為分塊文件
- `chunkIndex`: 分塊索引（0-based）
- `totalChunks`: 總分塊數
- `chunkText`: 此分塊的完整文字（主旨 + 部分內容）

### Qdrant Collection

**預設設定**：
- **Name**: `legislative_replies`
- **Vector Size**: 1536
- **Distance Metric**: Cosine
- **Index Type**: HNSW（自動）

## Environment Variables

### 必要環境變數

**OpenAI API**：
```bash
export OPENAI_API_KEY="sk-..."
```

**Qdrant**：
```bash
# 本地 Qdrant
export QDRANT_URL="http://localhost:6333"

# Qdrant Cloud
export QDRANT_URL="https://xxx.gcp.cloud.qdrant.io:6333"
export QDRANT_API_KEY="your-api-key"
```

**GitHub（僅 CI 環境）**：
```bash
export GITHUB_TOKEN="${{ secrets.GITHUB_TOKEN }}"
```

### GitHub Actions Secrets 設定

在 GitHub repository 的 Settings → Secrets and variables → Actions 新增：

1. `OPENAI_API_KEY` - OpenAI API 金鑰
2. `QDRANT_URL` - Qdrant 伺服器 URL
3. `QDRANT_API_KEY` - Qdrant API 金鑰（Cloud 版需要）

`GITHUB_TOKEN` 由 GitHub Actions 自動提供，無需手動設定。

## Usage Patterns

### 典型腳本結構

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. 載入必要模組
source "${SCRIPT_DIR}/lib/core.sh"
source "${SCRIPT_DIR}/lib/args.sh"
source "${SCRIPT_DIR}/lib/legislative.sh"

# 2. 檢查必要指令
require_cmd curl jq

# 3. 初始化環境
legislative_init_env || {
  echo "❌ 環境初始化失敗"
  exit 1
}

# 4. 解析參數
parse_args "$@"
arg_required query QUERY_TEXT "查詢文字"
arg_optional limit RESULT_LIMIT "10"

# 5. 業務邏輯
# ...
```

### 使用場景 1：維護者（每日更新）

```bash
# 設定環境變數
export OPENAI_API_KEY="sk-..."
export QDRANT_URL="https://xxx.gcp.cloud.qdrant.io:6333"
export QDRANT_API_KEY="your-key"

# 1. 抓取最新資料
./fetch_legislative_data.sh --limit 100

# 2. 上傳到 Qdrant
./update_legislative_qdrant.sh --input data/daily/$(date +%Y-%m-%d).jsonl

# 3. 建立/更新 Release
./build_legislative_release.sh
```

### 使用場景 2：使用者（下載預計算資料）

```bash
# 設定環境變數
export QDRANT_URL="http://localhost:6333"
export OPENAI_API_KEY="sk-..."

# 1. 啟動本地 Qdrant（Docker）
docker run -p 6333:6333 qdrant/qdrant

# 2. 下載 Release
gh release download data-v202601 -p "legislative_202601.jsonl.gz"

# 3. 上傳到 Qdrant
./update_legislative_qdrant.sh --input legislative_202601.jsonl.gz

# 4. 查詢
./query_legislative_data.sh --query "原住民政策" --limit 5
```

## GitHub Actions Automation

### Workflow: daily-update.yml

**位置**: `.github/workflows/daily-update.yml`

**觸發條件**：
- **定時**: 每天 UTC 18:30（台北時間 02:30）
- **手動**: workflow_dispatch

**執行步驟**：

1. **Checkout repository** - 使用 `actions/checkout@v4`
2. **Setup environment** - 安裝 jq, curl, gzip, gh CLI
3. **Fetch legislative data** - 執行 `fetch_legislative_data.sh`
4. **Update Qdrant** - 執行 `update_legislative_qdrant.sh`
5. **Build monthly release** - 執行 `build_legislative_release.sh`
6. **Commit daily data** - 提交 `data/daily/` 到 Git

**手動觸發**：
```bash
# 使用 GitHub 介面
Actions → Daily Legislative Data Update → Run workflow

# 或使用 gh CLI
gh workflow run daily-update.yml
```

**所需 Secrets**：
- `OPENAI_API_KEY`
- `QDRANT_URL`
- `QDRANT_API_KEY`

## Development Guidelines

### 腳本開發規範

1. **錯誤處理**：
   - 所有腳本使用 `set -euo pipefail`
   - 遇到錯誤立即退出，防止錯誤累積

2. **參數解析**：
   - 統一使用 `lib/args.sh`
   - 提供清楚的參數說明

3. **指令檢查**：
   - 使用 `require_cmd` 檢查必要指令
   - 失敗時提供安裝指引

4. **模組載入**：
   - 檢查 `*_SH_LOADED` 變數防止重複載入
   - 使用絕對路徑載入模組

5. **環境初始化**：
   - 呼叫 `*_init_env` 函式驗證環境
   - 失敗時退出並顯示錯誤訊息

### Git Commit 規範

GitHub Actions 產生的 commit 訊息格式：

```
Add data for YYYY-MM-DD

- Fetched and embedded legislative data
- Updated Qdrant
- Updated monthly release

Co-Authored-By: GitHub Actions <actions@github.com>
```

## Platform Compatibility

### 支援平台

- ✅ **macOS**: 完整支援，自動處理 BSD 工具差異
- ✅ **Linux**: 支援主流發行版
  - Ubuntu, Debian
  - CentOS, RHEL, Fedora
  - Arch Linux
  - Alpine Linux

### 必要指令

核心依賴（透過 `require_cmd` 自動檢查）：

- `bash` >= 4.0
- `curl` - HTTP 請求
- `jq` - JSON 處理
- `gzip` - 壓縮/解壓縮
- `gh` - GitHub CLI（用於 Release 操作）
- `date` - 時間處理
- `md5` / `md5sum` - UUID 生成

## Troubleshooting

### 常見問題

**問題：未設定 OPENAI_API_KEY**
```
❌ [openai_init_env] 未設定 OPENAI_API_KEY
```
**解決方式**：
```bash
export OPENAI_API_KEY="sk-..."
```

---

**問題：Collection 不存在**
```
❌ Collection 不存在：legislative_replies
```
**解決方式**：腳本會自動建立，無需手動處理。如果持續失敗，檢查 Qdrant 連線。

---

**問題：curl 連線失敗**
```
❌ curl 失敗 exit=7
```
**解決方式**：
```bash
# 檢查 Qdrant 是否執行
curl ${QDRANT_URL}/collections

# 檢查網路連線
ping -c 3 api.openai.com
```

---

**問題：GitHub Release 權限不足**
```
HTTP 403: Resource not accessible by integration
```
**解決方式**：
- 確認 workflow 有 `contents: write` 權限
- 確認 workflow 有 `releases: write` 權限
- 檢查 `GITHUB_TOKEN` 設定

### 偵錯技巧

**啟用詳細輸出**：
```bash
bash -x ./fetch_legislative_data.sh --limit 10
```

**檢查 Qdrant 狀態**：
```bash
curl -H "api-key: ${QDRANT_API_KEY}" \
  ${QDRANT_URL}/collections/legislative_replies
```

**驗證 JSONL 格式**：
```bash
head -n 1 data/daily/2026-01-12.jsonl | jq .
```

**測試 OpenAI API**：
```bash
curl https://api.openai.com/v1/models \
  -H "Authorization: Bearer ${OPENAI_API_KEY}"
```

## Related Documentation

- `README.md` - 專案概覽、快速開始、Release 策略
- `USAGE.md` - 完整使用指南、參數說明、進階使用
- `.github/workflows/daily-update.yml` - 自動化工作流定義
