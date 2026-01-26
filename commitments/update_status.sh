#!/usr/bin/env bash
# commitments/update_status.sh - 更新承諾狀態
#
# 功能：
#   1. 讀取新文件，比對現有承諾
#   2. 找到相關文件時，追加追蹤紀錄
#   3. 檢查日期，更新已延宕/無更新狀態
#
# 使用方式：
#   ./commitments/update_status.sh --input data/daily/2026-01-24.jsonl
#
# 環境變數：
#   OPENAI_API_KEY: OpenAI API key

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 載入模組
source "${ROOT_DIR}/lib/core.sh"
source "${ROOT_DIR}/lib/args.sh"
source "${ROOT_DIR}/lib/openai.sh"

# 目錄
COMMITMENTS_DIR="${ROOT_DIR}/docs/commitments"
INDEX_FILE="${COMMITMENTS_DIR}/index.json"

########################################
# AI Prompts
########################################

SCREENING_SYSTEM_PROMPT='你是一個政策分析助理。給定一份新的政府文件和一份承諾清單，請判斷這份文件可能與哪些承諾相關。

回傳 JSON 格式：
{
  "related_ids": ["id1", "id2", ...]
}

如果都不相關，回傳：
{
  "related_ids": []
}

只回傳可能相關的承諾 ID，不要過度匹配。'

VERIFY_SYSTEM_PROMPT='你是一個政策分析助理。請判斷這份新文件是否與指定的承諾相關。

如果相關，請分析：
1. 這是進度更新、達成證據、還是其他相關資訊？
2. 如果是達成證據，承諾是否已完全達成？

回傳 JSON 格式：
{
  "is_related": true/false,
  "relation_type": "進度更新" | "達成證據" | "相關資訊" | null,
  "summary": "簡短摘要（50字內）",
  "is_fulfilled": true/false,
  "confidence": "high" | "medium" | "low"
}

如果不相關：
{
  "is_related": false,
  "relation_type": null,
  "summary": null,
  "is_fulfilled": false,
  "confidence": null
}'

########################################
# 函式
########################################

# 取得所有承諾清單（id + title）
get_commitment_list() {
  if [[ ! -f "$INDEX_FILE" ]]; then
    echo "[]"
    return
  fi

  jq -c '[.categories[].commitments[] | {id: .id, title: .title, file: .file}]' "$INDEX_FILE"
}

# 初步篩選：找出可能相關的承諾
screen_related_commitments() {
  local doc_content="$1"
  local commitment_list="$2"

  # 組合 prompt
  local user_message="## 新文件內容
${doc_content}

## 承諾清單
$(printf '%s' "$commitment_list" | jq -r '.[] | "- [\(.id)] \(.title)"')"

  local response
  if ! response="$(openai_chat_completion "gpt-4o-mini" "$SCREENING_SYSTEM_PROMPT" "$user_message" "json" 2>&1)"; then
    echo "[]"
    return 1
  fi

  printf '%s' "$response" | jq -c '.related_ids // []'
}

# 精確驗證：確認關聯並取得詳細資訊
verify_relationship() {
  local doc_content="$1"
  local commitment_content="$2"

  local user_message="## 新文件內容
${doc_content}

## 承諾內容
${commitment_content}"

  local response
  if ! response="$(openai_chat_completion "gpt-4o-mini" "$VERIFY_SYSTEM_PROMPT" "$user_message" "json" 2>&1)"; then
    echo '{"is_related": false}'
    return 1
  fi

  printf '%s' "$response"
}

# 讀取 Markdown 檔案內容（不含 frontmatter）
read_md_content() {
  local file_path="$1"
  # 跳過 frontmatter (--- ... ---)
  sed -n '/^---$/,/^---$/!p' "$file_path" | tail -n +2
}

# 讀取 Markdown frontmatter
read_md_frontmatter() {
  local file_path="$1"
  sed -n '/^---$/,/^---$/p' "$file_path" | tail -n +2 | head -n -1
}

