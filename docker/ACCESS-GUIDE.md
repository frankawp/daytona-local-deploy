# Daytona 访问指南

本指南涵盖开发环境（SSH 隧道）和生产环境部署配置。

---

## 目录

1. [开发环境访问（SSH 隧道）](#开发环境访问ssh-隧道)
2. [生产环境部署](#生产环境部署)

---

## 开发环境访问（SSH 隧道）

由于浏览器安全限制，`crypto.subtle` API 仅在安全上下文（HTTPS 或 localhost）中可用。通过 HTTP 公网 IP 访问服务时，会遇到以下错误：

```
Authentication Error
Crypto.subtle is available only in secure contexts (HTTPS).
```

### 解决方案：SSH 隧道

使用 SSH 隧道通过 localhost 访问服务，localhost 被视为安全上下文。

### 设置 SSH 隧道

在**本地机器**上运行以下命令：

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

将 `<YOUR_SERVER_IP>` 替换为服务器的公网 IP 地址。

### 访问服务

SSH 隧道建立后，通过 localhost 访问服务：

| 服务 | URL | 说明 |
|------|-----|------|
| Dashboard | http://localhost:3000/dashboard | 主界面 |
| API | http://localhost:3000 | API 端点 |
| Proxy | http://localhost:4000 | 代理服务 |
| Dex (OIDC) | http://localhost:5556/dex | 认证服务 |
| SSH Gateway | localhost:2222 | SSH 访问 |
| MinIO Console | http://localhost:9001 | 对象存储控制台 |
| Registry UI | http://localhost:5100 | Docker 镜像仓库 UI |
| PgAdmin | http://localhost:5050 | 数据库管理 |
| Jaeger | http://localhost:16686 | 分布式追踪 |
| MailDev | http://localhost:1080 | 邮件测试 |

### 登录凭据

- **用户名**: `dev@daytona.io`
- **密码**: `password`

### 注意事项

- 使用服务时保持 SSH 连接
- 所有流量通过 SSH 隧道加密
- 浏览器将 localhost 视为安全上下文，允许使用 `crypto.subtle` API

---

## 生产环境部署

生产环境部署使用 Caddy 作为反向代理，自动获取和续期 Let's Encrypt SSL 证书。

### 1. 创建环境配置文件

在 `docker/` 目录下创建 `.env` 文件：

```bash
# 必填 - 域名
DOMAIN=daytona.example.com

# 必填 - 安全密钥（生成命令: openssl rand -base64 32）
ENCRYPTION_KEY=<32字符加密密钥>
ENCRYPTION_SALT=<32字符加密盐>

# 必填 - 数据库密码
POSTGRES_PASSWORD=<安全的数据库密码>

# 必填 - MinIO 凭据
MINIO_ROOT_USER=<minio用户名>
MINIO_ROOT_PASSWORD=<安全的minio密码>

# 必填 - 服务间通信 API 密钥
PROXY_API_KEY=<安全的proxy-api-key>
RUNNER_API_KEY=<安全的runner-api-key>
SSH_GATEWAY_API_KEY=<安全的ssh-gateway-api-key>

# 可选 - 覆盖默认 URL（根据 DOMAIN 自动配置）
# PUBLIC_OIDC_DOMAIN=https://${DOMAIN}/dex
# DASHBOARD_URL=https://${DOMAIN}/dashboard
# DASHBOARD_BASE_API_URL=https://${DOMAIN}
# PROXY_DOMAIN=proxy.${DOMAIN}:8443
# PROXY_PROTOCOL=https
# PROXY_TEMPLATE_URL=https://{{PORT}}-{{sandboxId}}.proxy.${DOMAIN}:8443
# PROXY_TOOLBOX_BASE_URL=https://proxy.${DOMAIN}:8443
# SSH_GATEWAY_URL=${DOMAIN}:2222
```

### 2. 更新 Dex 配置

编辑 `docker/dex/config.yaml`，添加生产环境重定向 URI：

```yaml
issuer: https://daytona.example.com/dex

staticClients:
  - id: daytona
    redirectURIs:
      # 开发环境 (localhost)
      - 'http://localhost:3000'
      - 'http://localhost:3000/api/oauth2-redirect.html'
      - 'http://localhost:3009/callback'
      - 'http://proxy.localhost:4000/callback'
      # 生产环境 - 替换为你的域名
      - 'https://daytona.example.com'
      - 'https://daytona.example.com/api/oauth2-redirect.html'
      - 'https://daytona.example.com:3009/callback'
      - 'https://proxy.daytona.example.com:8443/callback'
    name: 'Daytona'
    public: true
```

**重要**：将 `issuer` 从 `http://localhost:5556/dex` 更新为 `https://<你的域名>/dex`。

### 3. 配置 Caddy 反向代理

#### 安装 Caddy

```bash
# Debian/Ubuntu
apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update
apt install caddy
```

#### 创建 Caddyfile

创建 `/etc/caddy/Caddyfile`：

```caddyfile
# =============================================================================
# Daytona Caddy 配置
# =============================================================================
# Caddy 自动获取并续期 Let's Encrypt SSL 证书。
# 启动前确保 DNS 记录已配置：
#   - daytona.example.com       -> 服务器 IP
#   - proxy.daytona.example.com -> 服务器 IP
# =============================================================================

# Dashboard & API (端口 443)
daytona.example.com {
    # Dex OIDC - 必须放在通用 reverse_proxy 之前
    handle /dex/* {
        reverse_proxy localhost:5556
    }

    # Dashboard & API
    reverse_proxy localhost:3000

    # 安全头
    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Content-Type-Options "nosniff"
        X-Frame-Options "DENY"
    }

    # 访问日志
    log {
        output file /var/log/caddy/daytona.access.log
    }
}

# Proxy 服务 (端口 8443)
proxy.daytona.example.com:8443 {
    reverse_proxy localhost:4000

    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Content-Type-Options "nosniff"
    }

    log {
        output file /var/log/caddy/proxy.access.log
    }
}
```

#### 创建日志目录

```bash
mkdir -p /var/log/caddy
```

#### 启动 Caddy

```bash
# 测试配置
caddy validate --config /etc/caddy/Caddyfile

# 启动服务
systemctl enable caddy
systemctl start caddy

# 查看状态
systemctl status caddy
```

#### 重新加载配置

修改配置后执行：

```bash
caddy reload --config /etc/caddy/Caddyfile
```

### 4. DNS 配置

在 DNS 服务商处添加以下记录：

| 记录类型 | 名称 | 值 |
|----------|------|-----|
| A | daytona.example.com | 服务器公网 IP |
| A | proxy.daytona.example.com | 服务器公网 IP |

### 5. 启动 Daytona 服务

```bash
cd docker
docker compose up -d

# 查看日志
docker compose logs -f api
```

### 6. 验证部署

```bash
# 健康检查
curl https://daytona.example.com/api/health

# 检查 OIDC 配置
curl https://daytona.example.com/dex/.well-known/openid-configuration

# 验证 issuer 是否正确
curl -s https://daytona.example.com/dex/.well-known/openid-configuration | grep issuer
```

### 生产环境访问地址

| 服务 | URL |
|------|-----|
| Dashboard | https://daytona.example.com/dashboard |
| API | https://daytona.example.com/api |
| Dex (OIDC) | https://daytona.example.com/dex |
| Proxy | https://proxy.daytona.example.com:8443 |
| SSH Gateway | ssh -p 2222 user@daytona.example.com |

### 云服务器安全组

在云服务器安全组中开放以下端口：

- **443** (Dashboard/API)
- **8443** (Proxy)
- **2222** (SSH Gateway)

### 故障排除

#### 认证错误：Invalid response Content-Type

如果遇到 `Invalid response Content-Type: text/html` 错误：

1. 检查 Caddyfile 中 `/dex/*` 路由是否正确配置
2. 检查 Dex 配置中 `issuer` 是否为生产环境 URL
3. 重启服务：
   ```bash
   caddy reload --config /etc/caddy/Caddyfile
   cd docker && docker compose restart dex
   ```

#### SSL 证书问题

Caddy 自动获取 Let's Encrypt 证书。如果证书获取失败：

1. 确保 DNS 记录已正确指向服务器 IP
2. 确保端口 80 和 443 可从公网访问
3. 查看 Caddy 日志：
   ```bash
   journalctl -u caddy -f
   ```

#### 查看 Dex 日志

```bash
docker compose logs dex -f
```

#### 查看 API 日志

```bash
docker compose logs api -f
```
