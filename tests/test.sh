#!/bin/bash

# Imaginary Nginx Test Suite
# Automates all security, performance, and functionality tests

set -euo pipefail

# Configuration
BASE_URL="${BASE_URL:-https://localhost}"
HTTPS_PORT="${HTTPS_PORT:-443}"
HTTP_PORT="${HTTP_PORT:-80}"
TEST_IMAGE_URL="${TEST_IMAGE_URL:-https://images-assets.nasa.gov/image/KSC-20251113-PH-BLU01_0008/KSC-20251113-PH-BLU01_0008~medium.jpg}"
TIMEOUT="${TIMEOUT:-10}"

# Use environment variables or defaults
BASE_URL="${BASE_URL:-https://localhost}"
TEST_IMAGE_URL="${TEST_IMAGE_URL:-https://images-assets.nasa.gov/image/KSC-20251113-PH-BLU01_0008/KSC-20251113-PH-BLU01_0008~medium.jpg}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Utility functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((TESTS_PASSED++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((TESTS_FAILED++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

run_test() {
    local test_name="$1"
    local test_command="$2"

    ((TESTS_TOTAL++))
    echo -e "\n${BLUE}Testing:${NC} $test_name"

    if eval "$test_command" >/dev/null 2>&1; then
        log_success "$test_name"
        return 0
    else
        log_error "$test_name"
        return 1
    fi
}

run_test_with_output() {
    local test_name="$1"
    local test_command="$2"

    ((TESTS_TOTAL++))
    echo -e "\n${BLUE}Testing:${NC} $test_name"

    if output=$(eval "$test_command" 2>&1); then
        log_success "$test_name"
        echo -e "${GREEN}Output:${NC} $output"
        return 0
    else
        log_error "$test_name"
        echo -e "${RED}Error:${NC} $output"
        return 1
    fi
}

# Wait for service to be ready
wait_for_service() {
    log_info "Waiting for Imaginary Nginx service to be ready..."
    log_info "Testing URL: $BASE_URL:$HTTPS_PORT"

    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if curl -k -s --connect-timeout 5 "$BASE_URL:$HTTPS_PORT/thumbnail?width=100&url=$TEST_IMAGE_URL" >/dev/null 2>&1; then
            log_info "Service is ready!"
            return 0
        fi

        echo -n "."
        sleep 2
        ((attempt++))
    done

    echo
    log_error "Service not ready after ${max_attempts} attempts"
    return 1
}

# Test functions
test_https_redirect() {
    local redirect_url=$(curl -I -L -s --connect-timeout $TIMEOUT "http://localhost:$HTTP_PORT/thumbnail?width=100&url=$TEST_IMAGE_URL" | grep -i "Location:" | cut -d' ' -f2)
    [[ "$redirect_url" == *"https://localhost"* ]]
}

test_security_headers() {
    local headers=$(curl -I -k -s --connect-timeout $TIMEOUT "$BASE_URL:$HTTPS_PORT/thumbnail?width=100&url=$TEST_IMAGE_URL")

    echo "$headers" | grep -q "X-Frame-Options: SAMEORIGIN" &&
    echo "$headers" | grep -q "X-Content-Type-Options: nosniff" &&
    echo "$headers" | grep -q "X-XSS-Protection: 1; mode=block" &&
    echo "$headers" | grep -q "Referrer-Policy: strict-origin-when-cross-origin"
}

test_ssl_certificate() {
    local cert_info=$(echo | timeout $TIMEOUT openssl s_client -connect localhost:$HTTPS_PORT -servername localhost 2>/dev/null | openssl x509 -text -noout 2>/dev/null)

    echo "$cert_info" | grep -q "RSA" &&
    echo "$cert_info" | grep -q "CN=localhost" &&
    echo "$cert_info" | grep -q "sha256WithRSAEncryption"
}

test_cache_functionality() {
    # First request should be MISS
    local first_response=$(curl -I -k -s --connect-timeout $TIMEOUT "$BASE_URL:$HTTPS_PORT/thumbnail?width=100&url=$TEST_IMAGE_URL" | grep "X-Proxy-Cache")

    # Wait a moment for cache to be written
    sleep 0.5

    # Second request should be HIT
    local second_response=$(curl -I -k -s --connect-timeout $TIMEOUT "$BASE_URL:$HTTPS_PORT/thumbnail?width=100&url=$TEST_IMAGE_URL" | grep "X-Proxy-Cache")

    # Different size should be MISS
    local different_response=$(curl -I -k -s --connect-timeout $TIMEOUT "$BASE_URL:$HTTPS_PORT/thumbnail?width=200&url=$TEST_IMAGE_URL" | grep "X-Proxy-Cache")

    [[ "$first_response" == *"MISS" ]] &&
    [[ "$second_response" == *"HIT" ]] &&
    [[ "$different_response" == *"MISS" ]]
}

