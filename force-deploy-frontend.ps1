# Force Deploy Frontend with Cache Busting
Write-Host "==========================================="
Write-Host "Force Deploying Frontend"
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
Write-Host "Step 2: Uploading to S3 with cache control..." -ForegroundColor Cyan
# Upload with no-cache headers to force refresh
aws s3 sync dist/ s3://cc-web-dev-917343669425 --delete --region us-east-1 --cache-control "no-cache, no-store, must-revalidate"

Write-Host ""
Write-Host "Step 3: Invalidating CloudFront cache..." -ForegroundColor Cyan
$invalidationId = aws cloudfront create-invalidation --distribution-id E2QJB013DCKJ2E --paths "/*" --region us-east-1 --query 'Invalidation.Id' --output text

Write-Host "Invalidation ID: $invalidationId" -ForegroundColor Green
Write-Host ""
Write-Host "Step 4: Waiting for invalidation to complete..." -ForegroundColor Cyan
Write-Host "This may take 2-3 minutes..." -ForegroundColor Yellow

aws cloudfront wait invalidation-completed --distribution-id E2QJB013DCKJ2E --id $invalidationId --region us-east-1

cd ..

Write-Host ""
Write-Host "==========================================="
Write-Host "Deployment Complete!"
Write-Host "==========================================="
Write-Host ""
Write-Host "Your site: https://d3hw1a5xeaznh4.cloudfront.net" -ForegroundColor Green
Write-Host ""
Write-Host "Changes deployed:"
Write-Host "  - 251 contributors (not 8)"
Write-Host "  - Network view by default"
Write-Host "  - Direct Graph API (fast!)"
Write-Host ""
Write-Host "Hard refresh your browser: Ctrl+Shift+R" -ForegroundColor Yellow
Write-Host ""
