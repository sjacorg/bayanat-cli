# Bayanat CLI

A command-line interface tool for installing and managing Bayanat applications. Bayanat is a Flask-based human rights data management system with PostgreSQL and Redis.

## Features

- **One-command installation** - Complete system setup with a single curl command
- **Application management** - Install, update, backup, and restore Bayanat applications
- **Automatic dependencies** - Handles system packages, database setup, and services
- **Current directory approach** - Works like modern CLI tools (Docker, npm, etc.)

## Installation

### System Setup (One Command)

```bash
curl -fsSL https://raw.githubusercontent.com/sjacorg/bayanat-cli/master/install.sh | bash
```

This automatically installs:
- All system dependencies (PostgreSQL, Redis, nginx, build tools)
- Bayanat CLI tool 
- Database and user setup
- Required services configuration

**Supported Systems:** Ubuntu 20.04+, Debian 11+

## Usage

### Install Bayanat Application

```bash
# Create project directory
mkdir -p /opt/myproject && cd /opt/myproject

# Install Bayanat application
bayanat install
```

### Update Existing Installation

```bash
cd /path/to/your/bayanat/project
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
- Python 3.8+ with development headers
- Build tools (gcc, make, etc.)
- Media processing tools (ffmpeg, exiftool)

## Architecture

The CLI uses a **separation of concerns** approach:

1. **Shell installer** (`install.sh`) - Handles system setup once
2. **Python CLI** (`bayanat`) - Manages Bayanat applications

This design provides:
- **Simple user experience** - One command does everything
- **Reliable installation** - Handles system variations
- **Easy maintenance** - Clear separation between system and app logic

## Development

To contribute to the CLI:

```bash
git clone https://github.com/sjacorg/bayanat-cli.git
cd bayanat-cli
pip install -e .
```

## License

This project is licensed under the GNU Affero General Public License v3.0. See the [LICENSE](license.txt) file for details.