# ContribConnect Bedrock Services Setup Script (Fixed)
param(
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1",
    [string]$AwsProfile = "default"
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Bedrock Services Setup (Fixed)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Environment: $Environment"
Write-Host "Region: $AwsRegion"
Write-Host ""

# Get AWS Account ID
$AwsAccountId = aws sts get-caller-identity --profile $AwsProfile --query Account --output text
Write-Host "AWS Account ID: $AwsAccountId" -ForegroundColor Green

# Get Knowledge Base Docs bucket name
Write-Host "Retrieving S3 bucket information..."
$KbBucketName = aws cloudformation describe-stacks --stack-name "cc-s3-$Environment" --region $AwsRegion --profile $AwsProfile --query "Stacks[0].Outputs[?OutputKey=='KnowledgeBaseDocsBucketName'].OutputValue" --output text

if (-not $KbBucketName) {
    Write-Host "Error: Could not find Knowledge Base docs bucket" -ForegroundColor Red
    exit 1
}

Write-Host "Knowledge Base Docs Bucket: $KbBucketName" -ForegroundColor Green

# Clean up any failed stack first
Write-Host ""
Write-Host "Checking for existing stack..."
$ExistingStack = aws cloudformation describe-stacks --stack-name "cc-bedrock-$Environment" --region $AwsRegion --profile $AwsProfile --query "Stacks[0].StackStatus" --output text 2>$null

if ($ExistingStack -eq "ROLLBACK_COMPLETE") {
    Write-Host "Cleaning up failed stack..." -ForegroundColor Yellow
    aws cloudformation delete-stack --stack-name "cc-bedrock-$Environment" --region $AwsRegion --profile $AwsProfile
    Write-Host "Waiting for stack deletion..."
    aws cloudformation wait stack-delete-complete --stack-name "cc-bedrock-$Environment" --region $AwsRegion --profile $AwsProfile
    Write-Host "Stack deleted" -ForegroundColor Green
}

Write-Host ""
Write-Host "Note: Bedrock setup requires proper IAM permissions" -ForegroundColor Yellow
Write-Host "Press Enter to continue..."
Read-Host

# Deploy Bedrock resources
Write-Host "Deploying Bedrock resources..." -ForegroundColor Yellow
Write-Host "This may take 5-10 minutes..." -ForegroundColor Cyan

aws cloudformation deploy --template-file infrastructure/cloudformation/bedrock-resources.yaml --stack-name "cc-bedrock-$Environment" --parameter-overrides "Environment=$Environment" "KnowledgeBaseDocsBucketName=$KbBucketName" --capabilities CAPABILITY_NAMED_IAM --region $AwsRegion --profile $AwsProfile --tags "Project=ContribConnect" "Environment=$Environment"

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Deployment failed. Checking error details..." -ForegroundColor Red
    Write-Host ""
    Write-Host "Common issues:" -ForegroundColor Yellow
    Write-Host "1. OpenSearch Serverless permissions issue (403 error)"
    Write-Host "2. IAM role propagation delay"
    Write-Host "3. Bedrock service quotas"
    Write-Host ""
    Write-Host "To see detailed errors, run:" -ForegroundColor Cyan
    Write-Host "aws cloudformation describe-stack-events --stack-name cc-bedrock-$Environment --region $AwsRegion --max-items 5"
    Write-Host ""
    Write-Host "To retry after fixing issues:" -ForegroundColor Cyan
    Write-Host "1. Delete the failed stack:"
    Write-Host "   aws cloudformation delete-stack --stack-name cc-bedrock-$Environment --region $AwsRegion"
    Write-Host "2. Wait for deletion:"
    Write-Host "   aws cloudformation wait stack-delete-complete --stack-name cc-bedrock-$Environment --region $AwsRegion"
    Write-Host "3. Run this script again"
    exit 1
}

# Get Bedrock resource IDs
Write-Host ""
Write-Host "Retrieving Bedrock resource information..."

$KnowledgeBaseId = aws cloudformation describe-stacks --stack-name "cc-bedrock-$Environment" --region $AwsRegion --profile $AwsProfile --query "Stacks[0].Outputs[?OutputKey=='KnowledgeBaseId'].OutputValue" --output text

$GuardrailId = aws cloudformation describe-stacks --stack-name "cc-bedrock-$Environment" --region $AwsRegion --profile $AwsProfile --query "Stacks[0].Outputs[?OutputKey=='GuardrailId'].OutputValue" --output text

$GuardrailVersion = aws cloudformation describe-stacks --stack-name "cc-bedrock-$Environment" --region $AwsRegion --profile $AwsProfile --query "Stacks[0].Outputs[?OutputKey=='GuardrailVersion'].OutputValue" --output text

Write-Host "OK - Bedrock resources deployed" -ForegroundColor Green
Write-Host "  Knowledge Base ID: $KnowledgeBaseId"
Write-Host "  Guardrail ID: $GuardrailId"
Write-Host "  Guardrail Version: $GuardrailVersion"

# Save configuration
$ConfigFile = "infrastructure/.bedrock-config-$Environment.json"
$Config = @{
    knowledgeBaseId = $KnowledgeBaseId
    guardrailId = $GuardrailId
    guardrailVersion = $GuardrailVersion
    kbBucketName = $KbBucketName
    region = $AwsRegion
    environment = $Environment
} | ConvertTo-Json

$Config | Out-File -FilePath $ConfigFile -Encoding utf8
Write-Host ""
Write-Host "Configuration saved to: $ConfigFile" -ForegroundColor Green
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Setup Complete!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
