#!/usr/bin/env bash
# qdrant.sh - Qdrant vector database helper functions
# 注意：預期被其他 script 用 `.` source 進來
# 不在這裡 set -euo pipefail，交給呼叫端決定。

if [[ -n "${QDRANT_SH_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
QDRANT_SH_LOADED=1

_qdrant_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "${_qdrant_lib_dir}/core.sh"

########################################
# 初始化：Qdrant 連接資訊
########################################
qdrant_init_env() {
  # 環境變數：
  # QDRANT_URL 或 QDRANT_ENDPOINT: Qdrant 伺服器 URL (例如 https://xxx.gcp.cloud.qdrant.io:6333)
  # QDRANT_API_KEY: API key (Qdrant Cloud 需要)
  : "${QDRANT_URL:=${QDRANT_ENDPOINT:-http://localhost:6333}}"
  : "${QDRANT_API_KEY:=}"

  local err=0

  if [[ -z "${QDRANT_URL:-}" ]]; then
    echo "❌ [qdrant_init_env] 未設定 QDRANT_URL" >&2
    err=1
  fi

  # 指令檢查
  if declare -f require_cmd >/dev/null 2>&1; then
    require_cmd curl
    require_cmd jq
  else
    for cmd in curl jq; do
      if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "❌ [qdrant_init_env] 需要指令：$cmd" >&2
        err=1
      fi
    done
  fi

  return "$err"
}

########################################
# Collection 管理
########################################

# qdrant_create_collection COLLECTION_NAME VECTOR_SIZE [DISTANCE]
#
# 功能：
#   - 建立新的 collection
#
# 參數：
#   COLLECTION_NAME: collection 名稱
#   VECTOR_SIZE: 向量維度 (例如 1536 for text-embedding-3-small)
#   DISTANCE: 距離計算方式 (Cosine, Euclid, Dot) 預設 Cosine
#
# 回傳值：
#   0  = 成功或已存在
#   >0 = 失敗
qdrant_create_collection() {
  local collection_name="$1"
  local vector_size="$2"
  local distance="${3:-Cosine}"

  require_cmd curl jq || return 1

  local payload
  payload="$(
    jq -n \
      --argjson size "$vector_size" \
      --arg dist "$distance" \
      '{
        vectors: {
          size: $size,
          distance: $dist
        }
      }'
  )"

  local tmp_body http_code
  tmp_body="$(mktemp)"

  local curl_args=(
    -sS -X PUT "${QDRANT_URL%/}/collections/${collection_name}"
    -H "Content-Type: application/json"
    --data-raw "$payload"
    -w '%{http_code}' -o "$tmp_body"
  )

  if [[ -n "${QDRANT_API_KEY:-}" ]]; then
    curl_args+=( -H "api-key: ${QDRANT_API_KEY}" )
  fi

  http_code="$(curl "${curl_args[@]}" 2>/dev/null)" || {
    local rc=$?
    echo "❌ [qdrant_create_collection] curl 失敗 exit=${rc}" >&2
    rm -f "$tmp_body"
    return 1
  }

  local resp
  resp="$(cat "$tmp_body")"
  rm -f "$tmp_body"

  # HTTP 200 = 成功創建
  # HTTP 409 = Collection 已存在（也視為成功）
  if [[ "$http_code" == "200" ]] || [[ "$http_code" == "409" ]]; then
    return 0
  fi

  echo "❌ [qdrant_create_collection] HTTP=${http_code}" >&2
  if jq -e . >/dev/null 2>&1 <<<"$resp"; then
    echo "$resp" | jq -C '.' >&2
  else
    echo "$resp" >&2
  fi
  return 1
}

