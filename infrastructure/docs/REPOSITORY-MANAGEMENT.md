# Repository Configuration Management Guide

This guide explains how to manage repository configurations for ContribConnect's data ingestion pipeline.

## Overview

The repository configuration system allows you to:
- Add/remove repositories for ingestion
- Enable/disable repositories without deleting them
- Configure ingestion parameters (topics, minimum stars)
- Track ingestion status and history
- Validate repository access before adding

## Components

### 1. DynamoDB Table: cc-repos

Stores repository configurations with the following schema:

```
Partition Key: org (String) - GitHub organization/owner
Sort Key: repo (String) - Repository name

Attributes:
- enabled (Boolean) - Whether ingestion is enabled
- topics (List<String>) - Repository topics/tags
- minStars (Number) - Minimum star count requirement
- description (String) - Repository description
- stars (Number) - Current star count
- language (String) - Primary programming language
- defaultBranch (String) - Default branch name
- ingestCursor (String) - Last ingestion timestamp
- lastIngestAt (String) - Last successful ingestion
- ingestStatus (String) - Current status (pending/success/error)
- createdAt (String) - Configuration creation time
- updatedAt (String) - Last update time
```

### 2. PowerShell Management Script

`infrastructure/scripts/manage-repositories.ps1` - CLI tool for managing repositories

### 3. Lambda Function

`lambda/repo-manager/lambda_function.py` - Programmatic API for repository management

## Quick Start

### Initialize the Repository Table

First, create the table and add sample repositories:

```powershell
.\infrastructure\scripts\manage-repositories.ps1 -Action init -Environment dev
```

This creates the `cc-repos-dev` table and adds three sample repositories:
- RooCodeInc/Roo-Code (enabled)
- facebook/react (enabled)
- microsoft/vscode (disabled)

### List All Repositories

```powershell
.\infrastructure\scripts\manage-repositories.ps1 -Action list -Environment dev
```

Output:
```
Repository              Enabled Stars  Language   Status  LastIngest
----------              ------- -----  --------   ------  ----------
RooCodeInc/Roo-Code     True    1234   TypeScript pending Never
facebook/react          True    220000 JavaScript pending Never
microsoft/vscode        False   160000 TypeScript pending Never
```

## PowerShell Script Usage

### Add a Repository

```powershell
.\infrastructure\scripts\manage-repositories.ps1 `
    -Action add `
    -Owner "microsoft" `
    -Repo "TypeScript" `
    -Topics @("typescript", "compiler", "language") `
    -MinStars 50000 `
    -Environment dev
```

**Parameters:**
- `Owner`: GitHub organization or user
- `Repo`: Repository name
- `Topics`: Array of topic tags (optional, uses GitHub topics if not provided)
- `MinStars`: Minimum star count requirement (default: 0)

**Validation:**
- Checks if repository exists and is accessible via GitHub CLI
- Verifies star count meets minimum requirement
- Fetches repository metadata automatically

### Remove a Repository

```powershell
.\infrastructure\scripts\manage-repositories.ps1 `
    -Action remove `
    -Owner "microsoft" `
    -Repo "vscode" `
    -Environment dev
```

**Note:** This permanently deletes the configuration. Use `disable` instead to temporarily stop ingestion.

### Enable a Repository

```powershell
.\infrastructure\scripts\manage-repositories.ps1 `
    -Action enable `
    -Owner "microsoft" `
    -Repo "vscode" `
    -Environment dev
```

Enables ingestion for a previously disabled repository.

### Disable a Repository

```powershell
.\infrastructure\scripts\manage-repositories.ps1 `
    -Action disable `
    -Owner "facebook" `
    -Repo "react" `
    -Environment dev
```

Temporarily disables ingestion without deleting the configuration.

## Lambda Function Usage

### Deploy the Lambda Function

```powershell
.\lambda\repo-manager\deploy.ps1 -Environment dev
```

### API Endpoints

The Lambda function supports the following actions:

#### 1. List Repositories

```json
{
  "action": "list",
  "enabledOnly": false
}
```