test_image_operations() {
    # Test all basic operations
    curl -k -s --connect-timeout $TIMEOUT "$BASE_URL:$HTTPS_PORT/thumbnail?width=100&height=100&url=$TEST_IMAGE_URL" >/dev/null &&
    curl -k -s --connect-timeout $TIMEOUT "$BASE_URL:$HTTPS_PORT/resize?width=800&url=$TEST_IMAGE_URL" >/dev/null &&
    curl -k -s --connect-timeout $TIMEOUT "$BASE_URL:$HTTPS_PORT/crop?width=500&height=500&url=$TEST_IMAGE_URL" >/dev/null
}

test_performance_threshold() {
    local start_time=$(date +%s.%N)
    curl -k -s --connect-timeout $TIMEOUT "$BASE_URL:$HTTPS_PORT/thumbnail?width=100&url=$TEST_IMAGE_URL" >/dev/null
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l)

    # Should complete within 5 seconds
    (( $(echo "$duration < 5" | bc -l) ))
}

test_quality_parameter() {
    # Test with quality parameter
    curl -k -s --connect-timeout $TIMEOUT "$BASE_URL:$HTTPS_PORT/thumbnail?width=100&quality=90&url=$TEST_IMAGE_URL" >/dev/null
}

test_error_handling() {
    # Test invalid URL should return 404
    local status_code=$(curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout $TIMEOUT "$BASE_URL:$HTTPS_PORT/thumbnail?width=100&url=https://invalid.example.com/image.jpg")
    [[ "$status_code" == "404" || "$status_code" == "500" ]]
}

test_response_headers() {
    local headers=$(curl -I -k -s --connect-timeout $TIMEOUT "$BASE_URL:$HTTPS_PORT/thumbnail?width=100&url=$TEST_IMAGE_URL")

    # Should have cache status header
    echo "$headers" | grep -q "X-Proxy-Cache"
}

test_server_version_hidden() {
    local headers=$(curl -I -k -s --connect-timeout $TIMEOUT "$BASE_URL:$HTTPS_PORT/thumbnail?width=100&url=$TEST_IMAGE_URL")

    # Should not reveal server version
    ! echo "$headers" | grep -q "nginx/[0-9]"
}

# Main test execution
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Imaginary Nginx Test Suite${NC}"
    echo -e "${BLUE}========================================${NC}"

    # Check dependencies
    local deps=("curl" "openssl" "bc")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            log_error "Required dependency not found: $dep"
            echo "Please install: $dep"
            exit 1
        fi
    done

    # Wait for service
    if ! wait_for_service; then
        exit 1
    fi

    echo -e "\n${BLUE}Starting tests...${NC}"

    # Security tests
    run_test "HTTPS redirect (HTTP → HTTPS)" "test_https_redirect"
    run_test_with_output "Security headers present" "test_security_headers"
    run_test_with_output "SSL certificate strength" "test_ssl_certificate"

    # Functionality tests
    run_test_with_output "Cache functionality (MISS/HIT)" "test_cache_functionality"
    run_test "Image operations (thumbnail/resize/crop)" "test_image_operations"
    run_test "Quality parameter support" "test_quality_parameter"
    run_test "Error handling (invalid URLs)" "test_error_handling"

    # Performance tests
    run_test "Performance threshold (< 5s)" "test_performance_threshold"
    run_test "Response headers present" "test_response_headers"
    run_test "Server version hidden" "test_server_version_hidden"

    # Results
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}Test Results${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "Total tests: ${TESTS_TOTAL}"
    echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
    echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "\n${GREEN}🎉 All tests passed!${NC}"
        exit 0
    else
        echo -e "\n${RED}❌ Some tests failed!${NC}"
        exit 1
    fi
}

# Help function
show_help() {
    cat << EOF
Imaginary Nginx Test Suite

Usage: $0 [OPTIONS]

Options:
    -h, --help              Show this help message
    -u, --url URL           Base URL (default: https://localhost)
    -p, --https-port PORT   HTTPS port (default: 443)
    -c, --http-port PORT    HTTP port (default: 80)
    -i, --image-url URL     Test image URL
    -t, --timeout SECONDS   Request timeout (default: 10)

Environment variables:
    BASE_URL               Base URL
    HTTPS_PORT            HTTPS port
    HTTP_PORT             HTTP port
    TEST_IMAGE_URL        Test image URL
    TIMEOUT               Request timeout

Examples:
    $0                                    # Run with defaults
    $0 -u https://localhost -p 8443      # Custom URL and port
    $0 --https-port 8443 --timeout 15    # Custom port and timeout

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -u|--url)
            BASE_URL="$2"
            shift 2
            ;;
        -p|--https-port)
            HTTPS_PORT="$2"
            shift 2
            ;;
        -c|--http-port)
            HTTP_PORT="$2"
            shift 2
            ;;
        -i|--image-url)
            TEST_IMAGE_URL="$2"
            shift 2
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run main function
main "$@"