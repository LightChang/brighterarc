#!/usr/bin/env bash
# query_legislative_data.sh - 查詢立法院資料
#
# 功能：
#   1. 將查詢文字轉為 embedding
#   2. 在 Qdrant 中搜尋最相似的文件
#   3. 格式化輸出結果
#
# 使用方式：
#   ./query_legislative_data.sh --query "查詢文字" [--limit N] [--format text|json]
#
# 環境變數：
#   OPENAI_API_KEY: OpenAI API key
#   QDRANT_URL: Qdrant 伺服器 URL
#   QDRANT_API_KEY: Qdrant API key (Cloud 版需要)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 載入模組
source "${SCRIPT_DIR}/lib/core.sh"
source "${SCRIPT_DIR}/lib/args.sh"
source "${SCRIPT_DIR}/lib/openai.sh"
source "${SCRIPT_DIR}/lib/qdrant.sh"

# 檢查必要指令
require_cmd curl jq

########################################
# 解析參數
########################################
parse_args "$@"

arg_required query QUERY_TEXT "查詢文字"
arg_optional limit RESULT_LIMIT "10"
arg_optional collection COLLECTION_NAME "legislative_replies"
arg_optional format OUTPUT_FORMAT "text"
arg_optional model EMBEDDING_MODEL "text-embedding-3-small"

########################################
# 初始化
########################################
openai_init_env || {
  echo "❌ OpenAI 環境初始化失敗" >&2
  exit 1
}

qdrant_init_env || {
  echo "❌ Qdrant 環境初始化失敗" >&2
  exit 1
}

########################################
# 產生查詢 embedding
########################################
if [[ "$OUTPUT_FORMAT" == "text" ]]; then
  echo "🔮 產生查詢 embedding..." >&2
fi

QUERY_EMBEDDING="$(openai_create_embedding "$EMBEDDING_MODEL" "$QUERY_TEXT")" || {
  echo "❌ Embedding 產生失敗" >&2
  exit 1
}

########################################
# 搜尋 Qdrant
########################################
if [[ "$OUTPUT_FORMAT" == "text" ]]; then
  echo "🔍 搜尋相似文件..." >&2
  echo "" >&2
fi

SEARCH_RESULT="$(qdrant_search "$COLLECTION_NAME" "$QUERY_EMBEDDING" "$RESULT_LIMIT")" || {
  echo "❌ 搜尋失敗" >&2
  exit 1
}

########################################
# 格式化輸出
########################################

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
  # JSON 格式：直接輸出原始結果
  printf '%s\n' "$SEARCH_RESULT" | jq '.result'
else
  # Text 格式：友善的文字輸出
  echo "==========================================="
  echo "查詢：${QUERY_TEXT}"
  echo "相似度搜尋結果（Top ${RESULT_LIMIT}）"
  echo "==========================================="
  echo ""

  # 解析並格式化每個結果
  index=1
  printf '%s\n' "$SEARCH_RESULT" | jq -r '.result[] | @json' | while IFS= read -r item; do
    SCORE="$(printf '%s' "$item" | jq -r '.score')"
    PAYLOAD="$(printf '%s' "$item" | jq -r '.payload')"

    TERM="$(printf '%s' "$PAYLOAD" | jq -r '.term // ""')"
    SESSION_PERIOD="$(printf '%s' "$PAYLOAD" | jq -r '.sessionPeriod // ""')"
    SESSION_TIMES="$(printf '%s' "$PAYLOAD" | jq -r '.sessionTimes // ""')"
    EY_NUMBER="$(printf '%s' "$PAYLOAD" | jq -r '.eyNumber // ""')"
    LY_NUMBER="$(printf '%s' "$PAYLOAD" | jq -r '.lyNumber // ""')"
    SUBJECT="$(printf '%s' "$PAYLOAD" | jq -r '.subject // ""')"
    CONTENT="$(printf '%s' "$PAYLOAD" | jq -r '.content // ""')"
    DOC_URL="$(printf '%s' "$PAYLOAD" | jq -r '.docUrl // ""')"
    IS_CHUNKED="$(printf '%s' "$PAYLOAD" | jq -r '.isChunked // false')"
    CHUNK_INDEX="$(printf '%s' "$PAYLOAD" | jq -r '.chunkIndex // ""')"
    CHUNK_TEXT="$(printf '%s' "$PAYLOAD" | jq -r '.chunkText // ""')"

    # 格式化相似度分數（保留 4 位小數）
    SCORE_FORMATTED="$(printf '%.4f' "$SCORE")"

    echo "${index}. [相似度: ${SCORE_FORMATTED}] 第 ${TERM} 屆第 ${SESSION_PERIOD} 會期"
    echo "   會議次數: ${SESSION_TIMES}"
    echo "   行政院文號: ${EY_NUMBER}"
    echo "   立法院文號: ${LY_NUMBER}"
    echo ""
    echo "   主題: ${SUBJECT}"
    echo ""

    # 如果是分塊的文件，顯示分塊資訊
    if [[ "$IS_CHUNKED" == "true" ]]; then
      echo "   內容 (Chunk ${CHUNK_INDEX}):"
      # 顯示前 300 字
      if [[ ${#CHUNK_TEXT} -gt 300 ]]; then
        printf '   %s...\n' "${CHUNK_TEXT:0:300}"
      else
        printf '   %s\n' "$CHUNK_TEXT"
      fi
    else
      echo "   內容:"
      # 顯示前 300 字
      if [[ ${#CONTENT} -gt 300 ]]; then
        printf '   %s...\n' "${CONTENT:0:300}"
      else
        printf '   %s\n' "$CONTENT"
      fi
    fi

    echo ""
    echo "   網址: ${DOC_URL}"
    echo ""
    echo "-------------------------------------------"
    echo ""

    index=$((index + 1))
  done
fi
