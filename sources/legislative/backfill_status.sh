#!/usr/bin/env bash
# sources/legislative/backfill_status.sh - 歷史資料追蹤狀態回填
#
# Phase 1（--phase1）：日期狀態更新（免費，不需 API）
#   - 掃描所有承諾 .md，若 target_date 已過期 → 標為「已延宕」
#   - 若超過 6 個月無更新 → 標為「無更新」
#
# Phase 2（預設）：AI 交叉比對（需 OPENAI_API_KEY）
#   - 合併所有 JSONL → 按 baseId 去重
#   - 排除「產生承諾的來源文件」→ 避免自我比對
#   - 呼叫 update_status.sh 進行 AI 比對
#
# 使用方式：
#   ./sources/legislative/backfill_status.sh --phase1          # 免費日期更新
#   ./sources/legislative/backfill_status.sh --dry-run         # Phase 2 預覽
#   ./sources/legislative/backfill_status.sh                   # Phase 2 正式執行
#
# 環境變數（Phase 2）：
#   OPENAI_API_KEY: OpenAI API key

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# 載入模組
source "${ROOT_DIR}/lib/core.sh"
source "${ROOT_DIR}/lib/args.sh"

# 目錄與腳本
DATA_DIR="${ROOT_DIR}/data/daily"
COMMITMENTS_DIR="${ROOT_DIR}/docs/commitments"
UPDATE_STATUS_SCRIPT="${ROOT_DIR}/commitments/update_status.sh"
BUILD_INDEX_SCRIPT="${ROOT_DIR}/commitments/build_index.sh"

########################################
# 跨平台 sed in-place
########################################

sed_inplace() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

########################################
# Phase 1：日期狀態更新
########################################

phase1_date_update() {
  local today
  today="$(date +%Y-%m-%d)"

  local six_months_ago
  if date -v-6m "+%Y-%m-%d" >/dev/null 2>&1; then
    six_months_ago="$(date -v-6m "+%Y-%m-%d")"
  else
    six_months_ago="$(date -d "-6 months" "+%Y-%m-%d")"
  fi

  echo "========================================="
  echo "Phase 1：日期狀態更新"
  echo "========================================="
  echo "今日: ${today}"
  echo "6 個月前: ${six_months_ago}"
  echo "========================================="
  echo ""

  local updated_delayed=0
  local updated_stale=0
  local skipped=0
  local total=0

  while IFS= read -r file; do
    total=$((total + 1))

    local status target_date last_updated

    # 讀取 frontmatter
    status="$(grep "^status:" "$file" | head -1 | sed 's/^[^:]*: *//; s/"//g')"
    target_date="$(grep "^target_date:" "$file" | head -1 | sed 's/^[^:]*: *//; s/"//g')"
    last_updated="$(grep "^last_updated:" "$file" | head -1 | sed 's/^[^:]*: *//; s/"//g')"

    # 跳過已達成的
    if [[ "$status" == "已達成" ]]; then
      skipped=$((skipped + 1))
      continue
    fi

    local need_update=false
    local new_status=""
    local reason=""

    # 檢查是否已延宕
    if [[ -n "$target_date" && "$target_date" != "null" && "$target_date" < "$today" ]]; then
      if [[ "$status" != "已延宕" ]]; then
        new_status="已延宕"
        reason="目標日期 ${target_date} 已過"
        need_update=true
      fi
    # 檢查是否無更新
    elif [[ -n "$last_updated" && "$last_updated" < "$six_months_ago" ]]; then
      if [[ "$status" != "無更新" ]]; then
        new_status="無更新"
        reason="超過 6 個月無更新（最後更新: ${last_updated}）"
        need_update=true
      fi
    fi

    if [[ "$need_update" == "true" ]]; then
      if [[ "$DRY_RUN" == "true" ]]; then
        echo "[預覽] $(basename "$file"): ${status} → ${new_status}（${reason}）"
      else
        sed_inplace "s/^status: .*/status: \"${new_status}\"/" "$file"
        sed_inplace "s/^last_updated: .*/last_updated: \"${today}\"/" "$file"

        # 追加紀錄
        cat >> "$file" << EOF

### ${today} [狀態變更]
**狀態**：${status} → ${new_status}
**原因**：${reason}
EOF
        echo "$(basename "$file"): ${status} → ${new_status}"
      fi

      if [[ "$new_status" == "已延宕" ]]; then
        updated_delayed=$((updated_delayed + 1))
      else
        updated_stale=$((updated_stale + 1))
      fi
    fi
  done < <(find "$COMMITMENTS_DIR" -name "*.md" -type f)

  echo ""
  echo "========================================="
  echo "Phase 1 完成"
  echo "========================================="
  echo "掃描承諾: ${total}"
  echo "已跳過（已達成）: ${skipped}"
  echo "標為「已延宕」: ${updated_delayed}"
  echo "標為「無更新」: ${updated_stale}"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    echo "以上為預覽模式，未實際修改任何檔案"
    echo "移除 --dry-run 參數以執行修改"
  fi
  echo "========================================="
}

########################################
# Phase 2：AI 交叉比對
########################################

