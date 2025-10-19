# Deploy Frontend to S3 and Invalidate CloudFront Cache

param(
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1",
    [string]$AwsProfile = "default"
)

$ErrorActionPreference = "Stop"

Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Deploy Frontend to S3" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""

# Get AWS Account ID
$AwsAccountId = aws sts get-caller-identity --profile $AwsProfile --query Account --output text

# S3 bucket name
$BucketName = "cc-web-$Environment-$AwsAccountId"

Write-Host "Bucket: $BucketName" -ForegroundColor Cyan
Write-Host "Region: $AwsRegion" -ForegroundColor Cyan
Write-Host ""

# Check if dist folder exists
if (-not (Test-Path "dist")) {
    Write-Host "Error: dist folder not found. Run 'npm run build' first." -ForegroundColor Red
    exit 1
}

# Sync to S3
Write-Host "Uploading files to S3..." -ForegroundColor Yellow
aws s3 sync dist/ s3://$BucketName/ --delete --region $AwsRegion --profile $AwsProfile

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to upload to S3" -ForegroundColor Red
    exit 1
}

Write-Host "Files uploaded successfully!" -ForegroundColor Green
Write-Host ""

# Get CloudFront distribution ID
Write-Host "Getting CloudFront distribution ID..." -ForegroundColor Yellow
$DistributionId = aws cloudformation describe-stacks --stack-name "cc-cloudfront-$Environment" --region $AwsRegion --profile $AwsProfile --query "Stacks[0].Outputs[?OutputKey=='DistributionId'].OutputValue" --output text 2>$null

if (-not $DistributionId) {
    Write-Host "Warning: Could not find CloudFront distribution. Trying alternative method..." -ForegroundColor Yellow
    
    # Try to find distribution by origin
    $Distributions = aws cloudfront list-distributions --profile $AwsProfile --query "DistributionList.Items[?Origins.Items[?DomainName=='$BucketName.s3.$AwsRegion.amazonaws.com']].Id" --output text 2>$null
    
    if ($Distributions) {
        $DistributionId = $Distributions.Split()[0]
    }
}

if ($DistributionId) {
    Write-Host "Distribution ID: $DistributionId" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Creating CloudFront invalidation..." -ForegroundColor Yellow
    
    $InvalidationId = aws cloudfront create-invalidation --distribution-id $DistributionId --paths "/*" --profile $AwsProfile --query 'Invalidation.Id' --output text
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Invalidation created: $InvalidationId" -ForegroundColor Green
        Write-Host "Cache will be cleared in a few minutes" -ForegroundColor Gray
    } else {
        Write-Host "Warning: Failed to create invalidation" -ForegroundColor Yellow
    }
} else {
    Write-Host "Warning: CloudFront distribution not found. Skipping cache invalidation." -ForegroundColor Yellow
    Write-Host "If you have CloudFront, manually invalidate with:" -ForegroundColor Gray
    Write-Host "  aws cloudfront create-invalidation --distribution-id YOUR_DIST_ID --paths '/*'" -ForegroundColor Gray
}

Write-Host ""
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""

if ($DistributionId) {
    # Get CloudFront domain
    $Domain = aws cloudfront get-distribution --id $DistributionId --profile $AwsProfile --query 'Distribution.DomainName' --output text 2>$null
    
    if ($Domain) {
        Write-Host "Your application is available at:" -ForegroundColor Cyan
        Write-Host "  https://$Domain" -ForegroundColor White
    }
} else {
    Write-Host "S3 Website URL:" -ForegroundColor Cyan
    Write-Host "  http://$BucketName.s3-website-$AwsRegion.amazonaws.com" -ForegroundColor White
}

Write-Host ""
