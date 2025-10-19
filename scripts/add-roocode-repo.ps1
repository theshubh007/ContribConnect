# Add RooCodeInc/Roo-Code repository to ContribConnect
param(
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1"
)

$ErrorActionPreference = "Stop"

Write-Host "Adding RooCodeInc/Roo-Code repository..." -ForegroundColor Cyan

# Add repository to DynamoDB
$RepoItem = @{
    repoId = @{ S = "repo#RooCodeInc/Roo-Code" }
    org = @{ S = "RooCodeInc" }
    repo = @{ S = "Roo-Code" }
    enabled = @{ BOOL = $true }
    addedAt = @{ S = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") }
} | ConvertTo-Json -Compress

aws dynamodb put-item `
    --table-name "cc-repos-$Environment" `
    --item $RepoItem `
    --region $AwsRegion

Write-Host "Repository added successfully!" -ForegroundColor Green

# Trigger ingestion Lambda
Write-Host "`nTriggering data ingestion..." -ForegroundColor Yellow

aws lambda invoke `
    --function-name "cc-ingest-$Environment" `
    --region $AwsRegion `
    response.json

$Response = Get-Content response.json | ConvertFrom-Json
Write-Host "`nIngestion Response:" -ForegroundColor Cyan
$Response | ConvertTo-Json -Depth 10

Write-Host "`nData ingestion started! Check logs:" -ForegroundColor Green
Write-Host "aws logs filter-log-events --log-group-name /aws/lambda/cc-ingest-$Environment --region $AwsRegion --start-time `$([DateTimeOffset]::UtcNow.AddMinutes(-5).ToUnixTimeMilliseconds())"
