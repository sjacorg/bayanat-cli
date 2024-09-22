# bayanat_cli/main.py

import typer

app = typer.Typer()

@app.callback()
def main():
    """
    Bayanat CLI Tool
    """
    pass  # Allows for subcommands like 'update'

@app.command()
def update():
    """
    Update the Bayanat application.
    """
    typer.echo("Update command is running.")

if __name__ == "__main__":
    app()
