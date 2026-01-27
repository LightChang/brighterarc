#!/usr/bin/env bash
# commitments/build_index.sh - 產生 index.json
#
# 功能：
#   1. 掃描 docs/commitments/ 下所有 .md 檔案
#   2. 讀取每個檔案的 frontmatter
#   3. 產生 index.json
#
# 使用方式：
#   ./commitments/build_index.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 載入模組
source "${ROOT_DIR}/lib/core.sh"

# 目錄
COMMITMENTS_DIR="${ROOT_DIR}/docs/commitments"
INDEX_FILE="${COMMITMENTS_DIR}/index.json"

########################################
# 函式
########################################

# 解析 YAML frontmatter
parse_frontmatter() {
  local file="$1"
  local key="$2"

  # 提取 frontmatter 區塊並找到指定 key，移除 key: 前綴和引號
  sed -n '/^---$/,/^---$/p' "$file" | grep "^${key}:" | head -1 | sed 's/^[^:]*: *//; s/"//g'
}

########################################
# 主程式
########################################

require_cmd jq

echo "========================================="
echo "產生承諾索引"
echo "========================================="
echo "掃描目錄: ${COMMITMENTS_DIR}"
echo "輸出檔案: ${INDEX_FILE}"
echo "========================================="
echo ""

# 確保目錄存在
mkdir -p "$COMMITMENTS_DIR"

# 使用臨時檔案來收集所有承諾資料（避免 bash 3.x 關聯陣列問題）
TEMP_COMMITMENTS="/tmp/build_index_commitments_$$.json"
echo "[]" > "$TEMP_COMMITMENTS"

# 開始建立 JSON
CATEGORIES_JSON="[]"
TOTAL_COUNT=0

# 掃描所有分類目錄
for category_dir in "$COMMITMENTS_DIR"/*/; do
  # 跳過非目錄
  [[ ! -d "$category_dir" ]] && continue

  category_name="$(basename "$category_dir")"
  echo "📁 ${category_name}"

  COMMITMENTS_JSON="[]"

  # 掃描該分類下的所有 .md 檔案
  for md_file in "$category_dir"*.md; do
    # 跳過不存在的檔案（glob 沒匹配時）
    [[ ! -f "$md_file" ]] && continue

    # 解析 frontmatter
    id="$(parse_frontmatter "$md_file" "id")"
    title="$(parse_frontmatter "$md_file" "title")"
    status="$(parse_frontmatter "$md_file" "status")"
    target_date="$(parse_frontmatter "$md_file" "target_date")"
    target_value="$(parse_frontmatter "$md_file" "target_value")"
    last_updated="$(parse_frontmatter "$md_file" "last_updated")"

    # 計算相對路徑
    relative_path="${category_name}/$(basename "$md_file")"

    echo "   📄 $(basename "$md_file")"

    # 建立承諾 JSON
    commitment_json="$(jq -n \
      --arg id "$id" \
      --arg title "$title" \
      --arg file "$relative_path" \
      --arg status "$status" \
      --arg target_date "$target_date" \
      --arg target_value "$target_value" \
      --arg last_updated "$last_updated" \
      '{
        id: $id,
        title: $title,
        file: $file,
        status: $status,
        target_date: (if $target_date == "null" or $target_date == "" then null else $target_date end),
        target_value: (if $target_value == "null" or $target_value == "" then null else $target_value end),
        last_updated: $last_updated
      }'
    )"

    # 加入陣列
    COMMITMENTS_JSON="$(printf '%s' "$COMMITMENTS_JSON" | jq --argjson c "$commitment_json" '. + [$c]')"

    # 收集到臨時檔案（用於後續統計）
    jq --argjson c "$commitment_json" '. + [$c]' "$TEMP_COMMITMENTS" > "${TEMP_COMMITMENTS}.tmp"
    mv "${TEMP_COMMITMENTS}.tmp" "$TEMP_COMMITMENTS"

    # 統計
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
  done

  # 計算該分類的承諾數
  category_count="$(printf '%s' "$COMMITMENTS_JSON" | jq 'length')"

  # 建立分類 JSON
  category_json="$(jq -n \
    --arg name "$category_name" \
    --argjson count "$category_count" \
    --argjson commitments "$COMMITMENTS_JSON" \
    '{
      name: $name,
      count: $count,
      commitments: $commitments
    }'
  )"

  # 加入分類陣列
  CATEGORIES_JSON="$(printf '%s' "$CATEGORIES_JSON" | jq --argjson c "$category_json" '. + [$c]')"
done

# 使用 jq 從所有承諾資料中計算狀態統計
STATUS_SUMMARY="$(jq '
  group_by(.status) |
  map({key: .[0].status, value: length}) |
  from_entries |
  {
    "追蹤中": (.["追蹤中"] // 0),
    "已達成": (.["已達成"] // 0),
    "已延宕": (.["已延宕"] // 0),
    "無更新": (.["無更新"] // 0)
  }
' "$TEMP_COMMITMENTS")"

# 清理臨時檔案
rm -f "$TEMP_COMMITMENTS"

# 產生最終 JSON
GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

FINAL_JSON="$(jq -n \
  --arg generated_at "$GENERATED_AT" \
  --argjson total "$TOTAL_COUNT" \
  --argjson status_summary "$STATUS_SUMMARY" \
  --argjson categories "$CATEGORIES_JSON" \
  '{
    generated_at: $generated_at,
    total_count: $total,
    status_summary: $status_summary,
    categories: $categories
  }'
)"

# 寫入檔案
printf '%s\n' "$FINAL_JSON" > "$INDEX_FILE"

echo ""
echo "========================================="
echo "索引產生完成"
echo "========================================="
echo "總承諾數: ${TOTAL_COUNT}"
echo "分類數: $(printf '%s' "$CATEGORIES_JSON" | jq 'length')"
echo ""
echo "狀態統計："
echo "  追蹤中: $(printf '%s' "$STATUS_SUMMARY" | jq '.["追蹤中"]')"
echo "  已達成: $(printf '%s' "$STATUS_SUMMARY" | jq '.["已達成"]')"
echo "  已延宕: $(printf '%s' "$STATUS_SUMMARY" | jq '.["已延宕"]')"
echo "  無更新: $(printf '%s' "$STATUS_SUMMARY" | jq '.["無更新"]')"
echo ""
echo "輸出檔案: ${INDEX_FILE}"
echo "========================================="
