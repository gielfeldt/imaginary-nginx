# Performance Tuning Guide

This guide covers performance optimization strategies, benchmarking approaches, and monitoring techniques for Imaginary Nginx.

## Performance Metrics

### Key Performance Indicators

#### Cache Performance
- **Cache Hit Ratio**: Target >95%
- **Cache Response Time**: <10ms for cached responses
- **Cache Warmup Time**: <5 minutes to 80% hit ratio
- **Cache Storage Efficiency**: >80% utilization

#### Request Handling
- **Request Rate**: Thousands per second capability
- **Response Time**: <50ms for transformed images
- **Throughput**: 1GB+ per minute on proper hardware
- **Error Rate**: <0.1% for healthy system

#### System Resources
- **CPU Utilization**: 70-80% optimal
- **Memory Usage**: Efficient use of cache zones
- **Disk I/O**: Optimized for cache operations
- **Network Bandwidth**: Full utilization available

## System Optimization

### Nginx Performance Tuning

#### Worker Configuration
```nginx
# cache/nginx.conf
worker_processes  auto;                 # Auto-detect CPU cores
worker_rlimit_nofile 65535;            # Increase file descriptor limit

events {
    worker_connections  8192;           # Connections per worker (was 1024)
    use                 epoll;         # Linux optimized I/O
    multi_accept        on;            # Accept multiple connections
}
```

#### HTTP Performance Settings
```nginx
http {
    sendfile            on;            # Kernel-level file sending
    tcp_nopush          on;            # Optimize packet sending
    tcp_nodelay         on;            # Disable Nagle's algorithm
    keepalive_timeout   65;            # Keep connections alive

    # Buffer tuning
    client_body_buffer_size     128k;
    client_max_body_size        100m;
    client_header_buffer_size   1k;
    large_client_header_buffers 4 4k;

    # Proxy buffer optimization
    proxy_buffer_size           4k;
    proxy_buffers               8 4k;
    proxy_busy_buffers_size     8k;
    proxy_temp_file_write_size  1024m;
}
```

#### Cache Optimization
```nginx
# Optimized cache path
proxy_cache_path  /cache/static
    levels=1:2                     # Directory structure
    keys_zone=STATIC:20m           # Increased from 10m
    inactive=365d                  # Cache TTL
    max_size=20g                   # Increased from 10g
    use_temp_path=off              # Direct I/O
    loader_files=1000;             # Preload cache entries
    loader_sleep=50ms;             # Preload timing
    loader_threshold=300;          # Preload concurrency
```

### File System Optimization

#### Cache Directory Structure
```bash
#!/bin/bash
# scripts/optimize-cache.sh
CACHE_DIR="./img-cache"

# Create optimized directory structure
mkdir -p $CACHE_DIR/static/{0..9}/{0..9}{0..9}
mkdir -p $CACHE_DIR/static.temp

# Set optimal permissions
chown -R 1000:1000 $CACHE_DIR  # nginx user in container
chmod -R 755 $CACHE_DIR

# Optimize filesystem (Linux)
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Disable atime for cache directory
    chattr +A $CACHE_DIR

    # Mount with noatime (requires fstab entry)
    # /dev/sdb1 /cache ext4 defaults,noatime 0 2
fi
```

#### Docker Volume Optimization
```yaml
# docker-compose.prod.yml
version: "3.8"
services:
  cache:
    volumes:
      - type: tmpfs
        target: /tmp
        tmpfs:
          size: 1G
          mode: 1777
      - type: bind
        source: ./img-cache
        target: /cache
        bind:
          propagation: rprivate
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
```

## CPU Optimization

### Worker Process Tuning
```nginx
# Advanced worker configuration
worker_processes  auto;
worker_cpu_affinity auto;  # Bind workers to CPU cores

# Optional: Manual CPU binding for specific hardware
# worker_cpu_affinity 0001 0010 0100 1000;
```

### Container CPU Allocation
```yaml
# docker-compose.cpu.yml
version: "3.8"
services:
  cache:
    deploy:
      resources:
        limits:
          cpus: '4.0'              # CPU limit
          memory: 8G               # Memory limit
        reservations:
          cpus: '2.0'              # CPU reservation
          memory: 4G               # Memory reservation
    environment:
      - NGINX_WORKER_PROCESSES=4   # Match CPU limit
```

### CPU Profiling
```bash
#!/bin/bash
# scripts/profile-cpu.sh
CONTAINER_NAME="imaginary_cache_1"

# Collect CPU statistics
docker exec $CONTAINER_NAME top -b -n 1 > cpu-stats.txt

# Profile with perf (if available)
docker exec $CONTAINER_NAME sh -c "apt-get update && apt-get install -y perf"
docker exec $CONTAINER_NAME perf record -g -p $(docker exec $CONTAINER_NAME pgrep nginx)
docker exec $CONTAINER_NAME perf report
```

## Memory Optimization

### Memory Zone Configuration
```nginx
# Optimize memory zones for better cache hit rates
proxy_cache_path  /cache/static
    keys_zone=STATIC:32m           # Increased key storage
    inactive=365d;

# Additional optimizations
open_file_cache          max=10000 inactive=20s;
open_file_cache_valid    30s;
open_file_cache_min_uses 2;
open_file_cache_errors   on;
```

