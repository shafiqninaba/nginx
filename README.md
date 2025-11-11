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

### 1. Configure Environment Variable in Railway

In your Railway NGINX service settings, add the following environment variable:

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

- **HEALTH_CHECK_ENDPOINTS** (required): Comma-separated list of service endpoints to wake up
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

```
HEALTH_CHECK_ENDPOINTS=https://worker-production-xxxx.up.railway.app/health,https://primary-production-xxxx.up.railway.app/health,https://postgres-production-xxxx.up.railway.app/,https://redis-production-xxxx.up.railway.app/
```

Make sure to use the actual Railway-provided URLs for each service.
