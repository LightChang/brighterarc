#!/usr/bin/env bash
# sources/legislative/init_commitments.sh - 從立法院資料初始化承諾
#
# 功能：
#   1. 掃描所有本地 JSONL 檔案
#   2. 呼叫 commitments/extract.sh 萃取承諾
#   3. 呼叫 commitments/build_index.sh 產生索引
#
# 使用方式：
#   ./sources/legislative/init_commitments.sh
#
# 環境變數：
#   OPENAI_API_KEY: OpenAI API key

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# 載入模組
source "${ROOT_DIR}/lib/core.sh"

# 資料目錄
DATA_DIR="${ROOT_DIR}/data/daily"
EXTRACT_SCRIPT="${ROOT_DIR}/commitments/extract.sh"
BUILD_INDEX_SCRIPT="${ROOT_DIR}/commitments/build_index.sh"

########################################
# 主程式
########################################

require_cmd jq

echo "========================================="
echo "立法院資料承諾初始化"
echo "========================================="
echo "資料目錄: ${DATA_DIR}"
echo "========================================="
echo ""

# 檢查必要腳本
if [[ ! -x "$EXTRACT_SCRIPT" ]]; then
  echo "❌ 找不到萃取腳本: ${EXTRACT_SCRIPT}"
  exit 1
fi

# 取得所有 JSONL 檔案（相容 bash 3.x）
JSONL_FILES=()
while IFS= read -r f; do
  JSONL_FILES+=("$f")
done < <(find "$DATA_DIR" -name "*.jsonl" -type f | sort)

TOTAL_FILES=${#JSONL_FILES[@]}

if [[ $TOTAL_FILES -eq 0 ]]; then
  echo "❌ 找不到任何 JSONL 檔案"
  exit 1
fi

echo "📁 找到 ${TOTAL_FILES} 個 JSONL 檔案"
echo ""

# 按 baseId 去重：合併所有檔案，每個 baseId 只保留最新版本
echo "🔄 合併檔案並按 baseId 去重..."
DEDUPED_FILE="/tmp/init_commitments_deduped_$$.jsonl"
trap 'rm -f "$DEDUPED_FILE"' EXIT

# 按檔案順序（日期升序）合併，jq 按 baseId 取最後出現的（最新）
jq -c '.' "${JSONL_FILES[@]}" | \
  jq -sc '
    [.[] | . + {_baseId: (.payload.baseId // .id)}] |
    group_by(._baseId) |
    map(.[-1] | del(._baseId)) |
    .[]
  ' > "$DEDUPED_FILE"

TOTAL_UNIQUE="$(wc -l < "$DEDUPED_FILE" | tr -d ' ')"
echo "📊 去重後文件數: ${TOTAL_UNIQUE}（原始檔案共 ${TOTAL_FILES} 個）"
echo ""

# 處理去重後的單一檔案
echo "========================================="
echo "處理去重後資料"
echo "========================================="

"$EXTRACT_SCRIPT" --input "$DEDUPED_FILE" || {
  echo "⚠️  處理失敗"
}

echo ""

echo ""
echo "========================================="
echo "萃取完成，產生索引..."
echo "========================================="

# 產生索引
"$BUILD_INDEX_SCRIPT"

echo ""
echo "========================================="
echo "初始化完成"
echo "========================================="
echo "來源檔案: ${TOTAL_FILES} 個"
echo "去重後文件: ${TOTAL_UNIQUE} 個"
echo ""
echo "下一步："
echo "  1. 檢查 docs/commitments/ 下的 .md 檔案"
echo "  2. git add docs/commitments/"
echo "  3. git commit -m 'Initialize commitments from legislative data'"
echo "  4. git push"
echo "========================================="
