# CLAUDE.md - 專案問題排除指南

## 專案概述

BrighterArc 是台灣立法院資料的自動化處理系統，每天自動：
1. 從立法院 API 抓取資料
2. 使用 OpenAI 計算 embeddings
3. 上傳到 Qdrant 向量資料庫
4. 更新 GitHub Release
5. 萃取政策承諾並追蹤狀態
6. 產生承諾索引與前端頁面

## 檔案結構

```
├── sources/legislative/             # 立法院資料管線
│   ├── fetch.sh                     # 抓取資料 + 計算 embeddings
│   ├── update_qdrant.sh             # 上傳到 Qdrant
│   ├── build_release.sh             # 建立/更新 GitHub Release
│   ├── query.sh                     # 語意搜尋查詢
│   └── init_commitments.sh          # 一次性初始化：掃描歷史資料萃取承諾
├── commitments/                     # 承諾識別引擎
│   ├── extract.sh                   # 使用 gpt-4o-mini 從 JSONL 萃取承諾
│   ├── update_status.sh             # 反向比對 + 兩階段 AI 驗證
│   └── build_index.sh               # 掃描 .md 產生 index.json
├── lib/
│   ├── core.sh                      # require_cmd, require_dep
│   ├── args.sh                      # parse_args, arg_required, arg_optional
│   ├── openai.sh                    # openai_create_embedding, openai_chat_completion
│   └── qdrant.sh                    # qdrant_* 函式（含重試機制）
├── docs/
│   ├── index.html                   # GitHub Pages SPA（承諾追蹤前端）
│   └── commitments/                 # 承諾 Markdown 檔案（按分類）
│       ├── {category}/{short_name}.md
│       └── index.json               # 自動產生的索引
├── data/
│   ├── daily/                       # 每日 JSONL 檔案（提交到 Git）
│   ├── monthly/                     # 月度彙整
│   └── commitments/                 # 承諾處理用暫存
└── .github/workflows/
    └── daily-update.yml             # 每天 UTC 18:30 自動執行
```

## 環境變數

| 變數 | 用途 | 必要性 |
|------|------|--------|
| `OPENAI_API_KEY` | OpenAI API | fetch, query, extract, update_status |
| `QDRANT_URL` | Qdrant 伺服器 | update_qdrant, query |
| `QDRANT_API_KEY` | Qdrant Cloud 認證 | update_qdrant, query (Cloud) |
| `GITHUB_TOKEN` | GitHub Release | build_release (Actions 自動提供) |

## 快速診斷命令

### 檢查本地狀態
```bash
# Git 狀態
git status

# 本地資料檔案
ls -lh data/daily/*.jsonl

# 檢查腳本語法
for f in sources/legislative/*.sh commitments/*.sh; do bash -n "$f" && echo "OK $f"; done
```

### 檢查遠端狀態
```bash
# GitHub Release
gh release view data-v$(date +%Y%m) --json assets

# Qdrant collection
curl -H "api-key: ${QDRANT_API_KEY}" "${QDRANT_URL}/collections/legislative_replies" | jq '.result.points_count'

# 最近 commits
gh api repos/OWNER/REPO/commits --jq '.[0:3] | .[] | "\(.sha[0:7]) \(.commit.message | split("\n")[0])"'
```

### 檢查 GitHub Actions
```bash
# 最近執行紀錄
gh run list --limit 5

# 查看特定執行的 log
gh run view <run-id> --log
```

## 常見問題排除

### 1. 網路超時錯誤

**症狀**：`curl exit=7` 或 `dial tcp ... i/o timeout`

**原因**：GitHub/Qdrant/OpenAI API 連線超時

**解決**：
- 重試命令
- `sources/legislative/build_release.sh` 已有內建重試機制（3 次，5 秒間隔）
- `lib/qdrant.sh` 已有內建重試機制
- `lib/openai.sh` chat completion 有指數退避重試（2→4→8s）

### 2. Release 檢查失敗導致資料覆蓋

