#!/bin/bash
set -e

# Bayanat CLI Installer
# Simple one-command installation for Bayanat CLI and system dependencies

echo "🚀 Bayanat CLI Installer"
echo "=========================="

log() { echo "[INFO] $1"; }
warn() { echo "[WARN] $1"; }
error() { echo "[ERROR] $1"; exit 1; }

# Simple OS detection
detect_os() {
    if [ "$(uname -s)" != "Linux" ]; then
        error "This installer only supports Linux systems"
    fi
    
    if ! command -v apt >/dev/null 2>&1; then
        error "This installer currently supports Ubuntu/Debian only"
    fi
    
    log "Detected Linux with apt package manager"
}

# Check if running as root or with sudo
check_privileges() {
    if [ "$EUID" -eq 0 ]; then
        log "Running as root"
    elif sudo -n true 2>/dev/null; then
        log "Running with sudo privileges"
    else
        error "This script requires root privileges or passwordless sudo"
    fi
}

# Install all system dependencies
install_dependencies() {
    log "Installing system dependencies..."
    
    apt update
    apt install -y \
        git postgresql postgresql-contrib postgis redis-server nginx \
        python3 python3-pip python3-venv python3-dev build-essential \
        libpq-dev libxml2-dev libxslt1-dev libssl-dev libffi-dev \
        libjpeg-dev libzip-dev libimage-exiftool-perl ffmpeg \
        curl wget pipx
    
    log "System dependencies installed"
}

# Setup PostgreSQL
setup_postgresql() {
    log "Setting up PostgreSQL..."
    
    systemctl enable postgresql
    systemctl start postgresql
    
    # Create database and user (ignore if exists)
    sudo -u postgres psql -c "CREATE USER bayanat WITH PASSWORD 'bayanat_password';" 2>/dev/null || true
    sudo -u postgres psql -c "CREATE DATABASE bayanat OWNER bayanat;" 2>/dev/null || true
    sudo -u postgres psql -d bayanat -c "CREATE EXTENSION IF NOT EXISTS postgis;" 2>/dev/null || true
    
    log "PostgreSQL configured"
}

# Setup other services
setup_services() {
    log "Setting up services..."
    
    systemctl enable redis-server
    systemctl start redis-server
    systemctl enable nginx
    
    log "Services configured"
}

# Create bayanat user (only if root)
setup_user() {
    if [ "$EUID" -eq 0 ]; then
        log "Creating bayanat user..."
        
        if ! id "bayanat" >/dev/null 2>&1; then
            useradd -m -s /bin/bash bayanat
        fi
        
        usermod -aG sudo bayanat
        echo 'bayanat ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/bayanat
        chmod 440 /etc/sudoers.d/bayanat
        
        log "Bayanat user configured"
    fi
}

# Install CLI
install_cli() {
    log "Installing Bayanat CLI..."
    
    pipx install git+https://github.com/level09/bayanat-cli.git --force
    pipx ensurepath
    
    # Add to current session PATH immediately
    export PATH="$HOME/.local/bin:$PATH"
    
    # Create symlink to make it globally accessible
    ln -sf "$HOME/.local/bin/bayanat" /usr/local/bin/bayanat 2>/dev/null || true
    
    log "CLI installed and ready to use"
}

# Main installation
main() {
    log "Starting installation..."
    
    detect_os
    check_privileges
    install_dependencies
    setup_postgresql
    setup_services
    setup_user
    install_cli
    
    echo ""
    log "🎉 Installation completed!"
    echo ""
    echo "Next steps:"
    echo "1. mkdir -p /opt/myproject && cd /opt/myproject"
    echo "2. bayanat install"
    echo ""
    log "PostgreSQL and Redis are running and ready!"
}

main "$@"