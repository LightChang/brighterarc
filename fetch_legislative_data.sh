#!/usr/bin/env bash
# fetch_legislative_data.sh - 抓取立法院資料並計算 embeddings
#
# 功能：
#   1. 從立法院 API 抓取最新的行政院答復資料
#   2. 使用 OpenAI 產生 embeddings
#   3. 儲存為 JSONL 格式到本地檔案
#
# 使用方式：
#   ./fetch_legislative_data.sh [--date YYYY-MM-DD] [--limit N] [--output FILE]
#
# 環境變數：
#   OPENAI_API_KEY: OpenAI API key

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 載入模組
source "${SCRIPT_DIR}/lib/core.sh"
source "${SCRIPT_DIR}/lib/args.sh"
source "${SCRIPT_DIR}/lib/openai.sh"

: "${LEGISLATIVE_API_BASE:=https://data.ly.gov.tw/odw}"

########################################
# 立法院 API 函式
########################################

legislative_init_env() {
  local err=0

  # 指令檢查
  if declare -f require_cmd >/dev/null 2>&1; then
    require_cmd curl
    require_cmd jq
  else
    for cmd in curl jq; do
      if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "❌ [legislative_init_env] 需要指令：$cmd" >&2
        err=1
      fi
    done
  fi

  return "$err"
}

# legislative_fetch_replies [TERM] [SESSION_PERIOD] [SESSION_TIMES] [MEETING_TIMES] [FILE_TYPE]
legislative_fetch_replies() {
  local term="${1:-}"
  local session_period="${2:-}"
  local session_times="${3:-}"
  local meeting_times="${4:-}"
  local file_type="${5:-json}"

  require_cmd curl || return 1

  local url="${LEGISLATIVE_API_BASE}/ID2Action.action"
  url+="?term=${term}"
  url+="&sessionPeriod=${session_period}"
  url+="&sessionTimes=${session_times}"
  url+="&meetingTimes=${meeting_times}"
  url+="&eyNumber="
  url+="&lyNumber="
  url+="&fileType=${file_type}"

  local tmp_body http_code
  tmp_body="$(mktemp)"

  http_code="$(
    curl -sS "$url" \
      -w '%{http_code}' \
      -o "$tmp_body" \
      2>/dev/null
  )" || {
    local rc=$?
    echo "❌ [legislative_fetch_replies] curl 失敗 exit=${rc}" >&2
    rm -f "$tmp_body"
    return 1
  }

  local resp
  resp="$(cat "$tmp_body")"
  rm -f "$tmp_body"

  if [[ "$http_code" != "200" ]]; then
    echo "❌ [legislative_fetch_replies] HTTP=${http_code}" >&2
    echo "$resp" >&2
    return 1
  fi

  printf '%s\n' "$resp"
}

