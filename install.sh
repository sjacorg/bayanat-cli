#!/bin/bash
set -e

# Setup comprehensive logging
# All output (stdout/stderr) is captured to timestamped log file
INSTALL_LOG="/tmp/bayanat-install-$(date +%Y%m%d-%H%M%S).log"

# Clean up old install logs (keep last 5)
find /tmp -name "bayanat-install-*.log" -type f -mtime +7 -delete 2>/dev/null || true

# Redirect all output to both console and log file
exec > >(tee -a "$INSTALL_LOG")
exec 2> >(tee -a "$INSTALL_LOG" >&2)

echo "🚀 Bayanat CLI Installer (HTTP API Architecture)"
echo "==============================================="
echo "📝 Installation log: $INSTALL_LOG"
echo ""

# Enhanced logging functions (output already captured via exec)
log() { 
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
}
error() { 
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1"
    echo ""
    echo "❌ Installation failed. Check log: $INSTALL_LOG"
    exit 1
}
success() { 
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1"
}

# Log system information for debugging
log_system_info() {
    log "=== System Information ==="
    log "Date: $(date)"
    log "User: $(whoami)"
    log "OS: $(uname -a)"
    log "Distribution: $(lsb_release -d 2>/dev/null | cut -f2 || echo 'Unknown')"
    log "Disk space: $(df -h / | tail -1)"
    log "Memory: $(free -h | head -2)"
    log "=========================="
}

# Run system info logging
log_system_info

# Parse command line arguments
parse_args() {
    INSTALL_MODE="full"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --companion-only)
                INSTALL_MODE="companion"
                shift ;;
            --help)
                show_usage
                exit 0 ;;
            *)
                error "Unknown option: $1" ;;
        esac
    done
}

# Show usage information
show_usage() {
    echo "Bayanat CLI Installer"
    echo ""
    echo "Usage:"
    echo "  $0                    # Full installation"
    echo "  $0 --companion-only   # Add update companion to existing installation"
    echo "  $0 --help             # Show this help"
    echo ""
    echo "Environment variables:"
    echo "  DOMAIN=example.com    # Custom domain (enables HTTPS)"
}

# Check system requirements
check_system() {
    [ "$(uname -s)" = "Linux" ] || error "Linux required"
    command -v apt >/dev/null || error "Ubuntu/Debian required"
    [ "$EUID" -eq 0 ] || sudo -n true 2>/dev/null || error "Root or passwordless sudo required"
    log "System checks passed"
}

# Install system packages
install_packages() {
    log "Installing system packages..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq \
        git postgresql postgresql-contrib postgis redis-server \
        python3 python3-pip python3-venv python3-dev build-essential \
        libpq-dev libxml2-dev libxslt1-dev libssl-dev libffi-dev \
        libjpeg-dev libzip-dev libimage-exiftool-perl ffmpeg curl wget
}

# Install and setup Caddy web server
setup_caddy() {
    log "Installing Caddy web server..."
    
    # Install Caddy
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor --batch --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
    apt-get update -qq
    apt-get install -y caddy
    
    log "Caddy installed successfully"
}

# Setup system services
setup_services() {
    log "Configuring system services..."
    
    # PostgreSQL
    systemctl enable --quiet postgresql && systemctl start postgresql
    
    # Redis
    systemctl enable --quiet redis-server && systemctl start redis-server
    
    # Caddy (will be configured later)
    systemctl enable --quiet caddy
}

# Create users with proper privilege separation
setup_users() {
    log "Setting up user accounts..."
    
    # Create bayanat user
    if ! id bayanat >/dev/null 2>&1; then
        useradd --system --home-dir /home/bayanat --create-home --shell /bin/bash bayanat
        log "Created bayanat user"
    fi
    
    # Create daemon user for API handler
    if ! id bayanat-daemon >/dev/null 2>&1; then
        useradd --system --home-dir /var/lib/bayanat-daemon --create-home --shell /bin/bash bayanat-daemon
        log "Created bayanat-daemon user"
    fi
    
    # Create application directory
    mkdir -p /opt/bayanat
    chown bayanat:bayanat /opt/bayanat
    chmod 755 /opt/bayanat
    
    # Create daemon directories
    mkdir -p /var/lib/bayanat-daemon
    chown bayanat-daemon:bayanat-daemon /var/lib/bayanat-daemon
    chmod 755 /var/lib/bayanat-daemon
    
    log "Users configured"
}

