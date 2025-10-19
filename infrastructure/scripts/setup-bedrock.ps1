# ContribConnect Bedrock Services Setup Script
# This script configures Bedrock Knowledge Base and Guardrails

param(
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1",
    [string]$AwsProfile = "default"
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "ContribConnect Bedrock Services Setup" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Environment: $Environment"
Write-Host "Region: $AwsRegion"
Write-Host "Profile: $AwsProfile"
Write-Host "==========================================" -ForegroundColor Cyan

# Get AWS Account ID
Write-Host "Getting AWS Account ID..."
$AwsAccountId = aws sts get-caller-identity --profile $AwsProfile --query Account --output text
Write-Host "AWS Account ID: $AwsAccountId" -ForegroundColor Green

# Get Knowledge Base Docs bucket name from S3 stack
Write-Host ""
Write-Host "Retrieving S3 bucket information..."
$KbBucketName = aws cloudformation describe-stacks `
  --stack-name "cc-s3-$Environment" `
  --region $AwsRegion `
  --profile $AwsProfile `
  --query "Stacks[0].Outputs[?OutputKey=='KnowledgeBaseDocsBucketName'].OutputValue" `
  --output text

if (-not $KbBucketName) {
    Write-Host "Error: Could not find Knowledge Base docs bucket. Please deploy S3 stack first." -ForegroundColor Red
    exit 1
}

Write-Host "Knowledge Base Docs Bucket: $KbBucketName" -ForegroundColor Green

# Check if Nova Pro model is enabled
Write-Host ""
Write-Host "Checking Bedrock model access..." -ForegroundColor Yellow
Write-Host "Note: You may need to manually enable Nova Pro model access in the AWS Console"
Write-Host "      Go to: Bedrock Console > Model access > Manage model access"
Write-Host "      Enable: Amazon Nova Pro (us.amazon.nova-pro-v1:0)"
Write-Host ""
Write-Host "Press Enter to continue after enabling model access, or Ctrl+C to cancel..."
Read-Host

# Deploy Bedrock resources
Write-Host ""
Write-Host "Deploying Bedrock Knowledge Base and Guardrails..." -ForegroundColor Yellow
aws cloudformation deploy `
  --template-file infrastructure/cloudformation/bedrock-resources.yaml `
  --stack-name "cc-bedrock-$Environment" `
  --parameter-overrides `
    "Environment=$Environment" `
    "KnowledgeBaseDocsBucketName=$KbBucketName" `
  --capabilities CAPABILITY_NAMED_IAM `
  --region $AwsRegion `
  --profile $AwsProfile `
  --tags "Project=ContribConnect" "Environment=$Environment"

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to deploy Bedrock resources" -ForegroundColor Red
    exit 1
}

# Get Bedrock resource IDs from stack outputs
Write-Host ""
Write-Host "Retrieving Bedrock resource information..."

$KnowledgeBaseId = aws cloudformation describe-stacks `
  --stack-name "cc-bedrock-$Environment" `
  --region $AwsRegion `
  --profile $AwsProfile `
  --query "Stacks[0].Outputs[?OutputKey=='KnowledgeBaseId'].OutputValue" `
  --output text

$GuardrailId = aws cloudformation describe-stacks `
  --stack-name "cc-bedrock-$Environment" `
  --region $AwsRegion `
  --profile $AwsProfile `
  --query "Stacks[0].Outputs[?OutputKey=='GuardrailId'].OutputValue" `
  --output text

$GuardrailVersion = aws cloudformation describe-stacks `
  --stack-name "cc-bedrock-$Environment" `
  --region $AwsRegion `
  --profile $AwsProfile `
  --query "Stacks[0].Outputs[?OutputKey=='GuardrailVersion'].OutputValue" `
  --output text

$VectorCollectionEndpoint = aws cloudformation describe-stacks `
  --stack-name "cc-bedrock-$Environment" `
  --region $AwsRegion `
  --profile $AwsProfile `
  --query "Stacks[0].Outputs[?OutputKey=='VectorCollectionEndpoint'].OutputValue" `
  --output text

Write-Host "✓ Bedrock resources deployed successfully" -ForegroundColor Green
Write-Host "  - Knowledge Base ID: $KnowledgeBaseId"
Write-Host "  - Guardrail ID: $GuardrailId"
Write-Host "  - Guardrail Version: $GuardrailVersion"
Write-Host "  - Vector Collection Endpoint: $VectorCollectionEndpoint"

