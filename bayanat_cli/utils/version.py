import subprocess
from pathlib import Path
import tomli

def get_bayanat_version(app_dir: str) -> str:
    """Get Bayanat version from pyproject.toml."""
    app_path = Path(app_dir)
    pyproject_path = app_path / 'pyproject.toml'
    
    # Read version from pyproject.toml (single source of truth)
    if pyproject_path.is_file():
        with pyproject_path.open('rb') as f:
            pyproject_data = tomli.load(f)
            return pyproject_data["project"]["version"]
    
    # Fallback to git tags only if pyproject.toml doesn't exist
    # This is mainly for backward compatibility with old installations
    try:
        return subprocess.check_output(
            ['git', 'describe', '--tags', '--abbrev=0'],
            cwd=app_path,
            stderr=subprocess.DEVNULL
        ).decode().strip().lstrip('v')
    except subprocess.CalledProcessError:
        pass

    return "unknown"

