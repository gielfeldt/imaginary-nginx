# Configuration Guide

This guide covers detailed configuration options for Imaginary Nginx, including environment variables, Nginx directives, and advanced caching strategies.

## Environment Variables

### Core Configuration

| Variable | Default | Required | Description |
|----------|---------|----------|-------------|
| `IMAGINARY_URL` | `http://imaginary:9000` | Yes | Backend Imaginary service URL |
| `BYPASS_CACHE` | `0` | No | Global cache bypass (0=enabled, 1=disabled) |
| `DEBUG` | - | No | Imaginary debug mode (uncomment in compose) |

### Setting Environment Variables

#### Docker Compose
```yaml
services:
  cache:
    environment:
      IMAGINARY_URL: "http://imaginary-backup:9000"
      BYPASS_CACHE: "1"
```

#### Docker Run
```bash
docker run -d \
  -e IMAGINARY_URL="http://custom-imaginary:9000" \
  -e BYPASS_CACHE="1" \
  imaginary-nginx
```

## Nginx Configuration

### Main Configuration (`cache/nginx.conf`)

#### Worker Settings
```nginx
worker_processes  auto;        # Auto-detect CPU cores
worker_connections  1024;     # Connections per worker
```

**Performance Tuning:**
- High traffic: Increase `worker_connections` to 4096+
- CPU-intensive workloads: Set `worker_processes` to CPU core count
- Memory constraints: Reduce `worker_connections`

#### Cache Configuration
```nginx
proxy_cache_path  /cache/static
    levels=1:2                      # Directory structure depth
    keys_zone=STATIC:10m           # Cache keys memory zone (10MB)
    inactive=365d                   # Remove unused items after 1 year
    max_size=10g                    # Maximum cache size (10GB)
    use_temp_path=off;              # Use direct I/O for better performance
```

**Cache Path Options:**
- `levels=1:2`: Creates 2-level directory structure (/cache/static/a/b/)
- `keys_zone`: Memory for cache keys (recommend 1% of max_size)
- `inactive`: Cache TTL for unused items
- `max_size`: Maximum disk usage (adjust based on available storage)

#### SSL Configuration
```nginx
ssl_certificate     /certs/server.crt;
ssl_certificate_key /certs/server.key;
ssl_protocols       TLSv1 TLSv1.1 TLSv1.2;
ssl_ciphers         HIGH:!aNULL:!MD5;
```

**Production SSL:**
```nginx
ssl_protocols       TLSv1.2 TLSv1.3;
ssl_ciphers         ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512;
ssl_prefer_server_ciphers on;
ssl_session_cache   shared:SSL:10m;
ssl_session_timeout 10m;
```

### Imaginary Configuration (`cache/imaginary.conf`)

#### Cache Settings
```nginx
proxy_cache            STATIC;
proxy_cache_valid      200  365d;    # Success responses: 1 year
proxy_cache_valid      404  10s;     # Not found: 10 seconds
proxy_cache_valid      406  10s;     # Not acceptable: 10 seconds
```

**Custom Cache TTLs:**
```nginx
proxy_cache_valid      200 301 302  7d;    # Include redirects
proxy_cache_valid      500 502 503 504  1m;  # Server errors: 1 minute
```

#### Cache Key Configuration
```nginx
proxy_cache_key $scheme$host$uri$is_args$args;
```

**Custom Cache Keys:**
```nginx
# Include user-agent for content negotiation
proxy_cache_key $scheme$host$uri$is_args$args$http_user_agent;

# Include Accept header for different formats
proxy_cache_key $scheme$host$uri$is_args$args$http_accept;
```

#### Bypass Configuration
```nginx
proxy_cache_bypass $bypass_cache;
proxy_cache_bypass $http_pragma $http_authorization;
```

## Advanced Configuration

### Custom Nginx Modules

Add to `cache/Dockerfile`:
```dockerfile
RUN apk add nginx-module-http-perl \
           nginx-module-http-image-filter \
           nginx-module-http-geoip
```

### Rate Limiting
```nginx
# Add to nginx.conf http block
limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;

# Add to location block
location / {
    limit_req zone=api burst=20 nodelay;
    # ... other config
}
```

### Request Size Limits
```nginx
client_max_body_size        100m;    # Max request size
client_body_buffer_size     128k;    # Request buffer size
proxy_buffer_size           4k;      # Proxy buffer size
proxy_buffers               4 32k;   # Proxy buffer count and size
```

### Health Checks
```nginx
location /health {
    access_log    off;
    return        200 "healthy\n";
    add_header    Content-Type text/plain;
}
```

### Custom Error Pages
```nginx
error_page   500 502 503 504  /50x.html;
location = /50x.html {
    root   /usr/share/nginx/html;
}
```

## Volume Mounts

### Persistent Cache
```yaml
volumes:
  - ./img-cache:/cache
```

