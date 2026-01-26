#!/usr/bin/env bash
# sources/legislative/init_commitments.sh - 從立法院資料初始化承諾
#
# 功能：
#   1. 掃描所有本地 JSONL 檔案
#   2. 呼叫 commitments/extract.sh 萃取承諾
#   3. 呼叫 commitments/build_index.sh 產生索引
#
# 使用方式：
#   ./sources/legislative/init_commitments.sh [--limit N]
#
# 環境變數：
#   OPENAI_API_KEY: OpenAI API key

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# 載入模組
source "${ROOT_DIR}/lib/core.sh"
source "${ROOT_DIR}/lib/args.sh"

# 資料目錄
DATA_DIR="${ROOT_DIR}/data/daily"
EXTRACT_SCRIPT="${ROOT_DIR}/commitments/extract.sh"
BUILD_INDEX_SCRIPT="${ROOT_DIR}/commitments/build_index.sh"

########################################
# 主程式
########################################

require_cmd jq

parse_args "$@"

arg_optional limit FILE_LIMIT "0"

echo "========================================="
echo "立法院資料承諾初始化"
echo "========================================="
echo "資料目錄: ${DATA_DIR}"
echo "檔案限制: ${FILE_LIMIT:-無限制}"
echo "========================================="
echo ""

# 檢查必要腳本
if [[ ! -x "$EXTRACT_SCRIPT" ]]; then
  echo "❌ 找不到萃取腳本: ${EXTRACT_SCRIPT}"
  exit 1
fi

# 取得所有 JSONL 檔案
mapfile -t JSONL_FILES < <(find "$DATA_DIR" -name "*.jsonl" -type f | sort)

TOTAL_FILES=${#JSONL_FILES[@]}

if [[ $TOTAL_FILES -eq 0 ]]; then
  echo "❌ 找不到任何 JSONL 檔案"
  exit 1
fi

echo "📁 找到 ${TOTAL_FILES} 個 JSONL 檔案"
echo ""

# 處理檔案
PROCESSED=0
for file in "${JSONL_FILES[@]}"; do
  # 檢查限制
  if [[ "$FILE_LIMIT" -gt 0 && "$PROCESSED" -ge "$FILE_LIMIT" ]]; then
    echo ""
    echo "✅ 已達檔案限制 ${FILE_LIMIT}"
    break
  fi

  PROCESSED=$((PROCESSED + 1))
  filename="$(basename "$file")"

  echo "========================================="
  echo "[${PROCESSED}/${TOTAL_FILES}] ${filename}"
  echo "========================================="

  # 呼叫萃取腳本
  "$EXTRACT_SCRIPT" --input "$file" || {
    echo "⚠️  處理失敗: ${file}"
    continue
  }

  echo ""
done

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
echo "處理檔案: ${PROCESSED} 個"
echo ""
echo "下一步："
echo "  1. 檢查 docs/commitments/ 下的 .md 檔案"
echo "  2. git add docs/commitments/"
echo "  3. git commit -m 'Initialize commitments from legislative data'"
echo "  4. git push"
echo "========================================="
