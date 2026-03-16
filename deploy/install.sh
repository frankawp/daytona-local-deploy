#!/bin/bash
# =============================================================================
# Daytona Installation Script
# =============================================================================
# This script sets up and starts Daytona with Caddy for production deployment.
#
# Prerequisites:
#   - Docker and Docker Compose installed
#   - Domain DNS records configured:
#     - <DOMAIN>         -> Server IP
#     - proxy.<DOMAIN>   -> Server IP
#     - *.proxy.<DOMAIN> -> Server IP
#   - Ports open: 80, 443, 8443, 2222
#
# Usage:
#   ./install.sh          # Interactive setup
#   ./install.sh --env    # Use existing .env file
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}"
echo "============================================================================="
echo "                    Daytona Production Installer                            "
echo "============================================================================="
echo -e "${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

# Check dependencies
check_dependencies() {
    echo -e "${YELLOW}Checking dependencies...${NC}"

    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Docker is not installed. Please install Docker first.${NC}"
        exit 1
    fi

    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Docker Compose is not installed. Please install Docker Compose first.${NC}"
        exit 1
    fi

    # Check if caddy with DNS providers is available or install it
    if ! docker image inspect caddy:latest-with-dns &> /dev/null 2>&1; then
        echo -e "${YELLOW}Building Caddy with DNS providers...${NC}"
        docker build -t caddy:latest-with-dns - <<'EOF'
FROM caddy:latest-builder AS builder
RUN xcaddy build \
    --with github.com/caddy-dns/alidns \
    --with github.com/caddy-dns/cloudflare \
    --with github.com/caddy-dns/route53

FROM caddy:latest
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
EOF
    fi

    echo -e "${GREEN}All dependencies satisfied.${NC}"
}

# Generate random keys
generate_keys() {
    echo -e "${YELLOW}Generating security keys...${NC}"

    ENCRYPTION_KEY=$(openssl rand -base64 32)
    ENCRYPTION_SALT=$(openssl rand -base64 32)
    POSTGRES_PASSWORD=$(openssl rand -hex 32)
    MINIO_ROOT_PASSWORD=$(openssl rand -hex 16)
    PROXY_API_KEY=$(openssl rand -hex 32)
    RUNNER_API_KEY=$(openssl rand -hex 32)
    SSH_GATEWAY_API_KEY=$(openssl rand -hex 32)
}

# Interactive configuration
interactive_setup() {
    echo -e "${BLUE}Starting interactive configuration...${NC}"
    echo ""

    # Domain
    read -p "Enter your domain (e.g., daytona.example.com): " DOMAIN
    if [ -z "$DOMAIN" ]; then
        echo -e "${RED}Domain is required.${NC}"
        exit 1
    fi

    # DNS Provider
    echo ""
    echo "Select your DNS provider for SSL certificate:"
    echo "  1) Aliyun DNS (alidns)"
    echo "  2) Cloudflare"
    echo "  3) AWS Route53"
    echo "  4) None (HTTP challenge, requires port 80)"
    read -p "Enter choice [1-4]: " DNS_CHOICE

    case $DNS_CHOICE in
        1)
            DNS_PROVIDER="alidns"
            read -p "Enter Aliyun Access Key ID: " ALIYUN_ACCESS_KEY_ID
            read -p "Enter Aliyun Access Key Secret: " ALIYUN_ACCESS_KEY_SECRET
            ;;
        2)
            DNS_PROVIDER="cloudflare"
            read -p "Enter Cloudflare API Token: " CLOUDFLARE_API_TOKEN
            ;;
        3)
            DNS_PROVIDER="route53"
            echo "Make sure AWS credentials are configured via environment variables or IAM role."
            ;;
        4)
            DNS_PROVIDER="http"
            echo "HTTP challenge will be used. Ensure port 80 is accessible."
            ;;
        *)
            echo -e "${RED}Invalid choice.${NC}"
            exit 1
            ;;
    esac

    # Admin user
    echo ""
    read -p "Enter admin email (default: admin@${DOMAIN}): " DEX_ADMIN_EMAIL
    DEX_ADMIN_EMAIL=${DEX_ADMIN_EMAIL:-"admin@${DOMAIN}"}

    read -p "Enter admin username (default: admin): " DEX_ADMIN_USERNAME
    DEX_ADMIN_USERNAME=${DEX_ADMIN_USERNAME:-"admin"}

    read -s -p "Enter admin password: " DEX_ADMIN_PASSWORD
    echo ""

    if [ -z "$DEX_ADMIN_PASSWORD" ]; then
        echo -e "${RED}Password is required.${NC}"
        exit 1
    fi

    # Generate password hash for Dex
    DEX_ADMIN_PASSWORD_HASH=$(echo "$DEX_ADMIN_PASSWORD" | htpasswd -BinC 10 "$DEX_ADMIN_USERNAME" | cut -d: -f2)

    # Generate security keys
    generate_keys
}

