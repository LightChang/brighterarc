#!/usr/bin/env bash
# query_commitments.sh - 查詢與追蹤政策承諾
#
# 功能：
#   1. 依關鍵字搜尋承諾
#   2. 依分類篩選承諾
#   3. 依目標日期篩選承諾
#   4. 顯示即將到期的承諾
#
# 使用方式：
#   ./query_commitments.sh --search "再生能源"
#   ./query_commitments.sh --category "能源政策"
#   ./query_commitments.sh --due-before 2025-12-31
#   ./query_commitments.sh --upcoming 90  # 90 天內到期

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 載入模組
source "${SCRIPT_DIR}/lib/core.sh"
source "${SCRIPT_DIR}/lib/args.sh"

########################################
# 輔助函式
########################################

# 日期轉 epoch（跨平台）
date_to_epoch() {
  local date_str="$1"
  if date -j -f "%Y-%m-%d" "$date_str" "+%s" 2>/dev/null; then
    return 0
  elif date -d "$date_str" "+%s" 2>/dev/null; then
    return 0
  else
    echo "0"
  fi
}

# 格式化輸出單個承諾
format_commitment() {
  local commitment="$1"
  local index="$2"

  local text category target_date target_value confidence
  local term session_period subject

  text="$(printf '%s' "$commitment" | jq -r '.text')"
  category="$(printf '%s' "$commitment" | jq -r '.category // "未分類"')"
  target_date="$(printf '%s' "$commitment" | jq -r '.target_date // "無期限"')"
  target_value="$(printf '%s' "$commitment" | jq -r '.target_value // "-"')"
  confidence="$(printf '%s' "$commitment" | jq -r '.confidence // "medium"')"
  responsible="$(printf '%s' "$commitment" | jq -r '.responsible_agency // "-"')"

  term="$(printf '%s' "$commitment" | jq -r '.source.term')"
  session_period="$(printf '%s' "$commitment" | jq -r '.source.sessionPeriod')"
  subject="$(printf '%s' "$commitment" | jq -r '.source.subject // ""' | head -c 60)"

  echo "-------------------------------------------"
  echo "${index}. [${category}] ${confidence} 信心度"
  echo ""
  echo "   📋 承諾內容："
  echo "   ${text}"
  echo ""
  echo "   📅 目標日期: ${target_date}"
  echo "   📊 目標值: ${target_value}"
  echo "   🏛️  負責機關: ${responsible}"
  echo ""
  echo "   📄 來源: 第 ${term} 屆第 ${session_period} 會期"
  echo "   ${subject}..."
}

########################################
# 主程式
########################################

# 檢查必要指令
require_cmd jq

# 解析參數
parse_args "$@"

arg_optional input INPUT_FILE "data/commitments"
arg_optional search SEARCH_TERM ""
arg_optional category CATEGORY_FILTER ""
arg_optional due-before DUE_BEFORE ""
arg_optional due-after DUE_AFTER ""
arg_optional upcoming UPCOMING_DAYS ""
arg_optional status STATUS_FILTER ""
arg_optional limit RESULT_LIMIT "20"
arg_optional format OUTPUT_FORMAT "text"

echo "========================================="
echo "政策承諾查詢系統"
echo "========================================="

# 準備輸入檔案列表
INPUT_FILES=()
if [[ -d "$INPUT_FILE" ]]; then
  while IFS= read -r -d '' f; do
    INPUT_FILES+=("$f")
  done < <(find "$INPUT_FILE" -name "*.jsonl" -print0 2>/dev/null)
elif [[ -f "$INPUT_FILE" ]]; then
  INPUT_FILES+=("$INPUT_FILE")
else
  echo "❌ 找不到輸入檔案或目錄: ${INPUT_FILE}"
  exit 1
fi

