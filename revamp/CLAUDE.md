# Revamp - 網站改版工作流程

## 概述

這是一個結構化的網站改版流程，包含 6 個階段，每個階段都有 Writer 和 Reviewer 角色確保品質。

---

## 流程總覽

```
0-Positioning → 1-Discovery → 2-Competitive → 3-Analysis → 4-Strategy → 5-Content-Spec → 執行 → Final-Review
     ↓              ↓             ↓              ↓            ↓              ↓                       ↓
  Review ✓      Review ✓      Review ✓      Review ✓     Review ✓       Review ✓                Review ✓
```

---

## 階段說明

| 階段 | 目的 | 輸出 |
|------|------|------|
| **0-positioning** | 釐清品牌定位、核心價值 | 定位文件 |
| **1-discovery** | 盤點現有內容 + 技術健檢 | 健檢報告 + KPI |
| **2-competitive** | 分析競爭對手 | 競品分析報告 |
| **3-analysis** | 受眾分析 + 內容差距 | 差距分析報告 |
| **4-strategy** | 改版計劃 + 優先級排序 | 改版計劃書 |
| **5-content-spec** | 每頁內容規格 | 內容規格書 |
| **final-review** | 驗收執行結果 | 驗收報告 |

---

## 使用方式

### 完整流程

```bash
# 依序執行各階段
請以 Writer 角色，參照 /path/to/revamp/0-positioning/CLAUDE.md 執行品牌定位分析
請以 Reviewer 角色，參照 /path/to/revamp/0-positioning/review/CLAUDE.md 檢查上述輸出

# ... 依序執行其他階段 ...

# 最後執行整合檢查
請以 Reviewer 角色，參照 /path/to/revamp/final-review/CLAUDE.md 驗收執行結果
```

### 單一階段

```bash
# 只執行特定階段
請以 Writer 角色，參照 /path/to/revamp/1-discovery/CLAUDE.md 執行網站健檢
```

---

## 自動化工具

在 `tools/` 目錄提供可直接執行的腳本（使用本地 Lighthouse，不受 API 配額限制）：

### site-audit.sh - 網站健檢

```bash
# 完整健檢
./tools/site-audit.sh https://example.com

# 只執行 Lighthouse
./tools/site-audit.sh https://example.com --lighthouse

# 只檢測安全性
./tools/site-audit.sh https://example.com --security

# 只檢測 SEO
./tools/site-audit.sh https://example.com --seo

# 輸出到檔案
./tools/site-audit.sh https://example.com --output report.json
```

**檢測項目**：
| 類別 | 工具 | 檢測內容 |
|------|------|----------|
| 效能 | Lighthouse | Performance, SEO, Accessibility, Best Practices, Core Web Vitals |
| 安全 | Mozilla Observatory | 安全評級, 測試通過數 |
| 安全 | SSL Labs | SSL 評級 |
| 安全 | HTTP Headers | HSTS, X-Frame-Options, CSP 等 |
| SEO | W3C Validator | HTML 錯誤/警告數量 |
| SEO | robots.txt / sitemap | 是否存在, URL 數量 |

### competitive-audit.sh - 競品分析

```bash
./tools/competitive-audit.sh https://our-site.com https://competitor1.com https://competitor2.com
```

**注意**：每個網站約需 30-60 秒

**輸出**：
- 比較表格（效能、SEO、Accessibility、LCP、CLS、FCP）
- JSON 格式數據

---

## 單獨指令參考

如需單獨執行某項檢測：

### PageSpeed Insights

```bash
URL="https://example.com"

# Mobile
curl -s "https://www.googleapis.com/pagespeedonline/v5/runPagespeed?url=${URL}&strategy=mobile" | jq '{
  performance: .lighthouseResult.categories.performance.score,
  lcp: .lighthouseResult.audits["largest-contentful-paint"].displayValue,
  cls: .lighthouseResult.audits["cumulative-layout-shift"].displayValue,
  tbt: .lighthouseResult.audits["total-blocking-time"].displayValue
}'
```

### Mozilla Observatory

```bash
DOMAIN="example.com"
curl -s "https://http-observatory.security.mozilla.org/api/v1/analyze?host=${DOMAIN}&rescan=true"
```

### SSL Labs

```bash
DOMAIN="example.com"
curl -s "https://api.ssllabs.com/api/v3/analyze?host=${DOMAIN}&fromCache=on" | jq '{grade: .endpoints[0].grade}'
```

### W3C HTML 驗證

```bash
URL="https://example.com"
curl -s "https://validator.w3.org/nu/?doc=${URL}&out=json" | jq '{
  errors: [.messages[] | select(.type=="error")] | length,
  warnings: [.messages[] | select(.subType=="warning")] | length
}'
```

### 壞連結檢查

```bash
# 需要 Node.js
npx broken-link-checker "https://example.com" --ordered --recursive
```

### Lighthouse 完整報告

```bash
# 需要 Node.js
npx lighthouse "https://example.com" --output json --output-path ./report.json --quiet
```

---

## 各階段輸出格式

所有階段的輸出應遵循以下原則：

1. **結構化**：使用 Markdown 表格、清單
2. **可追溯**：標註數據來源（哪個工具、哪個指令）
3. **可執行**：建議事項要具體、可操作
4. **有優先級**：重要事項標註優先級（P0/P1/P2）

---

## KPI 參考清單

| 類型 | KPI | 說明 | 測量方式 |
|------|-----|------|----------|
| **流量** | 自然搜尋流量 | 改版後 SEO 改善程度 | GA / Search Console |
| | 新訪客比例 | 觸及新用戶能力 | GA |
| **參與度** | 跳出率 | 內容符合預期程度 | GA |
| | 平均停留時間 | 內容價值 | GA |
| | 每次瀏覽頁數 | 導航/連結效果 | GA |
| **轉換** | 轉換率 | 目標行動完成率 | GA |
| | CTA 點擊率 | 行動呼籲效果 | GA / Hotjar |
| **SEO** | 關鍵字排名 | 目標關鍵字排名 | Search Console |
| | 點擊率 (CTR) | 標題/描述吸引力 | Search Console |
| **技術** | PageSpeed 分數 | 效能表現 | PageSpeed Insights |
| | Core Web Vitals | LCP/FID/CLS | PageSpeed Insights |

---

## 維護者

- 負責人：Lightman
- 適用專案：weiqi.kids 及相關專案
