# CLAUDE.md - 專案問題排除指南

## 專案概述

BrighterArc 是台灣立法院資料的自動化處理系統，每天自動：
1. 從立法院 API 抓取資料
2. 使用 OpenAI 計算 embeddings
3. 上傳到 Qdrant 向量資料庫
4. 更新 GitHub Release

## 檔案結構

```
├── fetch_legislative_data.sh    # 抓取資料 + 計算 embeddings
├── update_legislative_qdrant.sh # 上傳到 Qdrant
├── build_legislative_release.sh # 建立/更新 GitHub Release
├── query_legislative_data.sh    # 語意搜尋查詢
├── lib/
│   ├── core.sh                  # require_cmd, require_dep
│   ├── args.sh                  # parse_args, arg_required, arg_optional
│   ├── openai.sh                # openai_create_embedding
│   └── qdrant.sh                # qdrant_* 函式（含重試機制）
├── data/daily/                  # 每日 JSONL 檔案（提交到 Git）
└── .github/workflows/
    └── daily-update.yml         # 每天 UTC 18:30 自動執行
```

## 環境變數

| 變數 | 用途 | 必要性 |
|------|------|--------|
| `OPENAI_API_KEY` | OpenAI API | fetch, query |
| `QDRANT_URL` | Qdrant 伺服器 | update, query |
| `QDRANT_API_KEY` | Qdrant Cloud 認證 | update, query (Cloud) |
| `GITHUB_TOKEN` | GitHub Release | build_release (Actions 自動提供) |

## 快速診斷命令

### 檢查本地狀態
```bash
# Git 狀態
git status

# 本地資料檔案
ls -lh data/daily/*.jsonl

# 檢查腳本語法
for f in *.sh; do bash -n "$f" && echo "✅ $f"; done
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
- `build_legislative_release.sh` 已有內建重試機制（3 次，5 秒間隔）
- `lib/qdrant.sh` 已有內建重試機制

### 2. Release 檢查失敗導致資料覆蓋

**症狀**：`build_legislative_release.sh` 顯示「Release 不存在」但實際存在

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

### Release 命名規則
- Tag: `data-v202601`, `data-v202602`, ...
- 檔案: `legislative_202601.jsonl.gz`

## 關鍵函式位置

| 函式 | 檔案 | 用途 |
|------|------|------|
| `gh_release_exists` | build_legislative_release.sh:37 | 檢查 Release（含重試） |
| `gh_with_retry` | build_legislative_release.sh:75 | gh 命令重試包裝 |
| `qdrant_upsert_points_batch` | lib/qdrant.sh | 批次上傳（含重試） |
| `qdrant_get_existing_ids` | lib/qdrant.sh | 批次查詢已存在 ID |
| `openai_create_embedding` | lib/openai.sh | 產生 embedding |
| `legislative_fetch_replies` | fetch_legislative_data.sh:50 | 抓取立法院 API |

## GitHub Actions 時程

- **執行時間**：每天 UTC 18:30（台北時間 02:30）
- **時區設定**：`TZ=Asia/Taipei`（所有 date 命令使用台北時間）
- **手動觸發**：GitHub Actions 頁面 → Run workflow

## 驗證系統正常運作

```bash
# 1. 檢查最新 commit 日期
gh api repos/OWNER/REPO/commits --jq '.[0].commit.author.date'

# 2. 檢查 Release 更新日期
gh release view data-v$(date +%Y%m) --json publishedAt

# 3. 檢查 Qdrant points 數量
curl -s -H "api-key: ${QDRANT_API_KEY}" "${QDRANT_URL}/collections/legislative_replies" | jq '.result.points_count'

# 4. 測試查詢功能
./query_legislative_data.sh --query "測試" --limit 1
```
