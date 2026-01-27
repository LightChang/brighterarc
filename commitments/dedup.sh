#!/usr/bin/env bash
# commitments/dedup.sh - 去除重複的承諾檔案
#
# 功能：
#   1. 掃描 docs/commitments/**/*.md
#   2. 按 title 完全相同分組，保留最早建立的
#   3. 按 document_id 分組，相似 title 保留最完整的
#   4. 刪除空分類目錄
#   5. 輸出報告
#
# 使用方式：
#   ./commitments/dedup.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMMITMENTS_DIR="${ROOT_DIR}/docs/commitments"

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

echo "========================================="
echo "承諾去重工具"
echo "========================================="
echo "目錄: ${COMMITMENTS_DIR}"
echo "模式: $( $DRY_RUN && echo '預覽（不刪除）' || echo '執行刪除' )"
echo "========================================="
echo ""

########################################
# 步驟 1：掃描所有 .md 並萃取 metadata
########################################

echo "🔍 掃描承諾檔案..."

METADATA_FILE="/tmp/dedup_metadata_$$.json"
trap 'rm -f "$METADATA_FILE" /tmp/dedup_*.$$.*' EXIT

# 解析 frontmatter 欄位
parse_fm() {
  local file="$1" key="$2"
  sed -n '/^---$/,/^---$/p' "$file" | grep "^${key}:" | head -1 | sed 's/^[^:]*: *//; s/"//g'
}

# 解析巢狀欄位 (source.document_id)
parse_fm_nested() {
  local file="$1" key="$2"
  sed -n '/^---$/,/^---$/p' "$file" | grep "^  ${key}:" | head -1 | sed 's/^[^:]*: *//; s/"//g'
}

# 收集所有 .md 檔案的 metadata
echo "[]" > "$METADATA_FILE"

FILE_COUNT=0
while IFS= read -r md_file; do
  title="$(parse_fm "$md_file" "title")"
  doc_id="$(parse_fm_nested "$md_file" "document_id")"
  created_at="$(parse_fm "$md_file" "created_at")"
  file_size="$(wc -c < "$md_file" | tr -d ' ')"

  # 加入 metadata
  jq --arg path "$md_file" \
     --arg title "$title" \
     --arg doc_id "$doc_id" \
     --arg created "$created_at" \
     --argjson size "$file_size" \
     '. + [{path: $path, title: $title, document_id: $doc_id, created_at: $created, size: $size}]' \
     "$METADATA_FILE" > "${METADATA_FILE}.tmp"
  mv "${METADATA_FILE}.tmp" "$METADATA_FILE"

  FILE_COUNT=$((FILE_COUNT + 1))
done < <(find "$COMMITMENTS_DIR" -name "*.md" -type f | sort)

echo "📊 總檔案數: ${FILE_COUNT}"
echo ""

if [[ "$FILE_COUNT" -eq 0 ]]; then
  echo "ℹ️  沒有找到任何承諾檔案"
  exit 0
fi

########################################
# 步驟 2：按 title 完全相同分組去重
########################################

echo "🔄 步驟 1: 完全相同 title 去重..."

# 找出重複 title 群組，保留 created_at 最早的（相同則保留第一個）
TITLE_DUPES_TO_DELETE="/tmp/dedup_title_delete_$$.json"
jq '
  group_by(.title) |
  map(select(length > 1)) |
  map(sort_by(.created_at) | .[1:]) |
  flatten
' "$METADATA_FILE" > "$TITLE_DUPES_TO_DELETE"

TITLE_DELETE_COUNT="$(jq 'length' "$TITLE_DUPES_TO_DELETE")"
echo "   找到 ${TITLE_DELETE_COUNT} 個 title 完全重複檔案"

# 執行刪除
if [[ "$TITLE_DELETE_COUNT" -gt 0 ]]; then
  while IFS= read -r path; do
    if $DRY_RUN; then
      echo "   [預覽] 將刪除: $(basename "$path")"
    else
      rm -f "$path"
      echo "   🗑️  刪除: $(basename "$path")"
    fi
  done < <(jq -r '.[].path' "$TITLE_DUPES_TO_DELETE")

  # 從 metadata 中移除已刪除的（不論 dry-run，讓後續步驟計算正確）
  DELETED_PATHS="$(jq '[.[].path]' "$TITLE_DUPES_TO_DELETE")"
  jq --argjson deleted "$DELETED_PATHS" '
    [.[] | select(.path as $p | $deleted | index($p) | not)]
  ' "$METADATA_FILE" > "${METADATA_FILE}.tmp"
  mv "${METADATA_FILE}.tmp" "$METADATA_FILE"
fi

echo ""

########################################
# 步驟 3：同 document_id 下相似 title 去重
########################################

echo "🔄 步驟 2: 同 document_id 下相似承諾去重..."

DOCID_DUPES_TO_DELETE="/tmp/dedup_docid_delete_$$.json"

