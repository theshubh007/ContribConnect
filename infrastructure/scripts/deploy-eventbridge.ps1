# Deploy EventBridge Schedule for Data Ingestion
param(
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1",
    [string]$AwsProfile = "default",
    [string]$ScheduleExpression = "rate(6 hours)"
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Deploy EventBridge Schedule" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Environment: $Environment"
Write-Host "Region: $AwsRegion"
Write-Host "Schedule: $ScheduleExpression"
Write-Host ""

$StackName = "cc-eventbridge-$Environment"
$TemplateFile = "infrastructure/cloudformation/eventbridge-schedule.yaml"

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
        --parameters `
            ParameterKey=Environment,ParameterValue=$Environment `
            ParameterKey=ScheduleExpression,ParameterValue="$ScheduleExpression" `
        --capabilities CAPABILITY_NAMED_IAM `
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
        --parameters `
            ParameterKey=Environment,ParameterValue=$Environment `
            ParameterKey=ScheduleExpression,ParameterValue="$ScheduleExpression" `
        --capabilities CAPABILITY_NAMED_IAM `
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
Write-Host "Schedule Details:"
Write-Host "  Expression: $ScheduleExpression"
Write-Host "  Target: cc-ingest-$Environment Lambda"
Write-Host ""
Write-Host "To disable the schedule:"
Write-Host "  aws scheduler update-schedule --name cc-ingestion-schedule-$Environment --state DISABLED --region $AwsRegion"
Write-Host ""
Write-Host "To enable the schedule:"
Write-Host "  aws scheduler update-schedule --name cc-ingestion-schedule-$Environment --state ENABLED --region $AwsRegion"
