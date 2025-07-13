# bayanat_cli/main.py

import json
import os
import shlex
import subprocess
import sys
import time
import venv
from datetime import datetime
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


def pprint(message: str, style: Optional[str] = None):
    """Prints a message with newlines before and after."""
    if style:
        console.print(f"\n{message}", style=style)
    else:
        console.print(f"\n{message}")


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
        pprint(f"Error running command: {' '.join(command)}", "bold red")
        pprint(e.stderr)
        raise typer.Exit(code=1)


def check_system_requirements():
    """Check if the system meets the minimum requirements."""
    # Check Python version
    if sys.version_info < (3, 8):
        pprint("Python 3.8 or higher is required.", "bold red")
        raise typer.Exit(code=1)
    
    # Check if Git is installed
    try:
        run_command(["git", "--version"])
    except subprocess.CalledProcessError:
        pprint("Git is not installed. Please install Git to proceed.", "bold red")
        raise typer.Exit(code=1)


def backup_database(app_dir: str, output: Optional[str] = None) -> Optional[str]:
    """
    Create a backup of the database before updating.
    
    Args:
        app_dir: Path to the Bayanat application directory
        output: Optional custom output path for the backup file
        
    Returns:
        Path to the backup file or None if backup failed
    """
    pprint("Backing up the database...", "yellow")
    
    # Generate expected backup path
    if output:
        # Use the provided output path
        expected_backup_path = output
        command = f"backup-db --output {expected_backup_path}"
    else:
        # Use a timestamp for predictable backup filename
        timestamp = time.strftime("%Y%m%d_%H%M%S")
        expected_backup_dir = os.path.join(app_dir, "backups")
        expected_backup_path = os.path.join(expected_backup_dir, f"{timestamp}_bayanat_backup.dump")
        command = f"backup-db --output {expected_backup_path}"
    
    # Run the backup command with the expected path
    success, output_text = run_flask_command(app_dir, command)
    
    if not success:
        pprint(f"Database backup failed: {output_text}", "bold red")
        return None
    
    # Verify the file exists
    if os.path.exists(expected_backup_path):
        pprint(f"Database backup created at: {expected_backup_path}", "green")
        return expected_backup_path
    
    # Fallback to parsing output if our expected file doesn't exist
    for line in output_text.splitlines():
        if "Database backup created successfully at" in line:
            backup_path = line.split("at")[-1].strip()
            if os.path.exists(backup_path):
                pprint(f"Database backup created at: {backup_path}", "green")
                return backup_path
    
    pprint("Backup completed but couldn't locate backup file", "yellow")
    return None


def rollback_update(app_dir: str, backup_file: Optional[str] = None):
    """
    Rollback the update if something goes wrong.
    
    Args:
        app_dir: Path to the Bayanat application directory
        backup_file: Optional path to the database backup file to restore
    """
    pprint("Rolling back the update...", "yellow")
    
    # If we have a backup file, try to restore it
    if backup_file and os.path.exists(backup_file):
        pprint(f"Restoring database from backup: {backup_file}", "yellow")
        success, output = run_flask_command(app_dir, f"restore-db {backup_file}")
        
        if success:
            pprint("Database restored successfully.", "green")
        else:
            pprint(f"Failed to restore database: {output}", "bold red")
    else:
        pprint("No database backup file available for rollback.", "yellow")
    
    # Try to revert code to previous commit if Git is available
    if os.path.isdir(os.path.join(app_dir, ".git")):
        try:
            pprint("Reverting code to previous state...", "yellow")
            run_command(["git", "reset", "--hard", "HEAD@{1}"], cwd=app_dir)
            pprint("Code reverted to previous state.", "green")
        except Exception as e:
            pprint(f"Failed to revert code: {str(e)}", "bold red")


def fetch_latest_code(app_dir: str, repo_url: str, force: bool):
    """Fetch the latest code from the repository."""
    if not os.path.isdir(os.path.join(app_dir, ".git")):
        pprint("Cloning repository...", "yellow")
        run_command(["git", "clone", repo_url, app_dir])
    else:
        pprint("Fetching latest code...", "yellow")
        run_command(["git", "fetch"], cwd=app_dir)
        run_command(["git", "checkout", "master"], cwd=app_dir)
        if force:
            run_command(["git", "reset", "--hard", "origin/master"], cwd=app_dir)
        run_command(["git", "pull"], cwd=app_dir)