# 使用 Python 進行 title 相似度比對（union-find 傳遞性聚類）
# 結合 SequenceMatcher 和字元集 Jaccard 兩種指標
# 同一 document_id 下，任一指標超門檻即視為重複
# 每個相似群組保留 size 最大的（內容最完整）
python3 - "$METADATA_FILE" "$DOCID_DUPES_TO_DELETE" << 'PYEOF'
import json, sys
from difflib import SequenceMatcher
from collections import defaultdict

with open(sys.argv[1]) as f:
    entries = json.load(f)

groups = defaultdict(list)
for e in entries:
    did = e.get("document_id", "")
    if did:
        groups[did].append(e)

class UnionFind:
    def __init__(self, n):
        self.parent = list(range(n))
    def find(self, x):
        while self.parent[x] != x:
            self.parent[x] = self.parent[self.parent[x]]
            x = self.parent[x]
        return x
    def union(self, a, b):
        a, b = self.find(a), self.find(b)
        if a != b:
            self.parent[b] = a

def char_bigram_jaccard(a, b):
    """Character bigram Jaccard similarity - better for Chinese text."""
    if len(a) < 2 or len(b) < 2:
        return 1.0 if a == b else 0.0
    sa = set(a[i:i+2] for i in range(len(a)-1))
    sb = set(b[i:i+2] for i in range(len(b)-1))
    if not sa or not sb:
        return 0.0
    return len(sa & sb) / len(sa | sb)

def is_similar(t1, t2):
    """Two titles are similar if either metric exceeds threshold."""
    seq = SequenceMatcher(None, t1, t2).ratio()
    if seq > 0.4:
        return True
    jac = char_bigram_jaccard(t1, t2)
    if jac > 0.25:
        return True
    return False

to_delete = []

for doc_id, items in groups.items():
    if len(items) <= 1:
        continue

    n = len(items)
    uf = UnionFind(n)

    for i in range(n):
        for j in range(i + 1, n):
            if is_similar(items[i]["title"], items[j]["title"]):
                uf.union(i, j)

    clusters = defaultdict(list)
    for i in range(n):
        clusters[uf.find(i)].append(items[i])

    for cluster in clusters.values():
        if len(cluster) <= 1:
            continue
        cluster.sort(key=lambda x: -x["size"])
        to_delete.extend(cluster[1:])

with open(sys.argv[2], "w") as f:
    json.dump(to_delete, f)
PYEOF

DOCID_DELETE_COUNT="$(jq 'length' "$DOCID_DUPES_TO_DELETE")"
echo "   找到 ${DOCID_DELETE_COUNT} 個同 document_id 重複檔案"

if [[ "$DOCID_DELETE_COUNT" -gt 0 ]]; then
  while IFS= read -r path; do
    if $DRY_RUN; then
      echo "   [預覽] 將刪除: $(basename "$path")"
    else
      rm -f "$path"
      echo "   🗑️  刪除: $(basename "$path")"
    fi
  done < <(jq -r '.[].path' "$DOCID_DUPES_TO_DELETE")
fi

echo ""

########################################
# 步驟 4：清理空分類目錄
########################################

echo "🧹 清理空目錄..."
EMPTY_DIR_COUNT=0
for dir in "$COMMITMENTS_DIR"/*/; do
  [[ ! -d "$dir" ]] && continue
  # 檢查目錄是否有 .md 檔案
  md_count="$(find "$dir" -maxdepth 1 -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$md_count" -eq 0 ]]; then
    if $DRY_RUN; then
      echo "   [預覽] 將刪除空目錄: $(basename "$dir")"
    else
      rmdir "$dir" 2>/dev/null && echo "   🗑️  刪除空目錄: $(basename "$dir")"
    fi
    EMPTY_DIR_COUNT=$((EMPTY_DIR_COUNT + 1))
  fi
done
echo "   空目錄: ${EMPTY_DIR_COUNT} 個"
echo ""

########################################
# 步驟 5：報告
########################################

TOTAL_DELETED=$((TITLE_DELETE_COUNT + DOCID_DELETE_COUNT))
REMAINING=$((FILE_COUNT - TOTAL_DELETED))

echo "========================================="
echo "去重報告"
echo "========================================="
echo "原始檔案數: ${FILE_COUNT}"
echo "title 完全重複刪除: ${TITLE_DELETE_COUNT}"
echo "同 document_id 重複刪除: ${DOCID_DELETE_COUNT}"
echo "總計刪除: ${TOTAL_DELETED}"
echo "保留檔案: ${REMAINING}"
echo "清理空目錄: ${EMPTY_DIR_COUNT}"
echo "========================================="

if $DRY_RUN; then
  echo ""
  echo "⚠️  以上為預覽模式，未實際刪除任何檔案"
  echo "   移除 --dry-run 參數以執行刪除"
fi
