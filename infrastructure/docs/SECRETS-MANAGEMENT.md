# Secrets Management Guide

Complete guide for managing secrets in ContribConnect using AWS Secrets Manager.

## Overview

ContribConnect uses AWS Secrets Manager to securely store:
- **GitHub Personal Access Tokens (PAT)**: For accessing GitHub API
- **API Keys**: For frontend authentication
- **Other sensitive credentials**: Database passwords, third-party API keys

## Quick Start

### 1. Setup Secrets Manager

Run the setup script to create secrets:

```powershell
.\infrastructure\scripts\setup-secrets.ps1 `
    -Environment dev `
    -GitHubToken "ghp_your_token_here" `
    -ApiKey "cc-your-api-key-here"
```

If you don't provide tokens, the script will:
- Prompt you to enter a GitHub token (or skip)
- Generate a random API key automatically

### 2. Verify Secrets

Check that secrets were created:

```powershell
aws secretsmanager list-secrets --region us-east-1
```

### 3. Update Lambda Functions

The setup script automatically updates Lambda environment variables to reference the secrets.

## Creating GitHub Token

### Fine-Grained Personal Access Token (Recommended)

1. Go to https://github.com/settings/tokens?type=beta
2. Click "Generate new token"
3. Configure token:
   - **Name**: `ContribConnect dev`
   - **Expiration**: 90 days
   - **Repository access**: All repositories (or select specific ones)
   - **Permissions**:
     - Contents: Read-only
     - Issues: Read and write
     - Pull requests: Read and write
     - Metadata: Read-only (automatically included)

4. Click "Generate token"
5. Copy the token (starts with `github_pat_`)

### Classic Personal Access Token (Alternative)

1. Go to https://github.com/settings/tokens
2. Click "Generate new token (classic)"
3. Configure token:
   - **Note**: `ContribConnect dev`
   - **Expiration**: 90 days
   - **Scopes**:
     - `repo` (Full control of private repositories)
     - `read:org` (Read org and team membership)

4. Click "Generate token"
5. Copy the token (starts with `ghp_`)

## Secret Structure

### GitHub Token Secret

```json
{
  "token": "github_pat_xxxxxxxxxxxxx",
  "username": "your-github-username",
  "createdAt": "2025-10-19T12:00:00Z"
}
```

### API Key Secret

```json
{
  "key": "cc-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "environment": "dev",
  "createdAt": "2025-10-19T12:00:00Z"
}
```

## Using Secrets in Lambda Functions

### Method 1: Using the Secrets Utility (Recommended)

```python
from secrets import get_github_token, validate_api_key

def lambda_handler(event, context):
    # Validate API key
    api_key = event.get('headers', {}).get('x-api-key', '')
    if not validate_api_key(api_key, 'dev'):
        return {
            'statusCode': 401,
            'body': json.dumps({'error': 'Unauthorized'})
        }
    
    # Get GitHub token
    github_token = get_github_token('dev')
    
    # Use token
    headers = {'Authorization': f'token {github_token}'}
    response = requests.get('https://api.github.com/user', headers=headers)
    
    return {'statusCode': 200, 'body': json.dumps(response.json())}
```

### Method 2: Direct Boto3 Access

```python
import boto3
import json

secrets_client = boto3.client('secretsmanager')

def get_secret(secret_name):
    response = secrets_client.get_secret_value(SecretId=secret_name)
    return json.loads(response['SecretString'])

def lambda_handler(event, context):
    secret = get_secret('cc-github-token-dev')
    github_token = secret['token']
    
    # Use token...
```

### Method 3: Environment Variables (Not Recommended)

```python
import os

def lambda_handler(event, context):
    # Less secure - token visible in Lambda console
    github_token = os.environ.get('GITHUB_TOKEN')
```

## Secret Rotation

### Automatic Rotation (API Keys)

API keys can be automatically rotated:

```powershell
# Enable automatic rotation every 90 days
aws secretsmanager rotate-secret `
    --secret-id cc-api-key-dev `
    --rotation-lambda-arn arn:aws:lambda:us-east-1:123456789012:function:cc-secret-rotation-dev `
    --rotation-rules AutomaticallyAfterDays=90
```

### Manual Rotation (GitHub Tokens)

GitHub tokens must be manually rotated:

1. **Create new token** on GitHub (see instructions above)
2. **Update secret** in Secrets Manager:

```powershell
# Create new secret value
$newSecret = @{
    token = "github_pat_NEW_TOKEN_HERE"
    username = "your-username"
    createdAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
} | ConvertTo-Json

# Update secret
aws secretsmanager put-secret-value `
    --secret-id cc-github-token-dev `
    --secret-string $newSecret
```

3. **Revoke old token** on GitHub
4. **Test** that Lambda functions still work

### Rotation Schedule

- **GitHub Tokens**: Every 90 days (manual)
- **API Keys**: Every 90 days (can be automated)
- **Other Secrets**: As needed

## IAM Permissions

### Lambda Execution Role

Lambda functions need these permissions:

```json
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
        "arn:aws:secretsmanager:us-east-1:*:secret:cc-github-token-*",
        "arn:aws:secretsmanager:us-east-1:*:secret:cc-api-key-*"
      ]
    }
  ]
}
```

### Rotation Lambda Role

The rotation Lambda needs additional permissions:

```json
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
      "Resource": "arn:aws:secretsmanager:us-east-1:*:secret:cc-*"
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
```

## Retrieving Secrets

### Via AWS CLI

```powershell
# Get GitHub token
aws secretsmanager get-secret-value `
    --secret-id cc-github-token-dev `
    --query SecretString `
    --output text | ConvertFrom-Json

