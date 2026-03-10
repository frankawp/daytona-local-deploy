# SSH Tunnel Access

Due to browser security restrictions, the `crypto.subtle` API is only available in secure contexts (HTTPS or localhost). When accessing the service via HTTP public IP, you will encounter the following error:

```
Authentication Error
Crypto.subtle is available only in secure contexts (HTTPS).
```

## Solution: SSH Tunnel

Use SSH tunneling to access the service via localhost, which is considered a secure context.

### Setup SSH Tunnel

Run the following command on your **local machine**:

```bash
ssh -L 3000:localhost:3000 \
    -L 4000:localhost:4000 \
    -L 5556:localhost:5556 \
    -L 2222:localhost:2222 \
    -L 9001:localhost:9001 \
    -L 5100:localhost:5100 \
    -L 5050:localhost:5050 \
    -L 1080:localhost:1080 \
    -L 16686:localhost:16686 \
    root@<YOUR_SERVER_IP>
```

Replace `<YOUR_SERVER_IP>` with your server's public IP address.

### Access Services

Once the SSH tunnel is established, access the services via localhost:

| Service | URL | Description |
|---------|-----|-------------|
| Dashboard | http://localhost:3000/dashboard | Main web interface |
| API | http://localhost:3000 | API endpoint |
| Proxy | http://localhost:4000 | Proxy service |
| Dex (OIDC) | http://localhost:5556/dex | Authentication service |
| SSH Gateway | localhost:2222 | SSH access |
| MinIO Console | http://localhost:9001 | Object storage console |
| Registry UI | http://localhost:5100 | Docker registry UI |
| PgAdmin | http://localhost:5050 | Database management |
| Jaeger | http://localhost:16686 | Distributed tracing |
| MailDev | http://localhost:1080 | Email testing |

### Login Credentials

- **Username**: `dev@daytona.io`
- **Password**: `password`

### Notes

- Keep the SSH connection open while using the services
- All traffic is encrypted through the SSH tunnel
- The browser treats localhost as a secure context, allowing `crypto.subtle` API usage

## Alternative: Self-signed Certificate

If you need persistent HTTPS access without SSH tunneling, you can set up a reverse proxy with a self-signed certificate. However, this requires manually trusting the certificate in your browser.

### Generate Self-signed Certificate

```bash
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/daytona.key \
  -out /etc/nginx/ssl/daytona.crt \
  -subj "/CN=<YOUR_SERVER_IP>"
```

### Configure Nginx

Create `/etc/nginx/conf.d/daytona.conf`:

```nginx
# Daytona Dashboard & API (port 3000 -> 443)
server {
    listen 443 ssl;
    server_name _;

    ssl_certificate /etc/nginx/ssl/daytona.crt;
    ssl_certificate_key /etc/nginx/ssl/daytona.key;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# Daytona Proxy (port 4000 -> 8443)
server {
    listen 8443 ssl;
    server_name _;

    ssl_certificate /etc/nginx/ssl/daytona.crt;
    ssl_certificate_key /etc/nginx/ssl/daytona.key;

    location / {
        proxy_pass http://127.0.0.1:4000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# Dex OIDC (port 5556 -> 5557)
server {
    listen 5557 ssl;
    server_name _;

    ssl_certificate /etc/nginx/ssl/daytona.crt;
    ssl_certificate_key /etc/nginx/ssl/daytona.key;

    location /dex/ {
        proxy_pass http://127.0.0.1:5556/dex/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# MinIO Console (port 9001 -> 9443)
server {
    listen 9443 ssl;
    server_name _;

    ssl_certificate /etc/nginx/ssl/daytona.crt;
    ssl_certificate_key /etc/nginx/ssl/daytona.key;

    location / {
        proxy_pass http://127.0.0.1:9001;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# Registry UI (port 5100 -> 5443)
server {
    listen 5443 ssl;
    server_name _;

    ssl_certificate /etc/nginx/ssl/daytona.crt;
    ssl_certificate_key /etc/nginx/ssl/daytona.key;

    location / {
        proxy_pass http://127.0.0.1:5100;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# PgAdmin (port 5050 -> 5444)
server {
    listen 5444 ssl;
    server_name _;

    ssl_certificate /etc/nginx/ssl/daytona.crt;
    ssl_certificate_key /etc/nginx/ssl/daytona.key;

    location / {
        proxy_pass http://127.0.0.1:5050;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# Jaeger (port 16686 -> 16687)
server {
    listen 16687 ssl;
    server_name _;

    ssl_certificate /etc/nginx/ssl/daytona.crt;
    ssl_certificate_key /etc/nginx/ssl/daytona.key;

    location / {
        proxy_pass http://127.0.0.1:16686;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# MailDev (port 1080 -> 1081)
server {
    listen 1081 ssl;
    server_name _;

    ssl_certificate /etc/nginx/ssl/daytona.crt;
    ssl_certificate_key /etc/nginx/ssl/daytona.key;

    location / {
        proxy_pass http://127.0.0.1:1080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Start Nginx

```bash
nginx -t                    # Test configuration
systemctl enable nginx      # Enable on boot
systemctl restart nginx     # Restart service
```

### HTTPS Access URLs

| Service | HTTPS URL |
|---------|-----------|
| Dashboard | https://\<YOUR_SERVER_IP\> |
| Proxy | https://\<YOUR_SERVER_IP\>:8443 |
| Dex (OIDC) | https://\<YOUR_SERVER_IP\>:5557/dex |
| MinIO Console | https://\<YOUR_SERVER_IP\>:9443 |
| Registry UI | https://\<YOUR_SERVER_IP\>:5443 |
| PgAdmin | https://\<YOUR_SERVER_IP\>:5444 |
| Jaeger | https://\<YOUR_SERVER_IP\>:16687 |
| MailDev | https://\<YOUR_SERVER_IP\>:1081 |

### Browser Security Warning

When accessing via HTTPS with a self-signed certificate, your browser will show a security warning:

1. Click **Advanced** or **Show Details**
2. Click **Proceed to ... (unsafe)** or **Accept the Risk and Continue**

### Cloud Security Group

Make sure to open the following HTTPS ports in your cloud security group:

- 443 (Dashboard/API)
- 8443 (Proxy)
- 5557 (Dex)
- 9443 (MinIO)
- 5443 (Registry UI)
- 5444 (PgAdmin)
- 16687 (Jaeger)
- 1081 (MailDev)