# Configure sudo permissions for daemon user
setup_daemon_permissions() {
    log "Setting up daemon permissions..."
    
    # Create sudoers file for service management
    cat > /etc/sudoers.d/bayanat-daemon << 'EOF'
# Service management permissions for bayanat-daemon user

bayanat-daemon ALL=(ALL) NOPASSWD: \
    /bin/systemctl restart bayanat, \
    /bin/systemctl restart caddy, \
    /bin/systemctl is-active bayanat, \
    /bin/systemctl is-active caddy, \
    /bin/systemctl is-enabled bayanat, \
    /bin/systemctl is-enabled caddy

bayanat-daemon ALL=(bayanat) NOPASSWD: \
    /usr/bin/git -C /opt/bayanat pull
EOF

    # Validate sudoers syntax
    visudo -c -f /etc/sudoers.d/bayanat-daemon || error "Invalid sudoers configuration"
    
    log "Daemon permissions configured"
}

# Setup database
setup_database() {
    log "Configuring database..."
    
    # Create database user
    sudo -u postgres psql -c "CREATE USER bayanat;" 2>/dev/null || true
    sudo -u postgres psql -c "ALTER USER bayanat CREATEDB;" 2>/dev/null || true
    sudo -u postgres psql -c "CREATE DATABASE bayanat OWNER bayanat;" 2>/dev/null || true
    
    # Install PostgreSQL extensions
    sudo -u postgres psql -d bayanat -c "CREATE EXTENSION IF NOT EXISTS postgis;" 2>/dev/null || true
    sudo -u postgres psql -d bayanat -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;" 2>/dev/null || true
    
    # Configure PostgreSQL for local trust authentication
    PG_CONFIG=$(find /etc/postgresql -name pg_hba.conf | head -1)
    
    if [ -f "$PG_CONFIG" ]; then
        if ! grep -q "local.*bayanat.*trust" "$PG_CONFIG"; then
            sed -i '/^local.*all.*postgres.*peer/a local   all             bayanat                                 trust' "$PG_CONFIG"
            systemctl reload postgresql
            log "Configured PostgreSQL trust authentication"
        fi
    fi
    
    log "Database configured"
}

