# ContribConnect Bedrock Services Setup Script (Simplified)
param(
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1",
    [string]$AwsProfile = "default"
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Bedrock Services Setup" -ForegroundColor Cyan
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
Write-Host ""
Write-Host "Press Enter to continue..."
Read-Host

# Deploy Bedrock resources
Write-Host "Deploying Bedrock resources..." -ForegroundColor Yellow
aws cloudformation deploy --template-file infrastructure/cloudformation/bedrock-resources.yaml --stack-name "cc-bedrock-$Environment" --parameter-overrides "Environment=$Environment" "KnowledgeBaseDocsBucketName=$KbBucketName" --capabilities CAPABILITY_NAMED_IAM --region $AwsRegion --profile $AwsProfile --tags "Project=ContribConnect" "Environment=$Environment"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to deploy Bedrock resources" -ForegroundColor Red
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
