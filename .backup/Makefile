.PHONY: help test test-isolated test-isolated-keep test-local test-ci test-clean build up down logs clean dev-setup install-deps validate quick-test dev

# Default target
help:
	@echo "Imaginary Nginx - Test Suite"
	@echo ""
	@echo "Available commands:"
	@echo "  help              Show this help message"
	@echo "  test              Run automated tests (requires service running)"
	@echo "  test-isolated     Run tests in isolated Docker environment"
	@echo "  test-isolated-keep Run tests and keep containers running"
	@echo "  test-debug        Debug isolated test environment"
	@echo "  test-local        Start services and run tests with port mapping"
	@echo "  test-ci           Run tests in CI mode"
	@echo "  test-clean        Clean up isolated test environment"
	@echo "  build             Build Docker images"
	@echo "  up                Start services"
	@echo "  down              Stop services"
	@echo "  logs              Show service logs"
	@echo "  clean             Clean up Docker resources"
	@echo ""
	@echo "Testing Examples:"
	@echo "  make test-isolated              # Complete isolated testing"
	@echo "  make test-local                 # Traditional local testing"
	@echo "  make test                        # Run tests if service is running"
	@echo "  make test-isolated-keep         # Run tests and keep containers"
	@echo "  make test-clean                  # Clean up test environment"
	@echo ""
	@echo "Development Examples:"
	@echo "  make build && make up            # Build and start services"

# Test commands
test:
	@echo "Running automated tests (requires service running)..."
	@if [ ! -f tests/test.sh ]; then \
		echo "Error: tests/test.sh not found"; \
		exit 1; \
	fi
	@chmod +x tests/test.sh
	@./tests/test.sh

test-isolated:
	@echo "Running tests in isolated Docker environment..."
	@if [ ! -f tests/run-isolated-tests.sh ]; then \
		echo "Error: tests/run-isolated-tests.sh not found"; \
		exit 1; \
	fi
	@chmod +x tests/run-isolated-tests.sh
	@./tests/run-isolated-tests.sh

test-isolated-keep:
	@echo "Running tests in isolated environment (keeping containers)..."
	@chmod +x tests/run-isolated-tests.sh
	@./tests/run-isolated-tests.sh --keep

test-debug:
	@echo "Debugging isolated test environment..."
	@if [ ! -f tests/debug-test.sh ]; then \
		echo "Error: tests/debug-test.sh not found"; \
		exit 1; \
	fi
	@chmod +x tests/debug-test.sh
	@./tests/debug-test.sh

test-local:
	@echo "Starting services for local testing..."
	@echo "Creating docker-compose.override.yml for port mapping..."
	@printf 'version: "3.8"\nservices:\n  cache:\n    ports:\n      - "8080:80"\n      - "8443:443"\n' > docker-compose.override.yml
	@echo "Starting services..."
	@docker-compose up -d --build
	@echo "Waiting for services to be ready..."
	@sleep 15
	@echo "Running tests..."
	@export BASE_URL="https://localhost" HTTPS_PORT="8443" HTTP_PORT="8080" TEST_IMAGE_URL="https://images-assets.nasa.gov/image/KSC-20251113-PH-BLU01_0008/KSC-20251113-PH-BLU01_0008~medium.jpg" && \
	./tests/test.sh
	@echo "Cleaning up..."
	@docker-compose down

test-ci:
	@echo "Running tests in CI mode..."
	@export BASE_URL="https://localhost" HTTPS_PORT="443" HTTP_PORT="80" TEST_IMAGE_URL="https://httpbin.org/image/jpeg" && \
	./tests/test.sh

test-clean:
	@echo "Cleaning up isolated test environment..."
	@chmod +x tests/run-isolated-tests.sh
	@./tests/run-isolated-tests.sh --clean

# Docker commands
build:
	@echo "Building Docker images..."
	@docker-compose build

up:
	@echo "Starting services..."
	@docker-compose up -d

down:
	@echo "Stopping services..."
	@docker-compose down

logs:
	@echo "Showing service logs..."
	@docker-compose logs -f

clean:
	@echo "Cleaning up Docker resources..."
	@docker-compose down -v
	@docker system prune -f
	@rm -f docker-compose.override.yml

# Development commands
dev-setup: clean build
	@echo "Setting up development environment..."
	@printf 'version: "3.8"\nservices:\n  cache:\n    ports:\n      - "8080:80"\n      - "8443:443"\n    environment:\n      - BYPASS_CACHE=0\n    volumes:\n      - ./img-cache:/cache\n      - ./logs/nginx:/var/log/nginx\n  imaginary:\n    environment:\n      - DEBUG=*\n' > docker-compose.override.yml
	@docker-compose up -d
	@echo "Development environment ready!"
	@echo "Services available at:"
	@echo "  HTTP:  http://localhost:8080 (redirects to HTTPS)"
	@echo "  HTTPS: https://localhost:8443"

# Quick test command
quick-test:
	@echo "Running quick connectivity test..."
	@if ! command -v curl >/dev/null 2>&1; then \
		echo "Error: curl not found. Please install curl."; \
		exit 1; \
	fi
	@curl -k -s -o /dev/null -w "Status: %{http_code}\nTime: %{time_total}s\n" "https://localhost:8443/thumbnail?width=100&url=https://httpbin.org/image/jpeg" || \
	(echo "Service not responding. Try 'make dev-setup' first."; exit 1)

# Install dependencies
install-deps:
	@echo "Installing test dependencies..."
	@if command -v apt-get >/dev/null 2>&1; then \
		sudo apt-get update && sudo apt-get install -y curl openssl bc; \
	elif command -v brew >/dev/null 2>&1; then \
		brew install curl openssl; \
	elif command -v yum >/dev/null 2>&1; then \
		sudo yum install -y curl openssl bc; \
	else \
		echo "Please install curl, openssl, and bc manually"; \
	fi

# Validate configuration
validate:
	@echo "Validating configuration..."
	@if [ ! -f cache/nginx.conf ]; then \
		echo "Error: cache/nginx.conf not found"; \
		exit 1; \
	fi
	@if [ ! -f cache/imaginary.conf ]; then \
		echo "Error: cache/imaginary.conf not found"; \
		exit 1; \
	fi
	@if [ ! -f docker-compose.yml ]; then \
		echo "Error: docker-compose.yml not found"; \
		exit 1; \
	fi
	@echo "Configuration files found!"

# All-in-one development setup
dev: validate install-deps dev-setup quick-test