# Setup Caddy configuration
setup_web_server() {
    local DOMAIN=${1:-"127.0.0.1"}
    log "Configuring Caddy web server for domain: $DOMAIN"
    
    # Only use HTTP for IP addresses, everything else gets HTTPS
    local USE_HTTPS=true
    if [[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        USE_HTTPS=false
        log "Using HTTP-only configuration for IP address: $DOMAIN"
    else
        log "Using automatic HTTPS for domain: $DOMAIN"
    fi
    
    # Create Caddyfile
    if [ "$USE_HTTPS" = "false" ]; then
        cat > /etc/caddy/Caddyfile << EOF
http://$DOMAIN {
EOF
    else
        cat > /etc/caddy/Caddyfile << EOF
$DOMAIN {
EOF
    fi
    
    cat >> /etc/caddy/Caddyfile << EOF
    # Reverse proxy to Bayanat application
    reverse_proxy 127.0.0.1:5000
    
    # Handle static files
    handle_path /static/* {
        root * /opt/bayanat/enferno/static
        file_server
    }
    
    # Security headers
    header {$(if [ "$USE_HTTPS" = "true" ]; then echo "
        Strict-Transport-Security \"max-age=31536000; includeSubDomains\""; fi)
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        X-XSS-Protection "1; mode=block"
    }
    
    # File upload size limit
    request_body {
        max_size 100MB
    }
    
    # Deny access to sensitive files
    @sensitive {
        path *.py *.sh *.lua *.log *.md5 *.pl *.cgi
        path_regexp dotfiles /\\.
        path /.git/*
    }
    respond @sensitive 404
    
    # Logging
    log {
        output file /var/log/caddy/bayanat.log {
            roll_size 10MB
            roll_keep 5
        }
        format console
    }
}
EOF

    # Create log directory with proper permissions
    mkdir -p /var/log/caddy
    chown -R caddy:caddy /var/log/caddy
    chmod 755 /var/log/caddy
    
    # Create log file with correct ownership
    touch /var/log/caddy/bayanat.log
    chown caddy:caddy /var/log/caddy/bayanat.log
    
    # Test configuration
    caddy validate --config /etc/caddy/Caddyfile || error "Invalid Caddy configuration"
    
    # Stop any existing caddy process and restart
    systemctl stop caddy 2>/dev/null || true
    systemctl start caddy || error "Failed to start Caddy"
    
    log "Caddy configured for $DOMAIN"
}

# Skip CLI installation - using direct HTTP daemon instead

# Create HTTP API using systemd socket activation
create_api() {
    log "Creating HTTP API with systemd socket activation..."
    
    # Create API handler script
    API_HANDLER="/usr/local/bin/bayanat-handler.sh"
    cat > "$API_HANDLER" << 'EOF'
#!/bin/bash

LOG_FILE="/var/log/bayanat/api.log"
log() { echo "$(date -Iseconds) $*" >> "$LOG_FILE"; }

# Read request and extract service
read -r method path protocol
while IFS= read -r line && [ "$line" != $'\r' ]; do
    [[ "$line" =~ ^Content-Length:\ ([0-9]+) ]] && content_length="${BASH_REMATCH[1]}"
done

# Read body and extract service
body=""
[ -n "$content_length" ] && [ "$content_length" -gt 0 ] && read -r -N "$content_length" body
service=$(echo "$body" | sed -n 's/.*"service":"\([^"]*\)".*/\1/p')

# Unified response function
respond() { printf "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n%s" ${#1} "$1"; }

# Service validation moved to individual endpoints that need it

# Helper functions for update process
respond_error() {
    local message="$1"
    log "ERROR: $message"
    respond "{\"success\":false,\"error\":\"$message\"}"
}

respond_success() {
    local message="$1"
    log "SUCCESS: $message"
    respond "{\"success\":true,\"message\":\"$message\"}"
}

# Simple update process for basic prototype
update_bayanat() {
    log "Starting basic update process"
    
    # Step 1: Check access
    if ! cd /opt/bayanat; then
        respond_error "Cannot access /opt/bayanat"
        return
    fi
    
    # Step 2: Pull new code
    log "Pulling updates from git"
    git_output=$(sudo -u bayanat /usr/bin/git -C /opt/bayanat pull 2>&1)
    git_status=$?
    if [ $git_status -ne 0 ]; then
        respond_error "Git pull failed"
        return
    fi

    # Check if already up to date
    if echo "$git_output" | grep -q "Already up to date"; then
        log "Repository already up to date"
        respond_success "System already up to date"
        return
    fi
    
    # Step 3: Install dependencies
    log "Installing dependencies"
    if [ -f "requirements/main.txt" ]; then
        if ! sudo -u bayanat /opt/bayanat/env/bin/pip install --quiet -r requirements/main.txt; then
            respond_error "Failed to install dependencies"
            return
        fi
    fi
    
    # Step 4: Apply migrations
    log "Applying database migrations"
    if ! sudo -u bayanat bash -c "cd /opt/bayanat && source env/bin/activate && flask apply-migrations"; then
        respond_error "Database migration failed"
        return
    fi
    
    # Step 5: Restart service
    log "Restarting Bayanat service"
    if ! sudo systemctl restart bayanat; then
        respond_error "Failed to restart service"
        return
    fi
    
    # Step 6: Basic health check
    log "Performing health check"
    sleep 3
    if ! sudo systemctl is-active bayanat >/dev/null 2>&1; then
        respond_error "Service not running after update"
        return
    fi
    
    # Success
    new_commit=$(git rev-parse HEAD 2>/dev/null)
    log "Update completed successfully"
    respond_success "Updated to commit $new_commit"
}

# Handle API endpoints
case "$path" in
    "/restart-service")
        # Validate service for this endpoint
        [[ "$service" =~ ^(bayanat|caddy)$ ]] || { respond '{"success":false,"error":"Invalid service"}'; exit; }
        log "Restarting: $service"
        sudo systemctl restart "$service" 2>/dev/null && 
            respond '{"success":true,"message":"Service restarted"}' ||
            respond '{"success":false,"error":"Restart failed"}' ;;
    
    "/service-status")
        # Validate service for this endpoint
        [[ "$service" =~ ^(bayanat|caddy)$ ]] || { respond '{"success":false,"error":"Invalid service"}'; exit; }
        respond "{\"success\":true,\"service\":\"$service\",\"status\":\"$(sudo systemctl is-active "$service" 2>/dev/null || echo inactive)\",\"enabled\":\"$(sudo systemctl is-enabled "$service" 2>/dev/null || echo disabled)\"}" ;;
    
    "/update-bayanat")
        update_bayanat ;;
    
    "/health")
        sudo systemctl is-active bayanat >/dev/null 2>&1 && sudo systemctl is-active caddy >/dev/null 2>&1 &&
            respond '{"success":true,"status":"healthy"}' ||
            respond '{"success":false,"status":"unhealthy"}' ;;
    
    *) respond '{"success":false,"error":"Not found"}' ;;
esac
EOF
    
    chmod +x "$API_HANDLER"
    
    # Create log directory
    mkdir -p /var/log/bayanat
    
    # Set proper ownership for log directory and create log file
    chown bayanat-daemon:bayanat-daemon /var/log/bayanat
    touch /var/log/bayanat/api.log
    chown bayanat-daemon:bayanat-daemon /var/log/bayanat/api.log
    
    # Create systemd socket
    cat > /etc/systemd/system/bayanat-api.socket << 'EOF'
[Unit]
Description=Bayanat HTTP API Socket

[Socket]
ListenStream=127.0.0.1:8080
Accept=yes

[Install]
WantedBy=sockets.target
EOF
    
    # Create systemd service for socket activation
    cat > /etc/systemd/system/bayanat-api@.service << 'EOF'
[Unit]
Description=Bayanat HTTP API Handler

[Service]
Type=oneshot
User=bayanat-daemon
Group=bayanat-daemon
ExecStart=/usr/local/bin/bayanat-handler.sh
StandardInput=socket
StandardOutput=socket
StandardError=journal
EOF
    
    # Configure git safe directory for daemon user
    sudo -u bayanat-daemon git config --global --add safe.directory /opt/bayanat
    
    # Enable and start socket
    systemctl daemon-reload
    systemctl enable bayanat-api.socket
    systemctl start bayanat-api.socket
    
    success "HTTP API created with systemd socket activation"
}