# qdrant_collection_exists COLLECTION_NAME
#
# 功能：
#   - 檢查 collection 是否存在
#
# 回傳值：
#   0  = 存在
#   1  = 不存在
qdrant_collection_exists() {
  local collection_name="$1"

  require_cmd curl jq || return 1

  local tmp_body http_code
  tmp_body="$(mktemp)"

  local curl_args=(
    -sS -X GET "${QDRANT_URL%/}/collections/${collection_name}"
    -w '%{http_code}' -o "$tmp_body"
  )

  if [[ -n "${QDRANT_API_KEY:-}" ]]; then
    curl_args+=( -H "api-key: ${QDRANT_API_KEY}" )
  fi

  http_code="$(curl "${curl_args[@]}" 2>/dev/null)" || {
    rm -f "$tmp_body"
    return 1
  }

  rm -f "$tmp_body"

  if [[ "$http_code" == "200" ]]; then
    return 0
  else
    return 1
  fi
}

########################################
# Points (向量點) 操作
########################################

# qdrant_upsert_point COLLECTION_NAME POINT_ID VECTOR_JSON PAYLOAD_JSON
#
# 功能：
#   - 插入或更新單一 point
#
# 參數：
#   COLLECTION_NAME: collection 名稱
#   POINT_ID: point 的唯一 ID (字串或數字)
#   VECTOR_JSON: embedding vector (JSON array of floats)
#   PAYLOAD_JSON: metadata (JSON object)
#
# 回傳值：
#   0  = 成功
#   >0 = 失敗
qdrant_upsert_point() {
  local collection_name="$1"
  local point_id="$2"
  local vector_json="$3"
  local payload_json="$4"

  require_cmd curl jq || return 1

  local max_retries=3
  local retry_delay=0.5

  local payload
  payload="$(
    printf '%s\n%s' "$vector_json" "$payload_json" | jq -sc \
      --arg id "$point_id" \
      '{
        points: [
          {
            id: $id,
            vector: .[0],
            payload: .[1]
          }
        ]
      }'
  )"

  for ((attempt=1; attempt<=max_retries; attempt++)); do
    local tmp_body http_code
    tmp_body="$(mktemp)"

    local curl_args=(
      -sS -X PUT "${QDRANT_URL%/}/collections/${collection_name}/points"
      -H "Content-Type: application/json"
      --data-raw "$payload"
      -w '%{http_code}' -o "$tmp_body"
    )

    if [[ -n "${QDRANT_API_KEY:-}" ]]; then
      curl_args+=( -H "api-key: ${QDRANT_API_KEY}" )
    fi

    http_code="$(curl "${curl_args[@]}" 2>/dev/null)"
    local curl_exit=$?

    # 如果 curl 成功
    if [[ $curl_exit -eq 0 ]]; then
      local resp
      resp="$(cat "$tmp_body")"
      rm -f "$tmp_body"

      if [[ "$http_code" == "200" ]]; then
        return 0
      fi

      # HTTP 錯誤（非網路錯誤），不重試
      echo "❌ [qdrant_upsert_point] HTTP=${http_code}" >&2
      if jq -e . >/dev/null 2>&1 <<<"$resp"; then
        echo "$resp" | jq -C '.' >&2
      else
        echo "$resp" >&2
      fi
      return 1
    fi

    # curl 失敗，判斷是否需要重試
    rm -f "$tmp_body"
    if [[ $attempt -lt $max_retries ]]; then
      echo "⚠️  [qdrant_upsert_point] curl 失敗 (exit=$curl_exit)，重試 $attempt/$max_retries..." >&2
      sleep $retry_delay
    else
      echo "❌ [qdrant_upsert_point] curl 失敗 (exit=$curl_exit)，已重試 $max_retries 次" >&2
      return 1
    fi
  done

  return 1
}

