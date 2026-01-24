#!/usr/bin/env bash
# extract_commitments.sh - 從立法院答復資料中萃取政策承諾
#
# 功能：
#   1. 讀取 JSONL 格式的立法院答復資料
#   2. 使用 OpenAI 識別並萃取政策承諾
#   3. 輸出結構化的承諾資料
#
# 使用方式：
#   ./extract_commitments.sh --input data/daily/2026-01-24.jsonl [--output commitments.jsonl]
#
# 環境變數：
#   OPENAI_API_KEY: OpenAI API key

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 載入模組
source "${SCRIPT_DIR}/lib/core.sh"
source "${SCRIPT_DIR}/lib/args.sh"
source "${SCRIPT_DIR}/lib/openai.sh"

########################################
# 承諾萃取 Prompt
########################################

COMMITMENT_SYSTEM_PROMPT='你是一個專門分析台灣政府政策文件的助理。你的任務是從行政院對立法院的答復文件中，識別並萃取具體的政策承諾。

政策承諾的定義：
- 政府明確表示將要達成的目標
- 有具體數字、時程或可衡量指標
- 承諾執行特定政策或措施

請以 JSON 格式輸出，包含以下欄位：
{
  "commitments": [
    {
      "text": "承諾的原文摘錄（保持原文，但可簡化冗長部分）",
      "target_date": "目標日期（YYYY-MM-DD 格式，若只有年份則用 YYYY-12-31，若無則為 null）",
      "target_value": "目標數值（如「20%」、「5.6GW」等，若無則為 null）",
      "category": "分類（如：能源政策、環境保護、經濟發展、社會福利、教育、交通建設、醫療衛生、國防外交、其他）",
      "responsible_agency": "負責機關（若文中有提及）",
      "confidence": "信心程度（high/medium/low）"
    }
  ]
}

注意事項：
1. 只萃取明確的承諾，不要包含模糊的願景陳述
2. 若文件中沒有找到任何承諾，回傳 {"commitments": []}
3. 保持 text 欄位簡潔，最多 200 字
4. 每個承諾應該是獨立、具體的項目'

########################################
# 處理函式
########################################

