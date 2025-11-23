#!/bin/bash

# Imaginary Nginx Test Suite
# Simplified working version

# Configuration
BASE_URL="${BASE_URL:-https://localhost}"
HTTPS_PORT="${HTTPS_PORT:-443}"
HTTP_PORT="${HTTP_PORT:-80}"
TEST_IMAGE_URL="${TEST_IMAGE_URL:-https://images-assets.nasa.gov/image/KSC-20251113-PH-BLU01_0008/KSC-20251113-PH-BLU01_0008~medium.jpg}"
TIMEOUT="${TIMEOUT:-10}"

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
    local redirect_url=$(curl -I -L -s --connect-timeout $TIMEOUT "http://cache-test:$HTTP_PORT/thumbnail?width=100&url=$TEST_IMAGE_URL" | grep -i "Location:" | cut -d' ' -f2)
    [[ "$redirect_url" == *"https"* ]]
}

test_security_headers() {
    local headers=$(curl -I -k -s --connect-timeout $TIMEOUT "$BASE_URL:$HTTPS_PORT/thumbnail?width=100&url=$TEST_IMAGE_URL")

    echo "$headers" | grep -q "X-Frame-Options: SAMEORIGIN" &&
    echo "$headers" | grep -q "X-Content-Type-Options: nosniff" &&
    echo "$headers" | grep -q "X-XSS-Protection: 1; mode=block" &&
    echo "$headers" | grep -q "Referrer-Policy: strict-origin-when-cross-origin"
}

test_image_operations() {
    # Test basic operations
    curl -k -s --connect-timeout $TIMEOUT "$BASE_URL:$HTTPS_PORT/thumbnail?width=100&height=100&url=$TEST_IMAGE_URL" >/dev/null &&
    curl -k -s --connect-timeout $TIMEOUT "$BASE_URL:$HTTPS_PORT/resize?width=800&url=$TEST_IMAGE_URL" >/dev/null
}

# Save results to files
save_results() {
    local results_dir="${1:-/tmp/test-results}"
    local timestamp=$(date +%Y%m%d_%H%M%S)

    mkdir -p "$results_dir"

    # Create JSON results for GitHub Actions
    local json_file="$results_dir/test_results.json"
    echo "{" > "$json_file"
    echo "  \"timestamp\": \"$timestamp\"," >> "$json_file"
    echo "  \"summary\": {" >> "$json_file"
    echo "    \"total\": $TESTS_TOTAL," >> "$json_file"
    echo "    \"passed\": $TESTS_PASSED," >> "$json_file"
    echo "    \"failed\": $TESTS_FAILED," >> "$json_file"
    echo "    \"success_rate\": $(echo "scale=2; $TESTS_PASSED * 100 / $TESTS_TOTAL" | bc -l)" >> "$json_file"
    echo "  }" >> "$json_file"
    echo "}" >> "$json_file"

    # Create simple text summary
    local summary_file="$results_dir/test_summary.txt"
    echo "Imaginary Nginx Test Results - $timestamp" > "$summary_file"
    echo "========================================" >> "$summary_file"
    echo "Total tests: $TESTS_TOTAL" >> "$summary_file"
    echo "Passed: $TESTS_PASSED" >> "$summary_file"
    echo "Failed: $TESTS_FAILED" >> "$summary_file"
    echo "Success rate: $(echo "scale=1; $TESTS_PASSED * 100 / $TESTS_TOTAL" | bc -l)%" >> "$summary_file"

    log_info "Results saved to: $results_dir"
}

# Main test execution
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Imaginary Nginx Test Suite${NC}"
    echo -e "${BLUE}========================================${NC}"

    # Wait for service
    if ! wait_for_service; then
        exit 1
    fi

    echo -e "\n${BLUE}Starting tests...${NC}"

    # Run tests
    run_test "HTTPS redirect (HTTP → HTTPS)" "test_https_redirect"
    run_test_with_output "Security headers present" "test_security_headers"
    run_test "Image operations (thumbnail/resize)" "test_image_operations"

    # Results
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}Test Results${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "Total tests: ${TESTS_TOTAL}"
    echo -e "${GREEN}Passed: ${TESTS_PASSED}${NC}"
    echo -e "${RED}Failed: ${TESTS_FAILED}${NC}"

    # Save results before exiting
    save_results "/tmp/test-results"

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "\n${GREEN}🎉 All tests passed!${NC}"
        exit 0
    else
        echo -e "\n${RED}❌ Some tests failed!${NC}"
        exit 1
    fi
}

# Run main function
main "$@"