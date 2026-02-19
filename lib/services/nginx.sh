#!/bin/bash

create_nginx_config() {
    # --- NGINX CONFIGURATION ---
    color_echo "Creating Nginx configuration: /etc/nginx/sites-available/$APP_CODE_NAME"
    if ! sudo tee "/etc/nginx/sites-available/$APP_CODE_NAME" > /dev/null << EOL
# Upstream for Keep-Alive
upstream ${APP_CODE_NAME}_backend {
    server 127.0.0.1:$APP_PORT;
    keepalive 64;
}

# Dynamic Connection Header
# If the client sends an Upgrade header (for WebSockets), set Connection to "upgrade".
# Otherwise, set it to "" (empty) to enable Keep-Alive for standard HTTP.
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      "";
}

server {
    listen 80;
    server_name $DOMAIN_NAME;

    # Cache file descriptors
    open_file_cache max=1000 inactive=20s;
    open_file_cache_valid 30s;
    open_file_cache_min_uses 2;
    open_file_cache_errors on;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
        allow all;
    }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'; frame-ancestors 'self';" always;

    location / {
        proxy_pass http://${APP_CODE_NAME}_backend;
        
        # Use the dynamic variables here
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Port \$server_port;

        proxy_redirect off;
        proxy_buffering on;

        # Tuning buffers
        proxy_buffer_size 128k;
        proxy_buffers 4 256k;
        proxy_busy_buffers_size 256k;

        # Timeouts
        proxy_connect_timeout 75s;
        proxy_send_timeout 300s;  # Increased for long uploads/requests
        proxy_read_timeout 300s;  # Increased for long responses
        send_timeout 300s;

        # Gzip compression
        gzip on;
        gzip_vary on;
        gzip_proxied any;
        gzip_comp_level $NGINX_GZIP_COMP_LEVEL;
        gzip_min_length 256; # Don't gzip very small files
        gzip_types text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;
    }

    # Static files caching (optional, if your FastAPI app serves static files through Nginx)
    # location /static/ {
    #     alias $APP_DIR/static/; # Adjust path to your static files
    #     expires 30d;
    #     add_header Cache-Control "public, no-transform";
    # }

    # Deny access to sensitive files if any are directly in webroot (not typical for proxy setup)
    # location ~* /(\.git|\.hg|\.svn)/ {
    #     deny all;
    # }
}
EOL
    then
        echo -e "${RED}Failed to create Nginx configuration.${NC}"
        exit 1
    fi
    color_echo "Nginx configuration created."

    # Enable Nginx site
    if [ -L "/etc/nginx/sites-enabled/$APP_CODE_NAME" ]; then
        color_echo "Nginx site symlink already exists. Overwriting."
        sudo rm -f "/etc/nginx/sites-enabled/$APP_CODE_NAME" # Remove if exists to avoid ln error
    fi
    sudo ln -s "/etc/nginx/sites-available/$APP_CODE_NAME" "/etc/nginx/sites-enabled/"
    color_echo "Nginx site enabled."

    color_echo "Testing Nginx configuration..."
    if ! sudo nginx -t; then
        echo -e "${RED}Nginx configuration test failed. Check errors above.${NC}"
        echo "The problematic Nginx config file is likely /etc/nginx/sites-available/$APP_CODE_NAME"
        exit 1
    fi
    color_echo "Nginx configuration test successful."

    color_echo "Restarting Nginx..."
    if ! sudo systemctl restart nginx; then
        echo -e "${RED}Failed to restart Nginx.${NC}"
        exit 1
    fi
    color_echo "Nginx restarted successfully."
}
