#!/usr/bin/env bash
# update_legislative_qdrant.sh - 上傳 JSONL 資料到 Qdrant
#
# 功能：
#   1. 讀取 JSONL 檔案（支援 .jsonl 和 .jsonl.gz）
#   2. 自動建立 Collection（如不存在）
#   3. 批次上傳到 Qdrant
#   4. 顯示進度
#
# 使用方式：
#   ./update_legislative_qdrant.sh --input FILE [--collection NAME] [--batch-size N] [--skip-existing]
#
# 環境變數：
#   QDRANT_URL: Qdrant 伺服器 URL
#   QDRANT_API_KEY: Qdrant API key (Cloud 版需要)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# 載入模組
source "${ROOT_DIR}/lib/core.sh"
source "${ROOT_DIR}/lib/args.sh"
source "${ROOT_DIR}/lib/qdrant.sh"

# 檢查必要指令
require_cmd curl jq

########################################
# 解析參數
########################################
parse_args "$@"

arg_required input INPUT_FILE "輸入檔案路徑"
arg_optional collection COLLECTION_NAME "legislative_replies"
arg_optional batch-size BATCH_SIZE "100"

# 處理 flag（如果有 --skip-existing 會設為 "1"）
SKIP_EXISTING="${ARG_skip_existing:-false}"

echo "========================================="
echo "上傳資料到 Qdrant"
echo "========================================="
echo "輸入檔案: ${INPUT_FILE}"
echo "Collection: ${COLLECTION_NAME}"
echo "批次大小: ${BATCH_SIZE}"
echo "跳過已存在: ${SKIP_EXISTING}"
echo "========================================="
echo ""

########################################
# 初始化
########################################
echo "🔧 初始化環境..."

qdrant_init_env || {
  echo "❌ Qdrant 環境初始化失敗"
  exit 1
}

echo "✅ 環境初始化完成"
echo ""

########################################
# 檢查輸入檔案
########################################
if [[ ! -f "$INPUT_FILE" ]]; then
  echo "❌ 輸入檔案不存在：${INPUT_FILE}"
  exit 1
fi

# 建立臨時目錄用於解壓縮
TMP_DIR="$(mktemp -d)"
trap "rm -rf '$TMP_DIR'" EXIT

# 如果是 .gz 檔案，解壓縮
WORKING_FILE="$INPUT_FILE"
if [[ "$INPUT_FILE" == *.gz ]]; then
  echo "📦 解壓縮檔案..."
  WORKING_FILE="${TMP_DIR}/data.jsonl"
  gunzip -c "$INPUT_FILE" > "$WORKING_FILE"
  echo "✅ 解壓縮完成"
  echo ""
fi

########################################
# 讀取並分析資料
########################################
echo "📊 分析資料檔案..."

# 計算總筆數
TOTAL_POINTS="$(wc -l < "$WORKING_FILE" | tr -d ' ')"
echo "總 points: ${TOTAL_POINTS}"

# 讀取第一筆資料以判斷 vector_size
FIRST_POINT="$(head -n 1 "$WORKING_FILE")"
VECTOR_SIZE="$(printf '%s' "$FIRST_POINT" | jq '.vector | length')"
echo "Vector 維度: ${VECTOR_SIZE}"

echo ""

########################################
# 檢查並建立 Collection
########################################
echo "🗂️  檢查 Qdrant collection..."

if ! qdrant_collection_exists "$COLLECTION_NAME"; then
  echo "⚠️  Collection 不存在，建立中..."
  if qdrant_create_collection "$COLLECTION_NAME" "$VECTOR_SIZE" "Cosine"; then
    echo "✅ Collection 建立成功"
  else
    echo "❌ Collection 建立失敗"
    exit 1
  fi
else
  echo "✅ Collection 已存在"
fi
echo ""

########################################
# 批次上傳
########################################
echo "📤 開始上傳資料..."

UPLOADED_COUNT=0
SKIPPED_COUNT=0
ERROR_COUNT=0
BATCH_NUM=0

# 建立臨時批次檔案
BATCH_FILE="${TMP_DIR}/batch.json"

