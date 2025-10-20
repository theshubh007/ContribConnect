# Deploy Lambda with checkpoint/resume support and increased timeout

param(
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1"
)

Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Deploying Lambda with Resume Support" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Update Lambda timeout to 15 minutes (AWS maximum)
Write-Host "Step 1: Updating Lambda timeout to 15 minutes (AWS maximum)..." -ForegroundColor Yellow
.\lambda\update-timeout.ps1 -Environment $Environment -AwsRegion $AwsRegion

Write-Host ""

# Step 2: Deploy updated Lambda code
Write-Host "Step 2: Deploying updated Lambda code..." -ForegroundColor Yellow
.\lambda\redeploy-ingest.ps1 -Environment $Environment -AwsRegion $AwsRegion

Write-Host ""
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "New Features:" -ForegroundColor Yellow
Write-Host "  - Checkpoint/Resume: Automatically saves progress every 10 PRs" -ForegroundColor Green
Write-Host "  - Maximum Timeout: 15 minutes (900 seconds - AWS Lambda max)" -ForegroundColor Green
Write-Host "  - Auto-Resume: If Lambda times out, next run continues where it left off" -ForegroundColor Green
Write-Host ""
Write-Host "To invoke PR scraping:" -ForegroundColor Yellow
Write-Host "  aws lambda invoke --function-name cc-ingest-$Environment --cli-binary-format raw-in-base64-out --payload" -NoNewline
Write-Host " '{" -NoNewline
Write-Host '"mode":"prs"' -NoNewline
Write-Host "}' --region $AwsRegion response.json"
Write-Host ""
Write-Host "To reset checkpoint (start from beginning):" -ForegroundColor Yellow
Write-Host "  .\lambda\reset-checkpoint.ps1 -Org RooCodeInc -Repo Roo-Code -Environment $Environment"
Write-Host ""
Write-Host "To monitor logs:" -ForegroundColor Yellow
Write-Host "  aws logs tail /aws/lambda/cc-ingest-$Environment --follow --region $AwsRegion"