### Memory Usage Monitoring
```bash
#!/bin/bash
# scripts/monitor-memory.sh
CONTAINER_NAME="imaginary_cache_1"

while true; do
    echo "=== $(date) ==="
    docker stats $CONTAINER_NAME --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"

    # Cache statistics
    CACHE_SIZE=$(docker exec $CONTAINER_NAME du -sh /cache/ 2>/dev/null | cut -f1)
    echo "Cache Size: $CACHE_SIZE"

    sleep 30
done
```

## Network Optimization

### Connection Tuning
```nginx
# Connection optimization
keepalive_requests 10000;           # Keep-alive requests per connection
keepalive_timeout 65;               # Keep-alive timeout

# TCP optimization (in container or host)
# tcp_nodelay on;                  # Already enabled above
# tcpnopush on;                    # Already enabled above

# HTTP/2 support (add to server block)
listen 443 ssl http2;
```

### Network Settings (Host Level)
```bash
# /etc/sysctl.conf optimizations
# TCP buffer sizes
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# TCP connection settings
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_max_tw_buckets = 5000

# Apply settings
sudo sysctl -p
```

## Caching Performance

### Cache Warming Strategies
```bash
#!/bin/bash
# scripts/warm-cache.sh
BASE_URL="http://localhost"
IMAGES=(
    "https://homepages.cae.wisc.edu/~ece533/images/baboon.png"
    "https://homepages.cae.wisc.edu/~ece533/images/lena.png"
    "https://homepages.cae.wisc.edu/~ece533/images/monarch.png"
)

SIZES=(100 200 400 800 1200)
OPERATIONS=(resize thumbnail crop)

echo "Starting cache warmup..."

for img in "${IMAGES[@]}"; do
    for size in "${SIZES[@]}"; do
        for op in "${OPERATIONS[@]}"; do
            url="$BASE_URL/$op?width=$size&url=$(echo $img | sed 's/&/%26/g')"
            echo "Warming: $op ${size}px - $(basename $img)"

            # Make request with timeout
            timeout 30 curl -s -o /dev/null "$url" &

            # Parallel requests (limit concurrency)
            if (( $(jobs -r | wc -l) >= 10 )); then
                wait -n
            fi
        done
    done
done

wait
echo "Cache warmup completed"
```

### Cache Analysis
```bash
#!/bin/bash
# scripts/analyze-cache.sh
CACHE_DIR="./img-cache"

echo "=== Cache Analysis ==="
echo "Total Cache Size: $(du -sh $CACHE_DIR | cut -f1)"
echo "Number of Files: $(find $CACHE_DIR -type f | wc -l)"
echo "Directory Count: $(find $CACHE_DIR -type d | wc -l)"

# File size distribution
echo "=== File Size Distribution ==="
find $CACHE_DIR -type f -exec du -b {} + | awk '
{size[$1]++}
END {
    for (s in size) {
        printf "%-12s %d files\n", s, size[s]
    }
}' | sort -n

# Cache hit rate estimation (requires access logs)
if [ -f "./logs/nginx/access.log" ]; then
    echo "=== Cache Hit Rate ==="
    grep "X-Proxy-Cache: HIT" ./logs/nginx/access.log | wc -l > hits
    grep "X-Proxy-Cache:" ./logs/nginx/access.log | wc -l > total
    HITS=$(cat hits)
    TOTAL=$(cat total)
    if [ $TOTAL -gt 0 ]; then
        RATE=$(echo "scale=2; $HITS * 100 / $TOTAL" | bc)
        echo "Hit Rate: ${RATE}% ($HITS/$TOTAL)"
    fi
    rm hits total
fi
```

## Benchmarking

### Load Testing with Apache Bench
```bash
#!/bin/bash
# scripts/benchmark.sh
BASE_URL="http://localhost"
TEST_URL="/thumbnail?width=400&url=https://homepages.cae.wisc.edu/~ece533/images/baboon.png"

echo "=== Performance Benchmark ==="

# Different concurrency levels
for CONCURRENCY in 10 50 100 200 500; do
    echo "Testing with $CONCURRENCY concurrent requests..."

    ab -n 1000 -c $CONCURRENCY "$BASE_URL$TEST_URL" > "benchmark_$CONCURRENCY.txt"

    # Extract key metrics
    RPS=$(grep "Requests per second" "benchmark_$CONCURRENCY.txt" | awk '{print $4}')
    RTIME=$(grep "Time per request.*mean" "benchmark_$CONCURRENCY.txt" | awk '{print $4}')

    echo "Concurrency: $CONCURRENCY, RPS: $RPS, Response Time: ${RTIME}ms"
done
```

