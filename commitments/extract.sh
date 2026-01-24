#!/usr/bin/env bash
# commitments/extract.sh - 從文件中萃取政策承諾
#
# 功能：
#   1. 讀取 JSONL 格式的資料
#   2. 使用 AI 識別並萃取政策承諾
#   3. 產生 Markdown 檔案到 docs/commitments/
#
# 使用方式：
#   ./commitments/extract.sh --input data/daily/2026-01-24.jsonl
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

# 輸出目錄
COMMITMENTS_DIR="${ROOT_DIR}/docs/commitments"

########################################
# 承諾萃取 Prompt
########################################

EXTRACT_SYSTEM_PROMPT='你是一個專門分析台灣政府政策文件的助理。你的任務是從行政院對立法院的答復文件中，識別並萃取具體的政策承諾。

政策承諾的定義：
- 政府明確表示將要達成的目標
- 有具體數字、時程或可衡量指標
- 承諾執行特定政策或措施

請以 JSON 格式輸出，包含以下欄位：
{
  "commitments": [
    {
      "title": "承諾標題（簡短描述，20字內）",
      "short_name": "檔名用（20字內，只能用中文、數字、連字號，例如：2025-再生能源20%）",
      "category": "分類（能源政策、環境保護、經濟發展、社會福利、教育、交通建設、醫療衛生、國防外交、其他）",
      "text": "承諾的原文摘錄（保持原文，最多200字）",
      "target_date": "目標日期（YYYY-MM-DD 格式，若只有年份則用 YYYY-12-31，若無則為 null）",
      "target_value": "目標數值（如「20%」、「5.6GW」等，若無則為 null）",
      "responsible_agency": "負責機關（若文中有提及，否則為 null）"
    }
  ]
}

注意事項：
1. 只萃取明確的承諾，不要包含模糊的願景陳述
2. 若文件中沒有找到任何承諾，回傳 {"commitments": []}
3. 每個承諾應該是獨立、具體的項目
4. short_name 用於檔名，必須簡潔且唯一'

########################################
# 函式
########################################

# 產生承諾 ID
generate_commitment_id() {
  local text="$1"
  local hash
  if command -v md5sum >/dev/null 2>&1; then
    hash="$(printf '%s' "$text" | md5sum | awk '{print $1}')"
  elif command -v md5 >/dev/null 2>&1; then
    hash="$(printf '%s' "$text" | md5)"
  fi
  printf '%s-%s-%s-%s-%s\n' \
    "${hash:0:8}" "${hash:8:4}" "${hash:12:4}" "${hash:16:4}" "${hash:20:12}"
}

# 檢查承諾是否已存在
commitment_exists() {
  local title="$1"
  local index_file="${COMMITMENTS_DIR}/index.json"

  if [[ ! -f "$index_file" ]]; then
    return 1
  fi

  jq -e --arg title "$title" '.categories[].commitments[] | select(.title == $title)' "$index_file" >/dev/null 2>&1
}

# 建立 Markdown 檔案
create_commitment_md() {
  local id="$1"
  local title="$2"
  local short_name="$3"
  local category="$4"
  local text="$5"
  local target_date="$6"
  local target_value="$7"
  local responsible_agency="$8"
  local source_info="$9"

  # 確保分類目錄存在
  local category_dir="${COMMITMENTS_DIR}/${category}"
  mkdir -p "$category_dir"

  # 檔案路徑
  local file_path="${category_dir}/${short_name}.md"

  # 如果檔案已存在，跳過
  if [[ -f "$file_path" ]]; then
    echo "   ⏭️  檔案已存在: ${file_path}"
    return 0
  fi

  local today
  today="$(date +%Y-%m-%d)"

  # 解析來源資訊
  local src_doc_id src_term src_session src_ey_number src_url
  src_doc_id="$(printf '%s' "$source_info" | jq -r '.document_id')"
  src_term="$(printf '%s' "$source_info" | jq -r '.term')"
  src_session="$(printf '%s' "$source_info" | jq -r '.session_period')"
  src_ey_number="$(printf '%s' "$source_info" | jq -r '.ey_number')"
  src_url="$(printf '%s' "$source_info" | jq -r '.url')"

  # 處理 null 值
  [[ "$target_date" == "null" || -z "$target_date" ]] && target_date="null" || target_date="\"${target_date}\""
  [[ "$target_value" == "null" || -z "$target_value" ]] && target_value="null" || target_value="\"${target_value}\""
  [[ "$responsible_agency" == "null" || -z "$responsible_agency" ]] && responsible_agency="null" || responsible_agency="\"${responsible_agency}\""

  # 產生 Markdown 內容
  cat > "$file_path" << EOF
---
id: "${id}"
title: "${title}"
category: "${category}"
status: "追蹤中"
target_date: ${target_date}
target_value: ${target_value}
responsible_agency: ${responsible_agency}
source:
  document_id: "${src_doc_id}"
  term: "${src_term}"
  session_period: "${src_session}"
  ey_number: "${src_ey_number}"
  url: "${src_url}"
created_at: "${today}"
last_updated: "${today}"
---

## 承諾原文

${text}

## 追蹤紀錄

### ${today} [初始建立]
從第${src_term}屆第${src_session}會期答復文件中萃取此承諾。
EOF

  echo "   ✅ 建立: ${file_path}"
  return 0
}

