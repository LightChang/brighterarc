#!/bin/bash

# =============================================================================
# Competitive Audit Tool (Local) - 競品分析工具（本地版）
# 用途：使用本地 Lighthouse CLI 進行網站效能分析，不受 API 配額限制
# 依賴：Node.js, Chrome/Chromium
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
    echo "Usage: $0 <our-url> <competitor1> [competitor2] [competitor3] ..."
    echo ""
    echo "使用本地 Lighthouse CLI 進行效能分析（不受 API 配額限制）"
    echo ""
    echo "依賴:"
    echo "  - Node.js (npx)"
    echo "  - Chrome 或 Chromium"
    echo ""
    echo "Examples:"
    echo "  $0 https://our-site.com https://competitor1.com https://competitor2.com"
    exit 1
}

# -----------------------------------------------------------------------------
# 檢查依賴
# -----------------------------------------------------------------------------
check_dependencies() {
    if ! command -v npx &> /dev/null; then
        echo -e "${RED}錯誤：需要 Node.js (npx)${NC}"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        echo -e "${RED}錯誤：需要 jq${NC}"
        exit 1
    fi

    # 檢查 Chrome
    local chrome_path=""
    if [ -f "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]; then
        chrome_path="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    elif command -v google-chrome &> /dev/null; then
        chrome_path=$(which google-chrome)
    elif command -v chromium &> /dev/null; then
        chrome_path=$(which chromium)
    fi

    if [ -z "$chrome_path" ]; then
        echo -e "${YELLOW}警告：找不到 Chrome，Lighthouse 可能無法執行${NC}"
    fi
}

# -----------------------------------------------------------------------------
# 使用 Lighthouse 取得數據
# -----------------------------------------------------------------------------
get_lighthouse_data() {
    local url=$1
    local name=$2
    local temp_file=$(mktemp)

    echo -e "${BLUE}檢測: ${name}${NC} (${url})" >&2
    echo -e "  使用本地 Lighthouse..." >&2

    # 執行 Lighthouse
    if npx lighthouse "$url" \
        --output=json \
        --output-path="$temp_file" \
        --chrome-flags="--headless --no-sandbox --disable-gpu" \
        --only-categories=performance,accessibility,seo \
        --quiet 2>/dev/null; then

        # 解析結果
        local perf=$(jq -r '(.categories.performance.score // 0) * 100 | floor' "$temp_file" 2>/dev/null)
        local seo=$(jq -r '(.categories.seo.score // 0) * 100 | floor' "$temp_file" 2>/dev/null)
        local access=$(jq -r '(.categories.accessibility.score // 0) * 100 | floor' "$temp_file" 2>/dev/null)
        local lcp=$(jq -r '.audits["largest-contentful-paint"].displayValue // "N/A"' "$temp_file" 2>/dev/null)
        local cls=$(jq -r '.audits["cumulative-layout-shift"].displayValue // "N/A"' "$temp_file" 2>/dev/null)
        local fcp=$(jq -r '.audits["first-contentful-paint"].displayValue // "N/A"' "$temp_file" 2>/dev/null)
        local tbt=$(jq -r '.audits["total-blocking-time"].displayValue // "N/A"' "$temp_file" 2>/dev/null)

        rm -f "$temp_file"

        echo -e "${GREEN}  完成${NC}" >&2

        echo "{\"name\": \"${name}\", \"url\": \"${url}\", \"performance\": ${perf:-0}, \"seo\": ${seo:-0}, \"accessibility\": ${access:-0}, \"lcp\": \"${lcp}\", \"cls\": \"${cls}\", \"fcp\": \"${fcp}\", \"tbt\": \"${tbt}\"}"
    else
        rm -f "$temp_file"
        echo -e "${RED}  失敗${NC}" >&2
        echo "{\"name\": \"${name}\", \"url\": \"${url}\", \"error\": true, \"performance\": 0, \"seo\": 0, \"accessibility\": 0, \"lcp\": \"N/A\", \"cls\": \"N/A\", \"fcp\": \"N/A\", \"tbt\": \"N/A\"}"
    fi
}

# -----------------------------------------------------------------------------
# 產出比較表
# -----------------------------------------------------------------------------
print_comparison_table() {
    local results=("$@")

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}競品比較報告 (Lighthouse)${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""

    # 表頭
    printf "%-15s | %-6s | %-6s | %-6s | %-10s | %-8s | %-10s\n" "網站" "效能" "SEO" "無障礙" "LCP" "CLS" "FCP"
    printf "%-15s-+-%-6s-+-%-6s-+-%-6s-+-%-10s-+-%-8s-+-%-10s\n" "---------------" "------" "------" "------" "----------" "--------" "----------"

    for result in "${results[@]}"; do
        local name=$(echo "$result" | jq -r '.name // "Unknown"')
        local perf=$(echo "$result" | jq -r '.performance // 0')
        local seo=$(echo "$result" | jq -r '.seo // 0')
        local access=$(echo "$result" | jq -r '.accessibility // 0')
        local lcp=$(echo "$result" | jq -r '.lcp // "N/A"')
        local cls=$(echo "$result" | jq -r '.cls // "N/A"')
        local fcp=$(echo "$result" | jq -r '.fcp // "N/A"')
        local error=$(echo "$result" | jq -r '.error // false')

        if [ "$error" = "true" ]; then
            printf "%-15s | %-6s | %-6s | %-6s | %-10s | %-8s | %-10s\n" \
                "${name:0:15}" "ERR" "ERR" "ERR" "-" "-" "-"
            continue
        fi

        # 顏色
        local p_color=$NC
        if [ "$perf" -ge 90 ]; then p_color=$GREEN
        elif [ "$perf" -ge 50 ]; then p_color=$YELLOW
        else p_color=$RED; fi

        printf "%-15s | ${p_color}%-6s${NC} | %-6s | %-6s | %-10s | %-8s | %-10s\n" \
            "${name:0:15}" "${perf}" "${seo}" "${access}" "${lcp:0:10}" "${cls:0:8}" "${fcp:0:10}"
    done

    echo ""
    echo "分數說明: 90+ = 優秀(綠), 50-89 = 需改善(黃), <50 = 差(紅)"
    echo ""
}

# -----------------------------------------------------------------------------
# 主程式
# -----------------------------------------------------------------------------
main() {
    if [ $# -lt 2 ]; then
        usage
    fi

    check_dependencies

    local our_url=$1
    shift
    local competitors=("$@")

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}競品 Lighthouse 分析（本地）${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "時間: $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "我們: ${our_url}"
    echo -e "競品數量: ${#competitors[@]}"
    echo -e "${YELLOW}注意: 本地分析較慢，每個網站約需 30-60 秒${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""

    local results=()

    # 檢測我們的網站
    echo -e "${YELLOW}=== 檢測我們的網站 ===${NC}"
    local our_result=$(get_lighthouse_data "$our_url" "我們")
    results+=("$our_result")
    echo ""

    # 檢測競品
    echo -e "${YELLOW}=== 檢測競品 ===${NC}"
    local i=1
    for competitor in "${competitors[@]}"; do
        local result=$(get_lighthouse_data "$competitor" "競品${i}")
        results+=("$result")
        ((i++))
        echo ""
    done

    # 產出比較表
    print_comparison_table "${results[@]}"

    # 輸出 JSON
    echo -e "${YELLOW}=== JSON 格式輸出 ===${NC}"
    echo "["
    local first=true
    for result in "${results[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            echo ","
        fi
        echo "$result" | jq .
    done
    echo "]"
}

# 執行
main "$@"
