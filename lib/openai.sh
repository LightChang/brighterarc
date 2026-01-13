#!/usr/bin/env bash
# openai.sh - OpenAI API helper functions (embeddings, etc.)
# 注意：預期被其他 script 用 `.` source 進來
# 不在這裡 set -euo pipefail，交給呼叫端決定。

if [[ -n "${OPENAI_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
OPENAI_SH_LOADED=1

_openai_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${_openai_lib_dir}/core.sh"

########################################
# 初始化：API key / base URL
########################################
openai_init_env() {
  # 優先順序：
  # 1) OPENAI_* 環境變數
  # 2) chatgpt.sh 已設定的 CHATGPT_*
  : "${OPENAI_API_KEY:=${CHATGPT_API_KEY:-}}"
  : "${OPENAI_BASE_URL:=${CHATGPT_BASE_URL:-https://api.openai.com/v1}}"

  local err=0

  if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    echo "❌ [openai_init_env] 未設定 OPENAI_API_KEY" >&2
    err=1
  fi

  # 指令檢查
  if declare -f require_cmd >/dev/null 2>&1; then
    require_cmd curl
    require_cmd jq
  else
    for cmd in curl jq; do
      if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "❌ [openai_init_env] 需要指令：$cmd" >&2
        err=1
      fi
    done
  fi

  return "$err"
}

########################################
# Embeddings API
########################################

# openai_create_embedding MODEL INPUT_TEXT
#
# 功能：
#   - 呼叫 OpenAI embeddings API
#   - 回傳 embedding vector (JSON array)
#
# 參數：
#   MODEL: embedding 模型名稱 (如 text-embedding-3-small)
#   INPUT_TEXT: 要 embedding 的文字
#
# stdout:
#   JSON array of floats (embedding vector)
#
# 回傳值：
#   0  = 成功
#   >0 = 失敗
openai_create_embedding() {
  local model="$1"
  local input_text="$2"

  require_cmd curl jq || return 1

  local payload
  payload="$(
    jq -n \
      --arg model "$model" \
      --arg input "$input_text" \
      '{
        model: $model,
        input: $input
      }'
  )"

  local tmp_body http_code
  tmp_body="$(mktemp)"

  local curl_args=(
    -sS -X POST "${OPENAI_BASE_URL%/}/embeddings"
    -H "Content-Type: application/json"
    -H "Authorization: Bearer ${OPENAI_API_KEY}"
    --data-raw "$payload"
    -w '%{http_code}' -o "$tmp_body"
  )

  http_code="$(curl "${curl_args[@]}" 2>/dev/null)" || {
    local rc=$?
    echo "❌ [openai_create_embedding] curl 失敗 exit=${rc}" >&2
    rm -f "$tmp_body"
    return 1
  }

  local resp
  resp="$(cat "$tmp_body")"
  rm -f "$tmp_body"

  if [[ "$http_code" != "200" ]]; then
    echo "❌ [openai_create_embedding] HTTP=${http_code}" >&2
    if jq -e . >/dev/null 2>&1 <<<"$resp"; then
      echo "$resp" | jq -C '.' >&2
    else
      echo "$resp" >&2
    fi
    return 1
  fi

  # 提取 embedding vector
  local embedding
  embedding="$(printf '%s' "$resp" | jq '.data[0].embedding')" || return 1

  if [[ -z "$embedding" || "$embedding" == "null" ]]; then
    echo "❌ [openai_create_embedding] 無法提取 embedding" >&2
    return 1
  fi

  printf '%s\n' "$embedding"
}

# openai_create_embedding_batch MODEL INPUT_ARRAY_JSON
#
# 功能：
#   - 批次呼叫 OpenAI embeddings API
#   - INPUT_ARRAY_JSON 是 JSON array of strings
#   - 回傳 JSON array of embedding vectors
#
# 參數：
#   MODEL: embedding 模型名稱
#   INPUT_ARRAY_JSON: JSON array，例如 ["text1", "text2"]
#
# stdout:
#   JSON array of embedding arrays
#
openai_create_embedding_batch() {
  local model="$1"
  local input_array="$2"

  require_cmd curl jq || return 1

  local payload
  payload="$(
    printf '%s' "$input_array" | jq -c \
      --arg model "$model" \
      '{
        model: $model,
        input: .
      }'
  )"

  local tmp_body http_code
  tmp_body="$(mktemp)"

  local curl_args=(
    -sS -X POST "${OPENAI_BASE_URL%/}/embeddings"
    -H "Content-Type: application/json"
    -H "Authorization: Bearer ${OPENAI_API_KEY}"
    --data-raw "$payload"
    -w '%{http_code}' -o "$tmp_body"
  )

  http_code="$(curl "${curl_args[@]}" 2>/dev/null)" || {
    local rc=$?
    echo "❌ [openai_create_embedding_batch] curl 失敗 exit=${rc}" >&2
    rm -f "$tmp_body"
    return 1
  }

  local resp
  resp="$(cat "$tmp_body")"
  rm -f "$tmp_body"

  if [[ "$http_code" != "200" ]]; then
    echo "❌ [openai_create_embedding_batch] HTTP=${http_code}" >&2
    if jq -e . >/dev/null 2>&1 <<<"$resp"; then
      echo "$resp" | jq -C '.' >&2
    else
      echo "$resp" >&2
    fi
    return 1
  fi

  # 提取所有 embedding vectors
  local embeddings
  embeddings="$(printf '%s' "$resp" | jq '[.data[] | .embedding]')" || return 1

  if [[ -z "$embeddings" || "$embeddings" == "null" ]]; then
    echo "❌ [openai_create_embedding_batch] 無法提取 embeddings" >&2
    return 1
  fi

  printf '%s\n' "$embeddings"
}
