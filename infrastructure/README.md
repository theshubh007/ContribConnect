# ContribConnect Infrastructure

This directory contains Infrastructure as Code (IaC) for deploying ContribConnect AWS resources using CloudFormation.

## Architecture Overview

ContribConnect uses the following AWS services:

- **DynamoDB**: Graph storage (nodes/edges), repository configuration, agent sessions
- **S3**: Raw data storage, Knowledge Base documents, static web hosting
- **Lambda**: Serverless compute for agent proxy and tool functions
- **Bedrock**: Nova models, Knowledge Bases, Guardrails
- **API Gateway**: REST API endpoints
- **CloudFront**: CDN for web application
- **EventBridge**: Scheduled ingestion triggers
- **Secrets Manager**: GitHub tokens and API keys

## Directory Structure

```
infrastructure/
├── cloudformation/
│   ├── dynamodb-tables.yaml    # DynamoDB tables for graph and sessions
│   ├── s3-buckets.yaml          # S3 buckets for data and web hosting
│   └── iam-roles.yaml           # IAM roles for Lambda functions
├── scripts/
│   ├── deploy-infrastructure.sh  # Bash deployment script (Linux/Mac)
│   └── deploy-infrastructure.ps1 # PowerShell deployment script (Windows)
└── README.md                     # This file
```

## Prerequisites

1. **AWS CLI** installed and configured
   ```bash
   aws --version
   aws configure
   ```

2. **AWS Account** with appropriate permissions:
   - CloudFormation (create/update stacks)
   - DynamoDB (create tables)
   - S3 (create buckets)
   - IAM (create roles and policies)

3. **AWS Region**: us-east-1 (recommended for Bedrock Nova models)

## Deployment

### Option 1: Automated Deployment (Recommended)

#### Linux/Mac:
```bash
cd infrastructure/scripts
chmod +x deploy-infrastructure.sh
./deploy-infrastructure.sh dev us-east-1 default
```

#### Windows (PowerShell):
```powershell
cd infrastructure\scripts
.\deploy-infrastructure.ps1 -Environment dev -AwsRegion us-east-1 -AwsProfile default
```

Parameters:
- `Environment`: dev or prod (default: dev)
- `AwsRegion`: AWS region (default: us-east-1)
- `AwsProfile`: AWS CLI profile (default: default)

### Option 2: Manual Deployment

Deploy stacks in order:

1. **DynamoDB Tables**:
   ```bash
   aws cloudformation deploy \
     --template-file cloudformation/dynamodb-tables.yaml \
     --stack-name cc-dynamodb-dev \
     --parameter-overrides Environment=dev \
     --region us-east-1
   ```

2. **S3 Buckets**:
   ```bash
   aws cloudformation deploy \
     --template-file cloudformation/s3-buckets.yaml \
     --stack-name cc-s3-dev \
     --parameter-overrides Environment=dev \
     --region us-east-1
   ```

3. **IAM Roles** (requires table/bucket names from previous stacks):
   ```bash
   aws cloudformation deploy \
     --template-file cloudformation/iam-roles.yaml \
     --stack-name cc-iam-dev \
     --parameter-overrides \
       Environment=dev \
       NodesTableName=cc-nodes-dev \
       EdgesTableName=cc-edges-dev \
       ReposTableName=cc-repos-dev \
       AgentSessionsTableName=cc-agent-sessions-dev \
       RawDataBucketName=cc-raw-dev-123456789012 \
       KnowledgeBaseDocsBucketName=cc-kb-docs-dev-123456789012 \
     --capabilities CAPABILITY_NAMED_IAM \
     --region us-east-1
   ```

## Resources Created

### DynamoDB Tables

| Table Name | Purpose | Key Schema | GSI |
|------------|---------|------------|-----|
| cc-nodes-{env} | Graph nodes (repos, users, issues, PRs, files) | PK: nodeId | NodeTypeIndex |
| cc-edges-{env} | Graph edges (relationships) | PK: fromId, SK: toIdEdgeType | ReverseEdgeIndex |
| cc-repos-{env} | Repository configuration | PK: org, SK: repo | - |
| cc-agent-sessions-{env} | Agent conversation history | PK: sessionId, SK: ts | - |

### S3 Buckets