Response:
```json
{
  "success": true,
  "count": 3,
  "repositories": [
    {
      "repository": "RooCodeInc/Roo-Code",
      "enabled": true,
      "stars": 1234,
      "language": "TypeScript",
      "topics": ["ai", "code-assistant"],
      "ingestStatus": "success",
      "lastIngestAt": "2025-10-19T02:00:00Z"
    }
  ]
}
```

#### 2. Add Repository

```json
{
  "action": "add",
  "owner": "facebook",
  "repo": "react",
  "topics": ["javascript", "react", "frontend"],
  "minStars": 100,
  "enabled": true
}
```

Response:
```json
{
  "success": true,
  "repository": "facebook/react",
  "stars": 220000,
  "language": "JavaScript",
  "enabled": true
}
```

#### 3. Remove Repository

```json
{
  "action": "remove",
  "owner": "facebook",
  "repo": "react"
}
```

#### 4. Enable/Disable Repository

```json
{
  "action": "enable",
  "owner": "facebook",
  "repo": "react"
}
```

#### 5. Get Repository Details

```json
{
  "action": "get",
  "owner": "facebook",
  "repo": "react"
}
```

Response:
```json
{
  "success": true,
  "repository": {
    "org": "facebook",
    "repo": "react",
    "enabled": true,
    "stars": 220000,
    "language": "JavaScript",
    "topics": ["javascript", "react"],
    "description": "A declarative, efficient, and flexible JavaScript library",
    "ingestCursor": "2025-10-19T02:00:00Z",
    "lastIngestAt": "2025-10-19T02:15:00Z",
    "ingestStatus": "success",
    "createdAt": "2025-10-18T10:00:00Z",
    "updatedAt": "2025-10-19T02:15:00Z"
  }
}
```

### Invoke Lambda via CLI

```powershell
# List repositories
$payload = '{"action":"list"}'
$payload | Out-File -FilePath payload.json -Encoding ascii -NoNewline
aws lambda invoke --function-name cc-repo-manager-dev --payload file://payload.json response.json
Get-Content response.json | ConvertFrom-Json | ConvertTo-Json -Depth 10

# Add repository
$payload = '{"action":"add","owner":"vuejs","repo":"vue","topics":["javascript","vue","framework"],"minStars":50000}'
$payload | Out-File -FilePath payload.json -Encoding ascii -NoNewline
aws lambda invoke --function-name cc-repo-manager-dev --payload file://payload.json response.json
Get-Content response.json | ConvertFrom-Json | ConvertTo-Json -Depth 10
```

## Integration with Ingestion Pipeline

The ingestion Lambda (`cc-ingest`) automatically reads enabled repositories from the `cc-repos` table:

```python
# Pseudo-code from ingestion Lambda
def get_enabled_repos():
    response = repos_table.scan(
        FilterExpression='enabled = :enabled',
        ExpressionAttributeValues={':enabled': True}
    )
    return response['Items']

def lambda_handler(event, context):
    repos = get_enabled_repos()
    for repo in repos:
        ingest_repository(repo['org'], repo['repo'])
```

## Best Practices

### 1. Start with High-Quality Repositories

Focus on repositories with:
- Active maintenance (recent commits)
- Good documentation
- Clear contribution guidelines
- Healthy issue/PR activity
- Minimum star threshold (e.g., 1000+)

### 2. Use Topics for Filtering

Add relevant topics to help categorize repositories:
```powershell
-Topics @("javascript", "react", "frontend", "ui-library")
```

### 3. Monitor Ingestion Status

Regularly check ingestion status:
```powershell
.\infrastructure\scripts\manage-repositories.ps1 -Action list -Environment dev
```

Look for:
- Repositories stuck in "pending" status
- Recent "error" status
- Stale `lastIngestAt` timestamps

### 4. Disable Instead of Remove

When temporarily stopping ingestion, use `disable` instead of `remove` to preserve configuration and history.

### 5. Set Appropriate Star Thresholds

Use `minStars` to filter out low-quality repositories:
- Personal projects: 0-100 stars
- Community projects: 100-1000 stars
- Popular projects: 1000+ stars
- Major projects: 10000+ stars

## Troubleshooting

### Issue: Repository validation fails

**Error:** "Repository not found or not accessible"

**Solutions:**
1. Verify repository exists: `gh repo view owner/repo`
2. Check GitHub CLI authentication: `gh auth status`
3. Verify you have read access to the repository
4. Check for typos in owner/repo names