# legislative_generate_point_id TERM SESSION_PERIOD SESSION_TIMES EY_NUMBER LY_NUMBER
legislative_generate_point_id() {
  local term="$1"
  local session_period="$2"
  local session_times="$3"
  local ey_number="$4"
  local ly_number="${5:-}"

  # 組合唯一字串
  local unique_string="${term}-${session_period}-${session_times}-${ey_number}-${ly_number}"

  # 使用 md5 產生 UUID-like 格式
  local hash
  if command -v md5 >/dev/null 2>&1; then
    # macOS
    hash="$(printf '%s' "$unique_string" | md5)"
  elif command -v md5sum >/dev/null 2>&1; then
    # Linux
    hash="$(printf '%s' "$unique_string" | md5sum | awk '{print $1}')"
  else
    # Fallback: 使用簡單的數字 hash
    local num_hash=0
    for (( i=0; i<${#unique_string}; i++ )); do
      local char="${unique_string:$i:1}"
      local ascii
      ascii=$(printf '%d' "'$char")
      num_hash=$(( (num_hash * 31 + ascii) % 2147483647 ))
    done
    printf '%d\n' "$num_hash"
    return 0
  fi

  # 格式化成 UUID 格式
  printf '%s-%s-%s-%s-%s\n' \
    "${hash:0:8}" \
    "${hash:8:4}" \
    "${hash:12:4}" \
    "${hash:16:4}" \
    "${hash:20:12}"
}

# 檢查必要指令
require_cmd curl jq

########################################
# 解析參數
########################################
parse_args "$@"

arg_optional date TARGET_DATE "$(date +%Y-%m-%d)"
arg_optional limit FETCH_LIMIT "100"
arg_optional output OUTPUT_FILE "data/daily/${TARGET_DATE}.jsonl"
arg_optional model EMBEDDING_MODEL "text-embedding-3-small"

echo "========================================="
echo "立法院資料抓取與 Embedding 計算"
echo "========================================="
echo "目標日期: ${TARGET_DATE}"
echo "抓取筆數: ${FETCH_LIMIT}"
echo "輸出檔案: ${OUTPUT_FILE}"
echo "Embedding Model: ${EMBEDDING_MODEL}"
echo "========================================="
echo ""

########################################
# 初始化
########################################
echo "🔧 初始化環境..."

openai_init_env || {
  echo "❌ OpenAI 環境初始化失敗"
  exit 1
}

legislative_init_env || {
  echo "❌ Legislative 環境初始化失敗"
  exit 1
}

echo "✅ 環境初始化完成"
echo ""

# 確保輸出目錄存在
OUTPUT_DIR="$(dirname "$OUTPUT_FILE")"
mkdir -p "$OUTPUT_DIR"

# 建立臨時檔案來儲存已處理的 ID（相容 Bash 3.2）
PROCESSED_IDS_FILE="$(mktemp)"
trap "rm -f '$PROCESSED_IDS_FILE'" EXIT

# 確保輸出檔案存在（如果不存在就建立空檔案）
if [[ ! -f "$OUTPUT_FILE" ]]; then
  > "$OUTPUT_FILE"
  echo "✅ 輸出檔案已建立：${OUTPUT_FILE}"
  echo ""
fi

# 如果檔案有資料，載入已存在的 ID（支援增量更新）
if [[ -s "$OUTPUT_FILE" ]]; then
  echo "📋 載入已存在的資料..."
  # 載入 baseId（包含未分塊和分塊的所有 base IDs）
  jq -r '.payload.baseId' "$OUTPUT_FILE" 2>/dev/null | sort -u > "$PROCESSED_IDS_FILE" || true
  EXISTING_COUNT="$(wc -l < "$PROCESSED_IDS_FILE" | tr -d ' ')"
  echo "✅ 已載入 ${EXISTING_COUNT} 個已存在的 base ID"
  echo "ℹ️  將以增量模式繼續處理（跳過重複資料）"
  echo ""
fi

########################################
# 抓取最新資料（按會期逐批處理）
########################################
echo "📥 開始逐會期抓取並處理立法院資料..."
echo "ℹ️  目標：處理 ${FETCH_LIMIT} 筆文件"
echo ""

# 從第 11 屆開始，會期從大到小（假設較大會期較新）
START_TERM=11
CURRENT_TERM=$START_TERM

########################################
# 處理函數
########################################

# 處理單一 chunk 並寫入 JSONL
process_single_chunk() {
  local point_id="$1"
  local text="$2"
  local payload_base="$3"
  local is_chunked="$4"
  local chunk_index="$5"
  local total_chunks="$6"
  local base_id="${7:-$point_id}"

  # 產生 embedding（帶重試機制）
  echo "   🔮 產生 embedding..."
  local embedding
  local retry_count=0
  local max_retries=10

  while [[ $retry_count -lt $max_retries ]]; do
    if embedding="$(openai_create_embedding "$EMBEDDING_MODEL" "$text" 2>&1)"; then
      # 成功產生 embedding
      break
    else
      local exit_code=$?
      retry_count=$((retry_count + 1))

      if [[ $retry_count -lt $max_retries ]]; then
        echo "   ⚠️  Embedding 產生失敗（嘗試 ${retry_count}/${max_retries}）"
        echo "   ⏳ 偵測到網路異常，等待 1 分鐘後重試..."

        # 計算重試時間（跨平台相容）
        if date -v+1M '+%H:%M:%S' >/dev/null 2>&1; then
          # macOS
          echo "   ⏰ 將於 $(date -v+1M '+%H:%M:%S') 重試"
        elif date -d '+1 minute' '+%H:%M:%S' >/dev/null 2>&1; then
          # Linux
          echo "   ⏰ 將於 $(date -d '+1 minute' '+%H:%M:%S') 重試"
        fi

        sleep 60  # 等待 1 分鐘
        echo "   🔄 重新嘗試產生 embedding..."
      else
        echo "   ❌ Embedding 產生失敗（已重試 ${max_retries} 次）"
        ERROR_COUNT=$((ERROR_COUNT + 1))
        return 1
      fi
    fi
  done

  # 準備 payload
  local payload
  payload="$(printf '%s' "$payload_base" | jq \
    --arg is_chunked "$is_chunked" \
    --arg chunk_idx "$chunk_index" \
    --arg total "$total_chunks" \
    --arg chunk_text "$text" \
    --arg base_id "$base_id" \
    '. + {
      baseId: $base_id,
      isChunked: ($is_chunked == "true"),
      chunkIndex: (if $chunk_idx == "null" then null else ($chunk_idx | tonumber) end),
      totalChunks: (if $total == "null" then null else ($total | tonumber) end),
      chunkText: $chunk_text
    }'
  )"

  # 組合成 point 格式
  local point_json
  point_json="$(printf '%s\n%s' "$embedding" "$payload" | jq -sc \
    --arg id "$point_id" \
    '{
      id: $id,
      vector: .[0],
      payload: .[1]
    }'
  )"

  # 立即寫入最終檔案
  echo "$point_json" >> "$OUTPUT_FILE"

  if [[ "$is_chunked" == "true" ]]; then
    echo "   ✅ Chunk ${chunk_index} 已寫入檔案"
  else
    echo "   ✅ 已寫入檔案"
  fi

  NEW_COUNT=$((NEW_COUNT + 1))
  return 0
}