# 從單一文件萃取承諾
extract_from_document() {
  local doc_id="$1"
  local subject="$2"
  local content="$3"
  local source_info="$4"

  # 組合用於分析的文字
  local analysis_text="${subject}

${content}"

  # 截斷過長的內容
  if [[ ${#analysis_text} -gt 8000 ]]; then
    analysis_text="${analysis_text:0:8000}..."
  fi

  # 呼叫 AI
  local response
  if ! response="$(openai_chat_completion "gpt-4o-mini" "$EXTRACT_SYSTEM_PROMPT" "$analysis_text" "json" 2>&1)"; then
    echo "   ⚠️  AI 呼叫失敗: ${response}" >&2
    return 1
  fi

  # 驗證 JSON
  if ! printf '%s' "$response" | jq -e '.commitments' >/dev/null 2>&1; then
    echo "   ⚠️  回應格式錯誤" >&2
    return 1
  fi

  local count
  count="$(printf '%s' "$response" | jq '.commitments | length')"

  if [[ "$count" -eq 0 ]]; then
    echo "   ℹ️  無承諾"
    return 0
  fi

  echo "   ✅ 找到 ${count} 個承諾"

  # 處理每個承諾
  while IFS= read -r commitment; do
    local title short_name category text target_date target_value responsible_agency

    title="$(printf '%s' "$commitment" | jq -r '.title')"
    short_name="$(printf '%s' "$commitment" | jq -r '.short_name')"
    category="$(printf '%s' "$commitment" | jq -r '.category')"
    text="$(printf '%s' "$commitment" | jq -r '.text')"
    target_date="$(printf '%s' "$commitment" | jq -r '.target_date // empty')"
    target_value="$(printf '%s' "$commitment" | jq -r '.target_value // empty')"
    responsible_agency="$(printf '%s' "$commitment" | jq -r '.responsible_agency // empty')"

    # 檢查是否已存在
    if commitment_exists "$title"; then
      echo "      ⏭️  承諾已存在: ${title}"
      continue
    fi

    # 產生 ID
    local id
    id="$(generate_commitment_id "${title}${text}")"

    # 建立 Markdown
    create_commitment_md \
      "$id" "$title" "$short_name" "$category" "$text" \
      "$target_date" "$target_value" "$responsible_agency" "$source_info"

    NEW_COUNT=$((NEW_COUNT + 1))

    sleep 0.3
  done < <(printf '%s' "$response" | jq -c '.commitments[]')
}

########################################
# 主程式
########################################

require_cmd curl jq

parse_args "$@"

arg_required input INPUT_FILE "輸入 JSONL 檔案"

echo "========================================="
echo "政策承諾萃取"
echo "========================================="
echo "輸入檔案: ${INPUT_FILE}"
echo "輸出目錄: ${COMMITMENTS_DIR}"
echo "========================================="
echo ""

# 初始化
openai_init_env || {
  echo "❌ OpenAI 環境初始化失敗"
  exit 1
}

# 確保輸出目錄存在
mkdir -p "$COMMITMENTS_DIR"

# 檢查輸入檔案
if [[ ! -f "$INPUT_FILE" ]]; then
  echo "❌ 輸入檔案不存在: ${INPUT_FILE}"
  exit 1
fi

# 統計
TOTAL_DOCS=0
PROCESSED_DOCS=0
NEW_COUNT=0

# 計算文件數
TOTAL_DOCS="$(jq -s '[.[] | select(.payload.isChunked == false or .payload.chunkIndex == 0)] | length' "$INPUT_FILE")"
echo "📊 總文件數: ${TOTAL_DOCS}"
echo ""

echo "🔄 開始萃取承諾..."
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

  PROCESSED_DOCS=$((PROCESSED_DOCS + 1))
  echo "[${PROCESSED_DOCS}/${TOTAL_DOCS}] ${SUBJECT:0:50}..."

  # 準備來源資訊
  SOURCE_INFO="$(printf '%s' "$line" | jq -c '{
    document_id: .id,
    term: .payload.term,
    session_period: .payload.sessionPeriod,
    ey_number: .payload.eyNumber,
    url: .payload.docUrl
  }')"

  extract_from_document "$DOC_ID" "$SUBJECT" "$CONTENT" "$SOURCE_INFO"

  sleep 0.5
done < <(jq -c '.' "$INPUT_FILE")

echo ""
echo "========================================="
echo "萃取完成"
echo "========================================="
echo "處理文件: ${PROCESSED_DOCS} 筆"
echo "新增承諾: ${NEW_COUNT} 筆"
echo "========================================="