**症狀**：`build_release.sh` 顯示「Release 不存在」但實際存在

**原因**：網路問題導致 `gh release view` 失敗

**解決**：已修復，腳本現在會在網路錯誤時終止而非覆蓋

**手動修復已覆蓋的資料**：
```bash
# 合併所有每日檔案
cat data/daily/2026-01-*.jsonl | jq -s 'flatten | group_by(.id) | map(.[-1]) | .[]' -c > /tmp/merged.jsonl

# 壓縮並上傳
gzip -c /tmp/merged.jsonl > /tmp/legislative_202601.jsonl.gz
gh release upload data-v202601 /tmp/legislative_202601.jsonl.gz --clobber
```

### 3. GitHub Actions 檔案找不到

**症狀**：`資料抓取失敗：檔案不存在`

**可能原因**：
- API 沒有返回資料
- 時區問題（已修復：workflow 使用 `TZ=Asia/Taipei`）

**檢查**：
```bash
# 檢查 API 是否有資料
curl "https://data.ly.gov.tw/odw/ID2Action.action?term=11&sessionPeriod=1&sessionTimes=1&fileType=json" | jq '.dataList | length'
```

### 4. Qdrant 上傳失敗

**症狀**：`HTTP 4xx/5xx` 錯誤

**檢查步驟**：
```bash
# 1. 檢查連線
curl -H "api-key: ${QDRANT_API_KEY}" "${QDRANT_URL}/collections"

# 2. 檢查 collection 是否存在
curl -H "api-key: ${QDRANT_API_KEY}" "${QDRANT_URL}/collections/legislative_replies"

# 3. 檢查 points 格式
head -1 data/daily/2026-01-14.jsonl | jq '.id, (.vector | length), .payload.subject'
```

### 5. OpenAI Embedding 失敗

**症狀**：`openai_create_embedding` 返回錯誤

**檢查**：
```bash
# 驗證 API key
curl https://api.openai.com/v1/models -H "Authorization: Bearer ${OPENAI_API_KEY}" | jq '.data[0].id'
```

### 6. Git Push 被拒絕

**症狀**：`rejected - fetch first`

**原因**：遠端有新 commit（通常來自 Actions）

**解決**：
```bash
git pull --rebase origin main
git push origin main
```

### 7. 承諾萃取無結果

**症狀**：`extract.sh` 執行完畢但 `docs/commitments/` 沒有新檔案

**可能原因**：
- 文件中沒有具體的政策承諾（AI 判斷為模糊願景陳述）
- 承諾已存在（以 title 去重）
- OpenAI API 呼叫失敗

**檢查**：
```bash
# 查看已有多少承諾
find docs/commitments -name "*.md" | wc -l

# 查看 index.json
jq '.total_count, .status_summary' docs/commitments/index.json
```

### 8. 承諾狀態更新跳過

**症狀**：`update_status.sh` 顯示「無相關承諾」

**原因**：正常現象，不是每份文件都與現有承諾相關

## 資料格式

### JSONL Point 格式
```json
{
  "id": "uuid-string",
  "vector": [0.1, 0.2, ...],  // 1536 維
  "payload": {
    "term": "11",
    "sessionPeriod": "1",
    "sessionTimes": "1",
    "eyNumber": "院總第...",
    "lyNumber": "委員提案...",
    "subject": "主旨文字",
    "content": "答復內容",
    "docUrl": "https://...",
    "baseId": "原始文件 UUID",
    "isChunked": false,
    "chunkIndex": null,
    "totalChunks": null
  }
}
```

### 承諾 Markdown 格式
```yaml
---
id: "uuid"
title: "承諾標題"
category: "分類名稱"
status: "追蹤中"  # 追蹤中 | 已達成 | 已延宕 | 無更新
target_date: "YYYY-MM-DD" or null
target_value: "20%" or null
responsible_agency: "機關名稱" or null
source:
  document_id: "uuid"
  term: "11"
  session_period: "1"
  ey_number: "院總第..."
  url: "https://..."
created_at: "YYYY-MM-DD"
last_updated: "YYYY-MM-DD"
---

## 承諾原文
[原文摘錄]

## 追蹤紀錄
### YYYY-MM-DD [初始建立]
...
### YYYY-MM-DD [進度更新]
**來源類型**：立法院答復
**文件編號**：...
**來源連結**：...
**內容摘要**：...
**AI 判斷**：進度更新|達成證據|相關資訊
```

