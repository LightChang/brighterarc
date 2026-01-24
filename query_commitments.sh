#!/usr/bin/env bash
# query_commitments.sh - 語意搜尋政策承諾
#
# 功能：
#   1. 將查詢文字轉為 embedding
#   2. 在 Qdrant 中搜尋最相似的承諾
#   3. 格式化輸出結果
#
# 使用方式：
#   ./query_commitments.sh --query "再生能源目標"
#   ./query_commitments.sh --query "碳中和承諾" --limit 20
#   ./query_commitments.sh --query "教育政策" --format json
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
arg_optional collection COLLECTION_NAME "policy_commitments"
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
  echo "🔍 搜尋相似承諾..." >&2
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
  echo "政策承諾搜尋結果（Top ${RESULT_LIMIT}）"
  echo "==========================================="
  echo ""

  # 檢查是否有結果
  RESULT_COUNT="$(printf '%s\n' "$SEARCH_RESULT" | jq '.result | length')"

  if [[ "$RESULT_COUNT" -eq 0 ]]; then
    echo "ℹ️  沒有找到相關的承諾"
    echo ""
    echo "提示：請確認 policy_commitments collection 中已有資料"
    echo "     可先執行 ./extract_commitments.sh 萃取承諾"
    exit 0
  fi

  # 解析並格式化每個結果
  index=1
  printf '%s\n' "$SEARCH_RESULT" | jq -r '.result[] | @json' | while IFS= read -r item; do
    SCORE="$(printf '%s' "$item" | jq -r '.score')"
    PAYLOAD="$(printf '%s' "$item" | jq -r '.payload')"

    # 承諾資訊
    TEXT="$(printf '%s' "$PAYLOAD" | jq -r '.text // ""')"
    CATEGORY="$(printf '%s' "$PAYLOAD" | jq -r '.category // "未分類"')"
    TARGET_DATE="$(printf '%s' "$PAYLOAD" | jq -r '.target_date // "無期限"')"
    TARGET_VALUE="$(printf '%s' "$PAYLOAD" | jq -r '.target_value // "-"')"
    CONFIDENCE="$(printf '%s' "$PAYLOAD" | jq -r '.confidence // "medium"')"
    RESPONSIBLE="$(printf '%s' "$PAYLOAD" | jq -r '.responsible_agency // "-"')"
    STATUS="$(printf '%s' "$PAYLOAD" | jq -r '.status // "pending"')"

    # 來源資訊
    TERM="$(printf '%s' "$PAYLOAD" | jq -r '.source.term // ""')"
    SESSION_PERIOD="$(printf '%s' "$PAYLOAD" | jq -r '.source.sessionPeriod // ""')"
    SUBJECT="$(printf '%s' "$PAYLOAD" | jq -r '.source.subject // ""')"
    EY_NUMBER="$(printf '%s' "$PAYLOAD" | jq -r '.source.eyNumber // ""')"

    # 格式化相似度分數（保留 4 位小數）
    SCORE_FORMATTED="$(printf '%.4f' "$SCORE")"

    # 狀態顯示
    case "$STATUS" in
      pending) STATUS_ICON="⏳" ;;
      fulfilled) STATUS_ICON="✅" ;;
      unfulfilled) STATUS_ICON="❌" ;;
      modified) STATUS_ICON="🔄" ;;
      *) STATUS_ICON="❓" ;;
    esac

    # 信心程度顯示
    case "$CONFIDENCE" in
      high) CONF_ICON="🟢" ;;
      medium) CONF_ICON="🟡" ;;
      low) CONF_ICON="🔴" ;;
      *) CONF_ICON="⚪" ;;
    esac

    echo "${index}. [相似度: ${SCORE_FORMATTED}] ${STATUS_ICON} ${CATEGORY}"
    echo ""
    echo "   📋 承諾內容："
    echo "   ${TEXT}"
    echo ""
    echo "   📅 目標日期: ${TARGET_DATE}"
    echo "   📊 目標值: ${TARGET_VALUE}"
    echo "   🏛️  負責機關: ${RESPONSIBLE}"
    echo "   ${CONF_ICON} 信心程度: ${CONFIDENCE}"
    echo ""
    echo "   📄 來源: 第 ${TERM} 屆第 ${SESSION_PERIOD} 會期"
    echo "   ${SUBJECT:0:60}..."
    echo "   文號: ${EY_NUMBER}"
    echo ""
    echo "-------------------------------------------"
    echo ""

    index=$((index + 1))
  done

  # 顯示分類統計
  echo ""
  echo "📊 結果分類統計："
  printf '%s\n' "$SEARCH_RESULT" | jq -r '.result[].payload.category' | sort | uniq -c | sort -rn
fi