# 追加追蹤紀錄到 Markdown
append_tracking_record() {
  local file_path="$1"
  local relation_type="$2"
  local summary="$3"
  local source_info="$4"
  local is_fulfilled="$5"

  local today
  today="$(date +%Y-%m-%d)"

  local src_term src_session src_ey_number src_url
  src_term="$(printf '%s' "$source_info" | jq -r '.term')"
  src_session="$(printf '%s' "$source_info" | jq -r '.session_period')"
  src_ey_number="$(printf '%s' "$source_info" | jq -r '.ey_number')"
  src_url="$(printf '%s' "$source_info" | jq -r '.url')"

  # 決定紀錄類型
  local record_type="進度更新"
  if [[ "$is_fulfilled" == "true" ]]; then
    record_type="狀態變更"
  fi

  # 追加內容
  cat >> "$file_path" << EOF

### ${today} [${record_type}]
**來源類型**：立法院答復
**文件編號**：${src_ey_number}
**來源連結**：${src_url}
**內容摘要**：${summary}
**AI 判斷**：${relation_type}
EOF

  # 如果達成，更新 frontmatter 中的 status
  if [[ "$is_fulfilled" == "true" ]]; then
    # 更新 status 和 last_updated
    sed -i "s/^status: .*/status: \"已達成\"/" "$file_path"
    sed -i "s/^last_updated: .*/last_updated: \"${today}\"/" "$file_path"
    echo "      🎉 狀態變更為「已達成」"
  else
    # 只更新 last_updated
    sed -i "s/^last_updated: .*/last_updated: \"${today}\"/" "$file_path"
  fi
}