### Release 命名規則
- Tag: `data-v202601`, `data-v202602`, ...
- 檔案: `legislative_202601.jsonl.gz`

## 關鍵函式位置

| 函式 | 檔案 | 用途 |
|------|------|------|
| `gh_release_exists` | sources/legislative/build_release.sh:45 | 檢查 Release（含重試） |
| `gh_with_retry` | sources/legislative/build_release.sh:85 | gh 命令重試包裝 |
| `qdrant_upsert_points_batch` | lib/qdrant.sh | 批次上傳（含重試） |
| `qdrant_get_existing_ids` | lib/qdrant.sh | 批次查詢已存在 ID |
| `openai_create_embedding` | lib/openai.sh:67 | 產生 embedding |
| `openai_chat_completion` | lib/openai.sh:241 | Chat completion（JSON mode, 指數退避） |
| `legislative_fetch_replies` | sources/legislative/fetch.sh:51 | 抓取立法院 API |
| `extract_from_document` | commitments/extract.sh:165 | AI 萃取承諾 |
| `screen_related_commitments` | commitments/update_status.sh:86 | 初篩相關承諾 |
| `verify_relationship` | commitments/update_status.sh:107 | 精確驗證關聯 |
| `check_date_status` | commitments/update_status.sh:186 | 自動更新延宕/無更新狀態 |
| `parse_frontmatter` | commitments/build_index.sh:29 | 解析 YAML frontmatter |

## GitHub Actions 時程

- **執行時間**：每天 UTC 18:30（台北時間 02:30）
- **時區設定**：`TZ=Asia/Taipei`（所有 date 命令使用台北時間）
- **手動觸發**：GitHub Actions 頁面 → Run workflow

### 每日管線步驟
1. 抓取立法院資料 + 計算 embeddings
2. 上傳到 Qdrant + 驗證
3. 更新月度 GitHub Release
4. Commit 每日資料
5. 萃取新承諾（extract.sh）
6. 更新承諾狀態（update_status.sh）
7. 產生承諾索引（build_index.sh）
8. Commit 承諾變更

## 承諾追蹤系統

### 承諾狀態生命週期
- **追蹤中**：初始狀態，持續監控
- **已達成**：AI 驗證有達成證據
- **已延宕**：目標日期已過但未達成
- **無更新**：超過 6 個月沒有相關文件

### 兩階段 AI 驗證
1. **初篩**（screen_related_commitments）：快速判斷新文件可能與哪些承諾相關
2. **精確驗證**（verify_relationship）：讀取承諾 .md 內容，深度分析關聯類型

### 承諾分類
能源政策、環境保護、經濟發展、社會福利、教育、交通建設、醫療衛生、國防外交、其他

### 初始化歷史資料
```bash
# 掃描所有現有 JSONL 檔案萃取承諾（需要 OPENAI_API_KEY）
./sources/legislative/init_commitments.sh [--limit N]
```

## 驗證系統正常運作

```bash
# 1. 檢查最新 commit 日期
gh api repos/OWNER/REPO/commits --jq '.[0].commit.author.date'

# 2. 檢查 Release 更新日期
gh release view data-v$(date +%Y%m) --json publishedAt

# 3. 檢查 Qdrant points 數量
curl -s -H "api-key: ${QDRANT_API_KEY}" "${QDRANT_URL}/collections/legislative_replies" | jq '.result.points_count'

# 4. 測試查詢功能
./sources/legislative/query.sh --query "測試" --limit 1

# 5. 檢查承諾索引
jq '.total_count, .status_summary' docs/commitments/index.json
```
