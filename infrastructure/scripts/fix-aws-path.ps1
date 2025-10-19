# Fix AWS CLI PATH issue permanently
# This script adds the Python Scripts directory to your system PATH

$PythonScriptsPath = "C:\Users\HP\AppData\Roaming\Python\Python310\Scripts"

Write-Host "Adding Python Scripts directory to PATH..." -ForegroundColor Yellow
Write-Host "Path: $PythonScriptsPath" -ForegroundColor Cyan

# Get current user PATH
$CurrentPath = [Environment]::GetEnvironmentVariable("Path", "User")

# Check if already in PATH
if ($CurrentPath -like "*$PythonScriptsPath*") {
    Write-Host "✓ Path already exists in user PATH" -ForegroundColor Green
} else {
    # Add to user PATH
    $NewPath = "$CurrentPath;$PythonScriptsPath"
    [Environment]::SetEnvironmentVariable("Path", $NewPath, "User")
    Write-Host "✓ Added to user PATH permanently" -ForegroundColor Green
    Write-Host ""
    Write-Host "Please restart PowerShell for changes to take effect" -ForegroundColor Yellow
}

# Add to current session
if ($env:PATH -notlike "*$PythonScriptsPath*") {
    $env:PATH += ";$PythonScriptsPath"
    Write-Host "✓ Added to current session PATH" -ForegroundColor Green
}

Write-Host ""
Write-Host "Testing AWS CLI..." -ForegroundColor Yellow
aws --version

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ AWS CLI is working!" -ForegroundColor Green
} else {
    Write-Host "✗ AWS CLI test failed" -ForegroundColor Red
}
