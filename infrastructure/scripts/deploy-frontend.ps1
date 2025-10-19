# Deploy Frontend to S3 and CloudFront
param(
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1",
    [string]$AwsProfile = "default"
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Deploy Frontend" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# Get AWS Account ID
$AwsAccountId = aws sts get-caller-identity --profile $AwsProfile --query Account --output text

# Get bucket name
$WebBucket = "cc-web-$Environment-$AwsAccountId"

Write-Host ""
Write-Host "Step 1: Deploy CloudFront Distribution" -ForegroundColor Yellow
Write-Host ""

$StackName = "cc-cloudfront-$Environment"
$TemplateFile = "infrastructure/cloudformation/cloudfront.yaml"

# Check if stack exists
$ErrorActionPreference = "Continue"
$StackExists = aws cloudformation describe-stacks --stack-name $StackName --region $AwsRegion --profile $AwsProfile 2>&1
$StackFound = $LASTEXITCODE -eq 0
$ErrorActionPreference = "Stop"

if ($StackFound) {
    Write-Host "CloudFront stack exists. Updating..." -ForegroundColor Yellow
    
    aws cloudformation update-stack `
        --stack-name $StackName `
        --template-body file://$TemplateFile `
        --parameters `
            ParameterKey=Environment,ParameterValue=$Environment `
            ParameterKey=WebBucketName,ParameterValue=$WebBucket `
        --region $AwsRegion `
        --profile $AwsProfile
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Waiting for stack update (this may take 10-15 minutes)..."
        aws cloudformation wait stack-update-complete --stack-name $StackName --region $AwsRegion --profile $AwsProfile
        Write-Host "Stack updated!" -ForegroundColor Green
    } else {
        Write-Host "No updates needed" -ForegroundColor Yellow
    }
} else {
    Write-Host "Creating CloudFront stack (this may take 10-15 minutes)..." -ForegroundColor Yellow
    
    aws cloudformation create-stack `
        --stack-name $StackName `
        --template-body file://$TemplateFile `
        --parameters `
            ParameterKey=Environment,ParameterValue=$Environment `
            ParameterKey=WebBucketName,ParameterValue=$WebBucket `
        --region $AwsRegion `
        --profile $AwsProfile
    
    Write-Host "Waiting for stack creation..."
    aws cloudformation wait stack-create-complete --stack-name $StackName --region $AwsRegion --profile $AwsProfile
    Write-Host "Stack created!" -ForegroundColor Green
}

Write-Host ""
Write-Host "Step 2: Build Frontend" -ForegroundColor Yellow
Write-Host ""

# Check if frontend directory exists
if (-not (Test-Path "frontend")) {
    Write-Host "Error: frontend directory not found" -ForegroundColor Red
    exit 1
}

# Build frontend
Set-Location frontend
Write-Host "Installing dependencies..."
npm install

Write-Host "Building production bundle..."
npm run build

Set-Location ..

Write-Host ""
Write-Host "Step 3: Deploy to S3" -ForegroundColor Yellow
Write-Host ""

# Sync to S3
Write-Host "Uploading files to S3..."
aws s3 sync frontend/dist/ s3://$WebBucket/ --delete --region $AwsRegion --profile $AwsProfile

Write-Host ""
Write-Host "Step 4: Invalidate CloudFront Cache" -ForegroundColor Yellow
Write-Host ""

# Get distribution ID
$DistributionId = aws cloudformation describe-stacks --stack-name $StackName --region $AwsRegion --profile $AwsProfile --query "Stacks[0].Outputs[?OutputKey=='DistributionId'].OutputValue" --output text

Write-Host "Creating cache invalidation..."
aws cloudfront create-invalidation --distribution-id $DistributionId --paths "/*" --region $AwsRegion --profile $AwsProfile

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Get website URL
$WebsiteUrl = aws cloudformation describe-stacks --stack-name $StackName --region $AwsRegion --profile $AwsProfile --query "Stacks[0].Outputs[?OutputKey=='WebsiteURL'].OutputValue" --output text

Write-Host "Your website is live at:"
Write-Host "  $WebsiteUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host "Note: It may take a few minutes for CloudFront to propagate changes globally."
