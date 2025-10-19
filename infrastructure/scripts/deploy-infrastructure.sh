#!/bin/bash

# ContribConnect Infrastructure Deployment Script
# This script deploys all CloudFormation stacks for the ContribConnect project

set -e

# Configuration
ENVIRONMENT=${1:-dev}
AWS_REGION=${2:-us-east-1}
AWS_PROFILE=${3:-default}

echo "=========================================="
echo "ContribConnect Infrastructure Deployment"
echo "=========================================="
echo "Environment: $ENVIRONMENT"
echo "Region: $AWS_REGION"
echo "Profile: $AWS_PROFILE"
echo "=========================================="

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --profile $AWS_PROFILE --query Account --output text)
echo "AWS Account ID: $AWS_ACCOUNT_ID"

# Deploy DynamoDB Tables
echo ""
echo "Deploying DynamoDB tables..."
aws cloudformation deploy \
  --template-file infrastructure/cloudformation/dynamodb-tables.yaml \
  --stack-name cc-dynamodb-$ENVIRONMENT \
  --parameter-overrides Environment=$ENVIRONMENT \
  --region $AWS_REGION \
  --profile $AWS_PROFILE \
  --tags Project=ContribConnect Environment=$ENVIRONMENT

# Get DynamoDB table names from stack outputs
NODES_TABLE=$(aws cloudformation describe-stacks \
  --stack-name cc-dynamodb-$ENVIRONMENT \
  --region $AWS_REGION \
  --profile $AWS_PROFILE \
  --query "Stacks[0].Outputs[?OutputKey=='NodesTableName'].OutputValue" \
  --output text)

EDGES_TABLE=$(aws cloudformation describe-stacks \
  --stack-name cc-dynamodb-$ENVIRONMENT \
  --region $AWS_REGION \
  --profile $AWS_PROFILE \
  --query "Stacks[0].Outputs[?OutputKey=='EdgesTableName'].OutputValue" \
  --output text)

REPOS_TABLE=$(aws cloudformation describe-stacks \
  --stack-name cc-dynamodb-$ENVIRONMENT \
  --region $AWS_REGION \
  --profile $AWS_PROFILE \
  --query "Stacks[0].Outputs[?OutputKey=='ReposTableName'].OutputValue" \
  --output text)

SESSIONS_TABLE=$(aws cloudformation describe-stacks \
  --stack-name cc-dynamodb-$ENVIRONMENT \
  --region $AWS_REGION \
  --profile $AWS_PROFILE \
  --query "Stacks[0].Outputs[?OutputKey=='AgentSessionsTableName'].OutputValue" \
  --output text)

echo "✓ DynamoDB tables deployed successfully"
echo "  - Nodes: $NODES_TABLE"
echo "  - Edges: $EDGES_TABLE"
echo "  - Repos: $REPOS_TABLE"
echo "  - Sessions: $SESSIONS_TABLE"

# Deploy S3 Buckets
echo ""
echo "Deploying S3 buckets..."
aws cloudformation deploy \
  --template-file infrastructure/cloudformation/s3-buckets.yaml \
  --stack-name cc-s3-$ENVIRONMENT \
  --parameter-overrides Environment=$ENVIRONMENT \
  --region $AWS_REGION \
  --profile $AWS_PROFILE \
  --tags Project=ContribConnect Environment=$ENVIRONMENT

# Get S3 bucket names from stack outputs
RAW_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name cc-s3-$ENVIRONMENT \
  --region $AWS_REGION \
  --profile $AWS_PROFILE \
  --query "Stacks[0].Outputs[?OutputKey=='RawDataBucketName'].OutputValue" \
  --output text)

KB_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name cc-s3-$ENVIRONMENT \
  --region $AWS_REGION \
  --profile $AWS_PROFILE \
  --query "Stacks[0].Outputs[?OutputKey=='KnowledgeBaseDocsBucketName'].OutputValue" \
  --output text)

WEB_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name cc-s3-$ENVIRONMENT \
  --region $AWS_REGION \
  --profile $AWS_PROFILE \
  --query "Stacks[0].Outputs[?OutputKey=='WebBucketName'].OutputValue" \
  --output text)

echo "✓ S3 buckets deployed successfully"
echo "  - Raw Data: $RAW_BUCKET"
echo "  - KB Docs: $KB_BUCKET"
echo "  - Web: $WEB_BUCKET"

# Deploy IAM Roles
echo ""
echo "Deploying IAM roles..."
aws cloudformation deploy \
  --template-file infrastructure/cloudformation/iam-roles.yaml \
  --stack-name cc-iam-$ENVIRONMENT \
  --parameter-overrides \
    Environment=$ENVIRONMENT \
    NodesTableName=$NODES_TABLE \
    EdgesTableName=$EDGES_TABLE \
    ReposTableName=$REPOS_TABLE \
    AgentSessionsTableName=$SESSIONS_TABLE \
    RawDataBucketName=$RAW_BUCKET \
    KnowledgeBaseDocsBucketName=$KB_BUCKET \
  --capabilities CAPABILITY_NAMED_IAM \
  --region $AWS_REGION \
  --profile $AWS_PROFILE \
  --tags Project=ContribConnect Environment=$ENVIRONMENT

echo "✓ IAM roles deployed successfully"

# Summary
echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""
echo "Next Steps:"
echo "1. Configure Bedrock services (Knowledge Base, Guardrails)"
echo "2. Set up Amazon Q Business (optional)"
echo "3. Deploy Lambda functions"
echo "4. Configure API Gateway"
echo "5. Deploy frontend application"
echo ""
echo "Resource Names:"
echo "  DynamoDB Tables:"
echo "    - $NODES_TABLE"
echo "    - $EDGES_TABLE"
echo "    - $REPOS_TABLE"
echo "    - $SESSIONS_TABLE"
echo "  S3 Buckets:"
echo "    - $RAW_BUCKET"
echo "    - $KB_BUCKET"
echo "    - $WEB_BUCKET"
echo ""
