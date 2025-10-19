# ContribConnect Infrastructure Deployment Script (PowerShell)
# This script deploys all CloudFormation stacks for the ContribConnect project

param(
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1",
    [string]$AwsProfile = "default"
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "ContribConnect Infrastructure Deployment" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Environment: $Environment"
Write-Host "Region: $AwsRegion"
Write-Host "Profile: $AwsProfile"
Write-Host "==========================================" -ForegroundColor Cyan

# Get AWS Account ID
Write-Host "Getting AWS Account ID..."
$AwsAccountId = aws sts get-caller-identity --profile $AwsProfile --query Account --output text
Write-Host "AWS Account ID: $AwsAccountId" -ForegroundColor Green

# Deploy DynamoDB Tables
Write-Host ""
Write-Host "Deploying DynamoDB tables..." -ForegroundColor Yellow
aws cloudformation deploy `
  --template-file infrastructure/cloudformation/dynamodb-tables.yaml `
  --stack-name "cc-dynamodb-$Environment" `
  --parameter-overrides "Environment=$Environment" `
  --region $AwsRegion `
  --profile $AwsProfile `
  --tags "Project=ContribConnect" "Environment=$Environment"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to deploy DynamoDB tables" -ForegroundColor Red
    exit 1
}

# Get DynamoDB table names from stack outputs
$NodesTable = aws cloudformation describe-stacks `
  --stack-name "cc-dynamodb-$Environment" `
  --region $AwsRegion `
  --profile $AwsProfile `
  --query "Stacks[0].Outputs[?OutputKey=='NodesTableName'].OutputValue" `
  --output text

$EdgesTable = aws cloudformation describe-stacks `
  --stack-name "cc-dynamodb-$Environment" `
  --region $AwsRegion `
  --profile $AwsProfile `
  --query "Stacks[0].Outputs[?OutputKey=='EdgesTableName'].OutputValue" `
  --output text

$ReposTable = aws cloudformation describe-stacks `
  --stack-name "cc-dynamodb-$Environment" `
  --region $AwsRegion `
  --profile $AwsProfile `
  --query "Stacks[0].Outputs[?OutputKey=='ReposTableName'].OutputValue" `
  --output text

$SessionsTable = aws cloudformation describe-stacks `
  --stack-name "cc-dynamodb-$Environment" `
  --region $AwsRegion `
  --profile $AwsProfile `
  --query "Stacks[0].Outputs[?OutputKey=='AgentSessionsTableName'].OutputValue" `
  --output text

Write-Host "✓ DynamoDB tables deployed successfully" -ForegroundColor Green
Write-Host "  - Nodes: $NodesTable"
Write-Host "  - Edges: $EdgesTable"
Write-Host "  - Repos: $ReposTable"
Write-Host "  - Sessions: $SessionsTable"

# Deploy S3 Buckets
Write-Host ""
Write-Host "Deploying S3 buckets..." -ForegroundColor Yellow
aws cloudformation deploy `
  --template-file infrastructure/cloudformation/s3-buckets.yaml `
  --stack-name "cc-s3-$Environment" `
  --parameter-overrides "Environment=$Environment" `
  --region $AwsRegion `
  --profile $AwsProfile `
  --tags "Project=ContribConnect" "Environment=$Environment"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to deploy S3 buckets" -ForegroundColor Red
    exit 1
}

# Get S3 bucket names from stack outputs
$RawBucket = aws cloudformation describe-stacks `
  --stack-name "cc-s3-$Environment" `
  --region $AwsRegion `
  --profile $AwsProfile `
  --query "Stacks[0].Outputs[?OutputKey=='RawDataBucketName'].OutputValue" `
  --output text

$KbBucket = aws cloudformation describe-stacks `
  --stack-name "cc-s3-$Environment" `
  --region $AwsRegion `
  --profile $AwsProfile `
  --query "Stacks[0].Outputs[?OutputKey=='KnowledgeBaseDocsBucketName'].OutputValue" `
  --output text

$WebBucket = aws cloudformation describe-stacks `
  --stack-name "cc-s3-$Environment" `
  --region $AwsRegion `
  --profile $AwsProfile `
  --query "Stacks[0].Outputs[?OutputKey=='WebBucketName'].OutputValue" `
  --output text

Write-Host "✓ S3 buckets deployed successfully" -ForegroundColor Green
Write-Host "  - Raw Data: $RawBucket"
Write-Host "  - KB Docs: $KbBucket"
Write-Host "  - Web: $WebBucket"

# Deploy IAM Roles
Write-Host ""
Write-Host "Deploying IAM roles..." -ForegroundColor Yellow
aws cloudformation deploy `
  --template-file infrastructure/cloudformation/iam-roles.yaml `
  --stack-name "cc-iam-$Environment" `
  --parameter-overrides `
    "Environment=$Environment" `
    "NodesTableName=$NodesTable" `
    "EdgesTableName=$EdgesTable" `
    "ReposTableName=$ReposTable" `
    "AgentSessionsTableName=$SessionsTable" `
    "RawDataBucketName=$RawBucket" `
    "KnowledgeBaseDocsBucketName=$KbBucket" `
  --capabilities CAPABILITY_NAMED_IAM `
  --region $AwsRegion `
  --profile $AwsProfile `
  --tags "Project=ContribConnect" "Environment=$Environment"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to deploy IAM roles" -ForegroundColor Red
    exit 1
}

Write-Host "✓ IAM roles deployed successfully" -ForegroundColor Green

# Summary
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next Steps:"
Write-Host "1. Configure Bedrock services:"
Write-Host "   .\infrastructure\scripts\setup-bedrock.ps1 -Environment $Environment -AwsRegion $AwsRegion -AwsProfile $AwsProfile"
Write-Host ""
Write-Host "2. Initialize sample repositories:"
Write-Host "   python infrastructure\scripts\init-sample-repos.py $Environment $AwsRegion $AwsProfile"
Write-Host ""
Write-Host "3. Set up Amazon Q Business (optional)"
Write-Host "4. Deploy Lambda functions"
Write-Host "5. Configure API Gateway"
Write-Host "6. Deploy frontend application"
Write-Host ""
Write-Host "Resource Names:"
Write-Host "  DynamoDB Tables:"
Write-Host "    - $NodesTable"
Write-Host "    - $EdgesTable"
Write-Host "    - $ReposTable"
Write-Host "    - $SessionsTable"
Write-Host "  S3 Buckets:"
Write-Host "    - $RawBucket"
Write-Host "    - $KbBucket"
Write-Host "    - $WebBucket"
Write-Host ""
