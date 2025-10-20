# Deploy Graph API Gateway
Write-Host "==========================================="
Write-Host "Deploying Graph API Gateway"
Write-Host "==========================================="
Write-Host ""

$STACK_NAME = "cc-graph-api-dev"
$TEMPLATE_FILE = "infrastructure/graph-api-gateway.yaml"
$REGION = "us-east-1"

Write-Host "Step 1: Checking if stack exists..." -ForegroundColor Cyan
$stackExists = aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION 2>$null

if ($stackExists) {
    Write-Host "Stack exists, updating..." -ForegroundColor Yellow
    aws cloudformation update-stack `
        --stack-name $STACK_NAME `
        --template-body file://$TEMPLATE_FILE `
        --parameters ParameterKey=Environment,ParameterValue=dev `
        --capabilities CAPABILITY_IAM `
        --region $REGION

    if ($LASTEXITCODE -ne 0) {
        Write-Host "No updates to perform or update failed" -ForegroundColor Yellow
    } else {
        Write-Host "Waiting for stack update to complete..." -ForegroundColor Cyan
        aws cloudformation wait stack-update-complete --stack-name $STACK_NAME --region $REGION
    }
} else {
    Write-Host "Stack does not exist, creating..." -ForegroundColor Green
    aws cloudformation create-stack `
        --stack-name $STACK_NAME `
        --template-body file://$TEMPLATE_FILE `
        --parameters ParameterKey=Environment,ParameterValue=dev `
        --capabilities CAPABILITY_IAM `
        --region $REGION

    Write-Host "Waiting for stack creation to complete..." -ForegroundColor Cyan
    aws cloudformation wait stack-create-complete --stack-name $STACK_NAME --region $REGION
}

Write-Host ""
Write-Host "Step 2: Getting API URL..." -ForegroundColor Cyan
$apiUrl = aws cloudformation describe-stacks `
    --stack-name $STACK_NAME `
    --query 'Stacks[0].Outputs[?OutputKey==`GraphAPIUrl`].OutputValue' `
    --output text `
    --region $REGION

Write-Host ""
Write-Host "==========================================="
Write-Host "Deployment Complete!"
Write-Host "==========================================="
Write-Host ""
Write-Host "Graph API URL: $apiUrl" -ForegroundColor Green
Write-Host ""
Write-Host "Test the API:"
Write-Host "curl -X POST $apiUrl \\" -ForegroundColor Cyan
Write-Host '  -H "Content-Type: application/json" \' -ForegroundColor Cyan
Write-Host '  -d ''{"action":"get_top_contributors","params":{"repo":"RooCodeInc/Roo-Code","limit":300}}''' -ForegroundColor Cyan
Write-Host ""
Write-Host "Update your frontend to use this URL instead of the agent API"
Write-Host ""
