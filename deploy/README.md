# Daytona Production Deployment

This directory contains production deployment configuration for Daytona with Caddy reverse proxy.

## Architecture

```
                    ┌─────────────────────────────────────────┐
                    │              Caddy (HTTPS)              │
                    │                                         │
    :443 ──────────►│  domain.com          ──► localhost:3000 │
                    │  domain.com/dex/*    ──► localhost:5556 │
    :8443 ─────────►│  *.proxy.domain.com  ──► localhost:4000 │
                    └─────────────────────────────────────────┘
                                          │
                    ┌─────────────────────┴─────────────────────┐
                    │           Daytona Docker Services          │
                    │                                           │
                    │  ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐      │
                    │  │ API │  │Proxy│  │Runner│ │ SSH │      │
                    │  └─────┘  └─────┘  └─────┘  └─────┘      │
                    │                                           │
                    │  ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐      │
                    │  │ DB  │  │Redis│  │Dex  │  │MinIO│      │
                    │  └─────┘  └─────┘  └─────┘  └─────┘      │
                    └───────────────────────────────────────────┘
```

## Prerequisites

1. **Server Requirements**
   - Linux server (Ubuntu 22.04+ recommended)
   - Minimum 8GB RAM, 4 CPU cores
   - 100GB+ disk space

2. **Software**
   - Docker 24.0+
   - Docker Compose v2+

3. **DNS Configuration**
   Configure the following DNS records pointing to your server:
   ```
   domain.com           A      <server-ip>
   proxy.domain.com     A      <server-ip>
   *.proxy.domain.com   CNAME  proxy.domain.com
   ```

4. **Firewall**
   Open the following ports:
   - `80/tcp` - HTTP (for ACME challenge)
   - `443/tcp` - HTTPS Dashboard & API
   - `8443/tcp` - HTTPS Proxy service
   - `2222/tcp` - SSH Gateway

## Quick Start

### Option 1: Interactive Installation

```bash
cd deploy
chmod +x install.sh
./install.sh
```

The script will guide you through:
1. Domain configuration
2. DNS provider selection (for SSL certificate)
3. Admin user setup
4. Automatic key generation

### Option 2: Manual Configuration

1. Copy the example environment file:
   ```bash
   cp deploy/.env.example deploy/.env
   ```

2. Edit `.env` with your settings:
   ```bash
   vim deploy/.env
   ```

3. Run the installer:
   ```bash
   ./install.sh --env
   ```

## Configuration Files

| File | Description |
|------|-------------|
| `install.sh` | Main installation script |
| `.env.example` | Environment variables template |
| `caddy/Caddyfile` | Caddy reverse proxy configuration |
| `dex/config.yaml` | Dex OIDC provider configuration |

## SSL Certificates

Caddy automatically obtains and renews SSL certificates using ACME.

### DNS Challenge (Recommended)

For wildcard certificates (`*.proxy.domain.com`), DNS challenge is required.

Supported providers:
- **Aliyun DNS** - Configure `ALIYUN_ACCESS_KEY_ID` and `ALIYUN_ACCESS_KEY_SECRET`
- **Cloudflare** - Configure `CLOUDFLARE_API_TOKEN`
- **AWS Route53** - Configure AWS credentials via environment or IAM role

### HTTP Challenge

If no DNS provider is configured, HTTP challenge will be used for the main domain.
Port 80 must be accessible from the internet.

## Post-Installation

### Verify Services

```bash
# Check Daytona services
docker compose -f docker/docker-compose.yaml ps

# Check Caddy
docker logs caddy

# Check API health
curl https://your-domain.com/api/health
```

### Access Services

- **Dashboard**: `https://your-domain.com`
- **API**: `https://your-domain.com/api`
- **MinIO Console**: `http://localhost:9001` (port forward required)
- **PgAdmin**: `http://localhost:5050` (port forward required)

### Useful Commands

```bash
# View all logs
docker compose -f docker/docker-compose.yaml logs -f

# View specific service logs
docker compose -f docker/docker-compose.yaml logs -f api

# Restart services
docker compose -f docker/docker-compose.yaml restart

# Stop all services
docker compose -f docker/docker-compose.yaml down

# Restart Caddy
docker restart caddy

# Reload Caddy config
docker exec caddy caddy reload --config /etc/caddy/Caddyfile
```

## Troubleshooting

### SSL Certificate Issues

```bash
# Check Caddy logs for certificate errors
docker logs caddy 2>&1 | grep -i certificate

# Force certificate renewal
docker exec caddy caddy reload --config /etc/caddy/Caddyfile --force
```

### DNS Resolution

```bash
# Verify DNS records
dig your-domain.com
dig proxy.your-domain.com

# Test wildcard resolution
dig 12345.proxy.your-domain.com
```

### Service Health

```bash
# Check if services are responding
curl -k https://localhost:3000/api/health
curl -k https://localhost:4000/health
```

## Security Notes

1. **Change default passwords** - The installer generates random passwords, but verify they are strong
2. **Review firewall rules** - Only expose necessary ports
3. **Enable HTTPS only** - Caddy handles this automatically
4. **Regular updates** - Keep Docker images updated

## Upgrading

```bash
# Pull latest images
docker compose -f docker/docker-compose.yaml pull

# Restart services
docker compose -f docker/docker-compose.yaml up -d
```

## Backup

```bash
# Backup database
docker exec daytona-db-1 pg_dump -U user daytona > backup.sql

# Backup MinIO data
docker exec daytona-minio-1 mc mirror local/daytona /backup/daytona

# Backup volumes
docker run --rm -v daytona_db_data:/data -v $(pwd):/backup alpine tar czf /backup/db_backup.tar.gz /data
```