def install_dependencies(app_dir: str):
    """Install the required dependencies."""
    pprint("Installing dependencies...", "yellow")
    env_dir = os.path.join(app_dir, "env")
    
    if not os.path.isdir(env_dir):
        pprint("Creating virtual environment using virtualenv...", "yellow")
        run_command(["virtualenv", env_dir], cwd=app_dir)
    
    pip_path = os.path.join(env_dir, "bin", "pip")
    
    try:
        pprint("Upgrading pip...", "yellow")
        run_command([pip_path, "install", "--upgrade", "pip"], cwd=app_dir)
        
        # Use the new requirements location 
        requirements_path = os.path.join(app_dir, "requirements", "main.txt")
        
        pprint("Installing packages from requirements/main.txt...", "yellow")
        run_command([pip_path, "install", "-r", requirements_path], cwd=app_dir)
        
        # Install development requirements if they exist
        dev_requirements_path = os.path.join(app_dir, "requirements", "dev.txt")
        if os.path.exists(dev_requirements_path):
            pprint("Installing development packages...", "yellow")
            run_command([pip_path, "install", "-r", dev_requirements_path], cwd=app_dir)
            
        pprint("Dependencies installed successfully.", "green")
    except subprocess.CalledProcessError as e:
        pprint(f"Failed to install dependencies: {e.stderr}", "bold red")
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
    success, output = run_flask_command(app_dir, "apply-migrations --dry-run")
    pprint(output)  # Print the dry-run output
    if not success:
        return False, output
    
    if "No pending migrations to apply" in output:
        pprint("No pending migrations to apply.", "bold green")
        return True, "No pending migrations to apply."
    
    # Apply the migrations
    success, output = run_flask_command(app_dir, "apply-migrations")
    pprint(output)  # Print the migration output
    if not success:
        return False, output
    
    if "[Success]" in output:
        pprint("Migrations applied successfully.", "bold green")
        return True, "Migrations applied successfully."
    else:
        pprint(f"Migration process failed: {output}", "bold red")
        return False, f"Migration process failed: {output}"


def restart_services(app_dir: str, service_name: str = "bayanat"):
    """
    Restart the Bayanat service using systemctl.
    
    Args:
        app_dir: Path to the Bayanat application directory
        service_name: Name of the systemd service (default: "bayanat")
    
    Returns:
        True if restart successful, False otherwise
    """
    pprint("Restarting services...", "yellow")
    
    try:
        # Check if systemctl is available
        result = subprocess.run(["which", "systemctl"], capture_output=True, text=True)
        if result.returncode != 0:
            pprint("systemctl not found. Service restart requires systemd.", "bold red")
            return False
            
        # Attempt to restart the service
        pprint(f"Attempting to restart {service_name} service...", "yellow")
        result = subprocess.run(["systemctl", "restart", service_name], 
                           capture_output=True, text=True)
        
        if result.returncode == 0:
            pprint(f"Successfully restarted {service_name} service.", "green")
            return True
        elif "Access denied" in result.stderr or "Permission denied" in result.stderr:
            pprint("Permission denied. Try running with sudo or as root.", "bold red")
            return False
        else:
            pprint(f"Failed to restart service: {result.stderr}", "bold red")
            return False
    except Exception as e:
        pprint(f"Error during service restart: {str(e)}", "bold red")
        return False


def validate_bayanat_directory(app_dir: str) -> bool:
    """
    Check if the specified directory is a valid Bayanat application directory.
    """
    required_files = [
        'docker-compose.yml',
        'pyproject.toml',
        'README.md',
        'run.py'
    ]
    required_dirs = [
        'flask',
        'nginx',
        'docs',
        'tests',
        'requirements'  # Add requirements directory to required directories
    ]

    # Check specifically for requirements/main.txt
    if not os.path.isfile(os.path.join(app_dir, 'requirements', 'main.txt')):
        pprint("Error: Required file 'requirements/main.txt' not found", "bold red")
        return False

    for file in required_files:
        if not os.path.isfile(os.path.join(app_dir, file)):
            pprint(f"Error: Required file '{file}' not found in {app_dir}", "bold red")
            return False

    for directory in required_dirs:
        if not os.path.isdir(os.path.join(app_dir, directory)):
            pprint(f"Error: Required directory '{directory}' not found in {app_dir}", "bold red")
            return False

    return True

