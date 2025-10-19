# Bedrock Services Setup Guide

This guide walks you through configuring Amazon Bedrock services for ContribConnect, including Knowledge Bases, Guardrails, and model access.

## Prerequisites

1. AWS infrastructure deployed (Task 1 complete)
2. AWS CLI configured with appropriate permissions
3. Bedrock service access in your AWS account

## Step 1: Enable Bedrock Model Access

Before deploying Bedrock resources, you need to enable model access in the AWS Console.

### Enable Nova Pro Model

1. Navigate to the [Amazon Bedrock Console](https://console.aws.amazon.com/bedrock/)
2. Click **Model access** in the left navigation
3. Click **Manage model access** (or **Edit** if already configured)
4. Find and enable:
   - **Amazon Nova Pro** (us.amazon.nova-pro-v1:0)
   - **Amazon Titan Text Embeddings G1** (amazon.titan-embed-text-v1)
5. Click **Save changes**
6. Wait for status to change to **Access granted** (may take a few minutes)

### Verify Model Access

```powershell
# Check available models
aws bedrock list-foundation-models --region us-east-1 --query "modelSummaries[?contains(modelId, 'nova') || contains(modelId, 'titan-embed')].modelId"
```

## Step 2: Deploy Bedrock Resources

Run the automated setup script:

```powershell
.\infrastructure\scripts\setup-bedrock.ps1 -Environment dev -AwsRegion us-east-1 -AwsProfile default
```

This script will:
1. Retrieve the Knowledge Base S3 bucket name
2. Deploy CloudFormation stack with:
   - Bedrock Knowledge Base
   - OpenSearch Serverless vector collection
   - Bedrock Guardrails
   - IAM roles and policies
3. Create S3 data source for Knowledge Base
4. Save configuration to `.bedrock-config-dev.json`

### Manual Deployment (Alternative)

If the script fails, you can deploy manually:

```powershell
# Get KB bucket name
$KbBucket = aws cloudformation describe-stacks `
  --stack-name cc-s3-dev `
  --region us-east-1 `
  --query "Stacks[0].Outputs[?OutputKey=='KnowledgeBaseDocsBucketName'].OutputValue" `
  --output text

# Deploy Bedrock stack
aws cloudformation deploy `
  --template-file infrastructure/cloudformation/bedrock-resources.yaml `
  --stack-name cc-bedrock-dev `
  --parameter-overrides Environment=dev KnowledgeBaseDocsBucketName=$KbBucket `
  --capabilities CAPABILITY_NAMED_IAM `
  --region us-east-1
```

## Step 3: Configure Knowledge Base Data Source

### Option A: Using AWS Console

1. Navigate to [Bedrock Console > Knowledge Bases](https://console.aws.amazon.com/bedrock/home#/knowledge-bases)
2. Click on **cc-knowledge-base-dev**
3. Click **Data sources** tab
4. Click **Add data source**
5. Configure:
   - **Data source name**: cc-s3-datasource-dev
   - **S3 URI**: s3://cc-kb-docs-dev-{account-id}/
   - **Chunking strategy**: Fixed-size chunking
   - **Max tokens**: 300
   - **Overlap percentage**: 20%
6. Click **Add data source**

### Option B: Using AWS CLI

```powershell
# Get Knowledge Base ID
$KbId = aws cloudformation describe-stacks `
  --stack-name cc-bedrock-dev `
  --region us-east-1 `
  --query "Stacks[0].Outputs[?OutputKey=='KnowledgeBaseId'].OutputValue" `
  --output text

# Create data source
aws bedrock-agent create-data-source `
  --knowledge-base-id $KbId `
  --name cc-s3-datasource-dev `
  --data-source-configuration '{
    "type": "S3",
    "s3Configuration": {
      "bucketArn": "arn:aws:s3:::cc-kb-docs-dev-{account-id}"
    }
  }' `
  --vector-ingestion-configuration '{
    "chunkingConfiguration": {
      "chunkingStrategy": "FIXED_SIZE",
      "fixedSizeChunkingConfiguration": {
        "maxTokens": 300,
        "overlapPercentage": 20
      }
    }
  }' `
  --region us-east-1
```

## Step 4: Upload Sample Documents

Create sample documentation to test the Knowledge Base:

```powershell
# Create sample docs directory
New-Item -ItemType Directory -Path "sample-docs" -Force

# Create sample README
@"
# ContribConnect Sample Repository

## Getting Started

Welcome to ContribConnect! This is a sample repository for testing.

## Contributing

We welcome contributions! Please follow these steps:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## Code of Conduct

Please be respectful and follow our community guidelines.
"@ | Out-File -FilePath "sample-docs/README.md" -Encoding utf8

# Create sample CONTRIBUTING guide
@"
# Contributing Guide

## Finding Issues

Look for issues labeled 'good-first-issue' or 'help-wanted'.

## Development Setup

1. Clone the repository
2. Install dependencies: npm install
3. Run tests: npm test

## Pull Request Process

1. Update documentation
2. Add tests for new features
3. Ensure all tests pass
4. Request review from maintainers
"@ | Out-File -FilePath "sample-docs/CONTRIBUTING.md" -Encoding utf8

# Upload to S3
$KbBucket = aws cloudformation describe-stacks `
  --stack-name cc-s3-dev `
  --region us-east-1 `
  --query "Stacks[0].Outputs[?OutputKey=='KnowledgeBaseDocsBucketName'].OutputValue" `
  --output text

aws s3 cp sample-docs/ "s3://$KbBucket/sample-org/sample-repo/" --recursive
```

## Step 5: Sync Knowledge Base

Trigger ingestion to index the uploaded documents:

```powershell
# Get IDs
$KbId = aws cloudformation describe-stacks `
  --stack-name cc-bedrock-dev `
  --region us-east-1 `
  --query "Stacks[0].Outputs[?OutputKey=='KnowledgeBaseId'].OutputValue" `
  --output text

