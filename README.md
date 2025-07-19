# Bayanat CLI

A command-line interface tool for installing and managing Bayanat applications. Bayanat is a Flask-based human rights data management system with PostgreSQL and Redis.

## Features

- **One-command installation** - Complete system setup with a single curl command
- **Application management** - Install, update, backup, and restore Bayanat applications
- **Automatic dependencies** - Handles system packages, database setup, and services
- **Production-ready security** - Enterprise-grade security model with user separation

## Installation

### System Setup (One Command)

```bash
curl -fsSL https://raw.githubusercontent.com/sjacorg/bayanat-cli/master/install.sh | bash
```

This automatically installs:
- All system dependencies (PostgreSQL, Redis, nginx, Node.js)
- Bayanat CLI tool (Node.js) with global access via npm
- Secure two-user architecture for production deployments
- Database and services configuration with secure credentials
- systemd security hardening

**Supported Systems:** Ubuntu 20.04+, Debian 11+

## Security Model

### Production Architecture

The CLI implements a secure user separation designed for production environments:

- **Service account**: `bayanat` user runs applications and can restart services
- **Administrative control**: Existing admin user (root, ec2-user, etc.) manages system
- **Secure working directory**: `/opt/bayanat` with proper permissions
- **CLI global access**: Available system-wide via npm global installation

### Service Management

```bash
# Administrative tasks (as admin user)
systemctl status bayanat
systemctl restart bayanat
journalctl -u bayanat -f

# Application tasks (as bayanat user)
sudo su - bayanat
bayanat install
bayanat update
bayanat restart    # bayanat user can restart services directly
```

## Usage

### Install Bayanat Application

```bash
# Switch to service user
sudo su - bayanat

# Navigate to application directory
cd /opt/bayanat

# Install Bayanat application
bayanat install
```

### Update Existing Installation

```bash
# Switch to service user
sudo su - bayanat

# Navigate to installation directory
cd /opt/bayanat

# Update application
bayanat update
```

### Backup & Restore

```bash
# Create backup
bayanat backup

# Restore from backup
bayanat restore backup-file.sql
```

### Version Management

```bash
# Check current version
bayanat version

# Get help
bayanat --help
```

## Commands

| Command | Description |
|---------|-------------|
| `install` | Install Bayanat application in current directory |
| `update` | Update existing Bayanat application |
| `backup` | Create database backup |
| `restore` | Restore database from backup |
| `version` | Display version information |

## Installation Options

### Install Command Options

- `--force` - Force installation even if directory is not empty
- `--skip-system` - Skip system dependencies installation

### Update Command Options

- `--skip-git` - Skip Git operations
- `--skip-deps` - Skip dependency installation  
- `--skip-migrations` - Skip database migrations
- `--skip-restart` - Skip service restart
- `--force` - Force update even if already up-to-date

## System Requirements

The installer automatically handles all system requirements:

- **Operating System**: Ubuntu 20.04+, Debian 11+
- **Privileges**: Root access or passwordless sudo
- **Network**: Internet connection for package downloads

**Automatically installed:**
- PostgreSQL 14+ with PostGIS extension
- Redis server
- nginx web server
- Node.js LTS (for CLI)
- Python 3.8+ with development headers
- Build tools (gcc, make, etc.)
- Media processing tools (ffmpeg, exiftool)

## Architecture

### Security-First Design

The CLI implements enterprise-grade security with a two-user architecture:

| User | Purpose | Privileges | Usage |
|------|---------|------------|-------|
| Admin user | Administrative | sudo/root access | `systemctl restart bayanat` |
| `bayanat` | Service account | service restart only | `bayanat restart` |

### Component Separation

1. **Shell installer** (`install.sh`) - One-time system setup with security hardening
2. **Node.js CLI** (`bayanat`) - Application management without elevated privileges

### Security Features

- **Principle of least privilege** - Services run as non-privileged users
- **Defense in depth** - Multiple security layers
- **Production-ready deployment** - Secure by default configuration
- **systemd security hardening** - Modern container-style isolation

### systemd Security Template

The CLI configures services with hardened security settings:

```ini
[Unit]
Description=Bayanat Application
After=network.target postgresql.service redis.service

[Service]
User=bayanat
Group=bayanat
WorkingDirectory=/opt/bayanat
EnvironmentFile=/opt/bayanat/.env

# Security Hardening
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=/opt/bayanat
RestrictAddressFamilies=AF_INET AF_INET6
MemoryDenyWriteExecute=yes
RestrictRealtime=yes
LockPersonality=yes

# Process Management
ExecStart=/opt/bayanat/env/bin/uwsgi --ini uwsgi.ini
Restart=always
RestartSec=3
StartLimitIntervalSec=0

[Install]
WantedBy=multi-user.target
```

## Development

To contribute to the CLI development:

```bash
git clone https://github.com/sjacorg/bayanat-cli.git
cd bayanat-cli
npm install
npm link  # Links for local development testing
```

For production use, the CLI is installed globally via the installer script.

## License

This project is licensed under the GNU Affero General Public License v3.0. See the [LICENSE](license.txt) file for details.