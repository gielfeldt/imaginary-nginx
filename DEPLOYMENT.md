# Production Deployment Guide

This guide covers production deployment strategies, security best practices, and operational considerations for Imaginary Nginx.

## Production Architecture

### Recommended Setup

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   Client    │────▶│  Load        │────▶│ Imaginary   │
│             │     │  Balancer    │     │  Cluster    │
└─────────────┘     │  (HTTPS)     │     └─────────────┘
                    └──────────────┘
                           │
                   ┌───────▼───────┐
                   │   Imaginary   │
                   │  Nginx Cache  │
                   │  (Multi-az)   │
                   └───────────────┘
                           │
                   ┌───────▼───────┐
                   │  Shared Cache │
                   │  (S3/NFS)     │
                   └───────────────┘
```

## Production Requirements

### Minimum System Requirements

#### Small Deployment (<1K requests/sec)
- **CPU**: 2 cores
- **RAM**: 4GB
- **Storage**: 20GB SSD
- **Network**: 100Mbps

#### Medium Deployment (1K-10K requests/sec)
- **CPU**: 4 cores
- **RAM**: 8GB
- **Storage**: 100GB SSD
- **Network**: 1Gbps

#### Large Deployment (10K+ requests/sec)
- **CPU**: 8+ cores
- **RAM**: 16GB+
- **Storage**: 500GB+ SSD
- **Network**: 10Gbps

### SSL Certificates

#### Let's Encrypt (Recommended)
```yaml
# docker-compose.override.yml
version: "3"
services:
  cache:
    volumes:
      - ./certs/letsencrypt:/certs:ro
    environment:
      - SSL_CERT=/certs/letsencrypt/live/domain.com/fullchain.pem
      - SSL_KEY=/certs/letsencrypt/live/domain.com/privkey.pem
```

#### Certificate Setup Script
```bash
#!/bin/bash
# setup-ssl.sh
DOMAIN="your-domain.com"
EMAIL="admin@your-domain.com"

# Get Let's Encrypt certificate
docker run --rm -it \
  -v ./certs/letsencrypt:/etc/letsencrypt \
  -p 80:80 \
  certbot/certbot certonly --standalone -d $DOMAIN --email $EMAIL --agree-tos

# Set up auto-renewal
echo "0 12 * * * docker run --rm -v ./certs/letsencrypt:/etc/letsencrypt -p 80:80 certbot/certbot renew --quiet" | crontab -
```

#### Custom CA Certificates
```yaml
volumes:
  - ./certs/ca:/etc/ssl/certs:ro
  - ./certs/server:/certs:ro
```

## Docker Compose Production

### Production Docker Compose
```yaml
version: "3.8"

services:
  imaginary:
    image: h2non/imaginary:1.2.4
    command: -concurrency 20 -enable-url-source -mount /images
    restart: unless-stopped
    volumes:
      - ./images:/images:ro
    environment:
      - PORT=9000
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '1'
          memory: 1G

  cache:
    build: ./cache
    restart: unless-stopped
    volumes:
      - ./cache/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./cache/imaginary.conf:/etc/nginx/imaginary.conf:ro
      - ./certs:/certs:ro
      - ./img-cache:/cache
      - ./logs/nginx:/var/log/nginx
    environment:
      - IMAGINARY_URL=http://imaginary:9000
      - BYPASS_CACHE=0
    ports:
      - "80:80"
      - "443:443"
    depends_on:
      - imaginary
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 4G
        reservations:
          cpus: '1'
          memory: 2G
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  # Optional: Redis for distributed caching
  redis:
    image: redis:7-alpine
    restart: unless-stopped
    volumes:
      - ./data/redis:/data
    command: redis-server --appendonly yes --maxmemory 512mb --maxmemory-policy allkeys-lru
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M

networks:
  default:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
```

### Environment-Specific Configurations

#### Production Environment
```bash
# .env.production
COMPOSE_PROJECT_NAME=imaginary-prod
IMAGINARY_CONCURRENCY=20
NGINX_WORKERS=auto
CACHE_SIZE=50g
SSL_MODE=letsencrypt
LOG_LEVEL=warn
```

#### Staging Environment
```bash
# .env.staging
COMPOSE_PROJECT_NAME=imaginary-staging
IMAGINARY_CONCURRENCY=5
NGINX_WORKERS=2
CACHE_SIZE=5g
SSL_MODE=self-signed
LOG_LEVEL=info
```

## Kubernetes Deployment

### Namespace and ConfigMap
```yaml
# k8s/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: imaginary

---
# k8s/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: imaginary-config
  namespace: imaginary
data:
  nginx.conf: |
    # Production nginx configuration
    worker_processes auto;
    events {
        worker_connections 4096;
    }
    http {
        # Your production config
    }
  imaginary.conf: |
    # Imaginary-specific config