# qdrant_upsert_points_batch COLLECTION_NAME POINTS_JSON
#
# 功能：
#   - 批次插入或更新 points
#
# 參數：
#   COLLECTION_NAME: collection 名稱
#   POINTS_JSON: JSON array of points，格式：
#     [
#       {"id": "id1", "vector": [...], "payload": {...}},
#       {"id": "id2", "vector": [...], "payload": {...}}
#     ]
#
# 回傳值：
#   0  = 成功
#   >0 = 失敗
qdrant_upsert_points_batch() {
  local collection_name="$1"
  local points_json="$2"

  require_cmd curl jq || return 1

  # 使用臨時檔案避免命令行參數過長
  local tmp_payload tmp_body http_code
  tmp_payload="$(mktemp)"
  tmp_body="$(mktemp)"

  # 將 payload 寫入臨時檔案
  printf '%s' "$points_json" | jq -c '{points: .}' > "$tmp_payload"

  local curl_args=(
    -sS -X PUT "${QDRANT_URL%/}/collections/${collection_name}/points"
    -H "Content-Type: application/json"
    -d "@${tmp_payload}"
    -w '%{http_code}' -o "$tmp_body"
  )

  if [[ -n "${QDRANT_API_KEY:-}" ]]; then
    curl_args+=( -H "api-key: ${QDRANT_API_KEY}" )
  fi

  http_code="$(curl "${curl_args[@]}" 2>/dev/null)" || {
    local rc=$?
    echo "❌ [qdrant_upsert_points_batch] curl 失敗 exit=${rc}" >&2
    rm -f "$tmp_payload" "$tmp_body"
    return 1
  }

  local resp
  resp="$(cat "$tmp_body")"
  rm -f "$tmp_payload" "$tmp_body"

  if [[ "$http_code" == "200" ]]; then
    return 0
  fi

  echo "❌ [qdrant_upsert_points_batch] HTTP=${http_code}" >&2
  if jq -e . >/dev/null 2>&1 <<<"$resp"; then
    echo "$resp" | jq -C '.' >&2
  else
    echo "$resp" >&2
  fi
  return 1
}

# qdrant_point_exists COLLECTION_NAME POINT_ID
#
# 功能：
#   - 檢查 point 是否存在
#
# 回傳值：
#   0  = 存在
#   1  = 不存在
qdrant_point_exists() {
  local collection_name="$1"
  local point_id="$2"

  require_cmd curl jq || return 1

  local max_retries=3
  local retry_delay=0.5

  for ((attempt=1; attempt<=max_retries; attempt++)); do
    local tmp_body http_code
    tmp_body="$(mktemp)"

    local curl_args=(
      -sS -X GET "${QDRANT_URL%/}/collections/${collection_name}/points/${point_id}"
      -w '%{http_code}' -o "$tmp_body"
    )

    if [[ -n "${QDRANT_API_KEY:-}" ]]; then
      curl_args+=( -H "api-key: ${QDRANT_API_KEY}" )
    fi

    http_code="$(curl "${curl_args[@]}" 2>/dev/null)"
    local curl_exit=$?

    # 如果 curl 成功
    if [[ $curl_exit -eq 0 ]]; then
      local resp
      resp="$(cat "$tmp_body")"
      rm -f "$tmp_body"

      if [[ "$http_code" == "200" ]]; then
        # 檢查 result 是否為 null (point 不存在時 API 會回傳 200 但 result 為 null)
        local result
        result="$(printf '%s' "$resp" | jq -r '.result // "null"')"
        if [[ "$result" != "null" ]]; then
          return 0  # Point 存在
        fi
      fi
      return 1  # Point 不存在（HTTP 404 或 result 為 null）
    fi

    # curl 失敗，判斷是否需要重試
    rm -f "$tmp_body"
    if [[ $attempt -lt $max_retries ]]; then
      echo "⚠️  [qdrant_point_exists] curl 失敗 (exit=$curl_exit)，重試 $attempt/$max_retries..." >&2
      sleep $retry_delay
    else
      echo "❌ [qdrant_point_exists] curl 失敗 (exit=$curl_exit)，已重試 $max_retries 次" >&2
      return 1
    fi
  done

  return 1
}

########################################
# Batch Get (檢查多個 points 是否存在)
########################################

