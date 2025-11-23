FROM alpine:3.18

# Install test dependencies
RUN apk add --no-cache \
    curl \
    openssl \
    bash \
    bc \
    coreutils \
    jq

# Create tests directory
RUN mkdir -p /tests

# Copy test script (context is tests directory)
COPY test.sh /tests/test.sh
COPY README.md /tests/README.md

# Make test script executable
RUN chmod +x /tests/test.sh

# Create results directory
RUN mkdir -p /tmp/test-results

# Set working directory
WORKDIR /tests

# Default command
CMD ["/tests/test.sh"]