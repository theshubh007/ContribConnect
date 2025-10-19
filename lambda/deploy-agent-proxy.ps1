# Deploy Agent Proxy Lambda Function
param(
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1",
    [string]$AwsProfile = "default"
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Deploy Agent Proxy Lambda" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

# Get AWS Account ID
$AwsAccountId = aws sts get-caller-identity --profile $AwsProfile --query Account --output text

# Get resources from CloudFormation
Write-Host "Retrieving resource names..."
$SessionsTable = aws cloudformation describe-stacks --stack-name "cc-dynamodb-$Environment" --region $AwsRegion --query "Stacks[0].Outputs[?OutputKey=='AgentSessionsTableName'].OutputValue" --output text
$RoleArn = aws cloudformation describe-stacks --stack-name "cc-iam-$Environment" --region $AwsRegion --query "Stacks[0].Outputs[?OutputKey=='AgentProxyLambdaRoleArn'].OutputValue" --output text

Write-Host "Resources:"
Write-Host "  Sessions Table: $SessionsTable"
Write-Host "  Role ARN: $RoleArn"

# Create deployment package
Write-Host ""
Write-Host "Creating deployment package..." -ForegroundColor Yellow

$TempDir = "lambda/agent-proxy/.package"
if (Test-Path $TempDir) {
    Remove-Item $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

# Install dependencies
Write-Host "Installing dependencies..."
pip install -r lambda/agent-proxy/requirements.txt -t $TempDir --quiet

# Copy Lambda function
Copy-Item lambda/agent-proxy/lambda_function.py $TempDir/

# Create ZIP
$ZipFile = "lambda/agent-proxy/function.zip"
if (Test-Path $ZipFile) {
    Remove-Item $ZipFile -Force
}

Write-Host "Creating ZIP package..."
Compress-Archive -Path "$TempDir/*" -DestinationPath $ZipFile -Force

# Clean up temp directory
Remove-Item $TempDir -Recurse -Force

Write-Host "Package created: $ZipFile" -ForegroundColor Green

# Create or update Lambda function
$FunctionName = "cc-agent-proxy-$Environment"

Write-Host ""
Write-Host "Checking if function exists..."
$ErrorActionPreference = "Continue"
$FunctionCheck = aws lambda get-function --function-name $FunctionName --region $AwsRegion --profile $AwsProfile 2>&1
$FunctionExists = $LASTEXITCODE -eq 0
$ErrorActionPreference = "Stop"

if ($FunctionExists) {
    Write-Host "Updating existing function..." -ForegroundColor Yellow
    aws lambda update-function-code --function-name $FunctionName --zip-file "fileb://$ZipFile" --region $AwsRegion --profile $AwsProfile
    
    Start-Sleep -Seconds 2
    
    # Update configuration
    aws lambda update-function-configuration --function-name $FunctionName --environment "Variables={SESSIONS_TABLE=$SessionsTable,GRAPH_TOOL_FUNCTION=cc-graph-tool-$Environment,GITHUB_TOOL_FUNCTION=cc-github-tool-$Environment,MODEL_ID=us.amazon.nova-pro-v1:0}" --timeout 60 --memory-size 512 --region $AwsRegion --profile $AwsProfile
    
    Write-Host "Function updated successfully" -ForegroundColor Green
} else {
    Write-Host "Creating new function..." -ForegroundColor Yellow
    aws lambda create-function --function-name $FunctionName --runtime python3.13 --role $RoleArn --handler lambda_function.lambda_handler --zip-file "fileb://$ZipFile" --environment "Variables={SESSIONS_TABLE=$SessionsTable,GRAPH_TOOL_FUNCTION=cc-graph-tool-$Environment,GITHUB_TOOL_FUNCTION=cc-github-tool-$Environment,MODEL_ID=us.amazon.nova-pro-v1:0}" --timeout 60 --memory-size 512 --region $AwsRegion --profile $AwsProfile
    
    Write-Host "Function created successfully" -ForegroundColor Green
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Function Name: $FunctionName"
Write-Host ""
Write-Host "Test the agent:"
Write-Host '  $payload = ''{"message":"Find me expert reviewers for bug issues in facebook/react","sessionId":"test-123"}'''
Write-Host "  `$payload | Out-File -FilePath test-agent-payload.json -Encoding ascii -NoNewline"
Write-Host "  aws lambda invoke --function-name $FunctionName --region $AwsRegion --payload file://test-agent-payload.json response.json"
Write-Host "  Get-Content response.json"
