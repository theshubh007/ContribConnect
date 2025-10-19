# Setup GitHub Token in Secrets Manager
param(
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1",
    [string]$AwsProfile = "default"
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "GitHub Token Setup" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "You need a GitHub Personal Access Token with these scopes:" -ForegroundColor Yellow
Write-Host "  - repo (Full control of private repositories)"
Write-Host "  - read:org (Read org and team membership)"
Write-Host ""
Write-Host "To create a token:"
Write-Host "1. Go to: https://github.com/settings/tokens"
Write-Host "2. Click 'Generate new token (classic)'"
Write-Host "3. Select the scopes above"
Write-Host "4. Copy the token"
Write-Host ""

$Token = Read-Host "Enter your GitHub token" -AsSecureString
$TokenPlainText = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Token)
)

if (-not $TokenPlainText) {
    Write-Host "No token provided. Exiting." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Storing token in AWS Secrets Manager..." -ForegroundColor Yellow

$SecretName = "cc-github-token"
$SecretValue = @{token = $TokenPlainText} | ConvertTo-Json

# Check if secret exists
$ErrorActionPreference = "Continue"
$ExistingSecret = aws secretsmanager describe-secret --secret-id $SecretName --region $AwsRegion --profile $AwsProfile 2>&1
$SecretExists = $LASTEXITCODE -eq 0
$ErrorActionPreference = "Stop"

if ($SecretExists) {
    Write-Host "Updating existing secret..." -ForegroundColor Yellow
    aws secretsmanager update-secret --secret-id $SecretName --secret-string $SecretValue --region $AwsRegion --profile $AwsProfile | Out-Null
} else {
    Write-Host "Creating new secret..." -ForegroundColor Yellow
    aws secretsmanager create-secret --name $SecretName --secret-string $SecretValue --region $AwsRegion --profile $AwsProfile | Out-Null
}

Write-Host "✓ GitHub token stored successfully" -ForegroundColor Green
Write-Host ""
Write-Host "You can now run the ingestion Lambda:"
Write-Host "aws lambda invoke --function-name cc-ingest-$Environment --region $AwsRegion response.json"
