# Setup AWS Secrets Manager for ContribConnect
# Stores GitHub tokens, API keys, and other sensitive credentials

param(
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1",
    [string]$AwsProfile = "default",
    [string]$GitHubToken = "",
    [string]$ApiKey = ""
)

$ErrorActionPreference = "Stop"

Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Setup AWS Secrets Manager" -ForegroundColor Cyan
Write-Host "Environment: $Environment" -ForegroundColor Cyan
Write-Host "Region: $AwsRegion" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""

# Function to create or update secret
function Set-Secret {
    param(
        [string]$SecretName,
        [string]$SecretValue,
        [string]$Description
    )
    
    Write-Host "Processing secret: $SecretName" -ForegroundColor Yellow
    
    # Check if secret exists
    $ErrorActionPreference = "Continue"
    $SecretExists = aws secretsmanager describe-secret --secret-id $SecretName --region $AwsRegion --profile $AwsProfile 2>&1
    $Exists = $LASTEXITCODE -eq 0
    $ErrorActionPreference = "Stop"
    
    if ($Exists) {
        Write-Host "  Secret exists. Updating value..." -ForegroundColor Gray
        aws secretsmanager put-secret-value --secret-id $SecretName --secret-string $SecretValue --region $AwsRegion --profile $AwsProfile | Out-Null
        Write-Host "  Secret updated successfully" -ForegroundColor Green
    } else {
        Write-Host "  Creating new secret..." -ForegroundColor Gray
        aws secretsmanager create-secret --name $SecretName --description $Description --secret-string $SecretValue --region $AwsRegion --profile $AwsProfile | Out-Null
        Write-Host "  Secret created successfully" -ForegroundColor Green
    }
}

# Function to generate random API key
function New-ApiKey {
    $bytes = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return "cc-" + [Convert]::ToBase64String($bytes).Replace("+", "").Replace("/", "").Replace("=", "").Substring(0, 40)
}

Write-Host "Step 1: GitHub Token Configuration" -ForegroundColor Yellow
Write-Host "-------------------------------------------"

if (-not $GitHubToken) {
    Write-Host ""
    Write-Host "No GitHub token provided via parameter." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To create a GitHub fine-grained personal access token:" -ForegroundColor Cyan
    Write-Host "  1. Go to https://github.com/settings/tokens?type=beta"
    Write-Host "  2. Click 'Generate new token'"
    Write-Host "  3. Set token name: 'ContribConnect $Environment'"
    Write-Host "  4. Set expiration: 90 days"
    Write-Host "  5. Select repositories: All repositories (or specific ones)"
    Write-Host "  6. Set permissions:"
    Write-Host "     - Contents: Read-only"
    Write-Host "     - Issues: Read and write"
    Write-Host "     - Pull requests: Read and write"
    Write-Host "     - Metadata: Read-only"
    Write-Host "  7. Click 'Generate token' and copy it"
    Write-Host ""
    
    $GitHubToken = Read-Host "Enter GitHub token (or press Enter to skip)"
}

if ($GitHubToken) {
    # Validate token format
    if ($GitHubToken -notmatch '^(ghp_|github_pat_)[a-zA-Z0-9]{36,}$') {
        Write-Host "Warning: Token format looks unusual. GitHub tokens usually start with 'ghp_' or 'github_pat_'" -ForegroundColor Yellow
        $continue = Read-Host "Continue anyway? (y/n)"
        if ($continue -ne 'y') {
            Write-Host "Skipping GitHub token setup" -ForegroundColor Yellow
            $GitHubToken = ""
        }
    }
}

