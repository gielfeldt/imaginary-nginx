#!/bin/bash

# Isolated Test Runner
# Runs tests in a completely isolated Docker environment

set -euo pipefail

# Configuration
TEST_NETWORK="imaginary-test-network"
TEST_RESULTS_DIR="./test-results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
COMPOSE_FILE="tests/docker-compose.test.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Utility functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up test environment..."

    # Stop and remove containers
    local COMPOSE_ABS_PATH
    COMPOSE_ABS_PATH="$(cd "$(dirname "$COMPOSE_FILE")" && pwd)/$(basename "$COMPOSE_FILE")"

    if docker-compose -f "$COMPOSE_ABS_PATH" down -v --remove-orphans 2>/dev/null; then
        log_success "Test containers stopped and removed"
    fi

    # Remove network
    if docker network ls | grep -q "$TEST_NETWORK"; then
        docker network rm "$TEST_NETWORK" 2>/dev/null || true
        log_success "Test network removed"
    fi

    # Remove test runner container if it exists
    if docker ps -a | grep -q "test-runner"; then
        docker rm -f test-runner 2>/dev/null || true
        log_success "Test runner container removed"
    fi

    log_info "Cleanup completed"
}

# Handle interruption
trap cleanup EXIT INT TERM

# Create results directory
mkdir -p "$TEST_RESULTS_DIR"

# Prepare cache files
log_info "Preparing cache files for isolated testing..."
rm -rf tests/cache
mkdir -p tests/cache
cp cache/nginx.conf tests/cache/ 2>/dev/null || true
cp cache/imaginary.conf tests/cache/ 2>/dev/null || true

if [[ ! -f "tests/cache/nginx.conf" ]] || [[ ! -f "tests/cache/imaginary.conf" ]]; then
    log_error "Cache files not found or failed to copy"
    exit 1
fi

log_info "Cache files prepared successfully"

# Show help
show_help() {
    cat << EOF
Isolated Test Runner

Usage: $0 [OPTIONS]

Options:
    -h, --help              Show this help message
    -c, --clean            Only clean up existing test environment
    -k, --keep             Keep containers running after tests
    -v, --verbose          Enable verbose output
    -r, --results DIR      Results directory (default: ./test-results)
    -f, --file FILE        Docker Compose file (default: tests/docker-compose.test.yml)

Environment Variables:
    TEST_IMAGE_URL         Test image URL
    TIMEOUT                Request timeout in seconds
    BASE_URL               Service base URL

Examples:
    $0                                    # Run isolated tests
    $0 --clean                           # Clean up only
    $0 --keep                            # Run tests and keep containers
    $0 --verbose --results ./my-results  # Verbose mode with custom results dir

EOF
}

# Parse command line arguments
CLEAN_ONLY=false
KEEP_CONTAINERS=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -c|--clean)
            CLEAN_ONLY=true
            shift
            ;;
        -k|--keep)
            KEEP_CONTAINERS=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -r|--results)
            TEST_RESULTS_DIR="$2"
            shift 2
            ;;
        -f|--file)
            COMPOSE_FILE="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Only clean up if requested
if [[ "$CLEAN_ONLY" == "true" ]]; then
    cleanup
    exit 0
fi