@app.callback(invoke_without_command=True)
def main(ctx: typer.Context):
    """
    Bayanat CLI tool.
    """
    if ctx.invoked_subcommand is None:
        pprint("[bold red]Missing command.[/]")
        pprint("Use [bold blue]bayanat --help[/] to see available commands.")
        raise typer.Exit(code=1)

@app.command()
def update(
    path: str = typer.Argument(None, help="Path to the Bayanat application directory (auto-detected if not provided)"),
    skip_git: bool = typer.Option(False, help="Skip Git operations"),
    skip_deps: bool = typer.Option(False, help="Skip dependency installation"),
    skip_migrations: bool = typer.Option(False, help="Skip database migrations"),
    skip_restart: bool = typer.Option(False, help="Skip service restart"),
    force: bool = typer.Option(False, help="Force update even if already up-to-date"),
    service_name: str = typer.Option("bayanat", help="Name of the systemd service to restart")
):
    """
    Update the Bayanat application.
    """
    # Auto-detect Bayanat installation
    if path is None:
        current_dir = os.getcwd()
        # Look for .bayanat-cli metadata file
        if os.path.exists(os.path.join(current_dir, ".bayanat-cli")):
            path = os.path.join(current_dir, "bayanat")
        else:
            # Fallback to current directory for backward compatibility
            path = current_dir
    
    lock_applied = False # Flag to track if lock was successful
    backup_path = None # Store backup path for potential rollback
    try:
        # Validate the Bayanat directory before proceeding
        if not validate_bayanat_directory(path):
            pprint("Error: The specified directory does not appear to be a valid Bayanat application directory.", "bold red")
            raise typer.Exit(code=1)

        # Display current version
        current_version = get_bayanat_version(path)
        pprint(f"Current Bayanat version: {current_version}", "bold blue")
        display_version(current_version, "Current Bayanat version")
        
        # --- Add Lock Step --- 
        pprint("Attempting to lock the Bayanat application...", "yellow")
        lock_success, lock_output = run_flask_command(path, "lock --reason \"CLI update in progress\"")
        if not lock_success:
            pprint(f"Error: Failed to lock the Bayanat application. Output:\n{lock_output}", "bold red")
            raise typer.Exit(code=1)
        else:
            lock_applied = True
            pprint("Application locked successfully.", "green")
        # --- End Lock Step ---

        with Progress() as progress:
            task = progress.add_task("\n[green]Updating Bayanat...", total=100)

            check_system_requirements()
            progress.update(task, advance=10)

            backup_path = backup_database(path)
            progress.update(task, advance=10)

            if not skip_git:
                fetch_latest_code(path, BAYANAT_REPO_URL, force)
            progress.update(task, advance=20)

            # Check if the version is already up-to-date
            new_version = get_bayanat_version(path)
            
            # Track update in version history
            if current_version != new_version or force:
                # Update database to reflect new version from pyproject.toml
                pprint(f"Updating database version from {current_version} to {new_version}...", "yellow")
                success, _ = run_flask_command(path, f"set_version {new_version}")
                if not success:
                    pprint("Warning: Failed to update version in database.", "bold yellow")
                
                if not skip_deps:
                    pprint("Installing dependencies...", "yellow")
                    install_dependencies(path)
                progress.update(task, advance=20)

                if not skip_migrations:
                    pprint("Applying migrations...", "yellow")
                    success, output = apply_migrations(path)
                    if not success:
                        pprint(f"Error applying migrations: {output}", "bold red")
                        raise Exception("Migration failed")
                progress.update(task, advance=20)

                if not skip_restart:
                    pprint("Restarting services...", "yellow")
                    restart_services(path, service_name)
                progress.update(task, advance=20)
                
                # Verify versions match after update
                pprint("Verifying version consistency...", "yellow")
                success, output = run_flask_command(path, "get_version")
                if success:
                    # Check if settings and DB versions match
                    if "Warning:" in output:
                        pprint("Warning: Version mismatch detected after update.", "bold yellow")
                        pprint(output, "yellow")
                    else:
                        pprint("Version verification successful.", "green")
            else:
                pprint("Bayanat is already up-to-date!", "bold green")
                
            # --- Add Unlock Step (Success Path) --- 
            if lock_applied:
                pprint("Unlocking the Bayanat application...", "yellow")
                unlock_success, unlock_output = run_flask_command(path, "unlock")
                if not unlock_success:
                    # Log error but don't necessarily stop the whole process if unlocking fails
                    pprint(f"Warning: Failed to unlock application. Output:\n{unlock_output}", "bold yellow")
                else:
                    pprint("Application unlocked successfully.", "green")
            # --- End Unlock Step ---

        # Display updated version
        display_version(new_version, "Updated Bayanat version")

        pprint("Update completed successfully!", "bold green")
    except Exception as e:
        pprint(f"Error during update: {str(e)}", "bold red")
        
        # --- Add Unlock Step (Error Path) --- 
        if lock_applied:
            pprint("Attempting to unlock application after error...", "yellow")
            unlock_success, unlock_output = run_flask_command(path, "unlock")
            if not unlock_success:
                pprint(f"Warning: Failed to unlock application after error. Manual unlock may be required. Output:\n{unlock_output}", "bold yellow")
            else:
                pprint("Application unlocked.", "green")
        # --- End Unlock Step ---
        
        rollback_update(path, backup_path) # Pass backup_path to rollback
        raise typer.Exit(code=1)