phase2_ai_crossref() {
  echo "========================================="
  echo "Phase 2：AI 交叉比對"
  echo "========================================="
  echo ""

  # 檢查 update_status.sh 存在
  if [[ ! -f "$UPDATE_STATUS_SCRIPT" ]]; then
    echo "找不到 update_status.sh: ${UPDATE_STATUS_SCRIPT}"
    exit 1
  fi

  # Step 1: 合併所有 JSONL 並按 baseId 去重
  echo "Step 1: 合併 JSONL 並按 baseId 去重..."

  local jsonl_files=()
  while IFS= read -r f; do
    jsonl_files+=("$f")
  done < <(find "$DATA_DIR" -name "*.jsonl" -type f | sort)

  local file_count=${#jsonl_files[@]}
  if [[ $file_count -eq 0 ]]; then
    echo "找不到任何 JSONL 檔案"
    exit 1
  fi
  echo "   來源檔案: ${file_count} 個"

  local deduped_file="/tmp/backfill_deduped_$$.jsonl"
  jq -c '.' "${jsonl_files[@]}" | \
    jq -sc '
      [.[] | . + {_baseId: (.payload.baseId // .id)}] |
      group_by(._baseId) |
      map(.[-1] | del(._baseId)) |
      .[]
    ' > "$deduped_file"

  local total_unique
  total_unique="$(wc -l < "$deduped_file" | tr -d ' ')"
  echo "   去重後文件: ${total_unique} 個"

  # Step 2: 建立排除清單（承諾來源文件的 document_id）
  echo ""
  echo "Step 2: 建立排除清單..."

  local exclude_file="/tmp/backfill_exclude_$$.txt"
  : > "$exclude_file"

  while IFS= read -r md_file; do
    sed -n '/^---$/,/^---$/p' "$md_file" | grep '^ *document_id:' | head -1 | \
      sed 's/^[^:]*: *//; s/"//g' >> "$exclude_file"
  done < <(find "$COMMITMENTS_DIR" -name "*.md" -type f 2>/dev/null)

  sort -u "$exclude_file" -o "$exclude_file"
  local exclude_count
  exclude_count="$(wc -l < "$exclude_file" | tr -d ' ')"
  echo "   排除 document_id: ${exclude_count} 個"

  # Step 3: 過濾掉來源文件
  echo ""
  echo "Step 3: 過濾來源文件..."

  local filtered_file="/tmp/backfill_filtered_$$.jsonl"
  : > "$filtered_file"

  local kept=0
  local excluded=0
  while IFS= read -r line; do
    local base_id
    base_id="$(printf '%s' "$line" | jq -r '.payload.baseId // .id')"
    if grep -qxF "$base_id" "$exclude_file"; then
      excluded=$((excluded + 1))
    else
      printf '%s\n' "$line" >> "$filtered_file"
      kept=$((kept + 1))
    fi
  done < "$deduped_file"

  echo "   保留文件: ${kept} 個"
  echo "   排除文件: ${excluded} 個（來源文件）"

  if [[ $kept -eq 0 ]]; then
    echo ""
    echo "沒有需要比對的文件"
    rm -f "$deduped_file" "$exclude_file" "$filtered_file"
    return 0
  fi

  # Checkpoint 檔案（固定路徑，可續跑）
  local checkpoint_file="${ROOT_DIR}/data/commitments/backfill_checkpoint.txt"
  mkdir -p "$(dirname "$checkpoint_file")"

  local already_done=0
  if [[ -f "$checkpoint_file" ]]; then
    already_done="$(wc -l < "$checkpoint_file" | tr -d ' ')"
  fi

  # Step 4: 執行或預覽
  echo ""
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "========================================="
    echo "Phase 2 預覽"
    echo "========================================="
    echo "將處理 ${kept} 份文件（排除 ${excluded} 份來源文件）"
    if [[ "$already_done" -gt 0 ]]; then
      echo "已完成（checkpoint）: ${already_done} 筆，將自動跳過"
    fi
    echo ""
    echo "預估 API 費用："
    local remaining=$((kept - already_done))
    [[ $remaining -lt 0 ]] && remaining=0
    echo "  剩餘文件: ~${remaining} 份"
    echo "  篩選: ~${remaining} 次呼叫"
    echo "  驗證: 視篩選結果而定"
    echo "  模型: gpt-4o-mini"
    echo ""
    echo "斷點檔案: ${checkpoint_file}"
    echo "移除 --dry-run 參數以執行（中斷後可續跑）"
    echo "========================================="
  else
    echo "Step 4: 執行 AI 比對..."
    if [[ "$already_done" -gt 0 ]]; then
      echo "   📌 斷點續跑：已處理 ${already_done} 筆"
    fi
    echo ""
    "$UPDATE_STATUS_SCRIPT" --input "$filtered_file" --checkpoint "$checkpoint_file"
  fi

  # 清理暫存（checkpoint 不刪）
  rm -f "$deduped_file" "$exclude_file" "$filtered_file"
}

########################################
# 主程式
########################################

require_cmd jq

parse_args "$@"

# 解析選項
DRY_RUN="false"
PHASE1="false"

if [[ "${ARG_dry_run:-}" == "1" ]]; then
  DRY_RUN="true"
fi

if [[ "${ARG_phase1:-}" == "1" ]]; then
  PHASE1="true"
fi

if [[ "$PHASE1" == "true" ]]; then
  phase1_date_update
else
  phase2_ai_crossref
fi
