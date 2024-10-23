# bayanat_cli/main.py

import os
import subprocess
import sys
import time
import venv
from typing import List, Optional, Tuple
import requests

import typer
from rich.console import Console
from rich.progress import Progress
from rich.panel import Panel
from .utils.version import get_bayanat_version

# Centralized repository URL
BAYANAT_REPO_URL = "https://github.com/sjacorg/bayanat.git"

app = typer.Typer()
console = Console()


def run_command(command: List[str], cwd: Optional[str] = None) -> str:
    """
    Runs a shell command and returns the output.
    Raises an exception if the command fails.
    """
    try:
        result = subprocess.run(
            command,
            cwd=cwd,
            check=True,
            capture_output=True,
            text=True
        )
        return result.stdout
    except subprocess.CalledProcessError as e:
        console.print(f"[bold red]Error running command:[/] {' '.join(command)}")
        console.print(e.stderr)
        raise typer.Exit(code=1)


def check_system_requirements():
    """Check if the system meets the minimum requirements."""
    # Check Python version
    if sys.version_info < (3, 8):
        console.print("[bold red]Python 3.8 or higher is required.[/]")
        raise typer.Exit(code=1)
    
    # Check if Git is installed
    try:
        run_command(["git", "--version"])
    except subprocess.CalledProcessError:
        console.print("[bold red]Git is not installed. Please install Git to proceed.[/]")
        raise typer.Exit(code=1)


def backup_database(app_dir: str):
    """Create a backup of the database before updating."""
    # Implement database backup logic
    console.print("[yellow]Backing up the database...[/]")
    # Placeholder for backup logic
    pass


def rollback_update(app_dir: str):
    """Rollback the update if something goes wrong."""
    # Implement rollback logic (restore from backup, revert code, etc.)
    console.print("[yellow]Rolling back the update...[/]")
    # Placeholder for rollback logic
    pass


def fetch_latest_code(app_dir: str, repo_url: str, force: bool):
    """Fetch the latest code from the repository."""
    if not os.path.isdir(os.path.join(app_dir, ".git")):
        console.print("[yellow]Cloning repository...[/]")
        run_command(["git", "clone", repo_url, app_dir])
    else:
        console.print("[yellow]Fetching latest code...[/]")
        run_command(["git", "fetch"], cwd=app_dir)
        run_command(["git", "checkout", "master"], cwd=app_dir)
        if force:
            run_command(["git", "reset", "--hard", "origin/master"], cwd=app_dir)
        run_command(["git", "pull"], cwd=app_dir)


def install_dependencies(app_dir: str):
    """Install the required dependencies."""
    console.print("[yellow]Installing dependencies...[/]")
    env_dir = os.path.join(app_dir, "env")
    
    if not os.path.isdir(env_dir):
        console.print("[yellow]Creating virtual environment using virtualenv...[/]")
        run_command(["virtualenv", env_dir], cwd=app_dir)
    
    pip_path = os.path.join(env_dir, "bin", "pip")
    
    try:
        console.print("[yellow]Upgrading pip...[/]")
        run_command([pip_path, "install", "--upgrade", "pip"], cwd=app_dir)
        console.print("[yellow]Installing packages from requirements.txt...[/]")
        run_command([pip_path, "install", "-r", os.path.join(app_dir, "requirements.txt")], cwd=app_dir)
        console.print("[green]Dependencies installed successfully.[/]")
    except subprocess.CalledProcessError as e:
        console.print(f"[bold red]Failed to install dependencies:[/] {e.stderr}")
        raise typer.Exit(code=1)


def apply_migrations(app_dir: str) -> Tuple[bool, str]:
    """
    Apply database migrations via Bayanat CLI command.
    
    Args:
        app_dir: The application directory
    
    Returns:
        Tuple of (success: bool, message: str)
    """
    # First check for pending migrations
    success, output = run_migration_command(app_dir, "apply-migrations --dry-run")
    if not success:
        return False, output
    
    if "No pending migrations to apply" in output:
        return True, "No pending migrations to apply."
    
    # Apply the migrations
    success, output = run_migration_command(app_dir, "apply-migrations")
    if not success:
        return False, output
    
    if "[Success]" in output:
        return True, "Migrations applied successfully."
    else:
        return False, f"Migration process failed: {output}"


def restart_services(app_dir: str):
    """Restart the application services."""
    console.print("[yellow]Restarting services...[/]")
    # Placeholder for service restart logic
    pass


def validate_bayanat_directory(app_dir: str) -> bool:
    """
    Check if the specified directory is a valid Bayanat application directory.
    """
    required_files = [
        'docker-compose.yml',
        'requirements.txt',
        'pyproject.toml',
        'README.md',
        'run.py'
    ]
    required_dirs = [
        'flask',
        'nginx',
        'docs',
        'tests'
    ]

    for file in required_files:
        if not os.path.isfile(os.path.join(app_dir, file)):
            console.print(f"[bold red]Error:[/] Required file '{file}' not found in {app_dir}")
            return False

    for directory in required_dirs:
        if not os.path.isdir(os.path.join(app_dir, directory)):
            console.print(f"[bold red]Error:[/] Required directory '{directory}' not found in {app_dir}")
            return False

    return True

@app.callback(invoke_without_command=True)
def main(ctx: typer.Context):
    """
    Bayanat CLI tool.
    """
    if ctx.invoked_subcommand is None:
        console.print("[bold red]Missing command.[/]")
        console.print("Use [bold blue]bayanat --help[/] to see available commands.")
        raise typer.Exit(code=1)