**Directory Structure:**
```
./img-cache/
├── static/              # Main cache directory
│   ├── a/              # Level 1 directories
│   │   ├── ab/         # Level 2 directories
│   │   │   └── cached_file
├── static.temp/        # Temporary files
└── ...                 # Nginx internal files
```

### Custom SSL Certificates
```yaml
volumes:
  - ./certs:/certs:ro   # Read-only certificate mount
```

**Required Files:**
```
./certs/
├── server.crt          # SSL certificate
└── server.key          # Private key
```

### Local Image Storage
```yaml
volumes:
  - ./images:/images    # Mount local images
```

**Access in Imaginary:**
```bash
# Access local images
curl 'http://localhost/thumbnail?width=400&url=file:///images/local.jpg'
```

## Caching Strategies

### Cache Invalidation

#### Time-Based Invalidation
```nginx
# Different TTLs by endpoint
location ~* ^/resize/ {
    proxy_cache_valid 200  1d;     # Resized images: 1 day
}

location ~* ^/thumbnail/ {
    proxy_cache_valid 200  365d;   # Thumbnails: 1 year
}
```

#### Environment Variable Bypass

The cache bypass is controlled via the `BYPASS_CACHE` environment variable:

```bash
# Set in docker-compose.yml
services:
  cache:
    environment:
      BYPASS_CACHE: "1"  # Bypass all caching
```

#### Header-Based Bypass
```nginx
# Bypass with specific headers
proxy_cache_bypass $http_cache_control $http_authorization;
```

### Cache Warming

#### Preload Script
```bash
#!/bin/bash
# warm-cache.sh
IMAGES=(
    "https://example.com/image1.jpg"
    "https://example.com/image2.png"
)

SIZES=(100 200 400 800)

for img in "${IMAGES[@]}"; do
    for size in "${SIZES[@]}"; do
        echo "Warming: $img @ ${size}px"
        curl -s "http://localhost/thumbnail?width=$size&url=$img" > /dev/null
    done
done
```

### Cache Monitoring

#### Cache Status Header
```nginx
add_header X-Proxy-Cache $upstream_cache_status always;
```

**Status Values:**
- `MISS`: Not cached
- `HIT`: Served from cache
- `EXPIRED`: Cache expired, revalidated
- `UPDATING`: Cache being updated in background
- `BYPASS`: Cache bypassed

#### Log Analysis
```bash
# Extract cache statistics from logs
docker exec cache tail -f /var/log/nginx/access.log | \
    grep -E "X-Proxy-Cache" | \
    awk '{print $NF}' | sort | uniq -c
```

## Security Configuration

### Access Control
```nginx
# Restrict by IP
location /admin {
    allow 192.168.1.0/24;
    deny  all;
    # ... other config
}

# Basic authentication
location /private {
    auth_basic "Restricted";
    auth_basic_user_file /etc/nginx/.htpasswd;
    # ... other config
}
```

### Request Filtering
```nginx
# Block suspicious requests
if ($args ~* "(\.\./)|(union.*select)|(insert.*into)") {
    return 403;
}

# Limit allowed image operations
location ~* ^/(thumbnail|resize|crop)/ {
    # Allowed operations only
    proxy_pass http://unix:/var/run/nginx.socket;
}

location / {
    # Block all other operations
    return 403;
}
```

### CORS Configuration
```nginx
add_header 'Access-Control-Allow-Origin' '*';
add_header 'Access-Control-Allow-Methods' 'GET, OPTIONS';
add_header 'Access-Control-Allow-Headers' 'Origin, X-Requested-With, Content-Type, Accept';
```

## Troubleshooting Configuration

### Cache Issues
```bash
# Check cache directory permissions
docker exec cache ls -la /cache/

# Verify cache keys zone
docker exec cache nginx -T | grep "keys_zone"

# Monitor cache usage
docker exec cache du -sh /cache/
```

### SSL Issues
```bash
# Verify certificate
docker exec cache openssl x509 -in /certs/server.crt -text -noout

# Test SSL connection
docker exec cache openssl s_client -connect localhost:443
```

### Backend Connectivity
```bash
# Test Imaginary backend
docker exec cache curl -v http://imaginary:9000/

# Check resolver configuration
docker exec cache nslookup imaginary
```

## Performance Optimization

### Nginx Tuning
```nginx
# Add to nginx.conf
worker_processes  auto;
worker_rlimit_nofile 65535;

events {
    worker_connections  4096;
    use                 epoll;    # Linux
    multi_accept        on;
}

http {
    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;
    keepalive_timeout  65;
}
```

### File System Optimization
```bash
# Optimize cache directory
docker exec cache chown -R nginx:nginx /cache/
docker exec cache chmod -R 755 /cache/

# Set appropriate mount options in docker-compose.yml
volumes:
  - ./img-cache:/cache:consistency=cached
```

For more advanced performance tuning, see [PERFORMANCE.md](PERFORMANCE.md).