#!/bin/sh

# Function to send health check to a service
send_health_check() {
    endpoint=$1
    echo "Sending health check to: $endpoint"
    wget -q -O /dev/null --timeout=5 "$endpoint" 2>/dev/null || \
    curl -sf --max-time 5 "$endpoint" > /dev/null 2>&1 || \
    echo "Health check failed or service not yet ready: $endpoint"
}

# Read the HEALTH_CHECK_ENDPOINTS environment variable
# Expected format: https://service1.com/health,https://service2.com/health,https://service3.com/health
if [ -n "$HEALTH_CHECK_ENDPOINTS" ]; then
    echo "Health check endpoints configured: $HEALTH_CHECK_ENDPOINTS"

    # Generate nginx location blocks for each endpoint
    health_check_config=""
    counter=1

    # Split by comma and iterate
    IFS=','
    for endpoint in $HEALTH_CHECK_ENDPOINTS; do
        # Trim whitespace
        endpoint=$(echo "$endpoint" | xargs)

        if [ -n "$endpoint" ]; then
            echo "Configuring health check location for: $endpoint"

            # Create a location block for this health check
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
            counter=$((counter + 1))
        fi
    done

    # Replace placeholder in nginx config template
    sed "s|# HEALTH_CHECK_LOCATIONS_PLACEHOLDER|${health_check_config}|g" \
        /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

    echo "Nginx configuration generated with health check endpoints"
else
    echo "No HEALTH_CHECK_ENDPOINTS configured, using basic nginx config"
    # Just copy template without health checks
    sed "s|# HEALTH_CHECK_LOCATIONS_PLACEHOLDER||g" \
        /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf
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
    if [ -n "$HEALTH_CHECK_ENDPOINTS" ]; then
        echo "Sending initial health checks to wake up services..."
        IFS=','
        for endpoint in $HEALTH_CHECK_ENDPOINTS; do
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
    exit 1
fi
