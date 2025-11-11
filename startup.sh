#!/bin/sh

# Function to send health check to a service
send_health_check() {
    endpoint=$1
    echo "Sending health check to: $endpoint"
    wget -q -O /dev/null --timeout=5 "http://$endpoint" 2>/dev/null || \
    curl -sf --max-time 5 "http://$endpoint" > /dev/null 2>&1 || \
    echo "Health check failed or service not yet ready: $endpoint"
}

# Generate nginx configuration
echo "Generating nginx configuration..."

# Start building the config file
cat > /etc/nginx/nginx.conf <<'EOF_START'
events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    # Basic settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    server {
        listen 80;
        server_name _;

EOF_START

# Add proxy locations
root_path_proxied=false
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

            # Check if root path is being proxied
            if [ "$path" = "/" ]; then
                root_path_proxied=true
            fi

            cat >> /etc/nginx/nginx.conf <<EOF_PROXY
        location $path {
            proxy_pass http://${target};
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_connect_timeout 30s;
            proxy_read_timeout 300s;
            proxy_send_timeout 300s;
        }

EOF_PROXY
        fi
    done
else
    echo "No proxy routes configured"
fi

# Add health check locations
health_check_endpoints=""
if [ -n "$HEALTH_CHECK_ENDPOINTS" ]; then
    echo "Health check endpoints configured: $HEALTH_CHECK_ENDPOINTS"

    counter=1
    IFS=','
    for endpoint in $HEALTH_CHECK_ENDPOINTS; do
        endpoint=$(echo "$endpoint" | xargs)

        if [ -n "$endpoint" ]; then
            echo "Configuring health check location for: $endpoint"

            cat >> /etc/nginx/nginx.conf <<EOF_HEALTH
        location /health/service${counter} {
            proxy_pass http://${endpoint};
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_set_header Host \$host;
            proxy_connect_timeout 5s;
            proxy_read_timeout 10s;
            proxy_set_header X-Health-Check "true";
            access_log off;
        }

EOF_HEALTH

            # Store for later health check sending
            if [ -z "$health_check_endpoints" ]; then
                health_check_endpoints="$endpoint"
            else
                health_check_endpoints="$health_check_endpoints,$endpoint"
            fi
            counter=$((counter + 1))
        fi
    done
else
    echo "No health check endpoints configured"
fi

# Add static file serving (fallback) - only if root path is not already proxied
echo "DEBUG: root_path_proxied=$root_path_proxied"
if [ "$root_path_proxied" = "false" ]; then
    echo "Adding static file serving for root path"
    cat >> /etc/nginx/nginx.conf <<'EOF_END'
        # Serve static site content (fallback)
        location / {
            root /usr/share/nginx/html;
            index index.html;
            try_files $uri $uri/ /index.html;
        }
    }
}
EOF_END
else
    echo "Root path is proxied, skipping static file serving"
    cat >> /etc/nginx/nginx.conf <<'EOF_END'
    }
}
EOF_END
fi

echo "Nginx configuration generated"

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
    echo "Generated config:"
    cat /etc/nginx/nginx.conf
    exit 1
fi