# Create Data Source for Knowledge Base
Write-Host ""
Write-Host "Creating S3 data source for Knowledge Base..." -ForegroundColor Yellow

$DataSourceName = "cc-s3-datasource-$Environment"

# Check if data source already exists
$ExistingDataSources = aws bedrock-agent list-data-sources `
  --knowledge-base-id $KnowledgeBaseId `
  --region $AwsRegion `
  --profile $AwsProfile `
  --query "dataSourceSummaries[?name=='$DataSourceName'].dataSourceId" `
  --output text 2>$null

if ($ExistingDataSources) {
    Write-Host "Data source already exists: $ExistingDataSources" -ForegroundColor Yellow
    $DataSourceId = $ExistingDataSources
} else {
    # Create data source configuration
    $DataSourceConfig = @{
        name = $DataSourceName
        knowledgeBaseId = $KnowledgeBaseId
        dataSourceConfiguration = @{
            type = "S3"
            s3Configuration = @{
                bucketArn = "arn:aws:s3:::$KbBucketName"
                inclusionPrefixes = @()
            }
        }
        vectorIngestionConfiguration = @{
            chunkingConfiguration = @{
                chunkingStrategy = "FIXED_SIZE"
                fixedSizeChunkingConfiguration = @{
                    maxTokens = 300
                    overlapPercentage = 20
                }
            }
        }
    } | ConvertTo-Json -Depth 10

    # Save to temp file
    $TempFile = [System.IO.Path]::GetTempFileName()
    $DataSourceConfig | Out-File -FilePath $TempFile -Encoding utf8

    # Create data source
    $CreateResult = aws bedrock-agent create-data-source `
      --cli-input-json "file://$TempFile" `
      --region $AwsRegion `
      --profile $AwsProfile 2>&1

    Remove-Item $TempFile

    if ($LASTEXITCODE -eq 0) {
        $DataSourceId = ($CreateResult | ConvertFrom-Json).dataSource.dataSourceId
        Write-Host "✓ Data source created: $DataSourceId" -ForegroundColor Green
    } else {
        Write-Host "Warning: Could not create data source automatically" -ForegroundColor Yellow
        Write-Host "You may need to create it manually in the AWS Console"
        $DataSourceId = "manual-setup-required"
    }
}

# Summary
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Bedrock Setup Complete!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Configuration Summary:"
Write-Host "  Knowledge Base ID: $KnowledgeBaseId"
Write-Host "  Data Source ID: $DataSourceId"
Write-Host "  Guardrail ID: $GuardrailId"
Write-Host "  Guardrail Version: $GuardrailVersion"
Write-Host "  S3 Bucket: $KbBucketName"
Write-Host ""
Write-Host "Next Steps:"
Write-Host "1. Upload sample documents to S3 bucket:"
Write-Host "   aws s3 cp docs/ s3://$KbBucketName/ --recursive"
Write-Host ""
Write-Host "2. Sync Knowledge Base (trigger ingestion):"
Write-Host "   aws bedrock-agent start-ingestion-job \"
Write-Host "     --knowledge-base-id $KnowledgeBaseId \"
Write-Host "     --data-source-id $DataSourceId \"
Write-Host "     --region $AwsRegion"
Write-Host ""
Write-Host "3. Test Knowledge Base query:"
Write-Host "   aws bedrock-agent-runtime retrieve \"
Write-Host "     --knowledge-base-id $KnowledgeBaseId \"
Write-Host "     --retrieval-query text='How do I contribute?' \"
Write-Host "     --region $AwsRegion"
Write-Host ""
Write-Host "4. Continue with Lambda function deployment (Task 4)"
Write-Host ""

# Save configuration to file for later use
$ConfigFile = "infrastructure/.bedrock-config-$Environment.json"
$Config = @{
    knowledgeBaseId = $KnowledgeBaseId
    dataSourceId = $DataSourceId
    guardrailId = $GuardrailId
    guardrailVersion = $GuardrailVersion
    kbBucketName = $KbBucketName
    vectorCollectionEndpoint = $VectorCollectionEndpoint
    region = $AwsRegion
    environment = $Environment
} | ConvertTo-Json

$Config | Out-File -FilePath $ConfigFile -Encoding utf8
Write-Host "Configuration saved to: $ConfigFile" -ForegroundColor Green