```

### Imaginary Deployment
```yaml
# k8s/imaginary-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: imaginary
  namespace: imaginary
spec:
  replicas: 3
  selector:
    matchLabels:
      app: imaginary
  template:
    metadata:
      labels:
        app: imaginary
    spec:
      containers:
      - name: imaginary
        image: h2non/imaginary:1.2.4
        command: ["-concurrency", "20", "-enable-url-source"]
        ports:
        - containerPort: 9000
        resources:
          requests:
            memory: "1Gi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "2000m"
        livenessProbe:
          httpGet:
            path: /health
            port: 9000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health
            port: 9000
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: imaginary-service
  namespace: imaginary
spec:
  selector:
    app: imaginary
  ports:
  - port: 9000
    targetPort: 9000
  type: ClusterIP
```

### Nginx Cache Deployment
```yaml
# k8s/nginx-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: imaginary-nginx
  namespace: imaginary
spec:
  replicas: 2
  selector:
    matchLabels:
      app: imaginary-nginx
  template:
    metadata:
      labels:
        app: imaginary-nginx
    spec:
      containers:
      - name: nginx
        image: your-registry/imaginary-nginx:latest
        ports:
        - containerPort: 80
        - containerPort: 443
        env:
        - name: IMAGINARY_URL
          value: "http://imaginary-service:9000"
        resources:
          requests:
            memory: "2Gi"
            cpu: "1000m"
          limits:
            memory: "4Gi"
            cpu: "2000m"
        volumeMounts:
        - name: cache-storage
          mountPath: /cache
        - name: ssl-certs
          mountPath: /certs
          readOnly: true
      volumes:
      - name: cache-storage
        persistentVolumeClaim:
          claimName: cache-pvc
      - name: ssl-certs
        secret:
          secretName: ssl-certs
---
apiVersion: v1
kind: Service
metadata:
  name: imaginary-nginx-service
  namespace: imaginary
spec:
  selector:
    app: imaginary-nginx
  ports:
  - name: http
    port: 80
    targetPort: 80
  - name: https
    port: 443
    targetPort: 443
  type: LoadBalancer
```

### Persistent Storage
```yaml
# k8s/pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cache-pvc
  namespace: imaginary
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 100Gi
  storageClassName: fast-ssd
```

### Ingress Configuration
```yaml
# k8s/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: imaginary-ingress
  namespace: imaginary
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
    nginx.ingress.kubernetes.io/proxy-cache-valid: "200 365d"
spec:
  tls:
  - hosts:
    - images.yourdomain.com
    secretName: imagetls
  rules:
  - host: images.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: imaginary-nginx-service
            port:
              number: 80
```

## High Availability Setup

### Multi-Region Deployment
```yaml
# aws/cloudformation-template.yaml
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Imaginary Nginx Multi-AZ Deployment'

Resources:
  VPC:
    Type: AWS::EC2::VPC
    Properties:
      CidrBlock: 10.0.0.0/16
      EnableDnsSupport: true
      EnableDnsHostnames: true

  PublicSubnets:
    Type: AWS::EC2::Subnet
    Properties:
      VpcId: !Ref VPC
      CidrBlock: 10.0.1.0/24
      AvailabilityZone: us-east-1a
      MapPublicIpOnLaunch: true

  ECSCluster:
    Type: AWS::ECS::Cluster
    Properties:
      ClusterName: imaginary-prod
      CapacityProviders:
        - FARGATE
        - FARGATE_SPOT

  TaskDefinition:
    Type: AWS::ECS::TaskDefinition
    Properties:
      Cpu: '2048'
      Memory: '4096'
      NetworkMode: awsvpc
      RequiresCompatibilities:
        - FARGATE
      ContainerDefinitions:
        - Name: imaginary
          Image: h2non/imaginary:1.2.4
          PortMappings:
            - ContainerPort: 9000
```

### Load Balancer Configuration
```yaml
# docker-compose.lb.yml
version: "3.8"
services:
  # HAProxy Load Balancer
  load-balancer:
    image: haproxy:2.4-alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
      - ./certs:/certs:ro
    depends_on:
      - cache-1
      - cache-2
    deploy:
      replicas: 2

  cache-1:
    extends:
      file: docker-compose.yml
      service: cache
    environment:
      - INSTANCE_ID=1

  cache-2:
    extends:
      file: docker-compose.yml
      service: cache
    environment:
      - INSTANCE_ID=2
```

### HAProxy Configuration
```
# haproxy/haproxy.cfg
global
    daemon
    maxconn 4096

defaults
    mode http
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

frontend http_frontend
    bind *:80
    bind *:443 ssl crt /certs/server.pem
    redirect scheme https if !{ ssl_fc }
    default_backend cache_servers

backend cache_servers
    balance roundrobin
    option httpchk GET /health
    server cache1 cache-1:80 check
    server cache2 cache-2:80 check