# 分塊處理長文件
process_chunked_document() {
  local base_id="$1"
  local subject="$2"
  local content="$3"
  local payload_base="$4"

  local chunk_size=4000
  local overlap=500
  local content_len=${#content}
  local subject_len=${#subject}

  # 計算總 chunk 數
  local effective_chunk_size=$((chunk_size - subject_len - 10))
  local total_chunks=$(( (content_len + effective_chunk_size - overlap - 1) / (effective_chunk_size - overlap) ))

  echo "   📄 文件過長 (${content_len} 字)，分成 ${total_chunks} 個 chunks"

  local chunk_index=0
  local start_pos=0

  while [[ $start_pos -lt $content_len ]]; do
    # 計算此 chunk 的結束位置
    local end_pos=$((start_pos + effective_chunk_size))
    if [[ $end_pos -gt $content_len ]]; then
      end_pos=$content_len
    fi

    # 提取此 chunk 的內容
    local chunk_content="${content:start_pos:end_pos-start_pos}"
    local chunk_text="${subject}

${chunk_content}"

    # 產生 chunk 的 point ID（使用 hash 生成新的 UUID）
    local chunk_unique_string="${base_id}-chunk-${chunk_index}"
    local chunk_hash
    if command -v md5 >/dev/null 2>&1; then
      chunk_hash="$(printf '%s' "$chunk_unique_string" | md5)"
    elif command -v md5sum >/dev/null 2>&1; then
      chunk_hash="$(printf '%s' "$chunk_unique_string" | md5sum | awk '{print $1}')"
    fi
    # 格式化成 UUID
    local chunk_point_id
    chunk_point_id="$(printf '%s-%s-%s-%s-%s\n' \
      "${chunk_hash:0:8}" \
      "${chunk_hash:8:4}" \
      "${chunk_hash:12:4}" \
      "${chunk_hash:16:4}" \
      "${chunk_hash:20:12}")"

    # 處理此 chunk
    echo "   🆕 處理 Chunk ${chunk_index}/${total_chunks} (${start_pos}-${end_pos} 字)"
    echo "      Base ID: [$base_id]"
    echo "      Chunk ID: [$chunk_point_id]"
    process_single_chunk "$chunk_point_id" "$chunk_text" "$payload_base" \
      "true" "$chunk_index" "$total_chunks" "$base_id"

    # 移動到下一個 chunk（扣除重疊區域）
    start_pos=$((start_pos + effective_chunk_size - overlap))
    chunk_index=$((chunk_index + 1))

    # 避免 API rate limit
    sleep 0.5
  done
}

# 處理單一文件（可能分塊）
process_document() {
  local point_id="$1"
  local subject="$2"
  local content="$3"
  local payload_base="$4"

  # 組合文字
  local combined_text="${subject}

${content}"

  # 判斷是否需要分塊
  if [[ ${#combined_text} -le 4000 ]]; then
    # 短文件：單筆處理
    process_single_chunk "$point_id" "$combined_text" "$payload_base" "false" "null" "null"
  else
    # 長文件：分塊處理
    process_chunked_document "$point_id" "$subject" "$content" "$payload_base"
  fi
}

########################################
# 逐會期抓取並處理資料
########################################

NEW_COUNT=0
ERROR_COUNT=0
PROCESSED_COUNT=0
TOTAL_FETCHED=0
SKIPPED_COUNT=0
EMPTY_SESSION_COUNT=0

# 從第 11 屆開始往回抓（11→10→9→8）
# 每屆的會期從大到小（10→9→...→1，假設較大會期較新）
for (( term=START_TERM; term>=8; term-- )); do
  for (( period=10; period>=1; period-- )); do
    # 檢查是否已達到目標處理數量
    if [[ $PROCESSED_COUNT -ge $FETCH_LIMIT ]]; then
      echo ""
      echo "✅ 已處理 ${PROCESSED_COUNT} 筆文件，達到目標數量 ${FETCH_LIMIT}"
      break 2
    fi

    # 抓取這個會期的資料
    period_str="$(printf '%02d' $period)"
    echo "📥 抓取第 ${term} 屆第 ${period_str} 會期..."

    SESSION_DATA="$(legislative_fetch_replies "$term" "$period_str" "" "" "json")" || {
      echo "⚠️  第 ${term} 屆第 ${period_str} 會期抓取失敗，繼續下一個會期..." >&2
      continue
    }

    # 計算這個會期的資料筆數
    SESSION_COUNT="$(printf '%s' "$SESSION_DATA" | jq '.dataList | length')" || SESSION_COUNT=0

    if [[ "$SESSION_COUNT" -eq 0 ]]; then
      echo "ℹ️  第 ${term} 屆第 ${period_str} 會期無資料，繼續..."
      continue
    fi

    echo "✅ 取得 ${SESSION_COUNT} 筆資料"
    TOTAL_FETCHED=$((TOTAL_FETCHED + SESSION_COUNT))

    echo "🔄 開始處理第 ${term} 屆第 ${period_str} 會期的資料..."

    # 記錄該會期開始前的 PROCESSED_COUNT
    PREV_PROCESSED_COUNT=$PROCESSED_COUNT
    REACHED_LIMIT=false

    # 使用 jq 逐筆處理這個會期的資料
    while IFS= read -r item; do
      # 檢查是否已達到目標處理數量
      if [[ $PROCESSED_COUNT -ge $FETCH_LIMIT ]]; then
        echo "✅ 已處理 ${PROCESSED_COUNT} 筆文件，達到目標數量 ${FETCH_LIMIT}"
        REACHED_LIMIT=true
        break
      fi

      # 提取欄位
      TERM="$(printf '%s' "$item" | jq -r '.term // ""')"
      SESSION_PERIOD="$(printf '%s' "$item" | jq -r '.sessionPeriod // ""')"
      SESSION_TIMES="$(printf '%s' "$item" | jq -r '.sessionTimes // ""')"
      EY_NUMBER="$(printf '%s' "$item" | jq -r '.eyNumber // ""')"
      LY_NUMBER="$(printf '%s' "$item" | jq -r '.lyNumber // ""')"
      SUBJECT="$(printf '%s' "$item" | jq -r '.subject // ""')"
      CONTENT="$(printf '%s' "$item" | jq -r '.content // ""')"
      DOC_URL="$(printf '%s' "$item" | jq -r '.docUrl // ""')"

      # 產生唯一 ID (UUID)
      POINT_ID="$(legislative_generate_point_id "$TERM" "$SESSION_PERIOD" "$SESSION_TIMES" "$EY_NUMBER" "$LY_NUMBER")"

      # 檢查 ID 是否已存在（使用 grep 檢查臨時檔案）
      if grep -Fxq "$POINT_ID" "$PROCESSED_IDS_FILE" 2>/dev/null; then
        echo "⏭️  [${TERM}-${SESSION_PERIOD}-${SESSION_TIMES}] ${EY_NUMBER} → [$POINT_ID] 已存在，跳過"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        continue
      fi

      echo "🆕 [${TERM}-${SESSION_PERIOD}-${SESSION_TIMES}] ${EY_NUMBER} → [$POINT_ID] 處理中..."

      # 準備 base payload（不含 chunking 相關欄位）
      PAYLOAD_BASE="$(jq -n \
        --arg term "$TERM" \
        --arg period "$SESSION_PERIOD" \
        --arg times "$SESSION_TIMES" \
        --arg ey "$EY_NUMBER" \
        --arg ly "$LY_NUMBER" \
        --arg subject "$SUBJECT" \
        --arg content "$CONTENT" \
        --arg url "$DOC_URL" \
        '{
          term: $term,
          sessionPeriod: $period,
          sessionTimes: $times,
          eyNumber: $ey,
          lyNumber: $ly,
          subject: $subject,
          content: $content,
          docUrl: $url
        }'
      )"

      # 呼叫分塊處理函數
      process_document "$POINT_ID" "$SUBJECT" "$CONTENT" "$PAYLOAD_BASE"

      # 將 ID 加入已處理檔案
      echo "$POINT_ID" >> "$PROCESSED_IDS_FILE"

      # 成功處理一筆文件
      PROCESSED_COUNT=$((PROCESSED_COUNT + 1))
    done < <(printf '%s' "$SESSION_DATA" | jq -c '.dataList[]')

    # 如果達到 limit，立即停止所有抓取
    if [[ "$REACHED_LIMIT" == "true" ]]; then
      break 2
    fi

    # 計算該會期新增的資料數
    SESSION_NEW_COUNT=$((PROCESSED_COUNT - PREV_PROCESSED_COUNT))

    if [[ $SESSION_NEW_COUNT -eq 0 ]]; then
      # 該會期沒有新資料
      echo "ℹ️  第 ${term} 屆第 ${period_str} 會期沒有新資料"
      EMPTY_SESSION_COUNT=$((EMPTY_SESSION_COUNT + 1))

      # 如果連續 3 個會期都沒有新資料，停止抓取
      if [[ $EMPTY_SESSION_COUNT -ge 3 ]]; then
        echo ""
        echo "⚠️  連續 ${EMPTY_SESSION_COUNT} 個會期都沒有新資料"
        echo "⚠️  停止抓取"
        break 2
      fi
    else
      # 該會期有新資料
      echo "✅ 第 ${term} 屆第 ${period_str} 會期處理完成（新增 ${SESSION_NEW_COUNT} 筆）"
      EMPTY_SESSION_COUNT=0
    fi
    echo ""
  done
done

echo ""
echo "========================================="
echo "處理完成"
echo "========================================="
echo "總抓取資料: ${TOTAL_FETCHED} 筆（API 回傳）"
echo "處理文件數: ${PROCESSED_COUNT} 筆（新增）"
echo "跳過重複: ${SKIPPED_COUNT} 筆"
echo "目標數量: ${FETCH_LIMIT} 筆"
echo "寫入 points: ${NEW_COUNT} 筆（含分塊）"
echo "失敗數量: ${ERROR_COUNT} 筆"
echo "輸出檔案: ${OUTPUT_FILE}"
echo "========================================="

# 檢查是否達到目標數量
if [[ $PROCESSED_COUNT -lt $FETCH_LIMIT ]]; then
  if [[ $PROCESSED_COUNT -eq 0 ]]; then
    echo ""
    echo "⚠️ 警告：沒有找到新資料"
    echo "ℹ️ 所有資料都已存在於檔案中"
  else
    echo ""
    echo "ℹ️ 提示：實際處理數 < 目標數量"
    echo "ℹ️ 可能已經沒有更多新資料"
  fi
  echo ""
fi

# 顯示檔案大小與總 points 數
if [[ -f "$OUTPUT_FILE" ]]; then
  FILE_SIZE="$(ls -lh "$OUTPUT_FILE" | awk '{print $5}')"
  TOTAL_POINTS="$(jq -s 'length' "$OUTPUT_FILE" 2>/dev/null || echo "0")"
  echo "檔案大小: ${FILE_SIZE}"
  echo "總 points: ${TOTAL_POINTS} 筆"
fi