def check_virtualenv_support():
    """Ensure that the venv module is available for creating virtual environments."""
    try:
        import venv
    except ImportError:
        pprint("[bold red]Error:[/] Python's venv module is not available.")
        raise typer.Exit(code=1)

def check_permissions(directory: str):
    """Check if the current user has read/write permissions for the directory."""
    if not os.access(directory, os.R_OK | os.W_OK):
        pprint(f"[bold red]Error:[/] Insufficient permissions for directory '{directory}'.")
        raise typer.Exit(code=1)

def check_network_connectivity(url: str):
    """Check if the network is accessible and the URL is reachable."""
    try:
        response = requests.get(url, timeout=5)
        if response.status_code != 200:
            raise Exception("Failed to reach the repository")
    except requests.RequestException:
        pprint("[bold red]Error:[/] Network connectivity issue. Cannot reach the repository.")
        raise typer.Exit(code=1)

def display_version(version: str, message: str):
    """Display version information in a formatted panel."""
    panel = Panel(f"{message}: [bold blue]{version}[/]", expand=False)
    console.print(panel)  # Use console.print to render the Panel

@app.command()
def install(
    force: bool = typer.Option(False, help="Force installation, even if the directory is not empty")
):
    """
    Install the Bayanat application in the current directory.
    """
    app_dir = os.getcwd()  # Use current directory like Ghost CLI
    try:
        # Step 1: Check system requirements and network connectivity
        pprint("Checking system requirements...", "yellow")
        check_system_requirements()  # Checks Python version and Git installation
        check_virtualenv_support()    # Checks for venv availability
        check_network_connectivity(BAYANAT_REPO_URL)  # Checks access to the repository

        # Step 2: Verify the installation directory and permissions
        pprint(f"Installing Bayanat in: {app_dir}", "blue")
        check_permissions(app_dir)
        if os.listdir(app_dir) and not force:
            pprint(f"[bold red]Error:[/] Directory '{app_dir}' is not empty. Use --force to override.")
            raise typer.Exit(code=1)

        # Step 3: Create Bayanat directory structure
        pprint("Setting up directory structure...", "yellow")
        bayanat_dir = os.path.join(app_dir, "bayanat")
        if not os.path.exists(bayanat_dir):
            os.makedirs(bayanat_dir)

        # Step 4: Clone the repository into the bayanat subdirectory
        pprint("Cloning the Bayanat repository...", "yellow")
        fetch_latest_code(bayanat_dir, BAYANAT_REPO_URL, force=True)

        # Step 5: Create a virtual environment in the bayanat directory
        pprint("Setting up the virtual environment...", "yellow")
        env_dir = os.path.join(bayanat_dir, "env")
        if not os.path.exists(env_dir):
            venv.create(env_dir, with_pip=True)

        # Step 6: Install dependencies
        pprint("Installing dependencies...", "yellow")
        install_dependencies(bayanat_dir)

        # Step 7: Create CLI metadata file
        pprint("Creating installation metadata...", "yellow")
        cli_metadata = {
            "version": get_bayanat_version(bayanat_dir),
            "installed_at": datetime.now().isoformat(),
            "installation_type": "production"
        }
        with open(os.path.join(app_dir, ".bayanat-cli"), "w") as f:
            json.dump(cli_metadata, f, indent=2)

        # Step 8: Apply initial migrations (optional, will be done in setup)
        pprint("Applying initial database migrations...", "yellow")
        apply_migrations(bayanat_dir)

        # Step 9: Finalize installation
        pprint("Bayanat installation completed successfully!", "bold green")
        pprint(f"Run 'bayanat update' from {app_dir} to update in the future.", "blue")
    except Exception as e:
        pprint(f"Error during installation: {str(e)}", "bold red")
        rollback_update(bayanat_dir if 'bayanat_dir' in locals() else app_dir)
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
        pprint(f"Error retrieving version: {str(e)}", "bold red")
        raise typer.Exit(code=1)