```

## Monitoring and Logging

### Prometheus Monitoring
```yaml
# monitoring/prometheus.yml
version: "3.8"
services:
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - ./prometheus/data:/prometheus

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - ./grafana/data:/var/lib/grafana
      - ./grafana/dashboards:/etc/grafana/provisioning/dashboards

  nginx-exporter:
    image: nginx/nginx-prometheus-exporter:latest
    ports:
      - "9113:9113"
    command:
      - -nginx.scrape-uri
      - http://cache:80/nginx_status
```

### Nginx Status Module
```nginx
# Add to nginx.conf
location /nginx_status {
    stub_status on;
    access_log off;
    allow 127.0.0.1;
    allow 172.20.0.0/16;  # Docker network
    deny all;
}
```

### ELK Stack for Logging
```yaml
# logging/elk.yml
version: "3.8"
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:7.14.0
    environment:
      - discovery.type=single-node
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
    volumes:
      - ./elasticsearch/data:/usr/share/elasticsearch/data

  logstash:
    image: docker.elastic.co/logstash/logstash:7.14.0
    volumes:
      - ./logstash/pipeline:/usr/share/logstash/pipeline
      - ./logs/nginx:/var/log/nginx:ro

  kibana:
    image: docker.elastic.co/kibana/kibana:7.14.0
    ports:
      - "5601:5601"
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
```

## Security Hardening

### Security Headers
```nginx
# Add to nginx configuration
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
add_header Content-Security-Policy "default-src 'self'; img-src * data: blob:;" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
```

### Rate Limiting
```nginx
# Rate limiting by IP
limit_req_zone $binary_remote_addr zone=per_ip:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=per_ip_heavy:10m rate=1r/s;

# Apply to locations
location / {
    limit_req zone=per_ip burst=20 nodelay;
    # ... other config
}

location ~* ^/heavy/ {
    limit_req zone=per_ip_heavy burst=5 nodelay;
    # ... other config
}
```

### IP Whitelisting
```nginx
# Admin endpoints
location /admin {
    allow 192.168.1.0/24;
    allow 10.0.0.0/8;
    deny all;
    # ... other config
}
```

### Fail2Ban Integration
```bash
# fail2ban/jail.local
[nginx-http-auth]
enabled = true
filter = nginx-http-auth
logpath = /var/log/nginx/error.log
maxretry = 5
findtime = 600
bantime = 7200

[nginx-limit-req]
enabled = true
filter = nginx-limit-req
logpath = /var/log/nginx/error.log
maxretry = 10
findtime = 600
bantime = 7200
```

## Backup and Disaster Recovery

### Automated Backup Script
```bash
#!/bin/bash
# scripts/backup.sh
BACKUP_DIR="/backups/imaginary"
DATE=$(date +%Y%m%d_%H%M%S)

# Create backup directory
mkdir -p $BACKUP_DIR

# Backup cache
tar -czf $BACKUP_DIR/cache_$DATE.tar.gz ./img-cache/

# Backup configuration
tar -czf $BACKUP_DIR/config_$DATE.tar.gz ./cache/ ./docker-compose.yml ./.env*

# Backup to cloud storage (AWS S3 example)
aws s3 cp $BACKUP_DIR/cache_$DATE.tar.gz s3://your-backup-bucket/imaginary/
aws s3 cp $BACKUP_DIR/config_$DATE.tar.gz s3://your-backup-bucket/imaginary/

# Clean old backups (keep 30 days)
find $BACKUP_DIR -name "*.tar.gz" -mtime +30 -delete

echo "Backup completed: $DATE"
```

### Restore Procedure
```bash
#!/bin/bash
# scripts/restore.sh
BACKUP_DATE=$1
BACKUP_DIR="/backups/imaginary"

if [ -z "$BACKUP_DATE" ]; then
    echo "Usage: $0 <backup_date>"
    exit 1
fi

# Stop services
docker-compose down

# Restore cache
tar -xzf $BACKUP_DIR/cache_$BACKUP_DATE.tar.gz

# Restore configuration
tar -xzf $BACKUP_DIR/config_$BACKUP_DATE.tar.gz

# Start services
docker-compose up -d

echo "Restore completed: $BACKUP_DATE"
```

## Scaling Strategies

### Horizontal Scaling
```yaml
# docker-compose.scale.yml
version: "3.8"
services:
  cache:
    deploy:
      replicas: 3
    environment:
      - INSTANCE_ID={{.Task.Slot}}

  # Add Redis for distributed cache coordination
  redis:
    image: redis:7-alpine
    command: redis-server --maxmemory 2gb --maxmemory-policy allkeys-lru
```

### Auto-scaling with Kubernetes
```yaml
# k8s/hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: imaginary-nginx-hpa
  namespace: imaginary
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: imaginary-nginx
  minReplicas: 2
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

This deployment guide covers production-ready configurations for various scenarios. Always test thoroughly in a staging environment before deploying to production.