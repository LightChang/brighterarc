#!/bin/bash
# generate-sitemap.sh - 從 index.json 產生完整的 sitemap.xml
# 用法: ./scripts/generate-sitemap.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
INDEX_FILE="$PROJECT_ROOT/docs/commitments/index.json"
SITEMAP_FILE="$PROJECT_ROOT/docs/sitemap.xml"
BASE_URL="https://brighterarc.weiqi.kids"

# 檢查 index.json 是否存在
if [[ ! -f "$INDEX_FILE" ]]; then
  echo "錯誤：找不到 $INDEX_FILE"
  exit 1
fi

# 取得今天日期
TODAY=$(date +%Y-%m-%d)

# 開始產生 sitemap
cat > "$SITEMAP_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>${BASE_URL}/</loc>
    <lastmod>${TODAY}</lastmod>
    <changefreq>daily</changefreq>
    <priority>1.0</priority>
  </url>
EOF

# 從 index.json 擷取所有承諾 ID 並加入 sitemap
# 使用 jq 解析 JSON（結構為 categories[].commitments[]）
if command -v jq &> /dev/null; then
  jq -r '.categories[].commitments[] | "\(.id)\t\(.last_updated // "'$TODAY'")"' "$INDEX_FILE" | while IFS=$'\t' read -r id last_updated; do
    # SPA 使用 hash-based routing
    cat >> "$SITEMAP_FILE" << EOF
  <url>
    <loc>${BASE_URL}/#${id}</loc>
    <lastmod>${last_updated}</lastmod>
    <changefreq>weekly</changefreq>
    <priority>0.8</priority>
  </url>
EOF
  done
else
  echo "警告：未安裝 jq，僅產生首頁 URL"
fi

# 結束 sitemap
cat >> "$SITEMAP_FILE" << EOF
</urlset>
EOF

# 統計
URL_COUNT=$(grep -c '<url>' "$SITEMAP_FILE")
echo "已產生 sitemap.xml，共 ${URL_COUNT} 個 URL"
