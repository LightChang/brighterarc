#!/usr/bin/env bash
# build_legislative_release.sh - 建立/更新月度 GitHub Release
#
# 功能：
#   1. 判斷當前月份（YYYYMM）
#   2. 下載現有 Release legislative_YYYYMM.jsonl.gz（如存在）
#   3. 合併今天的資料 data/daily/YYYY-MM-DD.jsonl
#   4. 去重（同 ID 保留最新）
#   5. 壓縮
#   6. 更新/創建 GitHub Release
#
# 使用方式：
#   ./build_legislative_release.sh [--input FILE] [--month YYYYMM]
#
# 環境變數：
#   GITHUB_TOKEN: GitHub Personal Access Token (通常由 GitHub Actions 自動提供)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR"

# 載入模組
source "${SCRIPT_DIR}/lib/core.sh"
source "${SCRIPT_DIR}/lib/args.sh"

# 檢查必要指令
require_cmd jq gh gzip

########################################
# 解析參數
########################################
parse_args "$@"

arg_optional input INPUT_FILE "data/daily/$(date +%Y-%m-%d).jsonl"
arg_optional month TARGET_MONTH "$(date +%Y%m)"

RELEASE_TAG="data-v${TARGET_MONTH}"
RELEASE_FILE="legislative_${TARGET_MONTH}.jsonl"
RELEASE_FILE_GZ="${RELEASE_FILE}.gz"

echo "========================================="
echo "建立/更新月度 Release"
echo "========================================="
echo "目標月份: ${TARGET_MONTH}"
echo "Release Tag: ${RELEASE_TAG}"
echo "輸入檔案: ${INPUT_FILE}"
echo "Release 檔案: ${RELEASE_FILE_GZ}"
echo "========================================="
echo ""

########################################
# 檢查輸入檔案
########################################
if [[ ! -f "$INPUT_FILE" ]]; then
  echo "❌ 輸入檔案不存在：${INPUT_FILE}"
  exit 1
fi

# 轉換為絕對路徑（cd 到臨時目錄後仍可存取）
INPUT_FILE="$(cd "$(dirname "$INPUT_FILE")" && pwd)/$(basename "$INPUT_FILE")"

# 建立臨時目錄
TMP_DIR="$(mktemp -d)"
trap "rm -rf '$TMP_DIR'" EXIT

cd "$TMP_DIR"

########################################
# 下載現有 Release（如果存在）
########################################
echo "📥 檢查現有 Release..."

EXISTING_FILE=""
if gh release view "$RELEASE_TAG" >/dev/null 2>&1; then
  echo "✅ Release ${RELEASE_TAG} 已存在，下載中..."

  if gh release download "$RELEASE_TAG" -p "$RELEASE_FILE_GZ" 2>/dev/null; then
    echo "✅ 下載成功"

    # 解壓縮
    echo "📦 解壓縮現有資料..."
    gunzip -f "$RELEASE_FILE_GZ" || {
      echo "⚠️  解壓縮失敗，視為空檔案"
      > "$RELEASE_FILE"
    }

    EXISTING_FILE="$RELEASE_FILE"
    EXISTING_COUNT="$(wc -l < "$EXISTING_FILE" | tr -d ' ')"
    echo "✅ 現有資料：${EXISTING_COUNT} points"
  else
    echo "⚠️  下載失敗，視為新 Release"
  fi
else
  echo "ℹ️  Release ${RELEASE_TAG} 不存在，將建立新 Release"
fi

echo ""

########################################
# 合併與去重
########################################
echo "🔄 合併新資料..."

NEW_COUNT="$(wc -l < "$INPUT_FILE" | tr -d ' ')"
echo "新資料：${NEW_COUNT} points"

