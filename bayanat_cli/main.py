# bayanat_cli/main.py

import os
import subprocess
import sys
import time
import venv
from typing import List, Optional

import typer
from rich.console import Console
from rich.progress import Progress

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


def apply_migrations(app_dir: str):
    """Apply database migrations."""
    console.print("[yellow]Applying database migrations...[/]")
    # Placeholder for migration logic
    pass


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

@app.callback()
def main(ctx: typer.Context):
    """
    Bayanat CLI tool.
    """
    if ctx.invoked_subcommand is None:
        console.print("[bold red]Please specify a command. Use --help for more information.[/]")

@app.command()
def update(
    app_dir: str = typer.Option(".", help="Path to the Bayanat application directory"),
    repo_url: str = typer.Option("https://github.com/your-repo/bayanat.git", help="URL of the Bayanat repository"),
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
        if not validate_bayanat_directory(app_dir):
            console.print("[bold red]Error:[/] The specified directory does not appear to be a valid Bayanat application directory.")
            raise typer.Exit(code=1)

        with Progress() as progress:
            task = progress.add_task("[green]Updating Bayanat...", total=100)

            check_system_requirements()
            progress.update(task, advance=10)

            backup_database(app_dir)
            progress.update(task, advance=10)

            if not skip_git:
                fetch_latest_code(app_dir, repo_url, force)
            progress.update(task, advance=20)

            if not skip_deps:
                install_dependencies(app_dir)
            progress.update(task, advance=20)

            if not skip_migrations:
                apply_migrations(app_dir)
            progress.update(task, advance=20)

            if not skip_restart:
                restart_services(app_dir)
            progress.update(task, advance=20)

        console.print("[bold green]Update completed successfully![/]")
    except Exception as e:
        console.print(f"[bold red]Error during update:[/] {str(e)}")
        rollback_update(app_dir)
        raise typer.Exit(code=1)


if __name__ == "__main__":
    app()