# Main execution
main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Imaginary Nginx Isolated Test Runner${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "Test results will be saved to: ${GREEN}$TEST_RESULTS_DIR${NC}"
    echo -e "Timestamp: ${GREEN}$TIMESTAMP${NC}"

    # Check if docker and docker-compose are available
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi

    if ! command -v docker-compose >/dev/null 2>&1; then
        log_error "Docker Compose is not installed or not in PATH"
        exit 1
    fi

    # Clean up any existing test environment
    log_info "Cleaning up any existing test environment..."
    docker-compose -f "$COMPOSE_FILE" down -v --remove-orphans 2>/dev/null || true

    # Validate compose file first
    if ! docker-compose -f "$COMPOSE_FILE" config >/dev/null 2>&1; then
        log_error "Invalid Docker Compose configuration"
        docker-compose -f "$COMPOSE_FILE" config
        exit 1
    fi

    # Start the test environment
    log_info "Starting isolated test environment..."

    # Get absolute path for better Docker Compose compatibility
    local COMPOSE_ABS_PATH
    COMPOSE_ABS_PATH="$(cd "$(dirname "$COMPOSE_FILE")" && pwd)/$(basename "$COMPOSE_FILE")"

    if [[ "$VERBOSE" == "true" ]]; then
        if ! COMPOSE_FILE="$COMPOSE_ABS_PATH" docker-compose -f "$COMPOSE_ABS_PATH" up --build -d; then
            log_error "Failed to start test services"
            COMPOSE_FILE="$COMPOSE_ABS_PATH" docker-compose -f "$COMPOSE_ABS_PATH" logs
            exit 1
        fi
    else
        if ! COMPOSE_FILE="$COMPOSE_ABS_PATH" docker-compose -f "$COMPOSE_ABS_PATH" up --build -d 2>&1; then
            log_error "Failed to start test services"
            COMPOSE_FILE="$COMPOSE_ABS_PATH" docker-compose -f "$COMPOSE_ABS_PATH" logs
            exit 1
        fi
    fi

    # Update COMPOSE_FILE for later use
    COMPOSE_FILE="$COMPOSE_ABS_PATH"

    # Wait for services to be ready
    log_info "Waiting for services to be ready..."
    sleep 10

    # Check if services started successfully
    if ! docker-compose -f "$COMPOSE_FILE" ps | grep -q "Up"; then
        log_error "Failed to start test services"
        docker-compose -f "$COMPOSE_FILE" logs
        exit 1
    fi

    # Wait for health checks
    log_info "Waiting for health checks..."

    local max_wait=60
    local wait_time=0

    while [ $wait_time -lt $max_wait ]; do
        local healthy=$(docker-compose -f "$COMPOSE_FILE" ps --format '{{.Service}}:{{.Health}}' | grep -c "healthy" || echo "0")

        if [[ "$healthy" -ge 2 ]]; then
            log_success "All services are healthy"
            break
        fi

        echo -n "."
        sleep 2
        ((wait_time+=2))
    done

    if [[ $wait_time -ge $max_wait ]]; then
        log_error "Services failed health checks"
        docker-compose -f "$COMPOSE_FILE" logs
        exit 1
    fi

    echo

    # Show service status
    log_info "Test environment status:"
    docker-compose -f "$COMPOSE_FILE" ps

    echo

    # Run the tests
    log_info "Running tests in isolated environment..."

    local test_exit_code=0

    if [[ "$VERBOSE" == "true" ]]; then
        docker-compose -f "$COMPOSE_FILE" run --rm test-runner || test_exit_code=$?
    else
        docker-compose -f "$COMPOSE_FILE" run --rm test-runner >/dev/null 2>&1 || test_exit_code=$?
    fi

    # Copy test results
    if docker ps -a | grep -q "test-runner"; then
        log_info "Copying test results..."
        docker cp test-runner:/tmp/test-results/. "$TEST_RESULTS_DIR/" 2>/dev/null || true
    fi

    # Show results
    if [[ $test_exit_code -eq 0 ]]; then
        log_success "All tests passed! 🎉"

        # Show test results file if it exists
        if [[ -f "$TEST_RESULTS_DIR/test_results.json" ]]; then
            log_info "Test results saved to: $TEST_RESULTS_DIR/test_results.json"
        fi
    else
        log_error "Tests failed! ❌"

        # Show logs for debugging
        log_warning "Service logs for debugging:"
        docker-compose -f "$COMPOSE_FILE" logs --tail=50
    fi

    # Cleanup unless requested to keep
    if [[ "$KEEP_CONTAINERS" != "true" ]]; then
        cleanup
    else
        log_warning "Containers are kept running. Use '$0 --clean' to clean up."
        log_info "Test containers:"
        docker-compose -f "$COMPOSE_FILE" ps
    fi

    return $test_exit_code
}

# Run main function
main "$@"