# Load from existing .env
load_env() {
    if [ -f "$SCRIPT_DIR/.env" ]; then
        echo -e "${GREEN}Loading configuration from .env file...${NC}"
        source "$SCRIPT_DIR/.env"
    else
        echo -e "${RED}.env file not found. Run without --env for interactive setup.${NC}"
        exit 1
    fi
}

# Create environment file
create_env_file() {
    echo -e "${YELLOW}Creating .env file...${NC}"

    cat > "$SCRIPT_DIR/.env" << EOF
# Generated by Daytona installer on $(date)
DOMAIN=$DOMAIN

# Security Keys
ENCRYPTION_KEY=$ENCRYPTION_KEY
ENCRYPTION_SALT=$ENCRYPTION_SALT
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# MinIO
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD

# API Keys
PROXY_API_KEY=$PROXY_API_KEY
RUNNER_API_KEY=$RUNNER_API_KEY
SSH_GATEWAY_API_KEY=$SSH_GATEWAY_API_KEY

# OIDC URLs
PUBLIC_OIDC_DOMAIN=https://$DOMAIN/dex
DASHBOARD_URL=https://$DOMAIN/dashboard
DASHBOARD_BASE_API_URL=https://$DOMAIN

# Proxy
PROXY_DOMAIN=proxy.$DOMAIN:8443
PROXY_PROTOCOL=https
PROXY_TEMPLATE_URL=https://{{PORT}}-{{sandboxId}}.proxy.$DOMAIN:8443
PROXY_TOOLBOX_BASE_URL=https://proxy.$DOMAIN:8443

# SSH Gateway
SSH_GATEWAY_URL=$DOMAIN:2222

# DNS Provider (for Caddy SSL)
DNS_PROVIDER=$DNS_PROVIDER
EOF

    # Add DNS provider specific variables
    case $DNS_PROVIDER in
        alidns)
            cat >> "$SCRIPT_DIR/.env" << EOF

# Aliyun DNS
ALIYUN_ACCESS_KEY_ID=$ALIYUN_ACCESS_KEY_ID
ALIYUN_ACCESS_KEY_SECRET=$ALIYUN_ACCESS_KEY_SECRET
EOF
            ;;
        cloudflare)
            cat >> "$SCRIPT_DIR/.env" << EOF

# Cloudflare DNS
CLOUDFLARE_API_TOKEN=$CLOUDFLARE_API_TOKEN
EOF
            ;;
    esac

    # Add Dex admin
    cat >> "$SCRIPT_DIR/.env" << EOF

# Dex Admin
DEX_ADMIN_EMAIL=$DEX_ADMIN_EMAIL
DEX_ADMIN_USERNAME=$DEX_ADMIN_USERNAME
EOF

    echo -e "${GREEN}.env file created successfully.${NC}"
}

