#!/bin/bash
set -e

echo "🚀 Bayanat CLI Installer (HTTP API Architecture)"
echo "==============================================="

log() { echo "[INFO] $1"; }
error() { echo "[ERROR] $1"; exit 1; }
success() { echo "[SUCCESS] $1"; }

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
    
    # Create daemon user for package management
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
    mkdir -p /var/log/bayanat-daemon
    chown bayanat-daemon:bayanat-daemon /var/lib/bayanat-daemon
    chown bayanat-daemon:bayanat-daemon /var/log/bayanat-daemon
    chmod 755 /var/lib/bayanat-daemon /var/log/bayanat-daemon
    
    log "Users configured"
}

# Configure sudo permissions for daemon user
setup_daemon_permissions() {
    log "Setting up package daemon permissions..."
    
    # Create sudoers file for package installation
    cat > /etc/sudoers.d/bayanat-daemon << 'EOF'
# Package installation permissions for bayanat-daemon

bayanat-daemon ALL=(ALL) NOPASSWD: \
    /usr/bin/apt update, \
    /usr/bin/apt install *, \
    /usr/bin/apt upgrade *, \
    /usr/bin/dpkg -l, \
    /usr/bin/dpkg -s *
EOF

    # Validate sudoers syntax
    visudo -c -f /etc/sudoers.d/bayanat-daemon || error "Invalid sudoers configuration"
    
    log "Package daemon permissions configured"
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
    
    # Create Caddyfile
    cat > /etc/caddy/Caddyfile << EOF
$DOMAIN {
    # Reverse proxy to Bayanat application
    reverse_proxy 127.0.0.1:5000
    
    # Handle static files
    handle_path /static/* {
        root * /opt/bayanat/enferno/static
        file_server
    }
    
    # Security headers
    header {$(if [[ ! "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then echo "
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

# Install CLI
install_cli() {
    log "Installing Bayanat CLI..."
    
    # Install Node.js if not present
    if ! command -v node >/dev/null; then
        curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
        apt-get install -y nodejs
    fi
    
    # Install CLI package
    npm install -g git+https://github.com/sjacorg/bayanat-cli.git
    
    # Verify installation
    command -v bayanat >/dev/null || error "CLI installation failed"
    
    success "CLI installed: $(command -v bayanat)"
}

# Create privileged daemon
create_daemon() {
    log "Creating privileged HTTP daemon..."
    
    # Copy daemon script
    DAEMON_SCRIPT="/usr/local/bin/bayanat-daemon.js"
    cat > "$DAEMON_SCRIPT" << 'EOF'
#!/usr/bin/env node

const http = require('http');
const { execSync } = require('child_process');
const fs = require('fs');

const PORT = 8080;
const LOG_FILE = '/var/log/bayanat-daemon/operations.log';

// Package validation
const ALLOWED_PATTERNS = [
  /^python3-.+/, /^postgresql-.+/, /^lib.+-dev$/, /^ffmpeg$/, 
  /^exiftool$/, /^build-essential$/, /.+-common$/, /^redis-.+/, /^nginx-.+/
];

const BLOCKED_PATTERNS = [
  /^ssh.*/, /^sudo.*/, /^systemd.*/, /.*backdoor.*/, /^netcat.*/
];

function log(operation, details = {}) {
  const entry = { timestamp: new Date().toISOString(), operation, ...details };
  console.log(`[${entry.timestamp}] ${operation}:`, details);
  try {
    fs.appendFileSync(LOG_FILE, JSON.stringify(entry) + '\n');
  } catch (err) {
    console.error('Log write failed:', err.message);
  }
}

function validatePackage(pkg) {
  if (BLOCKED_PATTERNS.some(p => p.test(pkg))) {
    return { valid: false, reason: `Package '${pkg}' is blocked` };
  }
  if (ALLOWED_PATTERNS.some(p => p.test(pkg))) {
    return { valid: true };
  }
  return { valid: false, reason: `Package '${pkg}' not allowed` };
}

function installPackage(pkg) {
  const validation = validatePackage(pkg);
  if (!validation.valid) {
    log('package_rejected', { package: pkg, reason: validation.reason });
    return { success: false, error: validation.reason };
  }
  
  try {
    log('package_install_start', { package: pkg });
    // Run apt commands with sudo
    execSync('sudo apt update -qq', { stdio: 'pipe' });
    execSync(`sudo apt install -y ${pkg}`, { stdio: 'pipe' });
    log('package_install_success', { package: pkg });
    return { success: true, message: `Package '${pkg}' installed` };
  } catch (error) {
    log('package_install_error', { package: pkg, error: error.message });
    return { success: false, error: `Install failed: ${error.message}` };
  }
}

const server = http.createServer((req, res) => {
  res.setHeader('Access-Control-Allow-Origin', 'http://localhost');
  res.setHeader('Content-Type', 'application/json');
  
  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    res.end();
    return;
  }
  
  if (req.method !== 'POST' || req.url !== '/install-package') {
    res.writeHead(404);
    res.end(JSON.stringify({ error: 'Not found' }));
    return;
  }
  
  let body = '';
  req.on('data', chunk => body += chunk);
  req.on('end', () => {
    try {
      const request = JSON.parse(body);
      if (!request.package) {
        res.writeHead(400);
        res.end(JSON.stringify({ error: 'Package name required' }));
        return;
      }
      
      const result = installPackage(request.package);
      res.writeHead(result.success ? 200 : 400);
      res.end(JSON.stringify(result));
    } catch (error) {
      res.writeHead(400);
      res.end(JSON.stringify({ error: 'Invalid request' }));
    }
  });
});

