# Configure repositories for demo - only enable RooCodeInc/Roo-Code

param(
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1",
    [string]$AwsProfile = "default"
)

$ErrorActionPreference = "Stop"

Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Configure Repositories for Demo" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""

# Disable facebook/react
Write-Host "Disabling facebook/react..." -ForegroundColor Yellow
.\infrastructure\scripts\manage-repositories.ps1 -Action disable -Owner "facebook" -Repo "react" -Environment $Environment

# Disable microsoft/vscode
Write-Host "Disabling microsoft/vscode..." -ForegroundColor Yellow
.\infrastructure\scripts\manage-repositories.ps1 -Action disable -Owner "microsoft" -Repo "vscode" -Environment $Environment

# Enable RooCodeInc/Roo-Code
Write-Host "Enabling RooCodeInc/Roo-Code..." -ForegroundColor Yellow
.\infrastructure\scripts\manage-repositories.ps1 -Action enable -Owner "RooCodeInc" -Repo "Roo-Code" -Environment $Environment

Write-Host ""
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Configuration Complete!" -ForegroundColor Green
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Active repositories:" -ForegroundColor Cyan
Write-Host "  ✓ RooCodeInc/Roo-Code (enabled)" -ForegroundColor Green
Write-Host "  ✗ facebook/react (disabled)" -ForegroundColor Gray
Write-Host "  ✗ microsoft/vscode (disabled)" -ForegroundColor Gray
Write-Host ""
Write-Host "Now trigger ingestion to scrape only Roo-Code:" -ForegroundColor Yellow
Write-Host "  aws lambda invoke --function-name cc-ingest-$Environment --region $AwsRegion response.json" -ForegroundColor White
Write-Host ""