# 處理函式：上傳一個批次（會先檢查已存在的 IDs）
upload_batch() {
  local batch_file="$1"
  local batch_count
  batch_count="$(wc -l < "$batch_file" | tr -d ' ')"

  if [[ $batch_count -eq 0 ]]; then
    return 0
  fi

  BATCH_NUM=$((BATCH_NUM + 1))
  echo ""
  echo "📦 處理批次 #${BATCH_NUM} (${batch_count} points)..."

  # 組合成 JSON array
  local batch_json
  batch_json="$(jq -s '.' < "$batch_file")"

  # 如果設定跳過已存在的點，批次查詢已存在的 IDs
  if [[ "$SKIP_EXISTING" == "1" ]]; then
    # 提取所有 IDs
    local all_ids
    all_ids="$(printf '%s' "$batch_json" | jq -c '[.[].id]')"

    # 批次查詢已存在的 IDs
    local existing_ids
    if existing_ids="$(qdrant_get_existing_ids "$COLLECTION_NAME" "$all_ids" 2>/dev/null)"; then
      local existing_count
      existing_count="$(printf '%s' "$existing_ids" | jq 'length')"

      if [[ $existing_count -gt 0 ]]; then
        echo "⏭️  發現 ${existing_count} 筆已存在，過濾中..."
        SKIPPED_COUNT=$((SKIPPED_COUNT + existing_count))

        # 過濾掉已存在的 points
        batch_json="$(printf '%s\n%s' "$batch_json" "$existing_ids" | jq -sc '
          .[0] as $points |
          .[1] as $existing |
          $points | map(select(.id as $id | $existing | index($id) | not))
        ')"

        batch_count="$(printf '%s' "$batch_json" | jq 'length')"
        echo "📝 剩餘 ${batch_count} 筆需要上傳"
      fi
    else
      echo "⚠️  批次查詢已存在 IDs 失敗，直接上傳全部"
    fi
  fi

  # 如果過濾後沒有資料需要上傳
  if [[ $batch_count -eq 0 ]] || [[ "$(printf '%s' "$batch_json" | jq 'length')" -eq 0 ]]; then
    echo "✅ 批次 #${BATCH_NUM} 全部已存在，跳過"
    return 0
  fi

  # 上傳批次
  if qdrant_upsert_points_batch "$COLLECTION_NAME" "$batch_json"; then
    local uploaded
    uploaded="$(printf '%s' "$batch_json" | jq 'length')"
    echo "✅ 批次 #${BATCH_NUM} 上傳成功 (${uploaded} points)"
    UPLOADED_COUNT=$((UPLOADED_COUNT + uploaded))
  else
    echo "❌ 批次 #${BATCH_NUM} 上傳失敗"
    local failed
    failed="$(printf '%s' "$batch_json" | jq 'length')"
    ERROR_COUNT=$((ERROR_COUNT + failed))
  fi

  # 顯示進度
  local total_processed=$((UPLOADED_COUNT + SKIPPED_COUNT + ERROR_COUNT))
  local progress_pct=$((total_processed * 100 / TOTAL_POINTS))
  echo "進度: ${total_processed}/${TOTAL_POINTS} (${progress_pct}%)"
}

# 處理每一筆資料
while IFS= read -r line; do
  # 將此筆加入批次
  echo "$line" >> "$BATCH_FILE"

  # 當批次達到指定大小時，上傳
  BATCH_COUNT="$(wc -l < "$BATCH_FILE" | tr -d ' ')"
  if [[ $BATCH_COUNT -ge $BATCH_SIZE ]]; then
    upload_batch "$BATCH_FILE"
    # 清空批次檔案
    > "$BATCH_FILE"
  fi
done < "$WORKING_FILE"

# 處理最後一個不滿批次的資料
if [[ -s "$BATCH_FILE" ]]; then
  upload_batch "$BATCH_FILE"
fi

echo ""
echo "========================================="
echo "上傳完成"
echo "========================================="
echo "總 points: ${TOTAL_POINTS}"
echo "已上傳: ${UPLOADED_COUNT}"
echo "已跳過: ${SKIPPED_COUNT}"
echo "失敗: ${ERROR_COUNT}"
echo "========================================="

# 如果有錯誤，以非零狀態退出
if [[ $ERROR_COUNT -gt 0 ]]; then
  exit 1
fi
