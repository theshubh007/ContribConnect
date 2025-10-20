# Update Lambda timeout to 30 minutes

param(
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1",
    [int]$TimeoutSeconds = 900  # 15 minutes (AWS Lambda maximum)
)

$FunctionName = "cc-ingest-$Environment"

Write-Host "Updating Lambda timeout for $FunctionName..." -ForegroundColor Cyan
Write-Host "New timeout: $TimeoutSeconds seconds ($([math]::Round($TimeoutSeconds/60, 1)) minutes)" -ForegroundColor Yellow

aws lambda update-function-configuration `
    --function-name $FunctionName `
    --timeout $TimeoutSeconds `
    --region $AwsRegion

if ($LASTEXITCODE -eq 0) {
    Write-Host "Timeout updated successfully!" -ForegroundColor Green
} else {
    Write-Host "Failed to update timeout" -ForegroundColor Red
}
