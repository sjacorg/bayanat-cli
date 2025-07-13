# Bayanat CLI Installer Redesign

## Problem
Current installation process is too complex:
- Users need pipx, Python knowledge
- Complex privilege detection in Python
- System dependency management mixed with application logic
- Multiple steps required

## Solution: Separation of Concerns

### Shell Script (`install.sh`) - System Preparation
**Purpose:** One-time system setup and CLI installation

**Responsibilities:**
- Detect OS/architecture (Ubuntu, CentOS, etc.)
- Handle root vs sudo user scenarios automatically
- Install system dependencies:
  - PostgreSQL + PostGIS
  - Redis
  - Nginx
  - Build tools (gcc, python3-dev, etc.)
  - ExifTool and media processing tools
- Create dedicated `bayanat` user with proper permissions
- Download and install bayanat CLI binary to `/usr/local/bin/`
- Configure basic services (PostgreSQL, Redis)
- Set up passwordless sudo for bayanat user

### Python CLI - Application Operations
**Purpose:** Pure Bayanat application management

**Responsibilities:**
- Install Bayanat application (`bayanat install`)
- Update application (`bayanat update`)
- Database operations (`bayanat backup`, `bayanat restore`)
- Application-level commands (lock, unlock, version)
- Environment configuration
- Migrations and setup

## User Experience

### Installation (One Command)
```bash
curl -fsSL https://raw.githubusercontent.com/level09/bayanat-cli/master/install.sh | sh
```

### Application Management
```bash
# Install Bayanat application
cd /opt/myproject
bayanat install

# Future operations
bayanat update
bayanat backup
bayanat version
```

## Implementation Plan

### Phase 1: Shell Script Development
1. **Create `install.sh`** in bayanat-cli repo
2. **OS Detection** - Ubuntu 20.04+, CentOS/RHEL 8+
3. **User Privilege Handling** - root vs sudo scenarios
4. **System Dependencies** - PostgreSQL, Redis, build tools
5. **CLI Binary Installation** - download from GitHub releases
6. **Service Configuration** - start and enable services

### Phase 2: CLI Simplification  
1. **Remove system dependency code** from Python CLI
2. **Remove privilege detection** - assume system is prepared
3. **Focus on application logic** - install, update, backup operations
4. **Streamline installation process** - assume services are available

### Phase 3: Binary Distribution
1. **Create GitHub releases** with pre-built binaries
2. **CI/CD pipeline** for automatic binary building
3. **Multi-architecture support** (x86_64, arm64)

## Benefits

1. **Simplicity** - One curl command installs everything
2. **Speed** - No Python environment setup needed
3. **Reliability** - Shell script handles system variations better
4. **Maintainability** - Clear separation between system and app concerns
5. **Modern UX** - Follows patterns users expect

## Testing Strategy

### Option A: Include in Repo
- Add `install.sh` to bayanat-cli repo
- Test via GitHub raw URLs
- Easy version control and updates

### Option B: External Testing  
- Keep script local during development
- Upload via SCP to test server
- More controlled testing environment

**Recommendation:** Start with Option A for faster iteration.

## Migration Path

1. **Current users** - continue with pipx installation
2. **New installations** - use shell script installer  
3. **Gradual transition** - deprecate pipx approach over time
4. **Documentation update** - update installation instructions

## File Structure
```
bayanat-cli/
├── install.sh              # System preparation script
├── bayanat_cli/            # Python CLI application
├── scripts/                # Build and release scripts
└── docs/                   # Documentation
```

## Next Steps

1. Create `install.sh` with basic OS detection
2. Test on fresh Ubuntu server
3. Iterate and improve based on testing
4. Simplify Python CLI once shell script is proven
5. Set up binary releases and CI/CD