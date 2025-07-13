#!/bin/bash
set -e

echo "🚀 Bayanat CLI Installer"
echo "=========================="

log() { echo "[INFO] $1"; }
error() { echo "[ERROR] $1"; exit 1; }

# Check system requirements
check_system() {
    [ "$(uname -s)" = "Linux" ] || error "Linux required"
    command -v apt >/dev/null || error "Ubuntu/Debian required"
    [ "$EUID" -eq 0 ] || sudo -n true 2>/dev/null || error "Root or passwordless sudo required"
    log "System checks passed"
}

# Install everything needed
install_packages() {
    log "Installing packages..."
    export DEBIAN_FRONTEND=noninteractive
    apt update -qq
    apt install -y -qq \
        git postgresql postgresql-contrib postgis redis-server nginx \
        python3 python3-pip python3-venv python3-dev build-essential \
        libpq-dev libxml2-dev libxslt1-dev libssl-dev libffi-dev \
        libjpeg-dev libzip-dev libimage-exiftool-perl ffmpeg curl wget
}

# Setup services
setup_services() {
    log "Configuring services..."
    
    # PostgreSQL
    systemctl enable --quiet postgresql && systemctl start postgresql
    sudo -u postgres psql -c "CREATE USER bayanat WITH PASSWORD 'bayanat_password';" 2>/dev/null || true
    sudo -u postgres psql -c "CREATE DATABASE bayanat OWNER bayanat;" 2>/dev/null || true
    sudo -u postgres psql -d bayanat -c "CREATE EXTENSION IF NOT EXISTS postgis;" 2>/dev/null || true
    
    # Redis & Nginx
    systemctl enable --quiet redis-server && systemctl start redis-server
    systemctl enable --quiet nginx
}

# Create user (if root)
setup_user() {
    [ "$EUID" -eq 0 ] || return 0
    log "Creating bayanat user..."
    
    id bayanat >/dev/null 2>&1 || useradd -m -s /bin/bash bayanat
    usermod -aG sudo bayanat
    echo 'bayanat ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/bayanat
    chmod 440 /etc/sudoers.d/bayanat
}

# Install CLI
install_cli() {
    log "Installing CLI..."
    
    # Use pip with --break-system-packages for Ubuntu 24.04
    python3 -m pip install --break-system-packages git+https://github.com/level09/bayanat-cli.git --force-reinstall >/dev/null 2>&1
    
    # Create global symlink
    CLI_PATH=$(python3 -c "import sys; print(f'{sys.prefix}/bin/bayanat')" 2>/dev/null)
    [ -f "$CLI_PATH" ] && ln -sf "$CLI_PATH" /usr/local/bin/bayanat
    
    # Verify installation
    command -v bayanat >/dev/null || error "CLI installation failed"
    log "CLI ready: $(command -v bayanat)"
}

# Main
main() {
    log "Starting installation..."
    check_system
    install_packages  
    setup_services
    setup_user
    install_cli
    
    echo ""
    log "🎉 Installation complete!"
    echo ""
    echo "Usage:"
    echo "  mkdir /opt/myproject && cd /opt/myproject"
    echo "  bayanat install"
}

main "$@"