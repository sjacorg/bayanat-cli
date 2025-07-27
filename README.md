# Bayanat CLI

**Production installer and update companion for Bayanat**

A comprehensive deployment solution for Bayanat, the open-source human rights data management platform developed by the Syria Justice and Accountability Centre (SJAC).

## Features

🎯 **Complete Production Setup** - Full system installation with one command  
🔒 **Web-Based Updates** - Update system directly from Bayanat admin interface  
⚡ **Zero-Resource API** - Management interface with no idle resource consumption  
🌐 **Automatic HTTPS** - Let's Encrypt integration for production domains  
🛡️ **Security Architecture** - Multi-layer privilege separation and hardening  

## Quick Start

### Fresh Installation 

```bash
# Standard installation (auto-detects server IP)
curl -fsSL https://raw.githubusercontent.com/sjacorg/bayanat-cli/master/install.sh | bash

# Production installation with custom domain
export DOMAIN=your-domain.org
curl -fsSL https://raw.githubusercontent.com/sjacorg/bayanat-cli/master/install.sh | bash
```

### Add Update Companion (Existing Installations)

For existing Bayanat deployments, add the update companion:

```bash
curl -fsSL https://raw.githubusercontent.com/sjacorg/bayanat-cli/master/install.sh | bash -s -- --companion-only
```

**System Requirements:** Ubuntu 24.04+ with sudo access

## What Gets Installed

✅ **PostgreSQL** + PostGIS extensions (spatial data support)  
✅ **Redis** (caching and task queue)  
✅ **Caddy** web server (automatic HTTPS + security headers)  
✅ **Bayanat** app (latest from GitHub)  
✅ **Update API** (systemd socket activation - zero resources when idle)  
✅ **All systemd services** configured and hardened  

## After Installation

Your Bayanat instance will be available at:

```bash
# Standard installation
http://YOUR-SERVER-IP

# Domain installation  
https://your-domain.org
```

### Update System

The installer creates a companion HTTP API for system updates:

```bash
# Trigger system update
curl -X POST http://localhost:8080/update-bayanat

# Check system health
curl -X GET http://localhost:8080/health
```

**Web Interface Integration**: The update API runs on localhost only (`127.0.0.1:8080`) and is designed to be called from Bayanat's backend, enabling secure system updates through the web interface. 

## Architecture

### Security Model

The system implements a three-tier privilege separation model:

- **bayanat**: Application user with minimal system permissions
- **bayanat-daemon**: Service management user with limited sudo access
- **admin**: System administrator with full control

### Resource Management

The update API uses systemd socket activation:
- Zero processes running when idle
- API handler spawns only when requests arrive
- Optimal for resource-constrained environments

## System Management

### Service Status Monitoring

```bash
# Web interface connectivity
curl -I http://your-server-ip

# Service status verification
systemctl status bayanat             # Application service
systemctl status caddy              # Web server  
systemctl status bayanat-api.socket # Management API
systemctl status postgresql         # Database
systemctl status redis-server       # Cache service

# Log monitoring
journalctl -u bayanat -f            # Application logs
journalctl -u caddy -f              # Web server logs
tail -f /var/log/bayanat/api.log    # API operations
```

### Management API Reference

| Endpoint | Method | Purpose | Payload |
|----------|--------|---------|---------|
| `/update-bayanat` | POST | Update system (git pull, migrations, restart) | `{}` |
| `/restart-service` | POST | Restart application or web server | `{"service":"bayanat"}` |
| `/health` | GET | System health verification | - |
| `/service-status` | POST | Detailed service information | `{"service":"bayanat"}` |

### Web Interface Integration

Example implementation for admin interface:

```javascript
async function updateSystem() {
    const response = await fetch('http://localhost:8080/update-bayanat', { 
        method: 'POST' 
    });
    const result = await response.json();
    
    if (result.success) {
        showNotification('System updated successfully');
    } else {
        showError('Update failed: ' + result.error);
    }
}
```

## File Structure

```
/opt/bayanat/               # Application directory
├── env/                    # Python virtual environment
├── run.py                  # Flask application entry point  
├── uwsgi.ini              # uWSGI configuration
└── .env                   # Environment variables

/etc/caddy/Caddyfile        # Web server configuration
/usr/local/bin/bayanat-handler.sh  # Management API handler
/var/log/bayanat/api.log    # API operations log
```

## Troubleshooting

### Common Issues

**Web interface not accessible:**
```bash
# Verify service status
systemctl status bayanat caddy postgresql redis-server

# Check for errors
journalctl -u bayanat -n 20
journalctl -u caddy -n 20
```

**Management API unresponsive:**
```bash
# Verify API socket status
systemctl status bayanat-api.socket
ss -tlnp | grep :8080

# Test API connectivity
curl -X GET http://localhost:8080/health
```

**Database connectivity issues:**
```bash
# Test database connection
sudo -u bayanat psql -d bayanat -c "SELECT version();"

# Verify PostgreSQL status
systemctl status postgresql
```

**Service restart procedure:**
```bash
sudo systemctl restart bayanat caddy bayanat-api.socket
```

### Performance Optimization

- **High Traffic**: Increase uWSGI processes in `/opt/bayanat/uwsgi.ini` (default: 4 processes)
- **Memory Usage**: Default configuration requires ~1GB RAM
- **Storage**: Media files are stored in `/opt/bayanat/enferno/media/`

## System Requirements

- **Operating System**: Ubuntu 24.04+ (primary testing platform)
- **Memory**: 2GB RAM minimum (4GB recommended for production)
- **Storage**: 10GB available disk space minimum
- **Access**: Root or passwordless sudo access required
- **Network**: Internet connectivity for package installation

## Design Philosophy

This installer applies modern deployment practices to human rights data management:

- **Simplified Operations**: One-command installation with web-based updates
- **Resource Efficiency**: systemd socket activation ensures zero idle resource consumption
- **Security Focus**: Multi-layer privilege separation protects system integrity
- **Production Ready**: Hardened configuration suitable for organizational deployment

## License

GNU Affero General Public License v3.0 - see [LICENSE](license.txt)