# Complete Bayanat application setup
setup_bayanat_app() {
    log "Setting up Bayanat application..."
    
    # Switch to bayanat user context for app setup
    sudo -u bayanat bash << 'EOF'
        # Clone Bayanat directly into /opt/bayanat
        if [ ! -f "/opt/bayanat/run.py" ]; then
            # Remove empty directory and clone
            rmdir /opt/bayanat 2>/dev/null || rm -rf /opt/bayanat/*
            git clone https://github.com/sjacorg/bayanat.git /opt/bayanat
        fi
        
        cd /opt/bayanat
        
        # Create virtual environment
        python3 -m venv env
        source env/bin/activate
        
        # Install dependencies
        pip install --upgrade pip
        pip install -r requirements/main.txt
        
        # Generate environment file
        if [ ! -f ".env" ]; then
            chmod +x gen-env.sh
            ./gen-env.sh -n -o
            
            # Set database name
            if ! grep -q "POSTGRES_DB=" .env; then
                echo "" >> .env
                echo "POSTGRES_DB=bayanat" >> .env
            fi
        fi
        
        # Set Flask app
        export FLASK_APP=run.py
        
        # Initialize database
        flask create-db --create-exts
        flask import-data
        
        echo "Bayanat application setup completed"
EOF

    # Create systemd service for Bayanat
    cat > /etc/systemd/system/bayanat.service << 'EOF'
[Unit]
Description=UWSGI instance to serve Bayanat
After=network.target

[Service]
User=bayanat
Group=bayanat
WorkingDirectory=/opt/bayanat
EnvironmentFile=/opt/bayanat/.env
ExecStart=/opt/bayanat/env/bin/uwsgi --ini uwsgi.ini

# Restart options
Restart=always
RestartSec=1
StartLimitIntervalSec=0

# Process options
Type=notify
KillMode=mixed
KillSignal=SIGQUIT
TimeoutStopSec=5
TimeoutStartSec=30

# Logging
StandardOutput=journal
StandardError=journal
NotifyAccess=all

[Install]
WantedBy=multi-user.target
EOF

    # Create uwsgi configuration
    sudo -u bayanat cat > /opt/bayanat/uwsgi.ini << 'EOF'
[uwsgi]
module = run:app
master = true
processes = 4
http = 127.0.0.1:5000
vacuum = true
die-on-term = true
enable-threads = true
EOF

    # Enable and start services
    systemctl daemon-reload
    systemctl enable bayanat
    systemctl start bayanat
    systemctl start caddy
    
    log "Bayanat application and web server started"
}

# Show completion
show_completion() {
    local DOMAIN=${1:-"127.0.0.1"}
    
    # Only use HTTP for IP addresses, everything else gets HTTPS
    local USE_HTTPS=true
    if [[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        USE_HTTPS=false
    fi
    
    echo ""
    success "🎉 Bayanat installation complete!"
    echo ""
    echo "🌐 Web Interface:"
    if [ "$USE_HTTPS" = "false" ]; then
        echo "  http://$DOMAIN (HTTP only - IP address)"
    else
        echo "  https://$DOMAIN (automatic HTTPS via Caddy)"
    fi
    echo ""
    echo "🔧 Services:"
    echo "  • Bayanat App: systemctl status bayanat"
    echo "  • Caddy Server: systemctl status caddy"
    echo "  • HTTP API: systemctl status bayanat-api.socket"
    echo "  • PostgreSQL: systemctl status postgresql"
    echo "  • Redis: systemctl status redis-server"
    echo ""
    echo "📋 Security Architecture:"
    echo "  • Admin user: Full system access (existing user)"
    echo "  • bayanat user: Unprivileged application service"
    echo "  • bayanat-daemon user: Socket-activated HTTP API for service management"
    echo ""
    echo "📁 Important Paths:"
    echo "  • Application: /opt/bayanat"
    echo "  • Logs: /var/log/caddy/bayanat.log"
    echo "  • Config: /etc/caddy/Caddyfile"
    echo ""
    echo "🔍 Monitoring:"
    echo "  • Application logs: journalctl -u bayanat -f"
    echo "  • Web server logs: journalctl -u caddy -f"
    echo "  • API logs: tail -f /var/log/bayanat/api.log"
    echo ""
    echo "💾 Database: postgresql:///bayanat (local trust authentication)"
    echo ""
    echo "📋 Installation Log: $INSTALL_LOG"
    echo ""
    echo "🚀 Ready to use!"
}

# Main installation flow
# Companion-only installation (for existing Bayanat setups)
companion_install() {
    local DOMAIN=${1:-"127.0.0.1"}
    
    log "Adding Bayanat companion to existing installation..."
    
    # Basic system checks
    [ "$(uname -s)" = "Linux" ] || error "Linux required"
    command -v systemctl >/dev/null || error "systemd required"
    
    # Check for existing Bayanat installation
    if ! id bayanat >/dev/null 2>&1 && [ ! -d "/opt/bayanat" ]; then
        echo ""
        echo "⚠️  No existing Bayanat installation detected."
        echo ""
        echo "Companion mode requires an existing Bayanat installation."
        echo "For a fresh installation, run without --companion-only:"
        echo ""
        echo "  export DOMAIN=$DOMAIN && ./install.sh"
        echo ""
        error "No existing Bayanat installation found"
    fi
    
    # Create daemon user if it doesn't exist
    if ! id bayanat-daemon >/dev/null 2>&1; then
        useradd --system --home-dir /var/lib/bayanat-daemon --create-home --shell /bin/bash bayanat-daemon
        log "Created bayanat-daemon user"
    fi
    
    # Create daemon directories
    mkdir -p /var/lib/bayanat-daemon
    chown bayanat-daemon:bayanat-daemon /var/lib/bayanat-daemon
    chmod 755 /var/lib/bayanat-daemon
    
    # Setup daemon permissions
    setup_daemon_permissions
    
    # Create API
    create_api
    
    success "🎉 Bayanat companion installed!"
    echo ""
    echo "🔧 API Management:"
    echo "  • HTTP API: http://localhost:8080"
    echo "  • Status: systemctl status bayanat-api.socket"
    echo "  • Logs: tail -f /var/log/bayanat/api.log"
    echo ""
    echo "📋 API Endpoints:"
    echo "  • POST /restart-service - Restart services"
    echo "  • POST /service-status - Check service status"
    echo "  • POST /update-bayanat - Update and restart"
    echo "  • GET /health - Health check"
    echo ""
    echo "📋 Installation Log: $INSTALL_LOG"
}

# Full installation (original main function)
main() {
    local DOMAIN=${1:-"127.0.0.1"}
    
    log "Starting Bayanat installation for domain: $DOMAIN"
    check_system
    install_packages
    setup_caddy
    setup_services
    setup_users
    setup_daemon_permissions
    setup_database
    setup_web_server "$DOMAIN"
    create_api
    setup_bayanat_app
    show_completion "$DOMAIN"
}

# Get server IP
get_server_ip() {
    local ip
    ip=$(curl -s --max-time 5 https://ipinfo.io/ip 2>/dev/null || \
         curl -s --max-time 5 https://icanhazip.com 2>/dev/null || \
         hostname -I | awk '{print $1}' || \
         echo "127.0.0.1")
    echo "$ip"
}

# Parse command line arguments
parse_args "$@"

# Get domain - preserve any existing DOMAIN environment variable
if [ -z "${DOMAIN:-}" ]; then
    DOMAIN=$(get_server_ip)
    log "No domain specified, using server IP: $DOMAIN"
else
    log "Using specified domain: $DOMAIN"
fi

# Execute based on install mode
case "$INSTALL_MODE" in
    "full")
        main "$DOMAIN" ;;
    "companion")
        companion_install "$DOMAIN" ;;
    *)
        error "Unknown install mode: $INSTALL_MODE" ;;
esac