# 檢查並更新延宕/無更新狀態
check_date_status() {
  local today
  today="$(date +%Y-%m-%d)"

  local six_months_ago
  if date -v-6m "+%Y-%m-%d" >/dev/null 2>&1; then
    six_months_ago="$(date -v-6m "+%Y-%m-%d")"
  else
    six_months_ago="$(date -d "-6 months" "+%Y-%m-%d")"
  fi

  echo "🔍 檢查日期狀態..."

  find "$COMMITMENTS_DIR" -name "*.md" -type f | while read -r file; do
    local status target_date last_updated

    # 讀取 frontmatter
    status="$(grep "^status:" "$file" | sed 's/status: *"\?\([^"]*\)"\?/\1/')"
    target_date="$(grep "^target_date:" "$file" | sed 's/target_date: *"\?\([^"]*\)"\?/\1/')"
    last_updated="$(grep "^last_updated:" "$file" | sed 's/last_updated: *"\?\([^"]*\)"\?/\1/')"

    # 跳過已達成的
    if [[ "$status" == "已達成" ]]; then
      continue
    fi

    local need_update=false
    local new_status=""

    # 檢查是否已延宕
    if [[ -n "$target_date" && "$target_date" != "null" && "$target_date" < "$today" ]]; then
      if [[ "$status" != "已延宕" ]]; then
        new_status="已延宕"
        need_update=true
      fi
    # 檢查是否無更新
    elif [[ -n "$last_updated" && "$last_updated" < "$six_months_ago" ]]; then
      if [[ "$status" != "無更新" ]]; then
        new_status="無更新"
        need_update=true
      fi
    fi

    if [[ "$need_update" == "true" ]]; then
      sed -i "s/^status: .*/status: \"${new_status}\"/" "$file"
      sed -i "s/^last_updated: .*/last_updated: \"${today}\"/" "$file"
      echo "   📝 $(basename "$file"): 狀態變更為「${new_status}」"

      # 追加紀錄
      cat >> "$file" << EOF

### ${today} [狀態變更]
**狀態**：${status} → ${new_status}
**原因**：$(if [[ "$new_status" == "已延宕" ]]; then echo "目標日期已過"; else echo "超過6個月無更新"; fi)
EOF
    fi
  done
}

########################################
# 主程式
########################################

require_cmd curl jq

parse_args "$@"

arg_required input INPUT_FILE "輸入 JSONL 檔案"

echo "========================================="
echo "承諾狀態更新"
echo "========================================="
echo "輸入檔案: ${INPUT_FILE}"
echo "承諾目錄: ${COMMITMENTS_DIR}"
echo "========================================="
echo ""

# 初始化
openai_init_env || {
  echo "❌ OpenAI 環境初始化失敗"
  exit 1
}

# 檢查輸入
if [[ ! -f "$INPUT_FILE" ]]; then
  echo "❌ 輸入檔案不存在: ${INPUT_FILE}"
  exit 1
fi

if [[ ! -f "$INDEX_FILE" ]]; then
  echo "ℹ️  index.json 不存在，跳過狀態更新"
  echo "   請先執行 build_index.sh"
  exit 0
fi

# 取得承諾清單
COMMITMENT_LIST="$(get_commitment_list)"
COMMITMENT_COUNT="$(printf '%s' "$COMMITMENT_LIST" | jq 'length')"

if [[ "$COMMITMENT_COUNT" -eq 0 ]]; then
  echo "ℹ️  沒有現有承諾，跳過比對"
  exit 0
fi

echo "📋 現有承諾數: ${COMMITMENT_COUNT}"
echo ""

# 統計
TOTAL_DOCS=0
MATCHED_DOCS=0
UPDATED_COMMITMENTS=0

# 處理每份新文件
echo "🔄 開始比對新文件..."
echo ""

while IFS= read -r line; do
  DOC_ID="$(printf '%s' "$line" | jq -r '.id')"
  SUBJECT="$(printf '%s' "$line" | jq -r '.payload.subject // ""')"
  CONTENT="$(printf '%s' "$line" | jq -r '.payload.content // ""')"
  IS_CHUNKED="$(printf '%s' "$line" | jq -r '.payload.isChunked')"
  CHUNK_INDEX="$(printf '%s' "$line" | jq -r '.payload.chunkIndex // 0')"

  # 跳過非首個 chunk
  if [[ "$IS_CHUNKED" == "true" && "$CHUNK_INDEX" != "0" ]]; then
    continue
  fi

  TOTAL_DOCS=$((TOTAL_DOCS + 1))
  echo "[${TOTAL_DOCS}] ${SUBJECT:0:50}..."

  # 準備來源資訊
  SOURCE_INFO="$(printf '%s' "$line" | jq -c '{
    document_id: .id,
    term: .payload.term,
    session_period: .payload.sessionPeriod,
    ey_number: .payload.eyNumber,
    url: .payload.docUrl
  }')"

  # 組合文件內容
  DOC_CONTENT="${SUBJECT}

${CONTENT:0:4000}"

  # Step 1: 初步篩選
  RELATED_IDS="$(screen_related_commitments "$DOC_CONTENT" "$COMMITMENT_LIST")"
  RELATED_COUNT="$(printf '%s' "$RELATED_IDS" | jq 'length')"

  if [[ "$RELATED_COUNT" -eq 0 ]]; then
    echo "   ℹ️  無相關承諾"
    continue
  fi

  echo "   🔍 可能相關: ${RELATED_COUNT} 個承諾"
  MATCHED_DOCS=$((MATCHED_DOCS + 1))

  # Step 2: 精確驗證每個候選
  for id in $(printf '%s' "$RELATED_IDS" | jq -r '.[]'); do
    # 找到對應的檔案
    FILE_PATH="$(printf '%s' "$COMMITMENT_LIST" | jq -r --arg id "$id" '.[] | select(.id == $id) | .file')"

    if [[ -z "$FILE_PATH" || ! -f "${COMMITMENTS_DIR}/${FILE_PATH}" ]]; then
      echo "      ⚠️  找不到檔案: ${id}"
      continue
    fi

    FULL_PATH="${COMMITMENTS_DIR}/${FILE_PATH}"
    COMMITMENT_CONTENT="$(read_md_content "$FULL_PATH")"

    # 驗證
    VERIFY_RESULT="$(verify_relationship "$DOC_CONTENT" "$COMMITMENT_CONTENT")"
    IS_RELATED="$(printf '%s' "$VERIFY_RESULT" | jq -r '.is_related')"

    if [[ "$IS_RELATED" != "true" ]]; then
      echo "      ❌ ${id}: 驗證後不相關"
      continue
    fi

    RELATION_TYPE="$(printf '%s' "$VERIFY_RESULT" | jq -r '.relation_type')"
    SUMMARY="$(printf '%s' "$VERIFY_RESULT" | jq -r '.summary')"
    IS_FULFILLED="$(printf '%s' "$VERIFY_RESULT" | jq -r '.is_fulfilled')"

    echo "      ✅ ${id}: ${RELATION_TYPE}"

    # 追加紀錄
    append_tracking_record "$FULL_PATH" "$RELATION_TYPE" "$SUMMARY" "$SOURCE_INFO" "$IS_FULFILLED"
    UPDATED_COMMITMENTS=$((UPDATED_COMMITMENTS + 1))

    sleep 0.3
  done

  sleep 0.5
done < <(jq -c '.' "$INPUT_FILE")

echo ""

# Step 3: 檢查日期狀態
check_date_status

echo ""
echo "========================================="
echo "狀態更新完成"
echo "========================================="
echo "處理文件: ${TOTAL_DOCS} 筆"
echo "有相關的: ${MATCHED_DOCS} 筆"
echo "更新承諾: ${UPDATED_COMMITMENTS} 筆"
echo "========================================="
