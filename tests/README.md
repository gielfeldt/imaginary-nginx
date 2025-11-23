# Test Suite

This directory contains the automated test suite for Imaginary Nginx.

## Files

- `test.sh` - Main test script that runs all security, performance, and functionality tests
- `README.md` - This documentation file

## Usage

### Local Testing

```bash
# Make sure the service is running
docker-compose up -d

# Run all tests with default settings
./tests/test.sh

# Run with custom settings
./tests/test.sh -u https://localhost -p 443

# Show help
./tests/test.sh --help
```

### Environment Variables

You can also configure tests using environment variables:

```bash
export BASE_URL="https://localhost"
export HTTPS_PORT="8443"
export HTTP_PORT="8080"
export TEST_IMAGE_URL="https://images-assets.nasa.gov/image/KSC-20251113-PH-BLU01_0008/KSC-20251113-PH-BLU01_0008~medium.jpg"
export TIMEOUT="10"

./tests/test.sh
```

## Test Categories

### 🔒 Security Tests

1. **HTTPS Redirect** - Verifies HTTP redirects to HTTPS
2. **Security Headers** - Checks for X-Frame-Options, X-Content-Type-Options, etc.
3. **SSL Certificate** - Validates certificate strength and configuration

### ⚡ Functionality Tests

4. **Cache Functionality** - Tests MISS/HIT cache behavior
5. **Image Operations** - Verifies thumbnail, resize, and crop operations
6. **Quality Parameter** - Tests image quality settings
7. **Error Handling** - Validates handling of invalid URLs
8. **Response Headers** - Checks for proper headers
9. **Server Version** - Ensures server version is hidden

### 🚀 Performance Tests

10. **Performance Threshold** - Ensures responses are under 5 seconds

## Test Results

The test script provides color-coded output:

- 🟢 **[PASS]** - Test passed
- 🔴 **[FAIL]** - Test failed
- 🔵 **[INFO]** - Informational message
- 🟡 **[WARN]** - Warning message

## GitHub Actions

The tests automatically run on GitHub Actions for:

- **Push** to main/master/develop branches
- **Pull requests** to main/master/develop branches
- **Manual dispatch** via workflow tab

### CI/CD Features

- **Automated Testing**: Full test suite on every push/PR
- **Security Scanning**: Trivy vulnerability scanning
- **Docker Security**: Container image vulnerability scanning
- **Service Health**: Automatic service startup and health checks
- **Fail Fast**: Builds fail immediately if any test fails
- **Detailed Logs**: Service logs shown on failure for debugging

## Requirements

The test script requires these dependencies:

- `curl` - For HTTP requests
- `openssl` - For SSL certificate testing
- `bc` - For floating point arithmetic

### Installation (Ubuntu/Debian)

```bash
sudo apt-get update
sudo apt-get install curl openssl bc
```

### Installation (macOS)

```bash
brew install curl openssl
```

## Custom Tests

To add new tests:

1. Create a test function in `test.sh`
2. Add the test to the main execution section
3. Update this README if needed

### Test Function Template

```bash
test_my_new_feature() {
    # Your test logic here
    # Return 0 for success, non-zero for failure
    curl -k -s --connect-timeout $TIMEOUT "$BASE_URL:$HTTPS_PORT/my-endpoint" | grep -q "expected-content"
}
```

Add to main function:
```bash
run_test "My New Feature" "test_my_new_feature"
```

## Troubleshooting

### Service Not Ready

If tests fail with "Service not ready", check:

```bash
docker-compose ps
docker-compose logs cache
```

### Permission Issues

Make sure the test script is executable:

```bash
chmod +x tests/test.sh
```

### Port Conflicts

Ensure ports are available or update test configuration:

```bash
# Check if ports are in use
netstat -tulpn | grep -E "(80|443|8443)"

# Use different ports
./tests/test.sh -p 9443 -c 9080
```

### SSL Certificate Issues

If HTTPS tests fail, verify the certificate:

```bash
openssl s_client -connect localhost:8443 -servername localhost
```

## Continuous Integration

The GitHub Actions workflow includes:

1. **Service Setup**: Automatic Docker Compose deployment
2. **Health Checks**: Service readiness verification
3. **Test Execution**: Full test suite run
4. **Security Scanning**: Code and container vulnerability analysis
5. **Cleanup**: Automatic resource cleanup

The workflow ensures the same tests run locally also run in CI/CD, providing consistent validation across environments.