if [[ ${#INPUT_FILES[@]} -eq 0 ]]; then
  echo "❌ 找不到任何 .jsonl 檔案"
  exit 1
fi

echo "資料來源: ${#INPUT_FILES[@]} 個檔案"

# 合併所有承諾資料
ALL_COMMITMENTS="$(cat "${INPUT_FILES[@]}" 2>/dev/null | jq -s '.')"
TOTAL_COUNT="$(printf '%s' "$ALL_COMMITMENTS" | jq 'length')"

echo "總承諾數: ${TOTAL_COUNT}"
echo "========================================="
echo ""

# 建立 jq 篩選條件
JQ_FILTER="."

# 關鍵字搜尋
if [[ -n "$SEARCH_TERM" ]]; then
  echo "🔍 搜尋: ${SEARCH_TERM}"
  JQ_FILTER="${JQ_FILTER} | select(.text | test(\"${SEARCH_TERM}\"; \"i\"))"
fi

# 分類篩選
if [[ -n "$CATEGORY_FILTER" ]]; then
  echo "📁 分類: ${CATEGORY_FILTER}"
  JQ_FILTER="${JQ_FILTER} | select(.category == \"${CATEGORY_FILTER}\")"
fi

# 狀態篩選
if [[ -n "$STATUS_FILTER" ]]; then
  echo "📌 狀態: ${STATUS_FILTER}"
  JQ_FILTER="${JQ_FILTER} | select(.status == \"${STATUS_FILTER}\")"
fi

# 目標日期篩選
if [[ -n "$DUE_BEFORE" ]]; then
  echo "📅 到期日 ≤ ${DUE_BEFORE}"
  JQ_FILTER="${JQ_FILTER} | select(.target_date != null and .target_date <= \"${DUE_BEFORE}\")"
fi

if [[ -n "$DUE_AFTER" ]]; then
  echo "📅 到期日 ≥ ${DUE_AFTER}"
  JQ_FILTER="${JQ_FILTER} | select(.target_date != null and .target_date >= \"${DUE_AFTER}\")"
fi

# 即將到期篩選
if [[ -n "$UPCOMING_DAYS" ]]; then
  TODAY="$(date +%Y-%m-%d)"
  # 計算 N 天後的日期
  if date -v+${UPCOMING_DAYS}d "+%Y-%m-%d" >/dev/null 2>&1; then
    # macOS
    FUTURE_DATE="$(date -v+${UPCOMING_DAYS}d "+%Y-%m-%d")"
  else
    # Linux
    FUTURE_DATE="$(date -d "+${UPCOMING_DAYS} days" "+%Y-%m-%d")"
  fi
  echo "⏰ ${UPCOMING_DAYS} 天內到期 (${TODAY} ~ ${FUTURE_DATE})"
  JQ_FILTER="${JQ_FILTER} | select(.target_date != null and .target_date >= \"${TODAY}\" and .target_date <= \"${FUTURE_DATE}\")"
fi

echo ""

# 執行查詢
RESULTS="$(printf '%s' "$ALL_COMMITMENTS" | jq -c "[.[] | ${JQ_FILTER}] | sort_by(.target_date) | .[0:${RESULT_LIMIT}]")"
RESULT_COUNT="$(printf '%s' "$RESULTS" | jq 'length')"

if [[ "$RESULT_COUNT" -eq 0 ]]; then
  echo "ℹ️  沒有找到符合條件的承諾"
  exit 0
fi

echo "找到 ${RESULT_COUNT} 筆結果"
echo "==========================================="

if [[ "$OUTPUT_FORMAT" == "json" ]]; then
  # JSON 格式輸出
  printf '%s' "$RESULTS" | jq '.'
else
  # 文字格式輸出
  INDEX=1
  while IFS= read -r commitment; do
    format_commitment "$commitment" "$INDEX"
    INDEX=$((INDEX + 1))
  done < <(printf '%s' "$RESULTS" | jq -c '.[]')
  echo "==========================================="
fi

# 顯示分類統計
if [[ "$OUTPUT_FORMAT" != "json" ]]; then
  echo ""
  echo "📊 結果分類統計："
  printf '%s' "$RESULTS" | jq -r '.[].category' | sort | uniq -c | sort -rn
fi
