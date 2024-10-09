# Bayanat CLI

Bayanat CLI is a  command-line interface tool for managing the Bayanat application, a Flask + Postgres based system. This CLI focuses on enabling seamless application updates and management.

## Features

- Easy application updates
- Dependency management
- Database migration handling
- Service restart capabilities

## Installation

```bash
pip install bayanat-cli
```

## Usage

To update the Bayanat application:

```bash
bayanat update [OPTIONS]
```

Options:
- `--app-dir TEXT`: Path to the Bayanat application directory (default: current directory)
- `--repo-url TEXT`: URL of the Bayanat repository
- `--skip-git`: Skip Git operations
- `--skip-deps`: Skip dependency installation
- `--skip-migrations`: Skip database migrations
- `--skip-restart`: Skip service restart
- `--force`: Force update even if already up-to-date

For more information on available commands:

```bash
bayanat --help
```

## Requirements

- Python 3.8+
- Git



## License

This system is distributed WITHOUT ANY WARRANTY under the GNU Affero General Public License v3.0.
