# GitHub Actions 設定說明

## 步驟一：設定 GitHub Secrets

在您的 GitHub repository 中設定以下 Secrets：

1. 前往 GitHub repository 頁面
2. 點選 **Settings** > **Secrets and variables** > **Actions**
3. 點選 **New repository secret** 並新增以下 secrets：

### 必要的 Secrets

| Secret 名稱 | 說明 | 範例值 |
|------------|------|--------|
| `OPENAI_API_KEY` | OpenAI API 金鑰 | `sk-proj-...` |
| `QDRANT_URL` | Qdrant 伺服器 URL | `https://xxx.gcp.cloud.qdrant.io:6333` |
| `QDRANT_API_KEY` | Qdrant API 金鑰 | `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...` |

### 設定方式

```
Name: OPENAI_API_KEY
Secret: sk-proj-your-actual-api-key

Name: QDRANT_URL
Secret: https://82bcf1af-99ea-4460-863b-78b2e9a03d96.us-east4-0.gcp.cloud.qdrant.io:6333

Name: QDRANT_API_KEY
Secret: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhY2Nlc3MiOiJtIn0.GlOW-RIjHJr4iBqAV58MNdCJ3LS9zjrOHiwV8M1PEDo
```

## 步驟二：啟用 GitHub Actions

1. 確保您的 repository 已啟用 GitHub Actions
2. 將所有檔案 commit 並 push 到 GitHub：

```bash
git add .
git commit -m "Add legislative data update workflow"
git push origin main
```

## 步驟三：執行方式

### 自動執行（定時）

GitHub Actions 會在以下時間自動執行：
- **每天台北時間 02:30**（UTC 18:30）
- 配合立法院資料每日 02:00 更新，延後 30 分鐘抓取確保資料已更新

您可以在 `.github/workflows/update-legislative-data.yml` 中修改 cron 排程：

```yaml
schedule:
  - cron: '30 18 * * *'  # 每天台北時間 02:30
  # - cron: '0 */6 * * *'  # 每 6 小時執行一次
  # - cron: '30 6 * * *'   # 每天台北時間 14:30
```

#### Cron 時間對照表

| Cron 表達式 | UTC 時間 | 台灣時間 (UTC+8) | 說明 |
|------------|---------|-----------------|------|
| `30 18 * * *` | 18:30 | 02:30 (隔天) | **目前設定**：每天凌晨 2:30 |
| `0 22 * * *` | 22:00 | 06:00 (隔天) | 每天早上 6 點 |
| `0 6 * * *` | 06:00 | 14:00 | 每天下午 2 點 |
| `0 */6 * * *` | 每 6 小時 | 每 6 小時 | 一天 4 次 |
| `0 0,12 * * *` | 00:00, 12:00 | 08:00, 20:00 | 每天 2 次 |

**注意**：因為時區換算，台北時間 00:00-07:59 對應到前一天的 UTC 時間。

### 手動執行

1. 前往 GitHub repository 頁面
2. 點選 **Actions** 標籤
3. 選擇 **Update Legislative Data to Qdrant** workflow
4. 點選 **Run workflow** 按鈕
5. 可以選擇性輸入參數：
   - **抓取資料筆數**（預設 100）
   - **Collection 名稱**（預設 legislative_replies）

## 步驟四：監控執行狀況

### 查看執行記錄

1. 前往 **Actions** 標籤
2. 點選任一執行記錄查看詳細 log
3. 可以看到每個步驟的執行結果

### 查看執行狀態

執行成功時，您會看到：
```
✅ 環境初始化完成
✅ Collection 已存在
✅ 抓取到 XX 筆資料
🔄 開始處理資料...
✅ 寫入成功
========================================
更新完成
========================================
總共抓取: XX 筆
新增資料: XX 筆
跳過資料: XX 筆
失敗資料: 0 筆
```

### 失敗通知

如果執行失敗：
1. GitHub 會自動保存 error logs（保留 7 天）
2. 您會在 Actions 頁面看到紅色的 ❌ 標記
3. 可以下載 error logs 進行除錯

## 步驟五：初次執行建議

### 測試執行

第一次執行建議：
1. 手動觸發 workflow
2. 設定少量資料測試（例如 limit = 10）
3. 檢查 logs 確認無誤
4. 再開啟定時執行

### 測試步驟

```bash
# 1. 本地測試（可選）
export OPENAI_API_KEY="your-key"
export QDRANT_URL="your-url"
export QDRANT_API_KEY="your-key"

./update_legislative_data.sh --limit 5

# 2. Push 到 GitHub
git add .
git commit -m "Setup GitHub Actions workflow"
git push

# 3. 在 GitHub 手動執行，設定 limit = 10
```

## 常見問題

### Q: GitHub Actions 是否免費？

A:
- **Public repository**: 完全免費，無限制
- **Private repository**:
  - Free plan: 每月 2,000 分鐘
  - Pro plan: 每月 3,000 分鐘
  - 本腳本每次執行約 2-5 分鐘

### Q: 如何調整執行頻率？

A: 編輯 `.github/workflows/update-legislative-data.yml` 中的 cron 表達式

### Q: 如何停止自動執行？

A:
1. 前往 **Actions** 標籤
2. 選擇該 workflow
3. 點選右上角的 **...** > **Disable workflow**

### Q: 執行失敗怎麼辦？

A:
1. 檢查 GitHub Secrets 是否正確設定
2. 查看 Actions logs 找出錯誤訊息
3. 確認 API keys 是否有效
4. 確認 Qdrant 連線是否正常

### Q: 如何查看 Qdrant 中的資料？

A:
```bash
# 使用 curl 查詢
curl -X POST "https://your-instance.gcp.cloud.qdrant.io:6333/collections/legislative_replies/points/scroll" \
  -H "api-key: your-api-key" \
  -H "Content-Type: application/json" \
  -d '{"limit": 10}'
```

## 資源限制

### GitHub Actions 限制
- 單次執行時間上限：6 小時
- 併發執行數：20 個（Free plan）
- Artifact 儲存：500 MB（Free plan）

### 建議設定
- **limit**: 100-500 筆/次（避免執行時間過長）
- **執行頻率**: 每天 1-4 次
- **監控**: 定期檢查執行狀況

## 進階設定

### 啟用失敗通知

在 `.github/workflows/update-legislative-data.yml` 中加入：

```yaml
- name: Notify on failure
  if: failure()
  uses: actions/github-script@v7
  with:
    script: |
      github.rest.issues.create({
        owner: context.repo.owner,
        repo: context.repo.repo,
        title: 'Legislative Data Update Failed',
        body: 'Workflow failed. Check logs: ' + context.payload.repository.html_url + '/actions/runs/' + context.runId
      })
```

### 多環境設定

如果需要測試環境和生產環境：

```yaml
on:
  schedule:
    - cron: '0 6 * * *'
  workflow_dispatch:
    inputs:
      environment:
        description: '執行環境'
        required: true
        default: 'production'
        type: choice
        options:
          - production
          - staging
```

## 支援

如有問題，請參考：
- [GitHub Actions 文件](https://docs.github.com/en/actions)
- [Cron 語法說明](https://crontab.guru/)
- 專案 Issues 頁面
