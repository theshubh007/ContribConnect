# Deploy API Gateway
param(
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1",
    [string]$AwsProfile = "default"
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Deploy API Gateway" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Environment: $Environment"
Write-Host "Region: $AwsRegion"
Write-Host ""

$StackName = "cc-api-gateway-$Environment"
$TemplateFile = "infrastructure/cloudformation/api-gateway.yaml"

# Check if stack exists
Write-Host "Checking if stack exists..."
$ErrorActionPreference = "Continue"
$StackExists = aws cloudformation describe-stacks --stack-name $StackName --region $AwsRegion --profile $AwsProfile 2>&1
$StackFound = $LASTEXITCODE -eq 0
$ErrorActionPreference = "Stop"

if ($StackFound) {
    Write-Host "Stack exists. Updating..." -ForegroundColor Yellow
    
    aws cloudformation update-stack `
        --stack-name $StackName `
        --template-body file://$TemplateFile `
        --parameters ParameterKey=Environment,ParameterValue=$Environment `
        --region $AwsRegion `
        --profile $AwsProfile
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Waiting for stack update to complete..."
        aws cloudformation wait stack-update-complete --stack-name $StackName --region $AwsRegion --profile $AwsProfile
        Write-Host "Stack updated successfully!" -ForegroundColor Green
    } else {
        Write-Host "No updates to perform or update failed" -ForegroundColor Yellow
    }
} else {
    Write-Host "Stack does not exist. Creating..." -ForegroundColor Yellow
    
    aws cloudformation create-stack `
        --stack-name $StackName `
        --template-body file://$TemplateFile `
        --parameters ParameterKey=Environment,ParameterValue=$Environment `
        --region $AwsRegion `
        --profile $AwsProfile
    
    Write-Host "Waiting for stack creation to complete..."
    aws cloudformation wait stack-create-complete --stack-name $StackName --region $AwsRegion --profile $AwsProfile
    Write-Host "Stack created successfully!" -ForegroundColor Green
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Get outputs
Write-Host "Stack Outputs:"
aws cloudformation describe-stacks --stack-name $StackName --region $AwsRegion --profile $AwsProfile --query "Stacks[0].Outputs" --output table

Write-Host ""
Write-Host "Test the API:"
$ApiUrl = aws cloudformation describe-stacks --stack-name $StackName --region $AwsRegion --profile $AwsProfile --query "Stacks[0].Outputs[?OutputKey=='AgentChatUrl'].OutputValue" --output text
Write-Host "  Endpoint: $ApiUrl"
Write-Host ""
Write-Host "  curl -X POST $ApiUrl \"
Write-Host "    -H 'Content-Type: application/json' \"
Write-Host "    -d '{\"message\":\"Find expert reviewers for CLA Signed issues in facebook/react\",\"sessionId\":\"test-456\"}'"
