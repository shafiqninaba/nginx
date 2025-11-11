# NGINX with Service Wake-up on Railway

This is an NGINX deployment that acts as a public entry point and automatically wakes up sleeping Railway services by sending health checks on startup.

[![Deploy on Railway](https://railway.app/button.svg)](https://railway.app/new/template/o3MbZe)


## ✨ Features

- NGINX reverse proxy as public entry point
- Automatic health check wake-up for sleeping Railway services
- Dynamic endpoint configuration via environment variables
- Static site serving
- Configurable health check endpoints

## 💁‍♀️ How to use

### 1. Configure Environment Variables in Railway

In your Railway NGINX service settings, add the following environment variables:

**PROXY_ROUTES** (required) - Define which paths should be proxied to your services:
```
PROXY_ROUTES=/api->https://primary-production-xxxx.up.railway.app
```

Format: `path->target_url,path2->target_url2`

Examples:
- Route all `/api/*` to Primary: `/api->https://primary.railway.app`
- Multiple routes: `/api->https://primary.railway.app,/ws->https://websocket.railway.app`
- Root proxy (everything): `/->https://primary.railway.app`

**HEALTH_CHECK_ENDPOINTS** (optional) - Services to wake up on startup:
```
HEALTH_CHECK_ENDPOINTS=https://worker-service.railway.app/health,https://primary-service.railway.app/health,https://postgres-service.railway.app/,https://redis-service.railway.app/
```

Replace the URLs with your actual Railway service URLs. Separate multiple endpoints with commas.

### 2. Deploy

The NGINX service will:
1. Generate nginx configuration with health check endpoints
2. Start nginx
3. Send initial health checks to all configured services to wake them up
4. Continue serving requests

### 3. Access Health Checks

Each configured endpoint is mapped to `/health/service{N}` on your NGINX service:
- `/health/service1` → First endpoint in the list
- `/health/service2` → Second endpoint in the list
- etc.

### 4. Serve Static Content

The `site/` directory contains your static files served at the root path `/`.

## 📝 Configuration

### Environment Variables

- **PROXY_ROUTES** (required): Define request routing to your backend services
  - Format: `path->target_url,path2->target_url2`
  - Example: `/api->https://primary.railway.app`
  - The path will be matched first in NGINX, so more specific paths should come first
  - Static files from `/site` directory are served as fallback

- **HEALTH_CHECK_ENDPOINTS** (optional): Comma-separated list of service endpoints to wake up
  - Example: `https://service1.com/health,https://service2.com/health`
  - Each service will receive a health check on NGINX startup
  - If not set, NGINX runs without health checks

### Customizing the Static Site

Edit files in the `site/` directory:
- `site/index.html` - Main HTML file
- `site/styles.css` - Styles
- `site/script.js` - JavaScript

### Advanced Configuration

To customize nginx behavior, edit `nginx.conf.template`. The startup script will process this template and inject health check locations automatically.

## 🔧 How It Works

1. **Startup**: The `startup.sh` script runs on container start
2. **Config Generation**: Reads `HEALTH_CHECK_ENDPOINTS` and generates nginx locations
3. **Nginx Start**: Starts nginx with the generated configuration
4. **Wake-up**: Sends health checks to all configured endpoints in parallel
5. **Monitor**: Keeps nginx running and monitors the process

## 🚀 Railway-Specific Setup

For your Railway deployment with Worker, Primary, Postgres, and Redis services:

**Example Configuration:**

```bash
# Route all API requests to Primary service
PROXY_ROUTES=/api->https://primary-production-xxxx.up.railway.app

# Wake up all services on startup
HEALTH_CHECK_ENDPOINTS=https://worker-production-xxxx.up.railway.app/health,https://primary-production-xxxx.up.railway.app/health,https://postgres-production-xxxx.up.railway.app/,https://redis-production-xxxx.up.railway.app/
```

**Complete Example (everything through Primary):**
```bash
# Proxy everything except static files to Primary
PROXY_ROUTES=/api->https://primary-production-xxxx.up.railway.app,/auth->https://primary-production-xxxx.up.railway.app,/graphql->https://primary-production-xxxx.up.railway.app

# Or proxy all requests to Primary (static site won't be served)
PROXY_ROUTES=/->https://primary-production-xxxx.up.railway.app
```

Make sure to use the actual Railway-provided URLs for each service.

### How Routing Works

1. NGINX receives request
2. Checks proxy routes (most specific first)
3. If match found, forwards to backend service
4. If no match, serves static files from `/site` directory
5. If file not found, serves `index.html` (SPA fallback)
