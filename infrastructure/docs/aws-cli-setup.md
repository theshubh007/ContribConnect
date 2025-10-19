# AWS CLI Setup Guide for Windows

This guide will help you install and configure AWS CLI on Windows.

## Step 1: Install AWS CLI

### Option A: Using MSI Installer (Recommended)

1. Download the AWS CLI MSI installer for Windows:
   - 64-bit: https://awscli.amazonaws.com/AWSCLIV2.msi
   - Or visit: https://aws.amazon.com/cli/

2. Run the downloaded MSI installer

3. Follow the installation wizard (use default settings)

4. Restart your PowerShell terminal

5. Verify installation:
   ```powershell
   aws --version
   ```
   
   Expected output: `aws-cli/2.x.x Python/3.x.x Windows/...`

### Option B: Using winget (Windows Package Manager)

If you have winget installed:

```powershell
winget install -e --id Amazon.AWSCLI
```

### Option C: Using Chocolatey

If you have Chocolatey installed:

```powershell
choco install awscli
```

## Step 2: Verify Installation

After installation, close and reopen PowerShell, then run:

```powershell
aws --version
```

If you see the version information, AWS CLI is installed correctly.

## Step 3: Configure AWS Credentials

You need AWS credentials to interact with AWS services. You have two options:

### Option A: AWS IAM User Credentials (Recommended for Development)

1. **Create IAM User** (if you don't have one):
   - Go to [AWS IAM Console](https://console.aws.amazon.com/iam/)
   - Click **Users** → **Add users**
   - Username: `contribconnect-dev`
   - Select **Access key - Programmatic access**
   - Attach policies:
     - `AdministratorAccess` (for development)
     - Or create custom policy with required permissions
   - Click through and **Download .csv** with credentials

2. **Configure AWS CLI**:
   ```powershell
   aws configure
   ```
   
   Enter the following when prompted:
   ```
   AWS Access Key ID [None]: YOUR_ACCESS_KEY_ID
   AWS Secret Access Key [None]: YOUR_SECRET_ACCESS_KEY
   Default region name [None]: us-east-1
   Default output format [None]: json
   ```

3. **Verify Configuration**:
   ```powershell
   aws sts get-caller-identity
   ```
   
   Expected output:
   ```json
   {
       "UserId": "AIDAXXXXXXXXXXXXXXXXX",
       "Account": "123456789012",
       "Arn": "arn:aws:iam::123456789012:user/contribconnect-dev"
   }
   ```

### Option B: AWS SSO (Single Sign-On)

If your organization uses AWS SSO:

```powershell
aws configure sso
```

Follow the prompts to authenticate via browser.

## Step 4: Test AWS Connection

Run a simple AWS command to verify connectivity:

```powershell
# List S3 buckets
aws s3 ls

# List EC2 regions
aws ec2 describe-regions --query "Regions[].RegionName" --output table

# Check your identity
aws sts get-caller-identity
```

## Step 5: Configure Named Profiles (Optional)

If you work with multiple AWS accounts, use named profiles:

```powershell
# Configure a profile
aws configure --profile contribconnect-dev

# Use the profile
aws s3 ls --profile contribconnect-dev

# Set default profile (optional)
$env:AWS_PROFILE = "contribconnect-dev"
```

## Required IAM Permissions

For ContribConnect deployment, your IAM user/role needs these permissions:

### Core Services
- **CloudFormation**: Full access (create/update/delete stacks)
- **DynamoDB**: Full access (create tables, read/write)
- **S3**: Full access (create buckets, upload/download)
- **Lambda**: Full access (create functions, update code)
- **IAM**: Full access (create roles and policies)

### AI/ML Services
- **Bedrock**: Full access (Knowledge Bases, Guardrails, model invocation)
- **Q Business**: Full access (optional, for Q Business setup)

### Networking & API
- **API Gateway**: Full access (create APIs, routes)
- **CloudFront**: Full access (create distributions)
- **EventBridge**: Full access (create rules)

### Security & Monitoring
- **Secrets Manager**: Full access (store/retrieve secrets)
- **CloudWatch**: Full access (logs, metrics, alarms)
- **X-Ray**: Full access (tracing)

### Minimal Policy Example

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudformation:*",
        "dynamodb:*",
        "s3:*",
        "lambda:*",
        "iam:*",
        "bedrock:*",
        "apigateway:*",
        "cloudfront:*",
        "events:*",
        "secretsmanager:*",
        "logs:*",
        "xray:*"
      ],
      "Resource": "*"
    }
  ]
}
```

## Troubleshooting

### AWS CLI Not Found After Installation

**Issue**: `aws : The term 'aws' is not recognized`

**Solutions**:
1. Restart PowerShell terminal
2. Check if AWS CLI is in PATH:
   ```powershell
   $env:PATH -split ';' | Select-String -Pattern 'AWS'
   ```
3. Manually add to PATH if needed:
   ```powershell
   $env:PATH += ";C:\Program Files\Amazon\AWSCLIV2"
   ```
4. Reinstall AWS CLI using MSI installer

### Invalid Credentials

**Issue**: `Unable to locate credentials`

**Solutions**:
1. Run `aws configure` again
2. Check credentials file:
   ```powershell
   Get-Content ~\.aws\credentials
   Get-Content ~\.aws\config
   ```
3. Verify IAM user has programmatic access enabled

### Access Denied Errors

**Issue**: `AccessDeniedException` or `UnauthorizedOperation`

**Solutions**:
1. Verify IAM user has required permissions
2. Check if MFA is required for your account
3. Ensure you're using the correct AWS region
4. Contact your AWS administrator

### Region Not Set

**Issue**: `You must specify a region`

**Solution**:
```powershell
# Set default region
aws configure set region us-east-1

# Or use environment variable
$env:AWS_DEFAULT_REGION = "us-east-1"

# Or specify in each command
aws s3 ls --region us-east-1
```

## Next Steps

After AWS CLI is configured:

1. **Verify your setup**:
   ```powershell
   .\infrastructure\scripts\verify-infrastructure.ps1 -Environment dev
   ```

2. **Deploy infrastructure**:
   ```powershell
   .\infrastructure\scripts\deploy-infrastructure.ps1 -Environment dev
   ```

3. **Configure Bedrock services**:
   ```powershell
   .\infrastructure\scripts\setup-bedrock.ps1 -Environment dev
   ```

## Additional Resources

- [AWS CLI Documentation](https://docs.aws.amazon.com/cli/)
- [AWS CLI Command Reference](https://awscli.amazonaws.com/v2/documentation/api/latest/index.html)
- [AWS CLI Configuration Guide](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-files.html)
- [IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
