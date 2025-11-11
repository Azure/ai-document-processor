<#
.SYNOPSIS
Starts the Azure Functions app locally (PowerShell version of startLocal.sh)

.Run from: repo root or scripts folder
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Ensure we run relative to this script's location
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

# Move into pipeline directory
Set-Location ..\pipeline

# Create venv if missing
if (-not (Test-Path .venv)) {
    Write-Host "Creating virtual environment..."
    python -m venv .venv
}

# Activate venv (Windows / PowerShell)
$activate = Join-Path .venv "Scripts\Activate.ps1"
if (-not (Test-Path $activate)) {
    Write-Error "Activation script not found at $activate"
    exit 1
}
& $activate

# Upgrade pip (optional but helpful)
python -m pip install --upgrade pip

# Install dependencies
pip install -r requirements.txt

# Start Azure Functions host
func start --build