# 從單一文件萃取承諾
extract_from_document() {
  local doc_id="$1"
  local subject="$2"
  local content="$3"
  local source_info="$4"

  # 組合用於分析的文字（限制長度避免超過 token 限制）
  local analysis_text="${subject}

${content}"

  # 截斷過長的內容（約 8000 字元）
  if [[ ${#analysis_text} -gt 8000 ]]; then
    analysis_text="${analysis_text:0:8000}..."
  fi

  # 呼叫 OpenAI API
  local response
  if ! response="$(openai_chat_completion "gpt-4o-mini" "$COMMITMENT_SYSTEM_PROMPT" "$analysis_text" "json" 2>&1)"; then
    echo "⚠️  文件 ${doc_id} 萃取失敗: ${response}" >&2
    return 1
  fi

  # 驗證 JSON 格式
  if ! printf '%s' "$response" | jq -e '.commitments' >/dev/null 2>&1; then
    echo "⚠️  文件 ${doc_id} 回應格式錯誤" >&2
    return 1
  fi

  # 取得承諾數量
  local commitment_count
  commitment_count="$(printf '%s' "$response" | jq '.commitments | length')"

  if [[ "$commitment_count" -eq 0 ]]; then
    echo "   ℹ️  無承諾"
    return 0
  fi

  echo "   ✅ 找到 ${commitment_count} 個承諾"

  # 為每個承諾加上來源資訊和 ID
  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  printf '%s' "$response" | jq -c --arg source_info "$source_info" --arg doc_id "$doc_id" --arg now "$now" '
    .commitments[] |
    . + {
      id: (($doc_id) + "-" + (. | @base64 | .[0:8])),
      source: ($source_info | fromjson),
      status: "pending",
      extracted_at: $now
    }
  '
}

########################################
# 主程式
########################################

# 檢查必要指令
require_cmd curl jq

# 解析參數
parse_args "$@"

arg_required input INPUT_FILE
arg_optional output OUTPUT_FILE ""
arg_optional limit PROCESS_LIMIT "0"
arg_optional model CHAT_MODEL "gpt-4o-mini"

# 若未指定輸出檔案，自動產生
if [[ -z "$OUTPUT_FILE" ]]; then
  INPUT_BASENAME="$(basename "$INPUT_FILE" .jsonl)"
  OUTPUT_FILE="data/commitments/${INPUT_BASENAME}-commitments.jsonl"
fi

echo "========================================="
echo "政策承諾萃取引擎"
echo "========================================="
echo "輸入檔案: ${INPUT_FILE}"
echo "輸出檔案: ${OUTPUT_FILE}"
echo "處理限制: ${PROCESS_LIMIT:-無限制}"
echo "使用模型: ${CHAT_MODEL}"
echo "========================================="
echo ""

# 初始化 OpenAI
echo "🔧 初始化環境..."
openai_init_env || {
  echo "❌ OpenAI 環境初始化失敗"
  exit 1
}
echo "✅ 環境初始化完成"
echo ""

# 檢查輸入檔案
if [[ ! -f "$INPUT_FILE" ]]; then
  echo "❌ 輸入檔案不存在: ${INPUT_FILE}"
  exit 1
fi

# 確保輸出目錄存在
OUTPUT_DIR="$(dirname "$OUTPUT_FILE")"
mkdir -p "$OUTPUT_DIR"

# 統計
TOTAL_DOCS=0
PROCESSED_DOCS=0
COMMITMENT_COUNT=0
ERROR_COUNT=0

# 計算總文件數（只計算非 chunk 或 chunk 0 的文件）
TOTAL_DOCS="$(jq -s '[.[] | select(.payload.isChunked == false or .payload.chunkIndex == 0)] | length' "$INPUT_FILE")"
echo "📊 總文件數: ${TOTAL_DOCS}"
echo ""

# 處理每個文件
echo "🔄 開始萃取承諾..."
echo ""

while IFS= read -r line; do
  # 檢查處理限制
  if [[ "$PROCESS_LIMIT" -gt 0 && "$PROCESSED_DOCS" -ge "$PROCESS_LIMIT" ]]; then
    echo ""
    echo "✅ 已達處理限制 ${PROCESS_LIMIT} 筆"
    break
  fi

  # 提取文件資訊
  DOC_ID="$(printf '%s' "$line" | jq -r '.id')"
  SUBJECT="$(printf '%s' "$line" | jq -r '.payload.subject // ""')"
  CONTENT="$(printf '%s' "$line" | jq -r '.payload.content // ""')"
  IS_CHUNKED="$(printf '%s' "$line" | jq -r '.payload.isChunked')"
  CHUNK_INDEX="$(printf '%s' "$line" | jq -r '.payload.chunkIndex // 0')"

  # 跳過非首個 chunk 的文件（避免重複處理）
  if [[ "$IS_CHUNKED" == "true" && "$CHUNK_INDEX" != "0" ]]; then
    continue
  fi

  # 如果是 chunked 文件，收集所有 chunks 的內容
  if [[ "$IS_CHUNKED" == "true" ]]; then
    BASE_ID="$(printf '%s' "$line" | jq -r '.payload.baseId')"
    # 合併所有 chunks 的 chunkText
    CONTENT="$(jq -r --arg base_id "$BASE_ID" '
      select(.payload.baseId == $base_id) |
      .payload.chunkText // .payload.content
    ' "$INPUT_FILE" | tr '\n' ' ')"
  fi

  PROCESSED_DOCS=$((PROCESSED_DOCS + 1))
  echo "[${PROCESSED_DOCS}/${TOTAL_DOCS}] ${DOC_ID:0:8}... ${SUBJECT:0:40}"

  # 準備來源資訊
  SOURCE_INFO="$(printf '%s' "$line" | jq -c '{
    document_id: .id,
    term: .payload.term,
    sessionPeriod: .payload.sessionPeriod,
    sessionTimes: .payload.sessionTimes,
    eyNumber: .payload.eyNumber,
    lyNumber: .payload.lyNumber,
    subject: .payload.subject
  }')"

  # 萃取承諾
  if commitments="$(extract_from_document "$DOC_ID" "$SUBJECT" "$CONTENT" "$SOURCE_INFO")"; then
    if [[ -n "$commitments" ]]; then
      # 寫入輸出檔案
      printf '%s\n' "$commitments" >> "$OUTPUT_FILE"
      # 計算本次新增的承諾數
      new_count="$(printf '%s' "$commitments" | wc -l | tr -d ' ')"
      COMMITMENT_COUNT=$((COMMITMENT_COUNT + new_count))
    fi
  else
    ERROR_COUNT=$((ERROR_COUNT + 1))
  fi

  # API rate limit 保護
  sleep 0.5

done < <(jq -c '.' "$INPUT_FILE")

echo ""
echo "========================================="
echo "萃取完成"
echo "========================================="
echo "處理文件: ${PROCESSED_DOCS} 筆"
echo "萃取承諾: ${COMMITMENT_COUNT} 筆"
echo "失敗文件: ${ERROR_COUNT} 筆"
echo "輸出檔案: ${OUTPUT_FILE}"
echo "========================================="

# 顯示承諾統計
if [[ -f "$OUTPUT_FILE" && -s "$OUTPUT_FILE" ]]; then
  echo ""
  echo "📊 承諾分類統計："
  jq -r '.category' "$OUTPUT_FILE" | sort | uniq -c | sort -rn
fi