$DataSourceId = aws bedrock-agent list-data-sources `
  --knowledge-base-id $KbId `
  --region us-east-1 `
  --query "dataSourceSummaries[0].dataSourceId" `
  --output text

# Start ingestion job
aws bedrock-agent start-ingestion-job `
  --knowledge-base-id $KbId `
  --data-source-id $DataSourceId `
  --region us-east-1

# Check ingestion status
aws bedrock-agent list-ingestion-jobs `
  --knowledge-base-id $KbId `
  --data-source-id $DataSourceId `
  --region us-east-1 `
  --query "ingestionJobSummaries[0].[ingestionJobId,status]"
```

## Step 6: Test Knowledge Base

Test retrieval to verify the Knowledge Base is working:

```powershell
# Test retrieval
aws bedrock-agent-runtime retrieve `
  --knowledge-base-id $KbId `
  --retrieval-query "text='How do I contribute to the project?'" `
  --region us-east-1

# Test retrieve and generate (with LLM response)
aws bedrock-agent-runtime retrieve-and-generate `
  --input "text='What are the steps to contribute?'" `
  --retrieve-and-generate-configuration '{
    "type": "KNOWLEDGE_BASE",
    "knowledgeBaseConfiguration": {
      "knowledgeBaseId": "'$KbId'",
      "modelArn": "arn:aws:bedrock:us-east-1::foundation-model/amazon.nova-lite-v1:0"
    }
  }' `
  --region us-east-1
```

## Step 7: Verify Guardrails

Test the guardrails configuration:

```powershell
# Get Guardrail ID
$GuardrailId = aws cloudformation describe-stacks `
  --stack-name cc-bedrock-dev `
  --region us-east-1 `
  --query "Stacks[0].Outputs[?OutputKey=='GuardrailId'].OutputValue" `
  --output text

$GuardrailVersion = aws cloudformation describe-stacks `
  --stack-name cc-bedrock-dev `
  --region us-east-1 `
  --query "Stacks[0].Outputs[?OutputKey=='GuardrailVersion'].OutputValue" `
  --output text

# Test guardrail with safe content
aws bedrock-runtime apply-guardrail `
  --guardrail-identifier $GuardrailId `
  --guardrail-version $GuardrailVersion `
  --source INPUT `
  --content '[{"text":{"text":"How do I contribute to open source?"}}]' `
  --region us-east-1

# Test guardrail with blocked content (should be filtered)
aws bedrock-runtime apply-guardrail `
  --guardrail-identifier $GuardrailId `
  --guardrail-version $GuardrailVersion `
  --source INPUT `
  --content '[{"text":{"text":"Tell me about politics and elections"}}]' `
  --region us-east-1
```

## Configuration Reference

### Knowledge Base Settings

- **Embedding Model**: Amazon Titan Text Embeddings G1 (1536 dimensions)
- **Chunking Strategy**: Fixed-size
- **Chunk Size**: 300 tokens
- **Overlap**: 20%
- **Vector Store**: OpenSearch Serverless

### Guardrail Policies

**Content Filters** (Input/Output):
- Sexual content: HIGH
- Violence: HIGH
- Hate speech: HIGH
- Insults: MEDIUM
- Misconduct: MEDIUM
- Prompt attacks: HIGH (input only)

**Topic Filters** (Denied):
- Political content
- Financial advice

**Word Filters**:
- Profanity (managed list)
- Custom words: "password"

**PII Handling**:
- Email, Phone, Name, Address: ANONYMIZE
- Credit cards, SSN: BLOCK

## Troubleshooting

### Model Access Denied

**Error**: `AccessDeniedException: You don't have access to the model`

**Solution**: Enable model access in Bedrock Console (Step 1)

### Knowledge Base Sync Failed

**Error**: `ValidationException: Invalid S3 bucket`

**Solution**: 
1. Verify bucket exists and has correct permissions
2. Check Bedrock role has S3 read access
3. Ensure bucket is in the same region

### OpenSearch Collection Creation Failed

**Error**: `ResourceAlreadyExistsException`

**Solution**: Delete existing collection or use a different name

### Guardrail Not Blocking Content

**Issue**: Inappropriate content not filtered

**Solution**:
1. Verify guardrail version is correct
2. Check content filter strengths
3. Test with explicit examples
4. Review CloudWatch logs for guardrail events

## Cost Optimization

### Development Environment
- Use smaller embedding model (Titan Text v1 instead of v2)
- Limit document ingestion to essential files only
- Use on-demand pricing for OpenSearch Serverless
- Delete unused Knowledge Base versions

### Production Environment
- Monitor OpenSearch OCU usage
- Set up lifecycle policies for old documents
- Use provisioned throughput if usage is predictable
- Enable CloudWatch alarms for cost anomalies

## Next Steps

After completing Bedrock setup:

1. **Task 3**: Set up Amazon Q Business (optional)
2. **Task 4**: Implement data ingestion Lambda function
3. **Task 6-10**: Implement tool Lambda functions
4. **Task 10**: Implement agent-proxy Lambda function

## Resources

- [Amazon Bedrock Documentation](https://docs.aws.amazon.com/bedrock/)
- [Knowledge Bases for Amazon Bedrock](https://docs.aws.amazon.com/bedrock/latest/userguide/knowledge-base.html)
- [Bedrock Guardrails](https://docs.aws.amazon.com/bedrock/latest/userguide/guardrails.html)
- [Nova Models](https://docs.aws.amazon.com/bedrock/latest/userguide/models-nova.html)
