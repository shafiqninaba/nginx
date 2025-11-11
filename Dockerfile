FROM nginx:alpine

# Install curl and wget for health checks (v2)
RUN apk add --no-cache curl wget bash

# Copy static site content
COPY site /usr/share/nginx/html

# Copy startup script (config is generated dynamically)
COPY startup.sh /startup.sh

# Make startup script executable
RUN chmod +x /startup.sh

# Expose port 80
EXPOSE 80

# Use startup script as entrypoint
CMD ["/startup.sh"]
