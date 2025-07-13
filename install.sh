#!/bin/bash
set -e

# Bayanat CLI Installer
# Simple one-command installation for Bayanat CLI and system dependencies

echo "🚀 Bayanat CLI Installer"
echo "=========================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        error "Cannot detect OS. /etc/os-release not found."
    fi
    
    log "Detected OS: $OS $VERSION"
}

# Check privileges
check_privileges() {
    if [ "$EUID" -eq 0 ]; then
        log "Running as root"
        USER_TYPE="root"
    elif sudo -n true 2>/dev/null; then
        log "Running with sudo privileges"
        USER_TYPE="sudo"
    else
        error "This script requires root privileges or passwordless sudo access"
    fi
}

# Install system dependencies for Ubuntu/Debian
install_ubuntu_dependencies() {
    log "Installing system dependencies for Ubuntu/Debian..."
    
    # Update package list
    apt update
    
    # Install required packages
    apt install -y \
        git \
        postgresql \
        postgresql-contrib \
        postgresql-client \
        postgis \
        redis-server \
        nginx \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        build-essential \
        libpq-dev \
        libxml2-dev \
        libxslt1-dev \
        libssl-dev \
        libffi-dev \
        libjpeg-dev \
        libzip-dev \
        libimage-exiftool-perl \
        ffmpeg \
        curl \
        wget
    
    log "System dependencies installed successfully"
}

# Install system dependencies for CentOS/RHEL
install_centos_dependencies() {
    log "Installing system dependencies for CentOS/RHEL..."
    
    # Update package list
    yum update -y || dnf update -y
    
    # Install EPEL repository
    yum install -y epel-release || dnf install -y epel-release
    
    # Install required packages
    yum install -y \
        git \
        postgresql \
        postgresql-server \
        postgresql-contrib \
        postgis \
        redis \
        nginx \
        python3 \
        python3-pip \
        python3-devel \
        gcc \
        gcc-c++ \
        make \
        libpq-devel \
        libxml2-devel \
        libxslt-devel \
        openssl-devel \
        libffi-devel \
        libjpeg-turbo-devel \
        perl-Image-ExifTool \
        ffmpeg \
        curl \
        wget || \
    dnf install -y \
        git \
        postgresql \
        postgresql-server \
        postgresql-contrib \
        postgis \
        redis \
        nginx \
        python3 \
        python3-pip \
        python3-devel \
        gcc \
        gcc-c++ \
        make \
        libpq-devel \
        libxml2-devel \
        libxslt-devel \
        openssl-devel \
        libffi-devel \
        libjpeg-turbo-devel \
        perl-Image-ExifTool \
        ffmpeg \
        curl \
        wget
    
    log "System dependencies installed successfully"
}

# Setup PostgreSQL
setup_postgresql() {
    log "Setting up PostgreSQL..."
    
    # Start and enable PostgreSQL
    systemctl enable postgresql || systemctl enable postgresql-14
    systemctl start postgresql || systemctl start postgresql-14
    
    # Create bayanat database and user (if not exists)
    sudo -u postgres psql -c "SELECT 1 FROM pg_user WHERE usename = 'bayanat'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE USER bayanat WITH PASSWORD 'bayanat_password';"
    
    sudo -u postgres psql -c "SELECT 1 FROM pg_database WHERE datname = 'bayanat'" | grep -q 1 || \
    sudo -u postgres psql -c "CREATE DATABASE bayanat OWNER bayanat;"
    
    # Enable PostGIS extension
    sudo -u postgres psql -d bayanat -c "CREATE EXTENSION IF NOT EXISTS postgis;"
    
    log "PostgreSQL setup completed"
}

# Setup Redis
setup_redis() {
    log "Setting up Redis..."
    
    # Start and enable Redis
    systemctl enable redis-server || systemctl enable redis
    systemctl start redis-server || systemctl start redis
    
    log "Redis setup completed"
}

# Setup nginx
setup_nginx() {
    log "Setting up nginx..."
    
    # Enable nginx (don't start yet - will be configured later)
    systemctl enable nginx
    
    log "Nginx enabled (configuration will be done during app installation)"
}

# Create bayanat user
create_bayanat_user() {
    if [ "$USER_TYPE" = "root" ]; then
        log "Creating bayanat user..."
        
        # Create user if doesn't exist
        if ! id "bayanat" &>/dev/null; then
            useradd -m -s /bin/bash bayanat
            log "Created bayanat user"
        else
            log "Bayanat user already exists"
        fi
        
        # Add to sudo group
        usermod -aG sudo bayanat
        
        # Configure passwordless sudo
        echo 'bayanat ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/bayanat
        chmod 440 /etc/sudoers.d/bayanat
        
        log "Bayanat user configured with sudo privileges"
    else
        log "Running as sudo user - using current user for installation"
    fi
}

# Download and install CLI binary
install_cli_binary() {
    log "Installing Bayanat CLI binary..."
    
    # Download latest release
    CLI_URL="https://github.com/level09/bayanat-cli/archive/refs/heads/master.zip"
    TEMP_DIR="/tmp/bayanat-cli-install"
    
    # For now, fall back to pip installation since we don't have releases yet
    log "Installing CLI via pip (temporary - will switch to binary releases)"
    
    # Install pipx if not available
    if ! command -v pipx &> /dev/null; then
        python3 -m pip install --user pipx
        python3 -m pipx ensurepath
    fi
    
    # Install bayanat-cli
    pipx install git+https://github.com/level09/bayanat-cli.git --force
    
    # Make sure it's in PATH
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;;
        *) echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
           export PATH="$HOME/.local/bin:$PATH" ;;
    esac
    
    log "Bayanat CLI installed successfully"
}

# Main installation function
main() {
    log "Starting Bayanat CLI installation..."
    
    # System checks
    detect_os
    check_privileges
    
    # Install dependencies based on OS
    case $OS in
        ubuntu|debian)
            install_ubuntu_dependencies
            ;;
        centos|rhel|rocky|almalinux)
            install_centos_dependencies
            ;;
        *)
            error "Unsupported OS: $OS. Please install manually."
            ;;
    esac
    
    # Setup services
    setup_postgresql
    setup_redis
    setup_nginx
    
    # User management
    create_bayanat_user
    
    # Install CLI
    install_cli_binary
    
    # Final message
    echo ""
    log "🎉 Bayanat CLI installation completed successfully!"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Create a directory for your Bayanat installation:"
    echo "   mkdir -p /opt/myproject && cd /opt/myproject"
    echo ""
    echo "2. Install Bayanat application:"
    echo "   bayanat install"
    echo ""
    echo "3. For updates in the future:"
    echo "   bayanat update"
    echo ""
    log "System services (PostgreSQL, Redis) are running and ready!"
}

# Run main function
main "$@"