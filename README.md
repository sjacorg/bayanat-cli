# Bayanat CLI

One-command installer for Bayanat, a Flask-based human rights data management system.

## Features

- **One-command setup** - installs everything automatically
- **Automatic HTTPS** with Let's Encrypt for domains
- **Zero-resource service management** via HTTP API
- **Production-ready** with proper user separation
- **Modern web server** with security headers and file upload limits

## Installation

### Complete Setup (One Command)

```bash
# Simple installation (auto-detects server IP, HTTP only)
curl -fsSL https://raw.githubusercontent.com/sjacorg/bayanat-cli/master/install.sh | bash

# With custom domain (automatic HTTPS)
export DOMAIN=example.com && curl -fsSL https://raw.githubusercontent.com/sjacorg/bayanat-cli/master/install.sh | bash
```

**What gets installed:**
- PostgreSQL + PostGIS, Redis, Python tools
- Caddy web server with automatic HTTPS
- Bayanat Flask application with virtual environment
- HTTP API for service management (systemd socket activation)
- All services configured with systemd security hardening

**Requirements:** Ubuntu 20.04+ or Debian 11+

Set `DOMAIN` environment variable for custom domain (optional).

## Security Architecture

**Privilege separation with three user levels:**
- **bayanat**: Runs the main application (unprivileged)
- **bayanat-daemon**: Manages services via HTTP API (limited sudo permissions)  
- **admin**: Full system access (your existing user)

**Zero-attack surface**: Service management API uses systemd socket activation - no running processes when idle.

## Usage

After installation:

```bash
# 🌐 Web interface ready at:
http://YOUR-SERVER-IP          # If no domain specified
https://example.com            # If domain specified (automatic HTTPS)

# 🔍 Monitor services
systemctl status bayanat           # Main application
systemctl status bayanat-api.socket  # Service management API
systemctl status caddy            # Web server
systemctl status postgresql       # Database
systemctl status redis-server     # Cache

# 📋 View logs
journalctl -u bayanat -f          # Application logs
journalctl -u caddy -f            # Web server logs  
tail -f /var/log/bayanat/api.log  # API operations log
```


## Architecture

- **Caddy** (80/443): Reverse proxy with automatic HTTPS
- **Bayanat** (5000): Flask application via uWSGI  
- **Service API** (8080): Zero-resource management via systemd socket activation

## File Structure

```
/opt/bayanat/
├── env/                    # Python virtual environment
├── run.py                  # Flask application entry point
├── uwsgi.ini              # uWSGI configuration
├── .env                   # Environment variables
└── enferno/               # Bayanat application code

/etc/caddy/
└── Caddyfile               # Web server configuration

/etc/systemd/system/
├── bayanat-api.socket      # HTTP API socket
└── bayanat-api@.service    # API handler service

/usr/local/bin/
└── bayanat-handler.sh      # Service management script

/var/log/
├── caddy/                  # Web server logs
└── bayanat/               # API operation logs
```

## Database

- PostgreSQL database: `bayanat`
- User: `bayanat` (trust auth)
- Extensions: PostGIS, pg_trgm

## Service Management

**Via HTTP API (recommended for app integrations):**
```bash
# Restart services
curl -X POST http://localhost:8080/restart-service \
  -H 'Content-Type: application/json' \
  -d '{"service":"bayanat"}'

# Check service status  
curl -X POST http://localhost:8080/service-status \
  -H 'Content-Type: application/json' \
  -d '{"service":"caddy"}'

# Update and restart Bayanat
curl -X POST http://localhost:8080/update-bayanat

# Health check
curl -X GET http://localhost:8080/health
```

**Via systemctl (admin access):**
```bash
# Restart services
sudo systemctl restart bayanat
sudo systemctl restart caddy

# View logs
sudo journalctl -u bayanat -f
sudo journalctl -u caddy -f
```

## Configuration

Caddy config at `/etc/caddy/Caddyfile`:

```caddyfile
example.com {
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

## API Endpoints

The service management API runs on `localhost:8080` using systemd socket activation:

| Endpoint | Method | Purpose | Payload |
|----------|--------|---------|---------|
| `/restart-service` | POST | Restart bayanat or caddy | `{"service":"bayanat"}` |
| `/service-status` | POST | Get service status | `{"service":"caddy"}` |
| `/update-bayanat` | POST | Pull code and restart | `{}` |
| `/health` | GET | Check system health | - |

**Security**: Only `bayanat` and `caddy` services allowed. All operations logged to `/var/log/bayanat/api.log`.

## Requirements

- Ubuntu 20.04+ or Debian 11+
- 2GB RAM (4GB recommended)
- 10GB disk space
- Root/sudo access
- Internet connection

## Troubleshooting

**Service not starting:**
```bash
# Check service status
sudo systemctl status bayanat
sudo systemctl status caddy
sudo systemctl status bayanat-api.socket

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

**API not responding:**
```bash
# Check socket is listening
sudo systemctl status bayanat-api.socket
ss -tlnp | grep :8080

# Test API manually
curl -X GET http://localhost:8080/health
```

**Performance tuning:**
- For high traffic: increase uWSGI processes in `/opt/bayanat/uwsgi.ini`
- All services use systemd security hardening for production use

## License

This project is licensed under the GNU Affero General Public License v3.0. See the [LICENSE](license.txt) file for details.