if [[ -n "$EXISTING_FILE" && -f "$EXISTING_FILE" ]]; then
  # 合併現有資料與新資料
  echo "🔀 合併並去重..."

  cat "$EXISTING_FILE" "$INPUT_FILE" | \
    jq -s '
      # 將所有 points 組成陣列
      flatten |
      # 依照 ID 分組
      group_by(.id) |
      # 每個 ID 群組保留 payload 最新的（如果有 updated 欄位）
      # 否則保留最後一筆
      map(
        if (.[0].payload.updated // null) != null then
          max_by(.payload.updated // "")
        else
          .[-1]
        end
      ) |
      # 輸出為行分隔的 JSON
      .[]
    ' -c > "${RELEASE_FILE}.new"

  mv "${RELEASE_FILE}.new" "$RELEASE_FILE"
else
  # 沒有現有資料，直接使用新資料
  echo "📄 使用新資料..."
  cp "$INPUT_FILE" "$RELEASE_FILE"
fi

FINAL_COUNT="$(wc -l < "$RELEASE_FILE" | tr -d ' ')"
echo "✅ 合併後：${FINAL_COUNT} points"

echo ""

########################################
# 壓縮
########################################
echo "📦 壓縮資料..."

gzip -f "$RELEASE_FILE"

COMPRESSED_SIZE="$(du -h "$RELEASE_FILE_GZ" | awk '{print $1}')"
echo "✅ 壓縮完成：${COMPRESSED_SIZE}"

echo ""

########################################
# 更新/建立 Release
########################################
echo "🚀 更新 GitHub Release..."

# 切換回 repo 目錄（gh 需要 git repo）
cd "$REPO_DIR"

# 複製壓縮檔到 repo 目錄
cp "${TMP_DIR}/${RELEASE_FILE_GZ}" "./${RELEASE_FILE_GZ}"

# 準備 Release 說明
RELEASE_YEAR="${TARGET_MONTH:0:4}"
RELEASE_MONTH="${TARGET_MONTH:4:2}"
RELEASE_NOTES="# 立法院資料 ${RELEASE_YEAR}-${RELEASE_MONTH}

本 Release 包含 ${RELEASE_YEAR} 年 ${RELEASE_MONTH} 月的立法院行政院答復資料及預先計算的 embeddings。

## 統計資訊

- **總 points**: ${FINAL_COUNT}
- **檔案大小**: ${COMPRESSED_SIZE}
- **最後更新**: $(date +%Y-%m-%d)
- **Embedding Model**: text-embedding-3-small (1536 維度)

## 使用方式

\`\`\`bash
# 1. 下載檔案
gh release download ${RELEASE_TAG} -p \"${RELEASE_FILE_GZ}\"

# 2. 上傳到 Qdrant
./update_legislative_qdrant.sh --input ${RELEASE_FILE_GZ}
\`\`\`

---

🤖 由 GitHub Actions 自動更新
"

if gh release view "$RELEASE_TAG" >/dev/null 2>&1; then
  # Release 已存在，更新檔案
  echo "♻️  更新現有 Release ${RELEASE_TAG}..."

  # 先刪除舊檔案（如果存在）
  gh release delete-asset "$RELEASE_TAG" "$RELEASE_FILE_GZ" -y 2>/dev/null || true

  # 上傳新檔案
  gh release upload "$RELEASE_TAG" "$RELEASE_FILE_GZ" --clobber

  # 更新 Release notes
  echo "$RELEASE_NOTES" | gh release edit "$RELEASE_TAG" -F -

  echo "✅ Release 更新成功"
else
  # Release 不存在，建立新 Release
  echo "🆕 建立新 Release ${RELEASE_TAG}..."

  echo "$RELEASE_NOTES" | gh release create "$RELEASE_TAG" \
    --title "立法院資料 ${RELEASE_YEAR}-${RELEASE_MONTH}" \
    -F - \
    "$RELEASE_FILE_GZ"

  echo "✅ Release 建立成功"
fi

# 清理複製的檔案
rm -f "./${RELEASE_FILE_GZ}"

echo ""
echo "========================================="
echo "Release 更新完成"
echo "========================================="
echo "Release Tag: ${RELEASE_TAG}"
REPO_NAME="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo "LightChang/brighterarc")"
echo "Release URL: https://github.com/${REPO_NAME}/releases/tag/${RELEASE_TAG}"
echo "========================================="
