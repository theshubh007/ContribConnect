# Deploy PR Scraping Enhancement
Write-Host "==========================================="
Write-Host "Deploying PR Scraping Enhancement"
Write-Host "==========================================="
Write-Host ""

Write-Host "Step 1: Updating Lambda timeout to 15 minutes..." -ForegroundColor Cyan
aws lambda update-function-configuration `
    --function-name cc-ingest-dev `
    --timeout 900 `
    --region us-east-1

Write-Host ""
Write-Host "Step 2: Deploying updated Lambda code..." -ForegroundColor Cyan
cd lambda/ingest
pip install -r requirements.txt -t .
Compress-Archive -Path * -DestinationPath ../ingest.zip -Force
cd ../..

aws lambda update-function-code `
    --function-name cc-ingest-dev `
    --zip-file fileb://lambda/ingest.zip `
    --region us-east-1

Remove-Item lambda/ingest.zip

Write-Host ""
Write-Host "==========================================="
Write-Host "Deployment Complete!"
Write-Host "==========================================="
Write-Host ""
Write-Host "Available Modes:" -ForegroundColor Yellow
Write-Host "  1. contributors - Fast (2-3 min) - Scrapes ALL contributors only"
Write-Host "  2. prs - Slow (20-30 min) - Scrapes ALL PRs with full details"
Write-Host "  3. full - Very Slow (25-35 min) - Scrapes everything"
Write-Host ""
Write-Host "Test Commands:" -ForegroundColor Cyan
Write-Host ""
Write-Host "# Test contributors-only mode (fast):"
Write-Host 'aws lambda invoke --function-name cc-ingest-dev --payload ''{"mode":"contributors"}'' --region us-east-1 response.json' -ForegroundColor Green
Write-Host ""
Write-Host "# Test PR scraping mode (slow - 20-30 minutes):"
Write-Host 'aws lambda invoke --function-name cc-ingest-dev --payload ''{"mode":"prs"}'' --region us-east-1 response.json' -ForegroundColor Green
Write-Host ""
Write-Host "# Test full mode (very slow - 25-35 minutes):"
Write-Host 'aws lambda invoke --function-name cc-ingest-dev --payload ''{"mode":"full"}'' --region us-east-1 response.json' -ForegroundColor Green
Write-Host ""
Write-Host "Monitor logs:"
Write-Host "aws logs tail /aws/lambda/cc-ingest-dev --follow --region us-east-1" -ForegroundColor Yellow
Write-Host ""
