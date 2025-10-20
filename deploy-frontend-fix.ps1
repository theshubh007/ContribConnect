# Deploy Frontend Fix for Contributors Display
Write-Host "==========================================="
Write-Host "Deploying Frontend Fix"
Write-Host "==========================================="
Write-Host ""

Write-Host "Step 1: Building frontend..." -ForegroundColor Cyan
cd frontend
npm run build

if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed!" -ForegroundColor Red
    cd ..
    exit 1
}

Write-Host ""
Write-Host "Step 2: Deploying to S3..." -ForegroundColor Cyan
aws s3 sync dist/ s3://cc-frontend-dev-917343669425 --delete --region us-east-1

if ($LASTEXITCODE -ne 0) {
    Write-Host "S3 sync failed!" -ForegroundColor Red
    cd ..
    exit 1
}

Write-Host ""
Write-Host "Step 3: Invalidating CloudFront cache..." -ForegroundColor Cyan
$distributionId = aws cloudfront list-distributions --query "DistributionList.Items[?Origins.Items[0].DomainName=='cc-frontend-dev-917343669425.s3.us-east-1.amazonaws.com'].Id" --output text --region us-east-1

if ($distributionId) {
    Write-Host "Found CloudFront distribution: $distributionId"
    aws cloudfront create-invalidation --distribution-id $distributionId --paths "/*" --region us-east-1
    Write-Host "Cache invalidation started"
} else {
    Write-Host "No CloudFront distribution found (this is OK if not using CloudFront)" -ForegroundColor Yellow
}

cd ..

Write-Host ""
Write-Host "==========================================="
Write-Host "Frontend Deployed Successfully!"
Write-Host "==========================================="
Write-Host ""
Write-Host "Changes:"
Write-Host "  - Now fetches REAL contributor data from DynamoDB"
Write-Host "  - Displays all 251 contributors instead of 8 mock ones"
Write-Host "  - Calls graph-tool Lambda directly"
Write-Host ""
Write-Host "Frontend URL: https://cc-frontend-dev-917343669425.s3.us-east-1.amazonaws.com/index.html"
Write-Host ""
Write-Host "Note: It may take 1-2 minutes for CloudFront cache to clear"
Write-Host "      You can force refresh with Ctrl+Shift+R"
Write-Host ""