@app.command()
def update(
    path: str = typer.Argument(".", help="Path to the Bayanat application directory"),
    skip_git: bool = typer.Option(False, help="Skip Git operations"),
    skip_deps: bool = typer.Option(False, help="Skip dependency installation"),
    skip_migrations: bool = typer.Option(False, help="Skip database migrations"),
    skip_restart: bool = typer.Option(False, help="Skip service restart"),
    force: bool = typer.Option(False, help="Force update even if already up-to-date")
):
    """
    Update the Bayanat application.
    """
    try:
        # Validate the Bayanat directory before proceeding
        if not validate_bayanat_directory(path):
            console.print("[bold red]Error:[/] The specified directory does not appear to be a valid Bayanat application directory.")
            raise typer.Exit(code=1)

        # Display current version
        current_version = get_bayanat_version(path)
        display_version(current_version, "Current Bayanat version")

        with Progress() as progress:
            task = progress.add_task("[green]Updating Bayanat...", total=100)

            check_system_requirements()
            progress.update(task, advance=10)

            backup_database(path)
            progress.update(task, advance=10)

            if not skip_git:
                fetch_latest_code(path, BAYANAT_REPO_URL, force)
            progress.update(task, advance=20)

            # Check if the version is already up-to-date
            new_version = get_bayanat_version(path)
            if current_version == new_version:
                console.print("[bold green]Bayanat is already up-to-date![/]")
                return

            if not skip_deps:
                install_dependencies(path)
            progress.update(task, advance=20)

            if not skip_migrations:
                apply_migrations(path)
            progress.update(task, advance=20)

            if not skip_restart:
                restart_services(path)
            progress.update(task, advance=20)

        # Display updated version
        display_version(new_version, "Updated Bayanat version")

        console.print("[bold green]Update completed successfully![/]")
    except Exception as e:
        console.print(f"[bold red]Error during update:[/] {str(e)}")
        rollback_update(path)
        raise typer.Exit(code=1)


def check_virtualenv_support():
    """Ensure that the venv module is available for creating virtual environments."""
    try:
        import venv
    except ImportError:
        console.print("[bold red]Error:[/] Python's venv module is not available.")
        raise typer.Exit(code=1)

def check_permissions(directory: str):
    """Check if the current user has read/write permissions for the directory."""
    if not os.access(directory, os.R_OK | os.W_OK):
        console.print(f"[bold red]Error:[/] Insufficient permissions for directory '{directory}'.")
        raise typer.Exit(code=1)

def check_network_connectivity(url: str):
    """Check if the network is accessible and the URL is reachable."""
    try:
        response = requests.get(url, timeout=5)
        if response.status_code != 200:
            raise Exception("Failed to reach the repository")
    except requests.RequestException:
        console.print("[bold red]Error:[/] Network connectivity issue. Cannot reach the repository.")
        raise typer.Exit(code=1)

def display_version(version: str, message: str):
    """Display version information in a formatted panel."""
    console.print(Panel(f"{message}: [bold blue]{version}[/]", expand=False))

@app.command()
def install(
    app_dir: str = typer.Argument(..., help="Directory where Bayanat will be installed"),
    force: bool = typer.Option(False, help="Force installation, even if the directory is not empty")
):
    """
    Install the Bayanat application in the specified directory.
    """
    try:
        # Step 1: Check system requirements and network connectivity
        console.print("[yellow]Checking system requirements...[/]")
        check_system_requirements()  # Checks Python version and Git installation
        check_virtualenv_support()    # Checks for venv availability
        check_network_connectivity(BAYANAT_REPO_URL)  # Checks access to the repository

        # Step 2: Verify the installation directory and permissions
        console.print("[yellow]Verifying installation directory...[/]")
        if os.path.exists(app_dir):
            check_permissions(app_dir)
            if os.listdir(app_dir) and not force:
                console.print(f"[bold red]Error:[/] Directory '{app_dir}' is not empty. Use --force to override.")
                raise typer.Exit(code=1)
        else:
            console.print(f"[yellow]Creating directory '{app_dir}'...[/]")
            os.makedirs(app_dir)
            check_permissions(app_dir)

        # Step 3: Clone the repository into the directory
        console.print("[yellow]Cloning the Bayanat repository...[/]")
        fetch_latest_code(app_dir, BAYANAT_REPO_URL, force=True)

        # Step 4: Create a virtual environment
        console.print("[yellow]Setting up the virtual environment...[/]")
        env_dir = os.path.join(app_dir, "env")
        if not os.path.exists(env_dir):
            venv.create(env_dir, with_pip=True)

        # Step 5: Install dependencies
        console.print("[yellow]Installing dependencies...[/]")
        install_dependencies(app_dir)

        # Step 6: Apply initial migrations (optional)
        console.print("[yellow]Applying initial database migrations...[/]")
        apply_migrations(app_dir)

        # Step 7: Finalize installation
        console.print("[bold green]Bayanat installation completed successfully![/]")
    except Exception as e:
        console.print(f"[bold red]Error during installation:[/] {str(e)}")
        rollback_update(app_dir)
        raise typer.Exit(code=1)


@app.command()
def version(path: str = typer.Argument(".", help="Path to the Bayanat application directory")):
    """
    Display the current version of the Bayanat application.
    """
    try:
        # Retrieve the current version
        current_version = get_bayanat_version(path)
        # Display the version using a formatted panel
        display_version(current_version, "Bayanat Version")
    except Exception as e:
        console.print(f"[bold red]Error retrieving version:[/] {str(e)}")
        raise typer.Exit(code=1)


if __name__ == "__main__":
    app()