# qdrant_get_existing_ids COLLECTION_NAME IDS_JSON
#
# 功能：
#   - 批次查詢哪些 point IDs 已存在
#
# 參數：
#   COLLECTION_NAME: collection 名稱
#   IDS_JSON: JSON array of point IDs，例如 ["id1", "id2", "id3"]
#
# stdout:
#   已存在的 IDs (JSON array)，例如 ["id1", "id3"]
#
# 回傳值：
#   0  = 成功
#   >0 = 失敗
qdrant_get_existing_ids() {
  local collection_name="$1"
  local ids_json="$2"

  require_cmd curl jq || return 1

  # 使用臨時檔案避免命令行參數過長
  local tmp_payload tmp_body http_code
  tmp_payload="$(mktemp)"
  tmp_body="$(mktemp)"

  # 將 payload 寫入臨時檔案
  printf '%s' "$ids_json" | jq -c '{
    ids: .,
    with_payload: false,
    with_vector: false
  }' > "$tmp_payload"

  local curl_args=(
    -sS -X POST "${QDRANT_URL%/}/collections/${collection_name}/points"
    -H "Content-Type: application/json"
    -d "@${tmp_payload}"
    -w '%{http_code}' -o "$tmp_body"
  )

  if [[ -n "${QDRANT_API_KEY:-}" ]]; then
    curl_args+=( -H "api-key: ${QDRANT_API_KEY}" )
  fi

  http_code="$(curl "${curl_args[@]}" 2>/dev/null)" || {
    local rc=$?
    echo "❌ [qdrant_get_existing_ids] curl 失敗 exit=${rc}" >&2
    rm -f "$tmp_payload" "$tmp_body"
    return 1
  }

  local resp
  resp="$(cat "$tmp_body")"
  rm -f "$tmp_payload" "$tmp_body"

  if [[ "$http_code" != "200" ]]; then
    echo "❌ [qdrant_get_existing_ids] HTTP=${http_code}" >&2
    if jq -e . >/dev/null 2>&1 <<<"$resp"; then
      echo "$resp" | jq -C '.' >&2
    else
      echo "$resp" >&2
    fi
    return 1
  fi

  # 提取已存在的 IDs
  printf '%s' "$resp" | jq -c '[.result[].id]'
}

########################################
# Search
########################################

# qdrant_search COLLECTION_NAME VECTOR_JSON LIMIT
#
# 功能：
#   - 搜尋最相似的 points
#
# 參數：
#   COLLECTION_NAME: collection 名稱
#   VECTOR_JSON: query vector (JSON array of floats)
#   LIMIT: 回傳結果數量
#
# stdout:
#   搜尋結果 JSON (包含 id, score, payload)
#
qdrant_search() {
  local collection_name="$1"
  local vector_json="$2"
  local limit="${3:-10}"

  require_cmd curl jq || return 1

  local max_retries=3
  local retry_delay=1

  local payload
  payload="$(
    printf '%s' "$vector_json" | jq -c \
      --argjson limit "$limit" \
      '{
        vector: .,
        limit: $limit,
        with_payload: true
      }'
  )"

  for ((attempt=1; attempt<=max_retries; attempt++)); do
    local tmp_body http_code
    tmp_body="$(mktemp)"

    local curl_args=(
      -sS -X POST "${QDRANT_URL%/}/collections/${collection_name}/points/search"
      -H "Content-Type: application/json"
      --data-raw "$payload"
      -w '%{http_code}' -o "$tmp_body"
      --connect-timeout 10
      --max-time 30
    )

    if [[ -n "${QDRANT_API_KEY:-}" ]]; then
      curl_args+=( -H "api-key: ${QDRANT_API_KEY}" )
    fi

    http_code="$(curl "${curl_args[@]}" 2>/dev/null)"
    local curl_exit=$?

    if [[ $curl_exit -eq 0 ]]; then
      local resp
      resp="$(cat "$tmp_body")"
      rm -f "$tmp_body"

      if [[ "$http_code" == "200" ]]; then
        printf '%s\n' "$resp"
        return 0
      fi

      echo "❌ [qdrant_search] HTTP=${http_code}" >&2
      if jq -e . >/dev/null 2>&1 <<<"$resp"; then
        echo "$resp" | jq -C '.' >&2
      else
        echo "$resp" >&2
      fi
      return 1
    fi

    rm -f "$tmp_body"
    if [[ $attempt -lt $max_retries ]]; then
      echo "⚠️  [qdrant_search] curl 失敗 (exit=$curl_exit)，重試 $attempt/$max_retries..." >&2
      sleep $retry_delay
    else
      echo "❌ [qdrant_search] curl 失敗 (exit=$curl_exit)，已重試 $max_retries 次" >&2
      return 1
    fi
  done

  return 1
}
