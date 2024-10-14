import subprocess
from pathlib import Path
import tomli

def get_bayanat_version(app_dir: str) -> str:
    """Get Bayanat version using various methods."""
    app_path = Path(app_dir)

    # Try to get version from installed package in Bayanat's environment
    try:
        version = subprocess.check_output(
            [str(app_path / 'env' / 'bin' / 'python'), '-c', 'import bayanat; print(bayanat.__version__)'],
            stderr=subprocess.DEVNULL
        ).decode().strip()
        return version
    except subprocess.CalledProcessError:
        pass

    # Try Git tags
    try:
        return subprocess.check_output(
            ['git', 'describe', '--tags', '--abbrev=0'],
            cwd=app_path,
            stderr=subprocess.DEVNULL
        ).decode().strip()
    except subprocess.CalledProcessError:
        pass

    # Try pyproject.toml
    pyproject_path = app_path / 'pyproject.toml'
    if pyproject_path.is_file():
        try:
            with pyproject_path.open('rb') as f:
                return tomli.load(f)['project']['version']
        except (KeyError, tomli.TOMLDecodeError):
            pass

    return "unknown"

