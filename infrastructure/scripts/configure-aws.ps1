# AWS CLI Configuration Helper
# This script helps you configure AWS CLI with your credentials

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "AWS CLI Configuration" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Check if AWS CLI is available
try {
    $version = aws --version 2>&1
    Write-Host "✓ AWS CLI detected: $version" -ForegroundColor Green
} catch {
    Write-Host "✗ AWS CLI not found. Please install it first." -ForegroundColor Red
    Write-Host "Run: pip3 install awscli --upgrade --user" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "You need AWS credentials to proceed." -ForegroundColor Yellow
Write-Host ""
Write-Host "Options:" -ForegroundColor Cyan
Write-Host "1. Use existing AWS IAM user credentials (Access Key ID + Secret Access Key)"
Write-Host "2. Create new IAM user in AWS Console"
Write-Host "3. Use AWS SSO (if your organization uses it)"
Write-Host ""

$choice = Read-Host "Select option (1/2/3)"

switch ($choice) {
    "1" {
        Write-Host ""
        Write-Host "Configuring AWS CLI with IAM user credentials..." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "You'll need:" -ForegroundColor Cyan
        Write-Host "  - AWS Access Key ID"
        Write-Host "  - AWS Secret Access Key"
        Write-Host "  - Default region (recommended: us-east-1)"
        Write-Host "  - Default output format (recommended: json)"
        Write-Host ""
        
        aws configure
        
        Write-Host ""
        Write-Host "Testing AWS connection..." -ForegroundColor Yellow
        $identity = aws sts get-caller-identity 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ AWS CLI configured successfully!" -ForegroundColor Green
            Write-Host ""
            Write-Host "Your AWS Identity:" -ForegroundColor Cyan
            Write-Host $identity
            Write-Host ""
            Write-Host "Next steps:" -ForegroundColor Yellow
            Write-Host "1. Deploy infrastructure:"
            Write-Host "   .\infrastructure\scripts\deploy-infrastructure.ps1 -Environment dev"
            Write-Host ""
            Write-Host "2. Configure Bedrock services:"
            Write-Host "   .\infrastructure\scripts\setup-bedrock.ps1 -Environment dev"
        } else {
            Write-Host "✗ Configuration failed. Please check your credentials." -ForegroundColor Red
            Write-Host "Error: $identity" -ForegroundColor Red
        }
    }
    
    "2" {
        Write-Host ""
        Write-Host "Creating IAM User in AWS Console:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Steps:" -ForegroundColor Cyan
        Write-Host "1. Go to: https://console.aws.amazon.com/iam/home#/users"
        Write-Host "2. Click 'Add users'"
        Write-Host "3. Username: contribconnect-dev"
        Write-Host "4. Select 'Access key - Programmatic access'"
        Write-Host "5. Attach policy: AdministratorAccess (for development)"
        Write-Host "6. Click through and download the .csv file"
        Write-Host "7. Come back here and select option 1"
        Write-Host ""
        Write-Host "Opening AWS IAM Console..." -ForegroundColor Yellow
        Start-Process "https://console.aws.amazon.com/iam/home#/users"
    }
    
    "3" {
        Write-Host ""
        Write-Host "Configuring AWS SSO..." -ForegroundColor Yellow
        Write-Host ""
        aws configure sso
        
        Write-Host ""
        Write-Host "Testing AWS connection..." -ForegroundColor Yellow
        $identity = aws sts get-caller-identity 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ AWS SSO configured successfully!" -ForegroundColor Green
            Write-Host ""
            Write-Host "Your AWS Identity:" -ForegroundColor Cyan
            Write-Host $identity
        } else {
            Write-Host "✗ Configuration failed." -ForegroundColor Red
            Write-Host "Error: $identity" -ForegroundColor Red
        }
    }
    
    default {
        Write-Host "Invalid option selected." -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Configuration Complete!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
