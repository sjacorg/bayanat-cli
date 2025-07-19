#!/bin/bash
set -e

echo "🚀 Bayanat CLI Installer"
echo "=========================="

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
    apt update -qq
    apt install -y -qq \
        git postgresql postgresql-contrib postgis redis-server nginx \
        python3 python3-pip python3-venv python3-dev build-essential \
        libpq-dev libxml2-dev libxslt1-dev libssl-dev libffi-dev \
        libjpeg-dev libzip-dev libimage-exiftool-perl ffmpeg curl wget
}

# Setup system services
setup_services() {
    log "Configuring system services..."
    
    # PostgreSQL
    systemctl enable --quiet postgresql && systemctl start postgresql
    
    # Generate secure random password for database
    DB_PASSWORD=$(openssl rand -base64 32)
    echo "Generated secure database password"
    
    # Create database user and database
    sudo -u postgres psql -c "CREATE USER bayanat WITH PASSWORD '$DB_PASSWORD';" 2>/dev/null || true
    sudo -u postgres psql -c "CREATE DATABASE bayanat OWNER bayanat;" 2>/dev/null || true
    sudo -u postgres psql -d bayanat -c "CREATE EXTENSION IF NOT EXISTS postgis;" 2>/dev/null || true
    
    # Save database credentials for user reference
    cat > /var/lib/bayanat/.db_credentials << EOF
# Database credentials (keep secure)
DB_PASSWORD=$DB_PASSWORD
DB_CONNECTION=postgresql://bayanat:$DB_PASSWORD@localhost/bayanat
EOF
    chown bayanat:bayanat /var/lib/bayanat/.db_credentials
    chmod 600 /var/lib/bayanat/.db_credentials
    
    # Redis & Nginx
    systemctl enable --quiet redis-server && systemctl start redis-server
    systemctl enable --quiet nginx
}

# Create users with proper security model
setup_users() {
    log "Setting up user accounts..."
    
    # Create non-privileged bayanat user (service account)
    if ! id bayanat >/dev/null 2>&1; then
        useradd --system --home-dir /var/lib/bayanat --create-home --shell /bin/bash bayanat
        log "Created bayanat system user"
    fi
    
    # Ensure ubuntu user exists with admin privileges (if not already present)
    if ! id ubuntu >/dev/null 2>&1; then
        useradd -m -s /bin/bash ubuntu
        usermod -aG sudo ubuntu
        log "Created ubuntu admin user"
    else
        # Ensure ubuntu has sudo access
        usermod -aG sudo ubuntu 2>/dev/null || true
    fi
    
    # Create bayanat working directory with proper permissions
    mkdir -p /var/lib/bayanat
    chown bayanat:bayanat /var/lib/bayanat
    chmod 755 /var/lib/bayanat
}

# Install CLI globally
install_cli() {
    log "Installing Bayanat CLI..."
    
    # Install CLI package
    python3 -m pip install --break-system-packages git+https://github.com/sjacorg/bayanat-cli.git --force-reinstall
    
    # Ensure CLI is accessible system-wide
    if ! command -v bayanat >/dev/null 2>&1; then
        # Create system-wide CLI wrapper
        cat > /usr/local/bin/bayanat << 'EOF'
#!/usr/bin/env python3
import sys
from bayanat_cli.main import main
if __name__ == "__main__":
    sys.exit(main())
EOF
        chmod +x /usr/local/bin/bayanat
        log "Created CLI at /usr/local/bin/bayanat"
    fi
    
    # Verify installation
    command -v bayanat >/dev/null || error "CLI installation failed"
    success "CLI installed: $(command -v bayanat)"
}

# Display completion message
show_completion() {
    echo ""
    success "🎉 Bayanat CLI installation complete!"
    echo ""
    echo "Security Model:"
    echo "  • ubuntu user: Administrative tasks, service management"
    echo "  • bayanat user: Runs applications, owns code"
    echo ""
    echo "Next Steps:"
    echo "  1. Switch to bayanat user:"
    echo "     sudo su - bayanat"
    echo ""
    echo "  2. Create your project:"
    echo "     cd /var/lib/bayanat"
    echo "     bayanat install"
    echo ""
    echo "  3. Manage services (as ubuntu/sudo):"
    echo "     sudo systemctl status bayanat"
    echo ""
    echo "Database credentials saved to:"
    echo "     /var/lib/bayanat/.db_credentials"
    echo ""
    echo "For help: bayanat --help"
}

# Main installation flow
main() {
    log "Starting Bayanat CLI installation..."
    check_system
    install_packages
    setup_services
    setup_users
    install_cli
    show_completion
}

main "$@"