server.listen(PORT, 'localhost', () => {
  log('daemon_start', { port: PORT, pid: process.pid });
  console.log(`Bayanat daemon listening on localhost:${PORT}`);
});

process.on('SIGTERM', () => server.close(() => process.exit(0)));
EOF
    
    chmod +x "$DAEMON_SCRIPT"
    chown bayanat-daemon:bayanat-daemon "$DAEMON_SCRIPT"
    
    # Create systemd service
    cat > /etc/systemd/system/bayanat-daemon.service << 'EOF'
[Unit]
Description=Bayanat Privileged HTTP Daemon
After=network.target

[Service]
Type=simple
User=bayanat-daemon
Group=bayanat-daemon
WorkingDirectory=/var/lib/bayanat-daemon
ExecStart=/usr/local/bin/bayanat-daemon.js

# Security options
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/var/log/bayanat-daemon
RestrictAddressFamilies=AF_INET AF_INET6
MemoryDenyWriteExecute=yes
RestrictRealtime=yes

# Process options
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # Start daemon
    systemctl daemon-reload
    systemctl enable bayanat-daemon
    systemctl start bayanat-daemon
    
    success "HTTP daemon created and started"
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
    echo ""
    success "🎉 Bayanat installation complete!"
    echo ""
    echo "🌐 Web Interface:"
    if [[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "  http://$DOMAIN (HTTP only - IP addresses cannot use HTTPS)"
    else
        echo "  https://$DOMAIN (automatic HTTPS via Caddy)"
    fi
    echo ""
    echo "🔧 Services:"
    echo "  • Bayanat App: systemctl status bayanat"
    echo "  • Caddy Server: systemctl status caddy"
    echo "  • Package Daemon: systemctl status bayanat-daemon"
    echo "  • PostgreSQL: systemctl status postgresql"
    echo "  • Redis: systemctl status redis-server"
    echo ""
    echo "📋 Security Architecture:"
    echo "  • Admin user: Full system access (existing user)"
    echo "  • bayanat user: Unprivileged application service"
    echo "  • bayanat-daemon user: Limited package installation only"
    echo ""
    echo "📁 Important Paths:"
    echo "  • Application: /opt/bayanat"
    echo "  • Logs: /var/log/caddy/bayanat.log"
    echo "  • Config: /etc/caddy/Caddyfile"
    echo ""
    echo "🔍 Monitoring:"
    echo "  • Application logs: journalctl -u bayanat -f"
    echo "  • Web server logs: journalctl -u caddy -f"
    echo "  • Package daemon: tail -f /var/log/bayanat-daemon/operations.log"
    echo ""
    echo "💾 Database: postgresql:///bayanat (local trust authentication)"
    echo ""
    echo "🚀 Ready to use!"
}

# Main installation flow
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
    install_cli
    create_daemon
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

# Get domain
DOMAIN="${DOMAIN:-}"
if [ -z "$DOMAIN" ]; then
    DOMAIN=$(get_server_ip)
    log "No domain specified, using server IP: $DOMAIN"
else
    log "Using specified domain: $DOMAIN"
fi

main "$DOMAIN"