# Configure Caddy
configure_caddy() {
    echo -e "${YELLOW}Configuring Caddy...${NC}"

    mkdir -p /var/log/caddy

    # Create Caddyfile from template
    cat > /etc/caddy/Caddyfile << EOF
# Dashboard & API (port 443)
$DOMAIN {
    handle /dex/* {
        reverse_proxy localhost:5556
    }

    reverse_proxy localhost:3000

    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "DENY"
    }

    log {
        output file /var/log/caddy/daytona.access.log
    }
}

# Proxy Service (port 8443)
*.proxy.$DOMAIN:8443, proxy.$DOMAIN:8443 {
EOF

    # Add DNS challenge configuration
    if [ "$DNS_PROVIDER" != "http" ]; then
        cat >> /etc/caddy/Caddyfile << EOF
    tls {
        issuer acme {
            challenges {
                dns {
EOF
        case $DNS_PROVIDER in
            alidns)
                cat >> /etc/caddy/Caddyfile << EOF
                    provider alidns {
                        access_key_id $ALIYUN_ACCESS_KEY_ID
                        access_key_secret $ALIYUN_ACCESS_KEY_SECRET
                    }
EOF
                ;;
            cloudflare)
                cat >> /etc/caddy/Caddyfile << EOF
                    provider cloudflare {
                        api_token $CLOUDFLARE_API_TOKEN
                    }
EOF
                ;;
            route53)
                cat >> /etc/caddy/Caddyfile << EOF
                    provider route53
EOF
                ;;
        esac

        cat >> /etc/caddy/Caddyfile << EOF
                }
            }
        }
    }
EOF
    fi

    cat >> /etc/caddy/Caddyfile << EOF
    reverse_proxy localhost:4000

    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Content-Type-Options "nosniff"
    }

    log {
        output file /var/log/caddy/proxy.access.log
    }
}
EOF

    echo -e "${GREEN}Caddy configured.${NC}"
}

# Configure Dex
configure_dex() {
    echo -e "${YELLOW}Configuring Dex...${NC}"

    mkdir -p "$PROJECT_ROOT/docker/dex"

    cat > "$PROJECT_ROOT/docker/dex/config.yaml" << EOF
issuer: https://$DOMAIN/dex

storage:
  type: sqlite3
  config:
    file: /var/dex/dex.db

web:
  http: 0.0.0.0:5556
  allowedOrigins: ['*']
  allowedHeaders: ['x-requested-with']

staticClients:
  - id: daytona
    redirectURIs:
      - 'https://$DOMAIN'
      - 'https://$DOMAIN/api/oauth2-redirect.html'
      - 'https://$DOMAIN:3009/callback'
      - 'https://proxy.$DOMAIN:8443/callback'
    name: 'Daytona'
    public: true

enablePasswordDB: true

staticPasswords:
  - email: '$DEX_ADMIN_EMAIL'
    hash: '$DEX_ADMIN_PASSWORD_HASH'
    username: '$DEX_ADMIN_USERNAME'
    userID: '1'
EOF

    echo -e "${GREEN}Dex configured.${NC}"
}

# Start services
start_services() {
    echo -e "${YELLOW}Starting Daytona services...${NC}"

    cd "$PROJECT_ROOT/docker"

    # Copy .env to docker directory
    cp "$SCRIPT_DIR/.env" .env

    # Start Daytona Docker services
    docker compose up -d

    echo -e "${GREEN}Daytona services started.${NC}"
}

# Start Caddy
start_caddy() {
    echo -e "${YELLOW}Starting Caddy...${NC}"

    # Stop system caddy if running
    systemctl stop caddy 2>/dev/null || true

    # Run Caddy in Docker with DNS providers
    docker run -d \
        --name caddy \
        --restart always \
        --network host \
        -v /etc/caddy/Caddyfile:/etc/caddy/Caddyfile:ro \
        -v /var/log/caddy:/var/log/caddy \
        -v caddy_data:/data \
        -v caddy_config:/config \
        caddy:latest-with-dns

    echo -e "${GREEN}Caddy started.${NC}"
}

# Show status
show_status() {
    echo ""
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}Daytona installation complete!${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo ""
    echo "Access your Daytona instance at:"
    echo -e "  ${BLUE}https://$DOMAIN${NC}"
    echo ""
    echo "Login credentials:"
    echo "  Email:    $DEX_ADMIN_EMAIL"
    echo "  Username: $DEX_ADMIN_USERNAME"
    echo ""
    echo "Useful commands:"
    echo "  View logs:       docker compose -f $PROJECT_ROOT/docker/docker-compose.yaml logs -f"
    echo "  Stop services:   docker compose -f $PROJECT_ROOT/docker/docker-compose.yaml down"
    echo "  Restart Caddy:   docker restart caddy"
    echo ""
}

# Main
main() {
    if [ "$1" == "--env" ]; then
        load_env
    else
        interactive_setup
        create_env_file
    fi

    check_dependencies
    configure_caddy
    configure_dex
    start_services
    start_caddy
    show_status
}

main "$@"
