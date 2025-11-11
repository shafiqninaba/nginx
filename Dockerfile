FROM nginx:alpine

# Install curl for health checks
RUN apk add --no-cache curl

# Copy static site content
COPY site /usr/share/nginx/html

# Copy nginx configuration template and startup script
COPY nginx.conf.template /etc/nginx/nginx.conf.template
COPY startup.sh /startup.sh

# Make startup script executable
RUN chmod +x /startup.sh

# Use startup script as entrypoint
CMD ["/startup.sh"]
