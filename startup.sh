#!/bin/sh

# Function to send health check to a service
send_health_check() {
    endpoint=$1
    echo "Sending health check to: $endpoint"
    wget -q -O /dev/null --timeout=5 "$endpoint" 2>/dev/null || \
    curl -sf --max-time 5 "$endpoint" > /dev/null 2>&1 || \
    echo "Health check failed or service not yet ready: $endpoint"
}

# Start with the template
cp /etc/nginx/nginx.conf.template /etc/nginx/nginx.conf

# Configure proxy locations
# Expected format: /api->https://primary.railway.app,/admin->https://admin.railway.app
proxy_config=""
if [ -n "$PROXY_ROUTES" ]; then
    echo "Proxy routes configured: $PROXY_ROUTES"

    IFS=','
    for route in $PROXY_ROUTES; do
        route=$(echo "$route" | xargs)
        if [ -n "$route" ]; then
            # Split by -> to get path and target
            path=$(echo "$route" | cut -d'>' -f1 | sed 's/-$//')
            target=$(echo "$route" | cut -d'>' -f2)

            echo "Configuring proxy: $path -> $target"

            proxy_config="${proxy_config}
        location $path {
            proxy_pass ${target};
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \"upgrade\";
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_connect_timeout 30s;
            proxy_read_timeout 300s;
            proxy_send_timeout 300s;
        }
"
        fi
    done
fi

# Replace proxy placeholder
if [ -n "$proxy_config" ]; then
    # Escape special characters for sed
    escaped_proxy=$(echo "$proxy_config" | sed 's/[\/&]/\\&/g')
    sed -i "s|# PROXY_LOCATIONS_PLACEHOLDER|${proxy_config}|g" /etc/nginx/nginx.conf
    echo "Proxy locations configured"
else
    sed -i "s|# PROXY_LOCATIONS_PLACEHOLDER||g" /etc/nginx/nginx.conf
    echo "No proxy routes configured"
fi

# Configure health check locations
# Expected format: https://service1.com/health,https://service2.com/health,https://service3.com/health
health_check_config=""
health_check_endpoints=""
if [ -n "$HEALTH_CHECK_ENDPOINTS" ]; then
    echo "Health check endpoints configured: $HEALTH_CHECK_ENDPOINTS"

    counter=1
    IFS=','
    for endpoint in $HEALTH_CHECK_ENDPOINTS; do
        endpoint=$(echo "$endpoint" | xargs)

        if [ -n "$endpoint" ]; then
            echo "Configuring health check location for: $endpoint"

            health_check_config="${health_check_config}
        location /health/service${counter} {
            proxy_pass ${endpoint};
            proxy_http_version 1.1;
            proxy_set_header Connection \"\";
            proxy_set_header Host \$host;
            proxy_connect_timeout 5s;
            proxy_read_timeout 10s;
            proxy_set_header X-Health-Check \"true\";
            access_log off;
        }
"
            # Store for later health check sending
            if [ -z "$health_check_endpoints" ]; then
                health_check_endpoints="$endpoint"
            else
                health_check_endpoints="$health_check_endpoints,$endpoint"
            fi
            counter=$((counter + 1))
        fi
    done
fi

# Replace health check placeholder
if [ -n "$health_check_config" ]; then
    sed -i "s|# HEALTH_CHECK_LOCATIONS_PLACEHOLDER|${health_check_config}|g" /etc/nginx/nginx.conf
    echo "Health check locations configured"
else
    sed -i "s|# HEALTH_CHECK_LOCATIONS_PLACEHOLDER||g" /etc/nginx/nginx.conf
    echo "No health check endpoints configured"
fi

# Test nginx configuration
echo "Testing nginx configuration..."
nginx -t

if [ $? -eq 0 ]; then
    echo "Nginx configuration is valid"

    # Start nginx in background
    echo "Starting nginx..."
    nginx

    # Wait a moment for nginx to fully start
    sleep 2

    # Send initial health checks to wake up services
    if [ -n "$health_check_endpoints" ]; then
        echo "Sending initial health checks to wake up services..."
        IFS=','
        for endpoint in $health_check_endpoints; do
            endpoint=$(echo "$endpoint" | xargs)
            if [ -n "$endpoint" ]; then
                send_health_check "$endpoint" &
            fi
        done
        wait
        echo "Initial health checks completed"
    fi

    # Keep container running and monitor nginx
    echo "Nginx is running. Monitoring..."
    while true; do
        # Check if nginx is still running
        if ! pgrep nginx > /dev/null; then
            echo "Nginx stopped unexpectedly. Exiting..."
            exit 1
        fi
        sleep 30
    done
else
    echo "Nginx configuration test failed!"
    cat /etc/nginx/nginx.conf
    exit 1
fi