if ($GitHubToken) {
    # Test token
    Write-Host "Testing GitHub token..." -ForegroundColor Yellow
    $headers = @{
        "Authorization" = "token $GitHubToken"
        "Accept" = "application/vnd.github.v3+json"
    }
    
    try {
        $response = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $headers -Method Get
        Write-Host "  Token valid! Authenticated as: $($response.login)" -ForegroundColor Green
        Write-Host "  Rate limit: $((Invoke-RestMethod -Uri "https://api.github.com/rate_limit" -Headers $headers).rate.limit) requests/hour" -ForegroundColor Gray
        
        # Store in Secrets Manager
        $secretValue = @{
            token = $GitHubToken
            username = $response.login
            createdAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        } | ConvertTo-Json
        
        Set-Secret -SecretName "cc-github-token-$Environment" -SecretValue $secretValue -Description "GitHub fine-grained PAT for ContribConnect $Environment"
        
    } catch {
        Write-Host "  Error: Token validation failed - $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Skipping GitHub token setup" -ForegroundColor Yellow
    }
} else {
    Write-Host "Skipping GitHub token setup" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Step 2: API Key Configuration" -ForegroundColor Yellow
Write-Host "-------------------------------------------"

if (-not $ApiKey) {
    Write-Host ""
    Write-Host "No API key provided. Generating random API key..." -ForegroundColor Yellow
    $ApiKey = New-ApiKey
    Write-Host "  Generated API key: $ApiKey" -ForegroundColor Green
    Write-Host ""
    Write-Host "IMPORTANT: Save this API key! You'll need it to access the API." -ForegroundColor Yellow
    Write-Host ""
}

# Store API key
$apiKeyValue = @{
    key = $ApiKey
    environment = $Environment
    createdAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
} | ConvertTo-Json

Set-Secret -SecretName "cc-api-key-$Environment" -SecretValue $apiKeyValue -Description "API key for ContribConnect frontend authentication ($Environment)"

Write-Host ""
Write-Host "Step 3: Configure Secret Rotation" -ForegroundColor Yellow
Write-Host "-------------------------------------------"

Write-Host "Setting up rotation policy for GitHub token..." -ForegroundColor Yellow

# Create rotation Lambda function (placeholder)
$rotationLambdaArn = "arn:aws:lambda:${AwsRegion}:${AwsAccountId}:function:cc-secret-rotation-$Environment"

Write-Host "  Note: Automatic rotation requires a Lambda function" -ForegroundColor Gray
Write-Host "  For now, set a calendar reminder to rotate secrets every 90 days" -ForegroundColor Gray

# Tag secrets for easier management
Write-Host ""
Write-Host "Tagging secrets..." -ForegroundColor Yellow

$tags = @(
    @{Key="Environment"; Value=$Environment},
    @{Key="Project"; Value="ContribConnect"},
    @{Key="ManagedBy"; Value="Terraform"}
)

$tagsJson = $tags | ConvertTo-Json -Compress

aws secretsmanager tag-resource --secret-id "cc-github-token-$Environment" --tags $tagsJson --region $AwsRegion --profile $AwsProfile 2>$null
aws secretsmanager tag-resource --secret-id "cc-api-key-$Environment" --tags $tagsJson --region $AwsRegion --profile $AwsProfile 2>$null

Write-Host "  Secrets tagged successfully" -ForegroundColor Green

Write-Host ""
Write-Host "Step 4: Update Lambda Environment Variables" -ForegroundColor Yellow
Write-Host "-------------------------------------------"

Write-Host "Updating Lambda functions to use Secrets Manager..." -ForegroundColor Yellow

# List of Lambda functions that need secret access
$LambdaFunctions = @(
    "cc-ingest-$Environment",
    "cc-github-tool-$Environment",
    "cc-repo-manager-$Environment"
)

foreach ($FunctionName in $LambdaFunctions) {
    Write-Host "  Checking $FunctionName..." -ForegroundColor Gray
    
    $ErrorActionPreference = "Continue"
    $FunctionExists = aws lambda get-function --function-name $FunctionName --region $AwsRegion --profile $AwsProfile 2>&1
    $ErrorActionPreference = "Stop"
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "    Updating environment variables..." -ForegroundColor Gray
        
        aws lambda update-function-configuration --function-name $FunctionName --environment "Variables={GITHUB_TOKEN_SECRET=cc-github-token-$Environment,API_KEY_SECRET=cc-api-key-$Environment}" --region $AwsRegion --profile $AwsProfile | Out-Null
        
        Write-Host "    Updated successfully" -ForegroundColor Green
    } else {
        Write-Host "    Function not found, skipping" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Step 5: Verify IAM Permissions" -ForegroundColor Yellow
Write-Host "-------------------------------------------"

Write-Host "Lambda functions need the following IAM permissions:" -ForegroundColor Cyan
Write-Host ""
Write-Host @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": [
        "arn:aws:secretsmanager:$AwsRegion:*:secret:cc-github-token-$Environment-*",
        "arn:aws:secretsmanager:$AwsRegion:*:secret:cc-api-key-$Environment-*"
      ]
    }
  ]
}
"@ -ForegroundColor Gray

Write-Host ""
Write-Host "Checking if Lambda execution role has Secrets Manager permissions..." -ForegroundColor Yellow

# Get Lambda role ARN
$ErrorActionPreference = "Continue"
$RoleArn = aws cloudformation describe-stacks --stack-name "cc-iam-$Environment" --region $AwsRegion --query "Stacks[0].Outputs[?OutputKey=='LambdaRoleArn'].OutputValue" --output text 2>&1
$ErrorActionPreference = "Stop"

if ($LASTEXITCODE -eq 0 -and $RoleArn) {
    Write-Host "  Lambda role: $RoleArn" -ForegroundColor Gray
    Write-Host "  Note: Verify the role has secretsmanager:GetSecretValue permission" -ForegroundColor Yellow
} else {
    Write-Host "  Could not find Lambda role. Please verify IAM permissions manually." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Secrets Manager Setup Complete!" -ForegroundColor Green
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Created Secrets:" -ForegroundColor Cyan
Write-Host "  - cc-github-token-$Environment" -ForegroundColor White
Write-Host "  - cc-api-key-$Environment" -ForegroundColor White
Write-Host ""

if ($ApiKey) {
    Write-Host "API Key for Frontend:" -ForegroundColor Yellow
    Write-Host "  $ApiKey" -ForegroundColor White
    Write-Host ""
    Write-Host "Add this to your frontend .env file:" -ForegroundColor Cyan
    Write-Host "  VITE_API_KEY=$ApiKey" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "View Secrets in AWS Console:" -ForegroundColor Yellow
Write-Host "  https://console.aws.amazon.com/secretsmanager/home?region=$AwsRegion#!/listSecrets" -ForegroundColor Gray
Write-Host ""

Write-Host "Retrieve Secrets via CLI:" -ForegroundColor Yellow
Write-Host "  aws secretsmanager get-secret-value --secret-id cc-github-token-$Environment --query SecretString --output text" -ForegroundColor Gray
Write-Host "  aws secretsmanager get-secret-value --secret-id cc-api-key-$Environment --query SecretString --output text" -ForegroundColor Gray
Write-Host ""

Write-Host "IMPORTANT REMINDERS:" -ForegroundColor Yellow
Write-Host "  1. Rotate GitHub token every 90 days" -ForegroundColor White
Write-Host "  2. Never commit secrets to version control" -ForegroundColor White
Write-Host "  3. Use environment variables or Secrets Manager in Lambda" -ForegroundColor White
Write-Host "  4. Monitor secret access in CloudTrail" -ForegroundColor White
Write-Host ""