def get_venv_python(app_dir: str) -> str:
    """
    Get the Python interpreter path from the virtualenv.
    Reads the venv path from pyproject.toml if available, otherwise uses default 'env'.
    """
    try:
        import tomli
        with open(os.path.join(app_dir, "pyproject.toml"), "rb") as f:
            config = tomli.load(f)
            venv_path = config.get("tool", {}).get("bayanat", {}).get("venv_path", "env")
    except (ImportError, FileNotFoundError, KeyError):
        venv_path = "env"
    
    python_path = os.path.join(app_dir, venv_path, "bin", "python")
    
    if not os.path.exists(python_path):
        raise FileNotFoundError(f"Virtual environment Python interpreter not found at {python_path}")
    
    return python_path

def run_flask_command(app_dir: str, command: str, env: dict = None) -> Tuple[bool, str]:
    """
    Run a Flask CLI command in the virtual environment.
    
    Args:
        app_dir: The application directory
        command: The Flask command to run
        env: Optional environment variables
        
    Returns:
        Tuple of (success: bool, output: str)
    """
    try:
        python_path = get_venv_python(app_dir)
        
        # Prepare the environment
        cmd_env = os.environ.copy()
        if env:
            cmd_env.update(env)
        
        # Ensure FLASK_APP is set
        cmd_env['FLASK_APP'] = 'run.py'
        
        # Run the Flask command using the virtual environment's Python
        result = subprocess.run(
            [python_path, "-m", "flask"] + shlex.split(command),
            cwd=app_dir,
            env=cmd_env,
            capture_output=True,
            text=True
        )
        
        if result.returncode == 0:
            return True, result.stdout
        else:
            error_msg = result.stderr or result.stdout
            return False, f"Command failed: {error_msg}"
            
    except FileNotFoundError as e:
        return False, f"Environment error: {str(e)}"
    except subprocess.CalledProcessError as e:
        return False, f"Command execution failed: {e.stderr or e.stdout}"
    except Exception as e:
        return False, f"Unexpected error: {str(e)}"

@app.command()
def backup(
    path: str = typer.Argument(".", help="Path to the Bayanat application directory"),
    output: str = typer.Option(None, "--output", "-o", help="Custom output file path for the backup")
):
    """
    Create a database backup without performing a full update.
    """
    try:
        # Validate the Bayanat directory before proceeding
        if not validate_bayanat_directory(path):
            pprint("Error: The specified directory does not appear to be a valid Bayanat application directory.", "bold red")
            raise typer.Exit(code=1)

        # Perform the backup
        backup_path = backup_database(path, output)
        
        if backup_path:
            pprint(f"Backup created successfully at: {backup_path}", "bold green")
        else:
            pprint("Backup operation failed.", "bold red")
            raise typer.Exit(code=1)
            
    except Exception as e:
        pprint(f"Error during backup: {str(e)}", "bold red")
        raise typer.Exit(code=1)

@app.command()
def restore(
    backup_file: str = typer.Argument(..., help="Path to the backup file to restore"),
    path: str = typer.Option(".", "--path", "-p", help="Path to the Bayanat application directory")
):
    """
    Restore a database from a backup file.
    """
    try:
        # Validate the Bayanat directory before proceeding
        if not validate_bayanat_directory(path):
            pprint("Error: The specified directory does not appear to be a valid Bayanat application directory.", "bold red")
            raise typer.Exit(code=1)
            
        # Verify backup file exists
        if not os.path.exists(backup_file):
            pprint(f"Error: Backup file not found: {backup_file}", "bold red")
            raise typer.Exit(code=1)
            
        # Try to restore
        pprint(f"Restoring database from backup: {backup_file}", "yellow")
        success, output = run_flask_command(path, f"restore-db {backup_file}")
        
        if success:
            pprint("Database restored successfully.", "bold green")
        else:
            pprint(f"Failed to restore database: {output}", "bold red")
            raise typer.Exit(code=1)
            
    except Exception as e:
        pprint(f"Error during restore: {str(e)}", "bold red")
        raise typer.Exit(code=1)

if __name__ == "__main__":
    app()