### WRK Load Testing
```bash
#!/bin/bash
# scripts/wrk-benchmark.sh
BASE_URL="http://localhost"
TEST_URL="/thumbnail?width=400&url=https://homepages.cae.wisc.edu/~ece533/images/baboon.png"

echo "=== WRK Benchmark ==="

# 12 threads, 400 connections for 30 seconds
wrk -t12 -c400 -d30s "$BASE_URL$TEST_URL"

# With custom script for different operations
cat > wrk-script.lua << 'EOF'
counter = 0

request = function()
    counter = counter + 1
    local sizes = {100, 200, 400, 800}
    local operations = {"resize", "thumbnail", "crop"}
    local size = sizes[counter % #sizes + 1]
    local op = operations[math.floor(counter / #sizes) % #operations + 1]

    local path = string.format("/%s?width=%d&url=https://example.com/test.jpg", op, size)
    return wrk.format("GET", path)
end
EOF

wrk -t12 -c400 -d30s -s wrk-script.lua "$BASE_URL"
```

### Performance Monitoring
```yaml
# monitoring/docker-compose.perf.yml
version: "3.8"
services:
  # Node Exporter for system metrics
  node-exporter:
    image: prom/node-exporter:latest
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'

  # Grafana for visualization
  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - ./grafana/dashboards:/etc/grafana/provisioning/dashboards
      - ./grafana/data:/var/lib/grafana
```

## Performance Profiling

### Nginx Request Timing
```nginx
# Add to nginx.conf for timing
log_format timing '$remote_addr - $remote_user [$time_local] '
                   '"$request" $status $body_bytes_sent '
                   '"$http_referer" "$http_user_agent" '
                   'rt=$request_time uct="$upstream_connect_time" '
                   'uht="$upstream_header_time" urt="$upstream_response_time" '
                   'cs=$upstream_cache_status';

access_log /var/log/nginx/timing.log timing;
```

### Cache Performance Analysis
```bash
#!/bin/bash
# scripts/cache-performance.sh
LOG_FILE="./logs/nginx/timing.log"

if [ ! -f "$LOG_FILE" ]; then
    echo "Timing log not found. Enable timing format in nginx.conf"
    exit 1
fi

echo "=== Cache Performance Analysis ==="

# Cache hit rate
echo "Cache Hit Rate:"
grep "cs=HIT" "$LOG_FILE" | wc -l > hits
grep "cs=" "$LOG_FILE" | wc -l > total
HITS=$(cat hits)
TOTAL=$(cat total)
if [ $TOTAL -gt 0 ]; then
    RATE=$(echo "scale=2; $HITS * 100 / $TOTAL" | bc)
    echo "  ${RATE}% ($HITS/$TOTAL requests)"
fi

# Average response times
echo "Response Times:"
echo "  Cache HIT: $(grep "cs=HIT" "$LOG_FILE" | awk '{sum+=$8; count++} END {if(count>0) print sum/count "ms"}')"
echo "  Cache MISS: $(grep "cs=MISS" "$LOG_FILE" | awk '{sum+=$8; count++} END {if(count>0) print sum/count "ms"}')"

# Slow requests (>100ms)
echo "Slow Requests (>100ms):"
grep "rt=[0-9]*\.[0-9][0-9][0-9]" "$LOG_FILE" | wc -l

# Clean up
rm hits total
```

## Troubleshooting Performance Issues

### Common Bottlenecks

#### High CPU Usage
```bash
# Check worker processes
docker exec cache ps aux | grep nginx

# Enable CPU profiling
docker exec cache strace -p $(docker exec cache pgrep nginx) -c

# Review error logs
docker exec cache tail -f /var/log/nginx/error.log
```

#### High Memory Usage
```bash
# Check memory zones
docker exec cache nginx -T 2>/dev/null | grep -E "(keys_zone|proxy_cache_path)"

# Monitor cache size
watch -n 5 'docker exec cache du -sh /cache/'
```

#### Slow Cache Responses
```bash
# Check disk I/O
docker exec cache iostat -x 1 5

# Verify cache directory permissions
docker exec cache ls -la /cache/

# Check for cache corruption
docker exec cache find /cache/ -name "*" -type f -exec file {} \;
```

### Performance Optimization Checklist

- [ ] Worker processes match CPU cores
- [ ] File descriptor limits increased
- [ ] Cache path optimized with correct size
- [ ] TCP settings tuned for network
- [ ] SSL termination efficient
- [ ] Cache warming implemented
- [ ] Monitoring and alerting configured
- [ ] Load balancing configured for scale
- [ ] Regular performance benchmarks scheduled
- [ ] Log rotation configured

## Real-World Performance Examples

### Small Instance Performance
```
Hardware: 2 CPU, 4GB RAM, 20GB SSD
Expected Performance:
- Requests/sec: 500-1000
- Cache Hit Ratio: 85-90%
- Average Response Time: 20-50ms
```

### Medium Instance Performance
```
Hardware: 4 CPU, 8GB RAM, 100GB SSD
Expected Performance:
- Requests/sec: 2000-5000
- Cache Hit Ratio: 90-95%
- Average Response Time: 10-30ms
```

### Large Instance Performance
```
Hardware: 8+ CPU, 16GB+ RAM, 500GB+ SSD
Expected Performance:
- Requests/sec: 10000+
- Cache Hit Ratio: 95-98%
- Average Response Time: 5-15ms
```

This performance guide provides comprehensive optimization strategies. Always benchmark in your specific environment and workload patterns for best results.