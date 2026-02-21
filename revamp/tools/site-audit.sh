#!/bin/bash

# =============================================================================
# Site Audit Tool (Local) - 網站健檢工具（本地版）
# 用途：使用本地 Lighthouse + 各種 API 進行網站健檢
# 依賴：Node.js, Chrome/Chromium, curl, jq
# =============================================================================

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# -----------------------------------------------------------------------------
# 使用說明
# -----------------------------------------------------------------------------
usage() {
    echo "Usage: $0 <URL> [OPTIONS]"
    echo ""
    echo "使用本地 Lighthouse + 各種 API 進行網站健檢"
    echo ""
    echo "Options:"
    echo "  --all           執行所有檢測（預設）"
    echo "  --lighthouse    只執行 Lighthouse 檢測"
    echo "  --security      只執行安全性檢測（Observatory, SSL, Headers）"
    echo "  --seo           只執行 SEO 檢測（HTML 驗證, robots, sitemap）"
    echo "  --output FILE   輸出到檔案（JSON 格式）"
    echo "  --help          顯示此說明"
    echo ""
    echo "Examples:"
    echo "  $0 https://example.com"
    echo "  $0 https://example.com --lighthouse"
    echo "  $0 https://example.com --all --output report.json"
    exit 1
}

# -----------------------------------------------------------------------------
# 檢查依賴
# -----------------------------------------------------------------------------
check_dependencies() {
    local missing=()

    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi

    if ! command -v jq &> /dev/null; then
        missing+=("jq")
    fi

    if ! command -v npx &> /dev/null; then
        missing+=("npx (Node.js)")
    fi

    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${RED}錯誤：缺少必要工具: ${missing[*]}${NC}"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# 解析 URL
# -----------------------------------------------------------------------------
parse_url() {
    local url=$1
    DOMAIN=$(echo "$url" | sed -E 's|^https?://||' | sed -E 's|/.*$||')
    if [[ ! "$url" =~ ^https?:// ]]; then
        URL="https://$url"
    else
        URL="$url"
    fi
}

# -----------------------------------------------------------------------------
# Lighthouse 本地檢測
# -----------------------------------------------------------------------------
check_lighthouse() {
    echo -e "${BLUE}[Lighthouse 本地檢測]${NC} 執行中（約 30-60 秒）..." >&2

    local temp_file=$(mktemp)

    npx lighthouse "$URL" \
        --output=json \
        --output-path="$temp_file" \
        --chrome-flags="--headless --no-sandbox --disable-gpu" \
        --only-categories=performance,accessibility,seo,best-practices \
        --quiet 2>/dev/null

    if [ -s "$temp_file" ]; then
        local result=$(jq '{
            performance: ((.categories.performance.score // 0) * 100 | floor),
            seo: ((.categories.seo.score // 0) * 100 | floor),
            accessibility: ((.categories.accessibility.score // 0) * 100 | floor),
            bestPractices: ((.categories["best-practices"].score // 0) * 100 | floor),
            fcp: .audits["first-contentful-paint"].displayValue,
            lcp: .audits["largest-contentful-paint"].displayValue,
            cls: .audits["cumulative-layout-shift"].displayValue,
            tbt: .audits["total-blocking-time"].displayValue,
            speedIndex: .audits["speed-index"].displayValue,
            tti: .audits["interactive"].displayValue
        }' "$temp_file" 2>/dev/null)

        rm -f "$temp_file"

        if [ -n "$result" ]; then
            echo "$result"
        else
            echo '{"error": "Lighthouse 解析失敗"}'
        fi
    else
        rm -f "$temp_file"
        echo '{"error": "Lighthouse 執行失敗"}'
    fi
}

# -----------------------------------------------------------------------------
# Mozilla Observatory
# -----------------------------------------------------------------------------
check_observatory() {
    echo -e "${BLUE}[Mozilla Observatory]${NC} 檢測中..." >&2

    local scan=$(curl -s -X POST "https://http-observatory.security.mozilla.org/api/v1/analyze?host=${DOMAIN}&rescan=true" 2>/dev/null)

    if [ -z "$scan" ]; then
        echo '{"error": "Observatory 請求失敗"}'
        return
    fi

    # 檢查是否是 HTML 錯誤頁面
    if echo "$scan" | grep -q "<html>"; then
        echo '{"error": "Observatory API 暫時不可用"}'
        return
    fi

    local state=$(echo "$scan" | jq -r '.state // "unknown"' 2>/dev/null)

    if [ "$state" = "PENDING" ] || [ "$state" = "RUNNING" ]; then
        echo -e "  掃描進行中，等待結果..." >&2
        sleep 5
        scan=$(curl -s "https://http-observatory.security.mozilla.org/api/v1/analyze?host=${DOMAIN}" 2>/dev/null)
    fi

    local result=$(echo "$scan" | jq '{
        grade: (.grade // "N/A"),
        score: (.score // 0),
        state: (.state // "N/A"),
        tests_passed: (.tests_passed // 0),
        tests_failed: (.tests_failed // 0)
    }' 2>/dev/null)

    if [ -n "$result" ]; then
        echo "$result"
    else
        echo '{"error": "Observatory 解析失敗"}'
    fi
}

# -----------------------------------------------------------------------------
# SSL Labs
# -----------------------------------------------------------------------------
check_ssl() {
    echo -e "${BLUE}[SSL Labs]${NC} 檢測中..." >&2

    local response=$(curl -s "https://api.ssllabs.com/api/v3/analyze?host=${DOMAIN}&fromCache=on&maxAge=24" 2>/dev/null)

    if [ -z "$response" ]; then
        echo '{"error": "SSL Labs 請求失敗"}'
        return
    fi

    local status=$(echo "$response" | jq -r '.status // "unknown"' 2>/dev/null)

    if [ "$status" = "IN_PROGRESS" ] || [ "$status" = "DNS" ]; then
        echo '{"status": "IN_PROGRESS", "message": "SSL 掃描進行中，請稍後重試"}'
    else
        local result=$(echo "$response" | jq '{
            status: (.status // "N/A"),
            grade: (.endpoints[0].grade // "N/A"),
            hasWarnings: (.endpoints[0].hasWarnings // false)
        }' 2>/dev/null)

        if [ -n "$result" ]; then
            echo "$result"
        else
            echo '{"error": "SSL Labs 解析失敗"}'
        fi
    fi
}

# -----------------------------------------------------------------------------
# HTTP Headers
# -----------------------------------------------------------------------------
check_headers() {
    echo -e "${BLUE}[HTTP Headers]${NC} 檢測中..." >&2

    # 過濾掉回車符
    local headers=$(curl -sI "${URL}" 2>/dev/null | tr -d '\r' | head -20)

    if [ -n "$headers" ]; then
        local has_hsts=$(echo "$headers" | grep -qi "strict-transport-security" && echo "true" || echo "false")
        local has_xframe=$(echo "$headers" | grep -qi "x-frame-options" && echo "true" || echo "false")
        local has_xcontent=$(echo "$headers" | grep -qi "x-content-type-options" && echo "true" || echo "false")
        local has_csp=$(echo "$headers" | grep -qi "content-security-policy" && echo "true" || echo "false")
        local server=$(echo "$headers" | grep -i "^server:" | cut -d: -f2- | tr -d '\r\n' | xargs 2>/dev/null || echo "N/A")

        cat <<EOF
{
    "hasHSTS": $has_hsts,
    "hasXFrameOptions": $has_xframe,
    "hasXContentTypeOptions": $has_xcontent,
    "hasCSP": $has_csp,
    "server": "$server"
}
EOF
    else
        echo '{"error": "無法取得 Headers"}'
    fi
}

# -----------------------------------------------------------------------------
# W3C HTML Validator
# -----------------------------------------------------------------------------
check_html() {
    echo -e "${BLUE}[W3C Validator]${NC} 檢測中..." >&2

    local response=$(curl -s "https://validator.w3.org/nu/?doc=${URL}&out=json" 2>/dev/null)

    if [ -z "$response" ]; then
        echo '{"error": "W3C 請求失敗"}'
        return
    fi

    local result=$(echo "$response" | jq '{
        errorCount: ([.messages[] | select(.type=="error")] | length),
        warningCount: ([.messages[] | select(.type=="info" and .subType=="warning")] | length),
        firstErrors: [.messages[] | select(.type=="error") | .message][:3]
    }' 2>/dev/null)

    if [ -n "$result" ]; then
        echo "$result"
    else
        echo '{"error": "W3C 解析失敗"}'
    fi
}

# -----------------------------------------------------------------------------
# SEO Files
# -----------------------------------------------------------------------------
check_seo_files() {
    echo -e "${BLUE}[SEO Files]${NC} 檢測中..." >&2

    local robots_status=$(curl -sI "${URL}/robots.txt" 2>/dev/null | head -1 | grep -oE "[0-9]{3}" | head -1 || echo "000")
    local has_robots=$([ "$robots_status" = "200" ] && echo "true" || echo "false")

    local sitemap_status=$(curl -sI "${URL}/sitemap.xml" 2>/dev/null | head -1 | grep -oE "[0-9]{3}" | head -1 || echo "000")
    local has_sitemap=$([ "$sitemap_status" = "200" ] && echo "true" || echo "false")

    local sitemap_count=0
    if [ "$has_sitemap" = "true" ]; then
        sitemap_count=$(curl -s "${URL}/sitemap.xml" 2>/dev/null | grep -c "<loc>" || echo "0")
    fi

    cat <<EOF
{
    "hasRobotsTxt": $has_robots,
    "hasSitemap": $has_sitemap,
    "sitemapUrlCount": $sitemap_count
}
EOF
}

# -----------------------------------------------------------------------------
# 主程式
# -----------------------------------------------------------------------------
main() {
    local run_all=true
    local run_lighthouse=false
    local run_security=false
    local run_seo=false
    local output_file=""
    local url=""

    while [ $# -gt 0 ]; do
        case $1 in
            --all) run_all=true; shift ;;
            --lighthouse) run_all=false; run_lighthouse=true; shift ;;
            --security) run_all=false; run_security=true; shift ;;
            --seo) run_all=false; run_seo=true; shift ;;
            --output) output_file="$2"; shift 2 ;;
            --help) usage ;;
            -*) echo -e "${RED}未知選項: $1${NC}"; usage ;;
            *) url="$1"; shift ;;
        esac
    done

    if [ -z "$url" ]; then
        echo -e "${RED}錯誤：請提供 URL${NC}"
        usage
    fi

    check_dependencies
    parse_url "$url"

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}網站健檢報告（本地版）${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "URL: ${URL}"
    echo -e "Domain: ${DOMAIN}"
    echo -e "時間: $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${GREEN}========================================${NC}"
    echo ""

    local results="{"
    results+="\"url\": \"${URL}\","
    results+="\"domain\": \"${DOMAIN}\","
    results+="\"timestamp\": \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\","

    if [ "$run_all" = true ] || [ "$run_lighthouse" = true ]; then
        echo ""
        echo -e "${YELLOW}=== Lighthouse 檢測 ===${NC}"
        local lighthouse_result=$(check_lighthouse)
        echo "$lighthouse_result" | jq .
        results+="\"lighthouse\": ${lighthouse_result},"
    fi

    if [ "$run_all" = true ] || [ "$run_security" = true ]; then
        echo ""
        echo -e "${YELLOW}=== 安全性檢測 ===${NC}"

        echo ""
        local observatory_result=$(check_observatory)
        echo "$observatory_result" | jq .

        echo ""
        local ssl_result=$(check_ssl)
        echo "$ssl_result" | jq .

        echo ""
        local headers_result=$(check_headers)
        echo "$headers_result" | jq .

        results+="\"security\": {\"observatory\": ${observatory_result}, \"ssl\": ${ssl_result}, \"headers\": ${headers_result}},"
    fi

    if [ "$run_all" = true ] || [ "$run_seo" = true ]; then
        echo ""
        echo -e "${YELLOW}=== SEO 檢測 ===${NC}"

        echo ""
        local html_result=$(check_html)
        echo "$html_result" | jq .

        echo ""
        local seo_files_result=$(check_seo_files)
        echo "$seo_files_result" | jq .

        results+="\"seo\": {\"html\": ${html_result}, \"files\": ${seo_files_result}},"
    fi

    # 移除最後的逗號，關閉 JSON
    results=$(echo "$results" | sed 's/,$//')
    results+="}"

    if [ -n "$output_file" ]; then
        echo "$results" | jq . > "$output_file"
        echo ""
        echo -e "${GREEN}結果已儲存到: ${output_file}${NC}"
    fi

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}檢測完成${NC}"
    echo -e "${GREEN}========================================${NC}"
}

main "$@"
