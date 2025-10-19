# ContribConnect Infrastructure Verification Script
# This script verifies that all infrastructure resources are properly deployed

param(
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1",
    [string]$AwsProfile = "default"
)

$ErrorActionPreference = "Continue"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "ContribConnect Infrastructure Verification" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Environment: $Environment"
Write-Host "Region: $AwsRegion"
Write-Host "Profile: $AwsProfile"
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

$AllChecksPass = $true

# Function to check resource existence
function Test-Resource {
    param(
        [string]$ResourceType,
        [string]$ResourceName,
        [scriptblock]$CheckCommand
    )
    
    Write-Host "Checking $ResourceType : $ResourceName..." -NoNewline
    try {
        $result = & $CheckCommand
        if ($result) {
            Write-Host " ✓" -ForegroundColor Green
            return $true
        } else {
            Write-Host " ✗ (Not Found)" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host " ✗ (Error: $($_.Exception.Message))" -ForegroundColor Red
        return $false
    }
}

# Check CloudFormation Stacks
Write-Host "CloudFormation Stacks:" -ForegroundColor Yellow
Write-Host "-" * 60

$stacks = @("cc-dynamodb-$Environment", "cc-s3-$Environment", "cc-iam-$Environment")
foreach ($stack in $stacks) {
    $check = Test-Resource "Stack" $stack {
        $status = aws cloudformation describe-stacks `
            --stack-name $stack `
            --region $AwsRegion `
            --profile $AwsProfile `
            --query "Stacks[0].StackStatus" `
            --output text 2>$null
        return ($status -eq "CREATE_COMPLETE" -or $status -eq "UPDATE_COMPLETE")
    }
    if (-not $check) { $AllChecksPass = $false }
}

Write-Host ""

# Check DynamoDB Tables
Write-Host "DynamoDB Tables:" -ForegroundColor Yellow
Write-Host "-" * 60

$tables = @(
    "cc-nodes-$Environment",
    "cc-edges-$Environment",
    "cc-repos-$Environment",
    "cc-agent-sessions-$Environment"
)

foreach ($table in $tables) {
    $check = Test-Resource "Table" $table {
        $status = aws dynamodb describe-table `
            --table-name $table `
            --region $AwsRegion `
            --profile $AwsProfile `
            --query "Table.TableStatus" `
            --output text 2>$null
        return ($status -eq "ACTIVE")
    }
    if (-not $check) { $AllChecksPass = $false }
}

Write-Host ""

# Check S3 Buckets
Write-Host "S3 Buckets:" -ForegroundColor Yellow
Write-Host "-" * 60

$accountId = aws sts get-caller-identity --profile $AwsProfile --query Account --output text
$buckets = @(
    "cc-raw-$Environment-$accountId",
    "cc-kb-docs-$Environment-$accountId",
    "cc-web-$Environment-$accountId"
)

foreach ($bucket in $buckets) {
    $check = Test-Resource "Bucket" $bucket {
        aws s3api head-bucket --bucket $bucket --profile $AwsProfile 2>$null
        return ($LASTEXITCODE -eq 0)
    }
    if (-not $check) { $AllChecksPass = $false }
}

Write-Host ""

# Check IAM Roles
Write-Host "IAM Roles:" -ForegroundColor Yellow
Write-Host "-" * 60

$roles = @(
    "cc-ingest-lambda-role-$Environment",
    "cc-graph-tool-lambda-role-$Environment",
    "cc-kb-tool-lambda-role-$Environment",
    "cc-qbiz-tool-lambda-role-$Environment",
    "cc-github-tool-lambda-role-$Environment",
    "cc-agent-proxy-lambda-role-$Environment"
)

foreach ($role in $roles) {
    $check = Test-Resource "Role" $role {
        $roleArn = aws iam get-role `
            --role-name $role `
            --profile $AwsProfile `
            --query "Role.Arn" `
            --output text 2>$null
        return ($roleArn -ne $null -and $roleArn -ne "")
    }
    if (-not $check) { $AllChecksPass = $false }
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan

if ($AllChecksPass) {
    Write-Host "All infrastructure checks passed! ✓" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next Steps:"
    Write-Host "1. Initialize sample repositories:"
    Write-Host "   python infrastructure/scripts/init-sample-repos.py $Environment $AwsRegion $AwsProfile"
    Write-Host ""
    Write-Host "2. Configure Bedrock services (Knowledge Base, Guardrails)"
    Write-Host "3. Deploy Lambda functions"
    Write-Host "4. Set up API Gateway"
    Write-Host "5. Deploy frontend application"
    exit 0
} else {
    Write-Host "Some infrastructure checks failed! ✗" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please review the errors above and:"
    Write-Host "1. Check CloudFormation stack events for details"
    Write-Host "2. Verify AWS credentials and permissions"
    Write-Host "3. Re-run the deployment script if needed"
    exit 1
}
