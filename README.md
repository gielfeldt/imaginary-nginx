
# Imaginary Nginx

A high-performance caching reverse proxy for [Imaginary](https://github.com/h2non/imaginary) image processing service. This project provides SSL termination, aggressive caching, and production-ready deployment configuration for image transformation workloads.

## Overview

Imaginary Nginx sits in front of the Imaginary image processing service to provide:

- **Aggressive Caching**: 365-day cache TTL for transformed images
- **SSL Termination**: HTTPS support with self-signed certificates
- **High Performance**: Unix socket communication, background cache updates
- **Production Ready**: Configurable, scalable, and fault-tolerant

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   Client    │────▶│   Nginx      │────▶│  Imaginary  │
│   (HTTPS)   │     │   (Cache)    │     │  Service    │
└─────────────┘     └──────────────┘     └─────────────┘
                           │
                   ┌───────▼───────┐
                   │    Cache      │
                   │   (10GB)      │
                   └───────────────┘
```

## Features

- **Smart Caching**: 365-day TTL for successful responses, short TTL for errors
- **Cache Bypass**: Environment variable control for cache invalidation
- **Background Updates**: Refreshes cache while serving stale content
- **SSL Support**: Self-signed certificates with configurable ciphers
- **Unix Socket**: Efficient backend communication
- **DNS Resolution**: Built-in resolver for service discovery
- **Health Checks**: Graceful error handling and stale content serving
- **Monitoring**: Cache status headers and comprehensive logging

## Quick Start

### Using Docker Compose (Recommended)

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd imaginary-nginx
   ```

2. **Start the services:**
   ```bash
   docker-compose up -d
   ```

3. **Test the service:**
   ```bash
   curl -I 'http://localhost/thumbnail?width=640&quality=95&url=https://homepages.cae.wisc.edu/~ece533/images/baboon.png'
   ```

### Custom Port Mapping

Create `docker-compose.override.yml` to map different ports:

```yaml
version: "3"

services:
  cache:
    ports:
      - 8080:80
      - 8443:443
```

Then run `docker-compose up -d`.

## Usage Examples

### Basic Image Transformations

```bash
# Thumbnail generation
curl 'http://localhost/thumbnail?width=400&height=300&url=https://example.com/image.jpg'

# Resize with quality control
curl 'http://localhost/resize?width=800&quality=85&url=https://example.com/image.jpg'

# Crop and resize
curl 'http://localhost/crop?width=500&height=500&quality=90&url=https://example.com/image.jpg'
```

### SSL/HTTPS Usage

```bash
# Using HTTPS with self-signed certificate
curl -k 'https://localhost/thumbnail?width=640&url=https://example.com/image.jpg'
```

### Cache Control

```bash
# Bypass cache (if BYPASS_CACHE=1)
curl 'http://localhost/thumbnail?width=640&nocache=1&url=https://example.com/image.jpg'

# Check cache status
curl -I 'http://localhost/thumbnail?width=640&url=https://example.com/image.jpg'
# Look for X-Proxy-Cache: HIT/MISS
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `IMAGINARY_URL` | `http://imaginary:9000` | Backend Imaginary service URL |
| `BYPASS_CACHE` | `0` | Global cache bypass flag (0/1) |
| `DEBUG` | - | Imaginary debug flag (uncomment to enable) |

### Volume Mounts (Optional)

Uncomment in `docker-compose.yml` to enable:

```yaml
volumes:
  - ./img-cache:/cache     # Persistent cache storage
  - ./images:/images       # Local image files
  - ./certs:/certs         # Custom SSL certificates
```

## Development

### Local Development Setup

1. **Start services with custom ports:**
   ```bash
   # Create docker-compose.override.yml
   cat > docker-compose.override.yml << EOF
   version: "3"
   services:
     cache:
       ports:
         - 81:80
         - 444:443
   EOF

   docker-compose up -d
   ```

2. **Monitor logs:**
   ```bash
   docker-compose logs -f cache
   docker-compose logs -f imaginary
   ```

3. **Cache debugging:**
   ```bash
   # Check cache headers
   curl -v 'http://localhost/thumbnail?width=100&url=https://example.com/image.jpg' 2>&1 | grep -E "(X-Proxy-Cache|Cache-Control)"

   # Inspect cache storage (if mounted)
   ls -la ./img-cache/
   ```

### Building from Source

```bash
# Build cache image
docker build -t imaginary-nginx ./cache

# Run manually
docker run -d --name imaginary \
  h2non/imaginary:1.2.4 -concurrency 10 -enable-url-source

docker run -d -p 80:80 \
  -e IMAGINARY_URL=http://imaginary:9000 \
  --link imaginary \
  imaginary-nginx
```

## Production Deployment

For production deployments, see [DEPLOYMENT.md](DEPLOYMENT.md).

Key considerations:
- Use proper SSL certificates instead of self-signed
- Configure persistent cache storage
- Set up monitoring and alerting
- Consider cache warmup strategies

## Performance

For performance tuning and benchmarks, see [PERFORMANCE.md](PERFORMANCE.md).

### Key Metrics
- **Cache Hit Ratio**: >95% typical for warm cache
- **Response Time**: <10ms for cached responses
- **Cache Size**: Configurable up to 10GB
- **Concurrency**: Handles thousands of concurrent requests

## Configuration Details

For detailed configuration options, see [CONFIGURATION.md](CONFIGURATION.md).

## Troubleshooting

### Common Issues

1. **502 Bad Gateway**: Imaginary service not running
   ```bash
   docker-compose ps
   docker-compose logs imaginary
   ```

2. **Cache not working**: Check cache directory permissions
   ```bash
   docker exec -it cache ls -la /cache/
   ```

3. **SSL errors**: Certificate issues
   ```bash
   docker exec -it cache ls -la /certs/
   ```

4. **High memory usage**: Adjust Nginx worker connections
   - Edit `cache/nginx.conf` worker_connections

### Health Checks

```bash
# Test Imaginary backend directly
docker exec -it cache curl http://imaginary:9000/health

# Test Nginx cache
curl -I http://localhost/health
```

## License

This project extends the Imaginary ecosystem. See individual component licenses for details.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## Support

- [Imaginary Documentation](https://github.com/h2non/imaginary)
- [Nginx Documentation](https://nginx.org/en/docs/)
- Issues: Report bugs via GitHub issues