# Get API key
aws secretsmanager get-secret-value `
    --secret-id cc-api-key-dev `
    --query SecretString `
    --output text | ConvertFrom-Json
```

### Via AWS Console

1. Go to https://console.aws.amazon.com/secretsmanager/
2. Click on the secret name
3. Click "Retrieve secret value"
4. View or copy the secret

### Via Python (Local Development)

```python
import boto3
import json

def get_secret(secret_name):
    client = boto3.client('secretsmanager', region_name='us-east-1')
    response = client.get_secret_value(SecretId=secret_name)
    return json.loads(response['SecretString'])

# Usage
github_secret = get_secret('cc-github-token-dev')
print(f"Token: {github_secret['token']}")
```

## Security Best Practices

### 1. Never Commit Secrets to Git

❌ **Bad:**
```python
GITHUB_TOKEN = "ghp_xxxxxxxxxxxxx"  # Never do this!
```

✅ **Good:**
```python
from secrets import get_github_token
github_token = get_github_token('dev')
```

### 2. Use Fine-Grained Tokens

- Prefer fine-grained PATs over classic tokens
- Grant minimum required permissions
- Limit to specific repositories when possible

### 3. Rotate Regularly

- Set calendar reminders for manual rotation
- Enable automatic rotation for API keys
- Revoke old tokens after rotation

### 4. Monitor Access

- Enable CloudTrail logging for Secrets Manager
- Set up CloudWatch alarms for unusual access patterns
- Review access logs regularly

### 5. Use Separate Secrets per Environment

- `cc-github-token-dev` for development
- `cc-github-token-prod` for production
- Never share secrets between environments

### 6. Limit IAM Permissions

- Grant `secretsmanager:GetSecretValue` only to Lambda functions that need it
- Use resource-based policies to restrict access
- Avoid wildcard permissions

## Troubleshooting

### Issue: "Secret not found"

**Error:** `ResourceNotFoundException: Secrets Manager can't find the specified secret`

**Solutions:**
1. Verify secret name: `aws secretsmanager list-secrets`
2. Check region: Secrets are region-specific
3. Verify IAM permissions

### Issue: "Access denied"

**Error:** `AccessDeniedException: User is not authorized to perform: secretsmanager:GetSecretValue`

**Solutions:**
1. Check Lambda execution role has `secretsmanager:GetSecretValue` permission
2. Verify resource ARN in IAM policy matches secret ARN
3. Check if secret has resource-based policy blocking access

### Issue: GitHub API returns 401

**Error:** `Bad credentials` from GitHub API

**Solutions:**
1. Verify token is valid: Test with `curl -H "Authorization: token YOUR_TOKEN" https://api.github.com/user`
2. Check token hasn't expired
3. Verify token has required permissions
4. Rotate token if compromised

### Issue: Lambda timeout retrieving secret

**Error:** Lambda times out when calling `get_secret_value`

**Solutions:**
1. Increase Lambda timeout (default: 3 seconds, increase to 10+)
2. Check VPC configuration (if Lambda is in VPC, needs VPC endpoint for Secrets Manager)
3. Verify network connectivity

### Issue: Rotation fails

**Error:** Rotation Lambda fails during rotation

**Solutions:**
1. Check rotation Lambda logs in CloudWatch
2. Verify rotation Lambda has correct permissions
3. Test rotation Lambda manually
4. Check if secret is in use during rotation

## Cost Optimization

### Secrets Manager Pricing

- **Secret storage**: $0.40 per secret per month
- **API calls**: $0.05 per 10,000 API calls

### Optimization Tips

1. **Cache secrets in Lambda**: Use container reuse to avoid repeated API calls
2. **Use environment variables for non-sensitive config**: Only use Secrets Manager for truly sensitive data
3. **Consolidate secrets**: Store multiple values in one secret (JSON format)
4. **Delete unused secrets**: Clean up old secrets to avoid storage costs

### Example Cost Calculation

For ContribConnect dev environment:
- 2 secrets (GitHub token + API key) = $0.80/month
- ~1000 Lambda invocations/day × 30 days = 30,000 API calls = $0.15/month
- **Total**: ~$1/month

## Monitoring

### CloudWatch Metrics

Monitor secret access:
- `GetSecretValue` API calls
- Failed authentication attempts
- Rotation success/failure

### CloudWatch Alarms

Create alarms for:
- Excessive secret access (potential leak)
- Failed rotation attempts
- Secrets nearing expiration

### CloudTrail Logging

Enable CloudTrail to log:
- Who accessed which secrets
- When secrets were rotated
- Changes to secret policies

Example CloudTrail query:
```
eventName = "GetSecretValue" AND 
requestParameters.secretId = "cc-github-token-dev"
```

## Frontend Integration

### Environment Variables

Add API key to frontend `.env` file:

```bash
VITE_API_KEY=cc-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

### API Requests

Include API key in requests:

```javascript
const response = await fetch('https://api.example.com/endpoint', {
  headers: {
    'x-api-key': import.meta.env.VITE_API_KEY,
    'Content-Type': 'application/json'
  }
});
```

### Security Note

API keys in frontend code are visible to users. For production:
- Use Cognito for user authentication
- Implement rate limiting
- Monitor for abuse

## Additional Resources

- [AWS Secrets Manager Documentation](https://docs.aws.amazon.com/secretsmanager/)
- [GitHub Token Best Practices](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token)
- [AWS Secrets Manager Pricing](https://aws.amazon.com/secrets-manager/pricing/)
- [Rotating AWS Secrets Manager Secrets](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotating-secrets.html)
