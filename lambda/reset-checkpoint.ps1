# Reset PR scraping checkpoint for a repository

param(
    [string]$Org = "RooCodeInc",
    [string]$Repo = "Roo-Code",
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1"
)

$TableName = "cc-repos-$Environment"

Write-Host "Resetting checkpoint for $Org/$Repo..." -ForegroundColor Cyan

$key = @{
    org = @{S = $Org}
    repo = @{S = $Repo}
} | ConvertTo-Json -Compress

$updateExpression = "SET lastProcessedPR = :pr, lastCheckpointAt = :now"
$expressionValues = @{
    ":pr" = @{N = "0"}
    ":now" = @{S = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")}
} | ConvertTo-Json -Compress

aws dynamodb update-item `
    --table-name $TableName `
    --key $key `
    --update-expression $updateExpression `
    --expression-attribute-values $expressionValues `
    --region $AwsRegion

if ($LASTEXITCODE -eq 0) {
    Write-Host "Checkpoint reset successfully!" -ForegroundColor Green
    Write-Host "Next run will start from the beginning." -ForegroundColor Yellow
} else {
    Write-Host "Failed to reset checkpoint" -ForegroundColor Red
}