| Bucket Name | Purpose | Features |
|-------------|---------|----------|
| cc-raw-{env}-{account} | Raw GitHub data (JSON) | Versioning, Encryption, Lifecycle (Glacier after 90 days) |
| cc-kb-docs-{env}-{account} | Knowledge Base documents | Versioning, Encryption |
| cc-web-{env}-{account} | Static web hosting | Versioning, Encryption, CloudFront OAC |

### IAM Roles

| Role Name | Used By | Permissions |
|-----------|---------|-------------|
| cc-ingest-lambda-role-{env} | Ingestion Lambda | DynamoDB (read/write), S3 (read/write), Secrets Manager |
| cc-graph-tool-lambda-role-{env} | Graph Tool Lambda | DynamoDB (read) |
| cc-kb-tool-lambda-role-{env} | KB Tool Lambda | Bedrock Knowledge Base (retrieve) |
| cc-qbiz-tool-lambda-role-{env} | Q Business Tool Lambda | Q Business (chat) |
| cc-github-tool-lambda-role-{env} | GitHub Tool Lambda | Secrets Manager (GitHub token) |
| cc-agent-proxy-lambda-role-{env} | Agent Proxy Lambda | Bedrock (converse), Lambda (invoke tools), DynamoDB (sessions) |

## Cost Estimates

### Development Environment (dev)
- **DynamoDB**: ~$5/month (on-demand, low usage)
- **S3**: ~$1/month (minimal storage)
- **Lambda**: Free tier covers most usage
- **Bedrock**: Pay-per-use (~$0.80 per 1M input tokens for Nova Pro)
- **Total**: ~$10-20/month

### Production Environment (prod)
- **DynamoDB**: ~$20-50/month (depends on traffic)
- **S3**: ~$5-10/month
- **Lambda**: ~$10-20/month
- **Bedrock**: ~$50-100/month (depends on usage)
- **Q Business**: ~$20/user/month (optional)
- **CloudFront**: ~$5-10/month
- **Total**: ~$100-200/month (without Q Business)

## Verification

After deployment, verify resources:

```bash
# List DynamoDB tables
aws dynamodb list-tables --region us-east-1

# List S3 buckets
aws s3 ls | grep cc-

# List IAM roles
aws iam list-roles --query 'Roles[?contains(RoleName, `cc-`)].RoleName'

# Check CloudFormation stacks
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE
```

## Cleanup

To delete all resources:

```bash
# Delete IAM roles stack
aws cloudformation delete-stack --stack-name cc-iam-dev --region us-east-1

# Empty and delete S3 buckets (required before stack deletion)
aws s3 rm s3://cc-raw-dev-{account} --recursive
aws s3 rm s3://cc-kb-docs-dev-{account} --recursive
aws s3 rm s3://cc-web-dev-{account} --recursive
aws cloudformation delete-stack --stack-name cc-s3-dev --region us-east-1

# Delete DynamoDB tables stack
aws cloudformation delete-stack --stack-name cc-dynamodb-dev --region us-east-1
```

## Troubleshooting

### Stack Creation Failed

Check CloudFormation events:
```bash
aws cloudformation describe-stack-events \
  --stack-name cc-dynamodb-dev \
  --region us-east-1 \
  --max-items 10
```

### Insufficient Permissions

Ensure your IAM user/role has these policies:
- CloudFormationFullAccess
- AmazonDynamoDBFullAccess
- AmazonS3FullAccess
- IAMFullAccess

### Bucket Name Already Exists

S3 bucket names must be globally unique. The templates use `{bucket-name}-{account-id}` to ensure uniqueness.

## Next Steps

After infrastructure deployment:

1. **Configure Bedrock Services** (Task 2)
   - Set up Knowledge Base with S3 data source
   - Create Guardrails
   - Enable Nova Pro model access

2. **Set up Secrets Manager**
   - Store GitHub fine-grained PAT
   - Store API key for frontend

3. **Deploy Lambda Functions** (Tasks 4, 6-10)
   - Package and deploy function code
   - Configure environment variables

4. **Configure API Gateway** (Task 11)
   - Create HTTP API
   - Set up routes and integrations

5. **Deploy Frontend** (Tasks 12-14)
   - Build React application
   - Upload to S3
   - Configure CloudFront

## Support

For issues or questions:
- Check CloudFormation stack events for error details
- Review IAM role permissions
- Verify AWS service quotas and limits
- Consult AWS documentation for specific services
