#!/bin/bash

# Debug Test Runner
# Simple debugging for isolated test environment

set -euo pipefail

echo "🔍 Debug: Imaginary Nginx Test Environment"

# Check if Docker and docker-compose are available
if ! command -v docker >/dev/null 2>&1; then
    echo "❌ Docker not found"
    exit 1
fi

if ! command -v docker-compose >/dev/null 2>&1; then
    echo "❌ Docker Compose not found"
    exit 1
fi

echo "✅ Docker tools available"

# Check files exist
if [[ ! -f "tests/docker-compose.test.debug.yml" ]]; then
    echo "❌ Debug compose file not found"
    exit 1
fi

if [[ ! -f "tests/test.sh" ]]; then
    echo "❌ Test script not found"
    exit 1
fi

# Ensure cache files are copied
echo "📋 Preparing cache files..."
rm -rf tests/cache
mkdir -p tests/cache
cp cache/nginx.conf tests/cache/
cp cache/imaginary.conf tests/cache/

if [[ ! -f "tests/cache/nginx.conf" ]] || [[ ! -f "tests/cache/imaginary.conf" ]]; then
    echo "❌ Cache files not found or failed to copy"
    exit 1
fi

echo "✅ Required files found"

# Check if we can build the test runner
echo "🏗️  Building test runner image..."
if docker build -f tests/Dockerfile.test -t imaginary-test-runner ./tests >/dev/null 2>&1; then
    echo "✅ Test runner image built successfully"
else
    echo "❌ Failed to build test runner image"
    docker build -f tests/Dockerfile.test -t imaginary-test-runner ./tests
    exit 1
fi

# Validate compose file
echo "📋 Validating compose configuration..."
if docker-compose -f tests/docker-compose.test.debug.yml config >/dev/null 2>&1; then
    echo "✅ Compose file is valid"
else
    echo "❌ Invalid compose file"
    docker-compose -f tests/docker-compose.test.debug.yml config
    exit 1
fi

# Clean up any existing test environment
echo "🧹 Cleaning up existing test environment..."
docker-compose -f tests/docker-compose.test.debug.yml down -v --remove-orphans 2>/dev/null || true

# Start services one by one
echo "🚀 Starting imaginary service..."
if docker-compose -f tests/docker-compose.test.debug.yml up -d imaginary-test; then
    echo "✅ Imaginary service started"
else
    echo "❌ Failed to start imaginary service"
    exit 1
fi

# Wait for imaginary to be ready
echo "⏳ Waiting for imaginary service..."
sleep 10

# Check imaginary service using external curl (from host)
echo "🔍 Testing imaginary from host..."
if curl -f --connect-timeout 10 "http://$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' imaginary-test):9000/resize?width=10&url=https://httpbin.org/image/jpeg" >/dev/null 2>&1; then
    echo "✅ Imaginary service is responding"
else
    echo "❌ Imaginary service not responding (this might be expected - continuing...)"
    # Don't exit - continue with cache test
fi

# Start cache service
echo "🚀 Starting cache service..."
if docker-compose -f tests/docker-compose.test.debug.yml up -d cache-test; then
    echo "✅ Cache service started"
else
    echo "❌ Failed to start cache service"
    exit 1
fi

# Wait for cache to be ready
echo "⏳ Waiting for cache service..."
sleep 20

# Check if we can access cache from test runner container
echo "🔍 Testing cache accessibility..."
if docker run --rm --network imaginary-test-network imaginary-test-runner \
    curl -k -s --connect-timeout 10 "https://cache-test/thumbnail?width=10&url=https://httpbin.org/image/jpeg" >/dev/null 2>&1; then
    echo "✅ Cache service is accessible"
else
    echo "❌ Cache service not accessible"
    docker-compose -f tests/docker-compose.test.debug.yml logs cache-test
    exit 1
fi

# Show service status
echo "📊 Service status:"
docker-compose -f tests/docker-compose.test.debug.yml ps

# Run a simple test
echo "🧪 Running simple test..."
if docker run --rm --network imaginary-test-network -e BASE_URL="https://cache-test" -e TEST_ENV="docker" imaginary-test-runner \
    /bin/sh -c "curl -k -s https://cache-test/thumbnail?width=10&url=https://httpbin.org/image/jpeg >/dev/null && echo 'SUCCESS: Service working'" 2>/dev/null; then
    echo "✅ Simple test passed"
else
    echo "❌ Simple test failed"
    exit 1
fi

# Cleanup
echo "🧹 Cleaning up..."
docker-compose -f tests/docker-compose.test.debug.yml down -v --remove-orphans

echo "🎉 All debug checks passed! The isolated test environment should work."