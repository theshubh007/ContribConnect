# ContribConnect Infrastructure Verification Script (Simplified)
param(
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1",
    [string]$AwsProfile = "default"
)

$ErrorActionPreference = "Continue"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Infrastructure Verification" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Environment: $Environment"
Write-Host "Region: $AwsRegion"
Write-Host ""

$AllPass = $true

# Check CloudFormation Stacks
Write-Host "CloudFormation Stacks:" -ForegroundColor Yellow
Write-Host "-" * 60

$stacks = @("cc-dynamodb-$Environment", "cc-s3-$Environment", "cc-iam-$Environment")
foreach ($stack in $stacks) {
    Write-Host "Checking $stack..." -NoNewline
    $status = aws cloudformation describe-stacks --stack-name $stack --region $AwsRegion --profile $AwsProfile --query "Stacks[0].StackStatus" --output text 2>$null
    
    if ($status -eq "CREATE_COMPLETE" -or $status -eq "UPDATE_COMPLETE") {
        Write-Host " OK" -ForegroundColor Green
    }
    else {
        Write-Host " FAILED" -ForegroundColor Red
        $AllPass = $false
    }
}

Write-Host ""

# Check DynamoDB Tables
Write-Host "DynamoDB Tables:" -ForegroundColor Yellow
Write-Host "-" * 60

$tables = @("cc-nodes-$Environment", "cc-edges-$Environment", "cc-repos-$Environment", "cc-agent-sessions-$Environment")
foreach ($table in $tables) {
    Write-Host "Checking $table..." -NoNewline
    $status = aws dynamodb describe-table --table-name $table --region $AwsRegion --profile $AwsProfile --query "Table.TableStatus" --output text 2>$null
    
    if ($status -eq "ACTIVE") {
        Write-Host " OK" -ForegroundColor Green
    }
    else {
        Write-Host " FAILED" -ForegroundColor Red
        $AllPass = $false
    }
}

Write-Host ""

# Check S3 Buckets
Write-Host "S3 Buckets:" -ForegroundColor Yellow
Write-Host "-" * 60

$accountId = aws sts get-caller-identity --profile $AwsProfile --query Account --output text
$buckets = @("cc-raw-$Environment-$accountId", "cc-kb-docs-$Environment-$accountId", "cc-web-$Environment-$accountId")

foreach ($bucket in $buckets) {
    Write-Host "Checking $bucket..." -NoNewline
    aws s3api head-bucket --bucket $bucket --profile $AwsProfile 2>$null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host " OK" -ForegroundColor Green
    }
    else {
        Write-Host " FAILED" -ForegroundColor Red
        $AllPass = $false
    }
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
    Write-Host "Checking $role..." -NoNewline
    $roleArn = aws iam get-role --role-name $role --profile $AwsProfile --query "Role.Arn" --output text 2>$null
    
    if ($roleArn) {
        Write-Host " OK" -ForegroundColor Green
    }
    else {
        Write-Host " FAILED" -ForegroundColor Red
        $AllPass = $false
    }
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan

if ($AllPass) {
    Write-Host "All checks passed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next: Enable Bedrock model access, then run:"
    Write-Host ".\infrastructure\scripts\setup-bedrock.ps1 -Environment $Environment -AwsRegion $AwsRegion"
}
else {
    Write-Host "Some checks failed!" -ForegroundColor Red
}
