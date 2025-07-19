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
    
    # Configure sudo permissions for bayanat to restart services only
    cat > /etc/sudoers.d/bayanat-services << 'EOF'
# Allow bayanat user to restart only bayanat services without password
bayanat ALL=(ALL) NOPASSWD: /bin/systemctl restart bayanat, /bin/systemctl restart bayanat-celery, /bin/systemctl status bayanat, /bin/systemctl status bayanat-celery
EOF
    chmod 440 /etc/sudoers.d/bayanat-services
    log "Configured service restart permissions for bayanat user"
}

# Setup database with trust authentication
setup_database() {
    log "Configuring database..."
    
    # Create database user and database (no password needed for local connections)
    sudo -u postgres psql -c "CREATE USER bayanat;" 2>/dev/null || true
    sudo -u postgres psql -c "CREATE DATABASE bayanat OWNER bayanat;" 2>/dev/null || true
    sudo -u postgres psql -d bayanat -c "CREATE EXTENSION IF NOT EXISTS postgis;" 2>/dev/null || true
    
    # Configure PostgreSQL for local trust authentication
    PG_CONFIG=$(find /etc/postgresql -name pg_hba.conf | head -1)
    
    # Add trust authentication for bayanat user
    if [ -f "$PG_CONFIG" ]; then
        if ! grep -q "local.*bayanat.*trust" "$PG_CONFIG"; then
            sed -i '/^local.*all.*postgres.*peer/a local   all             bayanat                                 trust' "$PG_CONFIG"
            systemctl reload postgresql
            log "Configured PostgreSQL trust authentication for bayanat user"
        fi
    else
        log "PostgreSQL config file not found - using default authentication"
    fi
    
    # Save simple connection info
    cat > /var/lib/bayanat/.db_info << EOF
# Database connection info
DB_USER=bayanat
DB_NAME=bayanat
DB_CONNECTION=postgresql://bayanat@localhost/bayanat
EOF
    chown bayanat:bayanat /var/lib/bayanat/.db_info
    chmod 644 /var/lib/bayanat/.db_info
}

# Install CLI globally
install_cli() {
    log "Installing Bayanat CLI..."
    
    # Install CLI package - Python packaging will automatically create the 'bayanat' command
    python3 -m pip install --break-system-packages git+https://github.com/sjacorg/bayanat-cli.git --force-reinstall
    
    # Verify installation
    command -v bayanat >/dev/null || error "CLI installation failed. Check if pyproject.toml has proper console script configuration."
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
    echo "Database info saved to:"
    echo "     /var/lib/bayanat/.db_info"
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
    setup_database
    install_cli
    show_completion
}

main "$@"