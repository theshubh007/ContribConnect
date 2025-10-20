# Quick script to reset repositories to only RooCode
# Run this from the project root

param(
    [string]$Environment = "dev",
    [string]$AwsProfile = "default"
)

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Resetting to RooCode Only" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Run the reset script
& ".\infrastructure\scripts\reset-to-roocode-only.ps1" -Environment $Environment -AwsProfile $AwsProfile

Write-Host ""
Write-Host "Done! Only RooCodeInc/Roo-Code is now configured." -ForegroundColor Green
Write-Host ""
