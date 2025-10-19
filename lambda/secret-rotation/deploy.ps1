# Deploy Secret Rotation Lambda Function

param(
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1",
    [string]$AwsProfile = "default",
    [string]$NotificationEmail = ""
)

$ErrorActionPreference = "Stop"

Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Deploy Secret Rotation Lambda" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan

# Get AWS Account ID
$AwsAccountId = aws sts get-caller-identity --profile $AwsProfile --query Account --output text

# Create deployment package
Write-Host ""
Write-Host "Creating deployment package..." -ForegroundColor Yellow
$TempDir = "lambda/secret-rotation/.package"
if (Test-Path $TempDir) {
    Remove-Item $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

# Install dependencies
Write-Host "Installing dependencies..."
pip install boto3 -t $TempDir --quiet

# Copy Lambda function
Copy-Item lambda/secret-rotation/lambda_function.py $TempDir/

# Create ZIP
$ZipFile = "lambda/secret-rotation/function.zip"
if (Test-Path $ZipFile) {
    Remove-Item $ZipFile -Force
}
Write-Host "Creating ZIP package..."
Compress-Archive -Path "$TempDir/*" -DestinationPath $ZipFile -Force

# Clean up temp directory
Remove-Item $TempDir -Recurse -Force

Write-Host "Package created: $ZipFile" -ForegroundColor Green

# Create IAM role for rotation Lambda
Write-Host ""
Write-Host "Creating IAM role for rotation Lambda..." -ForegroundColor Yellow

$RoleName = "cc-secret-rotation-role-$Environment"
$TrustPolicy = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
"@

$ErrorActionPreference = "Continue"
$RoleExists = aws iam get-role --role-name $RoleName --profile $AwsProfile 2>&1
$ErrorActionPreference = "Stop"

if ($LASTEXITCODE -ne 0) {
    Write-Host "  Creating role..." -ForegroundColor Gray
    $TrustPolicy | Out-File -FilePath trust-policy.json -Encoding utf8
    aws iam create-role --role-name $RoleName --assume-role-policy-document file://trust-policy.json --profile $AwsProfile | Out-Null
    Remove-Item trust-policy.json
    
    # Attach policies
    aws iam attach-role-policy --role-name $RoleName --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" --profile $AwsProfile
    
    # Create inline policy for Secrets Manager
    $SecretPolicy = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:PutSecretValue",
        "secretsmanager:UpdateSecretVersionStage"
      ],
      "Resource": "arn:aws:secretsmanager:$AwsRegion:$AwsAccountId:secret:cc-*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ses:SendEmail"
      ],
      "Resource": "*"
    }
  ]
}
"@
    $SecretPolicy | Out-File -FilePath secret-policy.json -Encoding utf8
    aws iam put-role-policy --role-name $RoleName --policy-name "SecretsManagerRotation" --policy-document file://secret-policy.json --profile $AwsProfile
    Remove-Item secret-policy.json
    
    Write-Host "  Role created successfully" -ForegroundColor Green
    
    # Wait for role to propagate
    Write-Host "  Waiting for role to propagate..." -ForegroundColor Gray
    Start-Sleep -Seconds 10
} else {
    Write-Host "  Role already exists" -ForegroundColor Gray
}

$RoleArn = "arn:aws:iam::${AwsAccountId}:role/$RoleName"

# Create or update Lambda function
$FunctionName = "cc-secret-rotation-$Environment"
Write-Host ""
Write-Host "Checking if function exists..."
$ErrorActionPreference = "Continue"
$FunctionCheck = aws lambda get-function --function-name $FunctionName --region $AwsRegion --profile $AwsProfile 2>&1
$FunctionExists = $LASTEXITCODE -eq 0
$ErrorActionPreference = "Stop"

$EnvVars = "Variables={ENVIRONMENT=$Environment"
if ($NotificationEmail) {
    $EnvVars += ",NOTIFICATION_EMAIL=$NotificationEmail"
}
$EnvVars += "}"

if ($FunctionExists) {
    Write-Host "Updating existing function..." -ForegroundColor Yellow
    aws lambda update-function-code --function-name $FunctionName --zip-file "fileb://$ZipFile" --region $AwsRegion --profile $AwsProfile | Out-Null
    Start-Sleep -Seconds 2
    
    # Update configuration
    aws lambda update-function-configuration --function-name $FunctionName --environment $EnvVars --timeout 60 --memory-size 256 --region $AwsRegion --profile $AwsProfile | Out-Null
    
    Write-Host "Function updated successfully" -ForegroundColor Green
} else {
    Write-Host "Creating new function..." -ForegroundColor Yellow
    aws lambda create-function --function-name $FunctionName --runtime python3.13 --role $RoleArn --handler lambda_function.lambda_handler --zip-file "fileb://$ZipFile" --environment $EnvVars --timeout 60 --memory-size 256 --region $AwsRegion --profile $AwsProfile | Out-Null
    
    Write-Host "Function created successfully" -ForegroundColor Green
}

# Grant Secrets Manager permission to invoke Lambda
Write-Host ""
Write-Host "Granting Secrets Manager permission to invoke Lambda..." -ForegroundColor Yellow

$ErrorActionPreference = "Continue"
aws lambda add-permission --function-name $FunctionName --statement-id "SecretsManagerAccess" --action "lambda:InvokeFunction" --principal "secretsmanager.amazonaws.com" --region $AwsRegion --profile $AwsProfile 2>&1 | Out-Null
$ErrorActionPreference = "Stop"

Write-Host "Permission granted" -ForegroundColor Green

Write-Host ""
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Function Name: $FunctionName"
Write-Host "Function ARN: arn:aws:lambda:$AwsRegion:${AwsAccountId}:function:$FunctionName"
Write-Host ""
Write-Host "To enable automatic rotation for a secret:"
Write-Host ""
Write-Host "  aws secretsmanager rotate-secret \"
Write-Host "    --secret-id cc-api-key-$Environment \"
Write-Host "    --rotation-lambda-arn arn:aws:lambda:$AwsRegion:${AwsAccountId}:function:$FunctionName \"
Write-Host "    --rotation-rules AutomaticallyAfterDays=90"
Write-Host ""