### Issue: Star count below minimum

**Error:** "Repository has X stars, minimum required is Y"

**Solutions:**
1. Lower the `minStars` threshold
2. Choose a different repository
3. Remove the star requirement: `-MinStars 0`

### Issue: Ingestion not starting

**Symptoms:** Repository added but never ingested

**Solutions:**
1. Verify repository is enabled: `enabled = true`
2. Check EventBridge rule is active
3. Verify ingestion Lambda has permissions to read `cc-repos` table
4. Check CloudWatch logs for ingestion Lambda

### Issue: Ingestion stuck in "pending"

**Symptoms:** `ingestStatus` never changes from "pending"

**Solutions:**
1. Manually trigger ingestion Lambda
2. Check for errors in CloudWatch logs
3. Verify GitHub token is valid
4. Check DynamoDB write permissions

## Security Considerations

### GitHub Token

The Lambda function requires a GitHub token for validation:
- Store token in environment variable or Secrets Manager
- Use fine-grained personal access token (PAT)
- Minimum permissions: `public_repo` (read-only)
- Rotate token every 90 days

### DynamoDB Permissions

Required IAM permissions:
```json
{
  "Effect": "Allow",
  "Action": [
    "dynamodb:PutItem",
    "dynamodb:GetItem",
    "dynamodb:UpdateItem",
    "dynamodb:DeleteItem",
    "dynamodb:Scan",
    "dynamodb:Query"
  ],
  "Resource": "arn:aws:dynamodb:*:*:table/cc-repos-*"
}
```

### API Access Control

If exposing the Lambda via API Gateway:
- Require API key authentication
- Implement rate limiting
- Log all configuration changes
- Restrict to admin users only

## Advanced Usage

### Bulk Import from CSV

Create a CSV file with repositories:

```csv
owner,repo,topics,minStars
facebook,react,"javascript,react,frontend",100000
vuejs,vue,"javascript,vue,framework",50000
angular,angular,"typescript,angular,framework",90000
```

Import script:
```powershell
Import-Csv repos.csv | ForEach-Object {
    .\infrastructure\scripts\manage-repositories.ps1 `
        -Action add `
        -Owner $_.owner `
        -Repo $_.repo `
        -Topics ($_.topics -split ',') `
        -MinStars $_.minStars `
        -Environment dev
}
```

### Automated Repository Discovery

Use GitHub API to discover repositories by topic:

```powershell
# Find popular TypeScript repositories
$repos = gh search repos --topic typescript --stars ">10000" --json nameWithOwner,stargazersCount --limit 20 | ConvertFrom-Json

foreach ($repo in $repos) {
    $parts = $repo.nameWithOwner -split '/'
    .\infrastructure\scripts\manage-repositories.ps1 `
        -Action add `
        -Owner $parts[0] `
        -Repo $parts[1] `
        -Topics @("typescript") `
        -MinStars 10000 `
        -Environment dev
}
```

### Scheduled Repository Updates

Create an EventBridge rule to periodically update repository metadata:

```json
{
  "schedule": "rate(7 days)",
  "target": "cc-repo-manager-dev",
  "input": {
    "action": "refresh_all"
  }
}
```

## Monitoring

### CloudWatch Metrics

Track repository management operations:
- Repository additions/removals
- Enable/disable operations
- Validation failures
- API call latency

### CloudWatch Logs Insights Queries

**Query 1: Recent repository additions**
```
SOURCE '/aws/lambda/cc-repo-manager-dev'
| fields @timestamp, repository, stars, language
| filter action = "add" and success = true
| sort @timestamp desc
| limit 20
```

**Query 2: Validation failures**
```
SOURCE '/aws/lambda/cc-repo-manager-dev'
| fields @timestamp, owner, repo, error
| filter success = false
| sort @timestamp desc
```

## Cost Optimization

- Use on-demand billing for `cc-repos` table (low write volume)
- Set TTL on old ingestion records if needed
- Disable unused repositories instead of keeping them enabled
- Batch repository operations when possible

## Additional Resources

- [DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)
- [GitHub API Documentation](https://docs.github.com/en/rest)
- [AWS Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
