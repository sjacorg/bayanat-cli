# Bayanat CLI

One-command installer for Bayanat, a Flask-based human rights data management system.

## Features

- One-command setup - installs everything automatically
- Automatic HTTPS with Let's Encrypt
- Secure package management via HTTP API
- Production-ready with user separation
- Modern web server with security headers

## Installation

### Complete Setup (One Command)

```bash
# Simple installation (auto-detects server IP, HTTP only)
curl -fsSL https://raw.githubusercontent.com/sjacorg/bayanat-cli/master/install.sh | bash

# With custom domain (automatic HTTPS)
export DOMAIN=your-domain.com && curl -fsSL https://raw.githubusercontent.com/sjacorg/bayanat-cli/master/install.sh | bash
```

**What gets installed:**
- PostgreSQL + PostGIS, Redis, Node.js, Python tools
- Caddy web server with automatic HTTPS
- Bayanat Flask application with virtual environment
- Security: separate users for app and package management
- All services configured with systemd

**Requirements:** Ubuntu 20.04+ or Debian 11+

Set `DOMAIN` environment variable for custom domain (optional).

## Security

Two users for privilege separation:
- **bayanat**: Runs the application (no sudo)
- **bayanat-daemon**: Installs packages only (limited sudo)
- **admin**: System management (your existing user)

Files are in `/opt/bayanat` (app) and `/var/lib/bayanat-daemon` (daemon).

## Usage

After installation:

```bash
# Web interface is ready at:
http://YOUR-SERVER-IP          # If no domain specified
https://your-domain.com        # If domain specified (automatic HTTPS)

# Monitor services (as admin user)
systemctl status bayanat          # Application status
systemctl status bayanat-daemon  # Package daemon status  
systemctl status caddy           # Web server status
systemctl status postgresql      # Database status
systemctl status redis-server    # Cache status

# View logs
journalctl -u bayanat -f         # Application logs
journalctl -u caddy -f           # Web server logs
tail -f /var/log/bayanat-daemon/operations.log  # Package operations
```


## Architecture

- **Caddy** (80/443): Reverse proxy with auto HTTPS
- **Bayanat** (5000): Flask app via uWSGI  
- **Package daemon** (8080): Package management API

## Files

```
/opt/bayanat/
├── env/                    # Python virtual environment
├── run.py                  # Flask application entry point
├── uwsgi.ini              # uWSGI configuration
├── .env                   # Environment variables
└── enferno/               # Bayanat application code

/etc/caddy/
└── Caddyfile               # Web server configuration

/var/log/
├── caddy/                  # Web server logs
└── bayanat-daemon/         # Package daemon logs

/usr/local/bin/
├── bayanat                 # CLI tool (if future extension)
└── bayanat-daemon.js       # Package management daemon
```

## Database

- PostgreSQL database: `bayanat`
- User: `bayanat` (trust auth)
- Extensions: PostGIS, pg_trgm

## Service Management

```bash
# Restart application
sudo systemctl restart bayanat

# Restart web server  
sudo systemctl restart caddy

# Restart package daemon
sudo systemctl restart bayanat-daemon

# View service logs
sudo journalctl -u bayanat -f      # Application logs
sudo journalctl -u caddy -f        # Web server logs
sudo journalctl -u bayanat-daemon -f  # Package daemon logs
```

## Configuration

Caddy config at `/etc/caddy/Caddyfile`:

```caddyfile
your-domain.com {
    reverse_proxy 127.0.0.1:5000
    
    handle_path /static/* {
        root * /opt/bayanat/enferno/static
        file_server
    }
    
    # Security headers automatically applied
    # File upload limits configured
    # Automatic HTTPS enabled
}
```

## Package API

HTTP daemon at `localhost:8080`:

```bash
# Example API usage (internal use only)
curl -X POST http://localhost:8080/install-package \
     -H 'Content-Type: application/json' \
     -d '{"package": "python3-requests"}'
```

Only whitelisted packages allowed, all operations logged.

## Requirements

- Ubuntu 20.04+ or Debian 11+
- 2GB RAM (4GB recommended)
- 10GB disk space
- Root/sudo access
- Internet connection

## Troubleshooting

## Troubleshooting

**Service not starting:**
```bash
# Check service status
sudo systemctl status bayanat
sudo systemctl status caddy
sudo systemctl status bayanat-daemon

# Check logs for errors
sudo journalctl -u bayanat -n 50
sudo journalctl -u caddy -n 50
```

**Database connection issues:**
```bash
# Test database connection
sudo -u bayanat psql -d bayanat -c "SELECT version();"

# Check PostgreSQL status
sudo systemctl status postgresql
```

**Web server not accessible:**
```bash
# Check Caddy configuration
sudo caddy validate --config /etc/caddy/Caddyfile

# Restart web server
sudo systemctl restart caddy
```

All services use systemd security hardening.

For high traffic, increase uWSGI processes in `/opt/bayanat/uwsgi.ini`.

## License

This project is licensed under the GNU Affero General Public License v3.0. See the [LICENSE](license.txt) file for details.