  # Design Document

## Overview

ContribConnect is a serverless, event-driven AI agent system built on AWS that helps developers discover and contribute to open-source projects. This design is optimized for hackathon deployment with minimal AWS costs (under $100 credit).

**Core AWS Services:**
- **Amazon Bedrock** with **Nova models** provides the reasoning engine
- **Bedrock AgentCore** (Converse API with tool use) orchestrates tool execution
- **Bedrock Knowledge Bases** provides semantic document search
- **Amazon Q Business** provides grounded documentation retrieval with citations
- **AWS Lambda** implements tool handlers and ingestion logic
- **Amazon DynamoDB** stores graph relationships, agent memory, and configuration
- **Amazon S3** stores raw data and Knowledge Base documents
- **Amazon CloudFront + S3** serves the static web application
- **Amazon API Gateway** exposes REST endpoints
- **Amazon EventBridge** schedules autonomous data ingestion

**Cost-Optimized Architecture:**
- DynamoDB adjacency list pattern replaces Neptune (graph queries)
- Bedrock Knowledge Bases + Q Business for document retrieval (replaces OpenSearch)
- Simple API key authentication replaces Cognito
- Manual AWS Console deployment replaces CDK infrastructure
- Most services use free tier or pay-per-use pricing
- **Note:** Q Business adds cost (~$20/user/month) but provides superior grounded answers

The architecture follows a clear separation of concerns with the agent as the orchestrator, tools as specialized services, and DynamoDB as the primary data store.

## Architecture

### High-Level Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Layer                               │
│  Browser → CloudFront (OAC) → S3 Static Web (React/Vite SPA)   │
└────────────────────────┬────────────────────────────────────────┘
                         │ HTTPS + API Key
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                      API Layer                                   │
│              API Gateway HTTP API                                │
│                (API Key validation)                              │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Agent Orchestration                           │
│         Lambda: agent-proxy                                      │
│              ↓                                                   │
│    Bedrock Converse API                                          │
│    + Nova (nova-pro-v1:0)                                        │
│    + Tool Use (AgentCore primitives)                             │
│    + Guardrails                                                  │
└──────┬──────────┬──────────┬──────────┬─────────────────────────┘
       │          │          │          │
       │ tool     │ tool     │ tool     │ tool
       │ call     │ call     │ call     │ call
       ▼          ▼          ▼          ▼
┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐
│ Lambda:  │ │ Lambda:  │ │ Lambda:  │ │ Lambda:  │
│ github-  │ │ graph-   │ │ kb-      │ │ qbiz-    │
│ tool     │ │ tool     │ │ tool     │ │ tool     │
└────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘
     │            │            │            │
     ▼            ▼            ▼            ▼
┌─────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐
│ GitHub  │ │ DynamoDB │ │ Bedrock  │ │ Q Biz    │
│ REST/   │ │ (graph   │ │Knowledge │ │ (S3 docs)│
│ GraphQL │ │ pattern) │ │  Bases   │ │          │
└─────────┘ └──────────┘ └──────────┘ └──────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    Data Ingestion Pipeline                       │
│                                                                  │
│  EventBridge (cron: nightly 02:00 UTC)                          │
│         ↓                                                        │
│  Lambda: ingest                                                  │
│         ↓                                                        │
│  ┌──────────────┬──────────────┬──────────────┐                │
│  ▼              ▼              ▼              ▼                │
│ GitHub API → S3 raw → DynamoDB → Knowledge Bases                │
│              (JSON)   (graph)    (vectors)                      │
│                                                                  │
│  DynamoDB: repo config + cursors + graph edges                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    Supporting Services                           │
│                                                                  │
│  • DynamoDB (agent sessions, tool logs, repo list, graph)       │
│  • S3 (raw data, Knowledge Base source, static web)             │
│  • CloudFront (CDN for web app)                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Data Flow Patterns

#### 1. User Query Flow
```
User → CloudFront → API Gateway → agent-proxy Lambda
  → Bedrock AgentCore (Nova + Converse)
  → Tool invocations (parallel when possible)
  → Tool results aggregated
  → Agent reasoning + response generation
  → Guardrails validation
  → Response streamed back to user
```

#### 2. Ingestion Flow
```
EventBridge schedule → ingest Lambda
  → GitHub API (issues, PRs, files, CODEOWNERS)
  → S3 (raw JSON with date partitions)
  → DynamoDB (graph edges using adjacency list pattern)
  → S3 (docs for Knowledge Base sync)
  → Bedrock Knowledge Base (auto-sync from S3)
  → DynamoDB (update cursors)
```

#### 3. Tool Execution Flow
```
Agent decides tool needed → Converse API invokes tool Lambda
  → Tool Lambda queries data store (DynamoDB/Knowledge Bases/GitHub/Q)
  → Tool returns structured JSON
  → Agent incorporates result into reasoning
```

## Components and Interfaces

### 1. Frontend (React/Vite SPA)

**Responsibilities:**
- Simple API key authentication (stored in localStorage)
- Chat interface for agent interaction
- Display of issue recommendations and PR drafts
- Real-time streaming of agent responses

**Key Technologies:**
- React 18+ with Vite for fast builds
- Fetch API with streaming for agent responses
- Hosted on S3 with CloudFront OAC
- No authentication library needed (simple API key header)

**API Contract:**
```typescript
// POST /api/agent/chat
// Headers: { "x-api-key": "demo-key-12345" }
Request: {
  sessionId: string;
  message: string;
  context?: {
    repos?: string[];
    skills?: string[];
  };
}

Response: {
  sessionId: string;
  response: string;
  toolCalls?: Array<{
    tool: string;
    input: object;
    output: object;
  }>;
  citations?: Array<{
    source: string;
    url: string;
  }>;
}
```

### 2. API Gateway + Lambda (agent-proxy)

**Responsibilities:**
- API key validation (simple header check)
- Route requests to Bedrock Converse API
- Handle streaming responses
- Error handling and logging

**Implementation:**
- API Gateway HTTP API with API key requirement
- Lambda runtime: Python 3.13
- Boto3 bedrock-runtime client for Converse API

**Key Code Pattern:**
```python
import boto3
import json

bedrock = boto3.client('bedrock-runtime', region_name='us-east-1')

# Simple API key validation
api_key = event['headers'].get('x-api-key')
if api_key != 'demo-key-12345':  # Store in env var
    return {'statusCode': 401, 'body': 'Unauthorized'}

response = bedrock.converse(
    modelId='us.amazon.nova-pro-v1:0',
    messages=[
        {'role': 'user', 'content': [{'text': user_message}]}
    ],
    toolConfig={
        'tools': [
            # Tool definitions for github, graph, kb, qbiz
        ]
    },
    guardrailConfig={
        'guardrailIdentifier': 'cc-guardrail-id',
        'guardrailVersion': 'DRAFT'
    }
)
```

### 3. Tool: github-tool (Lambda)

**Responsibilities:**
- Create draft PRs
- Request reviewers
- List PR files and changes
- Query issues and labels

**Interface:**
```python
# Input schema
{
  "action": "create_pr" | "request_reviewers" | "list_files",
  "repo": "owner/repo",
  "params": {
    # Action-specific parameters
  }
}

# Output schema
{
  "success": bool,
  "data": object,
  "error": string | null
}
```

**Implementation Details:**
- Uses GitHub REST API v3 and GraphQL API v4
- Authentication via fine-grained PAT or GitHub App token
- Rate limit handling with exponential backoff
- Caches repo metadata in memory

### 4. Tool: graph-tool (Lambda)

**Responsibilities:**
- Query DynamoDB graph using adjacency list pattern
- Return graph traversal results
- Find module owners, reviewer patterns, contributor history

**Interface:**
```python
# Input schema
{
  "query_type": "find_owners" | "find_reviewers" | "find_related_issues",
  "params": {
    "module_path": "src/auth",
    "repo": "owner/repo"
  }
}

# Output schema
{
  "results": [
    {"user": "alice", "pr_count": 15, "review_count": 8}
  ],
  "execution_time_ms": 45
}
```

**Implementation Details:**
- DynamoDB tables: `cc-nodes` (PK: nodeId) and `cc-edges` (PK: fromId, SK: toId#edgeType)
- Adjacency list pattern for efficient graph queries
- GSI for reverse lookups (toId → fromId)
- Query patterns: single-hop, multi-hop with pagination
- Query timeout: 10 seconds

### 5. Tool: kb-tool (Lambda)

**Responsibilities:**
- Semantic search over documentation and code using Bedrock Knowledge Bases
- Return top-K results with scores and citations
- Retrieve relevant context for agent reasoning

**Interface:**
```python
# Input schema
{
  "query": "authentication middleware configuration",
  "topK": 5,
  "filters": {
    "repo": "owner/repo"
  }
}

# Output schema
{
  "results": [
    {
      "content": "The auth middleware is configured in...",
      "score": 0.87,
      "source": "s3://cc-docs/owner/repo/README.md",
      "url": "https://github.com/owner/repo/blob/main/README.md"
    }
  ]
}
```

**Implementation Details:**
- Bedrock Knowledge Base with S3 data source
- Titan Text Embeddings G1 (1536-dim) for automatic indexing
- RetrieveAndGenerate API for grounded responses
- S3 bucket synced nightly with repo documentation
- No manual vector management needed

### 6. Tool: qbiz-tool (Lambda)

**Responsibilities:**
- Query Amazon Q Business for documentation answers
- Return grounded responses with citations
- Fallback to search-tool if Q unavailable

**Interface:**
```python
# Input schema
{
  "question": "Where is the auth middleware configured?",
  "topK": 3
}

# Output schema
{
  "answers": [
    {
      "text": "The auth middleware is configured in...",
      "sourceUrl": "s3://cc-docs-prod/repo/CONTRIBUTING.md",
      "confidence": "HIGH"
    }
  ]
}
```

**Implementation Details:**
- Q Business Chat API via boto3 qbusiness client
- S3 data source synced nightly
- Anonymous web experience for public access
- Graceful degradation if Q not available

### 7. Ingestion Pipeline (Lambda: ingest)

**Responsibilities:**
- Fetch data from GitHub for configured repos
- Store raw JSON in S3
- Build/update DynamoDB graph (adjacency list)
- Sync documentation to S3 for Knowledge Base
- Update DynamoDB cursors

**Implementation Details:**
- Triggered by EventBridge cron (nightly 02:00 UTC)
- Reads repo list from DynamoDB `cc-repos` table
- Uses GitHub GraphQL for efficient bulk queries
- Batch writes to DynamoDB (BatchWriteItem for nodes/edges)
- Syncs docs to S3 (Knowledge Base auto-syncs)
- Checkpointing via DynamoDB `ingestCursor` field

**Pseudo-code:**
```python
def handler(event, context):
    repos = get_enabled_repos()  # DynamoDB
    for repo in repos:
        cursor = repo['ingestCursor']
        
        # Fetch from GitHub
        issues = fetch_issues_since(repo, cursor)
        prs = fetch_prs_since(repo, cursor)
        docs = fetch_docs(repo)
        
        # Store raw
        save_to_s3(issues, prs, docs)
        
        # Update graph in DynamoDB
        upsert_graph_nodes(issues, prs)  # cc-nodes table
        upsert_graph_edges(issues, prs)  # cc-edges table
        
        # Sync docs to Knowledge Base S3 bucket
        sync_docs_to_kb(docs)
        
        # Update cursor
        update_cursor(repo, new_cursor)
```

## Data Models

### DynamoDB Graph Schema (Adjacency List Pattern)

**Table: cc-nodes**
```
Partition Key: nodeId (String) - Format: "{type}#{id}"
Attributes:
  - nodeType (String): "repo" | "module" | "user" | "issue" | "pr" | "file" | "label"
  - data (Map): Type-specific properties
  
Examples:
  - nodeId: "repo#owner/repo", data: {name, owner, url, topics, stars}
  - nodeId: "user#alice", data: {login, url, avatarUrl}
  - nodeId: "issue#owner/repo#123", data: {number, title, body, labels, state, createdAt, url}
  - nodeId: "pr#owner/repo#456", data: {number, title, body, status, createdAt, mergedAt, url}
```

**Table: cc-edges**
```
Partition Key: fromId (String) - Source node ID
Sort Key: toId#edgeType (String) - Format: "{targetNodeId}#{relationshipType}"
Attributes:
  - edgeType (String): "AUTHORED" | "REVIEWED" | "TOUCHES" | "FIXES" | "HAS_LABEL" | "OWNS" | "IN_REPO"
  - properties (Map): Edge-specific properties (e.g., timestamp, additions, deletions)
  
GSI: ReverseEdgeIndex
  - Partition Key: toId
  - Sort Key: fromId#edgeType
  - For reverse traversals (e.g., find all PRs that touch a file)
```

**Example Queries:**
```python
# Find module owners (users who authored PRs touching module files)
# 1. Query cc-edges: fromId = "module#src/auth" AND edgeType = "OWNS"
# 2. For each file, query GSI: toId = fileId AND edgeType = "TOUCHES"
# 3. For each PR, query cc-edges: fromId = prId AND edgeType = "AUTHORED"
# 4. Aggregate user counts

# Find good-first issues
# Query cc-nodes with filter: nodeType = "issue" AND data.labels contains "good-first-issue"
# (Use Scan with filter or maintain GSI on labels)

# Find likely reviewers for a module
# 1. Query cc-edges: fromId = "module#src/auth" AND edgeType = "OWNS"
# 2. For each file, query GSI: toId = fileId AND edgeType = "TOUCHES"
# 3. For each PR, query GSI: toId = prId AND edgeType = "REVIEWED"
# 4. Aggregate reviewer counts
```

### Bedrock Knowledge Base

**Data Source:** S3 bucket `cc-kb-docs-{env}`

**Document Structure:**
```
s3://cc-kb-docs-prod/
  {org}/
    {repo}/
      README.md
      CONTRIBUTING.md
      docs/
        *.md
      issues/
        issue-{number}.txt
      prs/
        pr-{number}-comments.txt
```

**Configuration:**
- Embedding Model: Titan Text Embeddings G1 (1536 dimensions)
- Chunking Strategy: Default (300 tokens with 20% overlap)
- Vector Store: Managed by Bedrock (no manual setup)
- Sync: Automatic on S3 changes or manual trigger

**Document Types:**
- Repository documentation (README, CONTRIBUTING, docs/)
- Issue descriptions and comments
- PR descriptions and review comments
- Code snippets with context

### DynamoDB Tables

**Table: cc-agent-sessions**
```
Partition Key: sessionId (String)
Sort Key: ts (String, ISO 8601)
Attributes:
  - toolName (String)
  - request (Map)
  - response (Map)
  - latencyMs (Number)
  - status (String: "success"|"error")
```

**Table: cc-repos**
```
Partition Key: org (String)
Sort Key: repo (String)
Attributes:
  - enabled (Boolean)
  - topics (List<String>)
  - minStars (Number)
  - ingestCursor (String, ISO 8601)
  - lastIngestAt (String, ISO 8601)
  - ingestStatus (String: "success"|"error")
```

**Table: cc-nodes** (see Graph Schema above)

**Table: cc-edges** (see Graph Schema above)

### S3 Bucket Layouts

**Bucket: cc-raw-{env}**
```
s3://cc-raw-prod/
  github/
    {org}/
      {repo}/
        issues/
          YYYY/MM/DD/
            issue-{number}.json
        pulls/
          YYYY/MM/DD/
            pr-{number}.json
            pr-{number}-files.json
```

**Bucket: cc-kb-docs-{env}** (Knowledge Base data source)
```
s3://cc-kb-docs-prod/
  {org}/
    {repo}/
      README.md
      CONTRIBUTING.md
      docs/
        *.md
      issues/
        issue-{number}.txt
      prs/
        pr-{number}-comments.txt
```

**Bucket: cc-web-{env}**
```
s3://cc-web-prod/
  index.html
  assets/
    *.js
    *.css
  favicon.ico
```

## Error Handling

### Agent-Level Errors

**Tool Invocation Failures:**
- Agent receives error response from tool
- Agent can retry with modified parameters
- Agent can choose alternative tool
- Agent explains error to user in natural language

**Guardrails Violations:**
- Input filtered: Agent receives sanitized input
- Output filtered: Agent regenerates response
- Logged to CloudWatch for review

**Model Errors (throttling, timeouts):**
- Exponential backoff with jitter
- Fallback to cached responses if available
- User-friendly error message

### Tool-Level Errors

**GitHub API Errors:**
- Rate limit: Return error with retry-after header
- 404: Return "resource not found" with suggestion
- Auth failure: Log and alert, return generic error to user

**DynamoDB Query Errors:**
- Throttling: Exponential backoff with jitter
- Timeout: Set 10s limit, return partial results
- Conditional check failure: Retry with updated data

**Knowledge Base Errors:**
- Sync in progress: Return cached results or wait
- Query timeout: Reduce topK and retry
- No results: Return empty array with suggestion

**Q Business Errors:**
- Service unavailable: Fallback to search-tool
- No results: Return empty array
- Auth error: Check IAM policy, log alert

### Ingestion Errors

**GitHub Fetch Failures:**
- Network error: Retry 3 times with backoff
- Rate limit: Sleep until reset, resume
- Repo deleted: Mark disabled in DynamoDB

**Data Store Write Failures:**
- S3: Retry with exponential backoff
- Neptune: Rollback transaction, log error
- OpenSearch: Retry bulk operation with smaller batch
- DynamoDB: Use conditional writes to avoid conflicts

### Logging Strategy

**CloudWatch Log Groups:**
- `/aws/lambda/cc-agent-proxy` - Agent orchestration logs
- `/aws/lambda/cc-github-tool` - GitHub API interactions
- `/aws/lambda/cc-graph-tool` - DynamoDB graph queries
- `/aws/lambda/cc-kb-tool` - Knowledge Base queries
- `/aws/lambda/cc-qbiz-tool` - Q Business interactions
- `/aws/lambda/cc-ingest` - Ingestion pipeline logs

**Structured Logging Format:**
```json
{
  "timestamp": "2025-10-18T12:34:56.789Z",
  "level": "INFO",
  "component": "github-tool",
  "action": "create_pr",
  "repo": "owner/repo",
  "duration_ms": 234,
  "status": "success",
  "metadata": {}
}
```

**Metrics (CloudWatch Metrics):**
- Tool invocation count (by tool, status)
- Tool latency (p50, p99)
- Agent response time
- Ingestion success/failure rate
- GitHub API rate limit remaining

## Testing Strategy

### Unit Testing

**Lambda Functions:**
- Mock AWS SDK calls (boto3)
- Test tool input validation
- Test error handling paths
- Test data transformations
- Test DynamoDB graph query logic

**Frontend Components:**
- React Testing Library for UI components
- Mock API responses
- Test API key handling
- Test streaming response handling

### Integration Testing

**Tool Integration:**
- Test against real DynamoDB/Knowledge Bases/Q instances (dev environment)
- Verify query correctness
- Test error scenarios (timeouts, invalid queries)

**Agent Integration:**
- Test tool orchestration with Bedrock Converse API
- Verify multi-turn conversations
- Test guardrails activation

**GitHub Integration:**
- Test against test repositories
- Verify PR creation, reviewer requests
- Test rate limit handling

### End-to-End Testing

**User Flows:**
1. Sign in → Ask for issue recommendations → Receive list
2. Select issue → Request PR draft → Verify PR created on GitHub
3. Ask documentation question → Receive answer with citations

**Ingestion Flow:**
- Trigger manual ingestion → Verify data in S3/Neptune/OpenSearch
- Check cursor updates in DynamoDB

### Performance Testing

**Load Testing:**
- Simulate 100 concurrent users
- Measure API Gateway → Lambda → Bedrock latency
- Verify auto-scaling of Lambda functions

**Query Performance:**
- DynamoDB: Measure query time for graph traversals
- Knowledge Bases: Measure retrieval latency
- Target: p99 < 2 seconds for tool calls

### Security Testing

**Authentication:**
- Test JWT validation
- Test expired token handling
- Test unauthorized access attempts

**IAM Policies:**
- Verify least-privilege access
- Test cross-service permissions
- Audit CloudTrail logs

**Data Access:**
- Test DynamoDB IAM policies
- Verify S3 bucket policies (no public access)
- Test Knowledge Base access permissions

## Deployment Architecture

### Environments

**Development (dev):**
- Single region (us-east-1)
- DynamoDB on-demand pricing
- Knowledge Base with minimal documents
- Simple API key: "dev-key-12345"
- GitHub test repositories

**Production (prod):**
- Single region (us-east-1)
- DynamoDB on-demand or provisioned (based on usage)
- Knowledge Base with full documentation
- Secure API key stored in Secrets Manager
- Real open-source repositories

### Infrastructure as Code

**Recommended for Hackathon: Manual AWS Console Deployment**
- Fastest setup for prototyping
- No IaC learning curve
- Easy to iterate and debug
- Cost-effective for single deployment

**Alternative Options (if needed):**
- AWS SAM for serverless-focused deployments
- AWS CloudFormation templates (YAML/JSON)
- Terraform for multi-cloud compatibility

**Key Infrastructure Components:**
```
- Data: DynamoDB tables (4 tables), S3 buckets (3 buckets)
- AI/ML: Bedrock (Nova, Knowledge Bases, Guardrails), Q Business
- Compute: Lambda functions (5 functions), API Gateway HTTP API
- Frontend: S3, CloudFront, OAC
- Monitoring: CloudWatch dashboards, alarms
- Scheduling: EventBridge rules
```

**Deployment Steps (Console):**
1. Create DynamoDB tables (cc-nodes, cc-edges, cc-repos, cc-agent-sessions)
2. Create S3 buckets (cc-raw, cc-kb-docs, cc-web)
3. Set up Bedrock Knowledge Base pointing to cc-kb-docs bucket
4. Create Lambda functions with Python 3.13 runtime
5. Create API Gateway HTTP API with API key requirement
6. Set up CloudFront distribution with S3 origin
7. Create EventBridge rule for nightly ingestion
8. Configure Q Business application (optional, adds cost)
9. Deploy frontend to S3 and invalidate CloudFront cache

**Estimated Setup Time:** 2-3 hours for manual console deployment

### CI/CD Pipeline

**GitHub Actions Workflow:**
1. Code push → Run tests
2. Build Lambda deployment packages
3. Build frontend (Vite)
4. Generate infrastructure templates (CloudFormation/Terraform)
5. Deploy to dev environment
6. Run integration tests
7. Manual approval for prod
8. Deploy to prod
9. Invalidate CloudFront cache

## Security Considerations

### Authentication & Authorization

- Simple API key authentication (x-api-key header)
- API key stored in AWS Secrets Manager (production)
- API Gateway validates API key on all requests
- For hackathon: hardcoded key in Lambda environment variable
- Future: Upgrade to Cognito for multi-user support

### Data Encryption

- S3: SSE-S3 encryption at rest (default)
- DynamoDB: Encryption at rest with AWS managed keys (default)
- Knowledge Bases: Encryption managed by Bedrock
- Q Business: Encryption at rest and in transit

### Network Security

- Lambda functions in VPC (optional, for Neptune access)
- Security groups restrict Neptune/OpenSearch access
- CloudFront with OAC prevents direct S3 access
- API Gateway with throttling (1000 req/sec)

### Secrets Management

- GitHub token stored in AWS Secrets Manager
- Rotated every 90 days
- Lambda retrieves at runtime (cached)

### IAM Least Privilege

**Lambda Execution Role:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ],
      "Resource": "arn:aws:bedrock:*::foundation-model/amazon.nova-*"
    },
    {
      "Effect": "Allow",
      "Action": ["aoss:APIAccessAll"],
      "Resource": "arn:aws:aoss:*:*:collection/cc-vector-*"
    },
    {
      "Effect": "Allow",
      "Action": ["neptune-db:connect"],
      "Resource": "arn:aws:neptune-db:*:*:cluster-*/database/*"
    }
  ]
}
```

## Scalability Considerations

### Lambda Concurrency

- Reserved concurrency per function (e.g., 100 for agent-proxy)
- Provisioned concurrency for low-latency tools (optional)
- Auto-scaling based on invocation rate

### Neptune Serverless

- Auto-scales NCUs (Neptune Capacity Units) based on load
- Min: 2.5 NCUs, Max: 128 NCUs
- Read replicas for query scaling (if needed)

### OpenSearch Serverless

- Auto-scales OCUs (OpenSearch Capacity Units)
- Vector collection optimized for KNN queries
- Index sharding for large datasets

### API Gateway

- Throttling: 1000 req/sec per account
- Burst: 2000 requests
- CloudFront caching for static assets (1 hour TTL)

### Cost Optimization

- Lambda: Use ARM64 (Graviton2) for 20% cost savings
- Neptune: Serverless pricing (pay per NCU-hour)
- OpenSearch: Serverless pricing (pay per OCU-hour)
- S3: Lifecycle policies (transition to Glacier after 90 days)
- CloudWatch: Log retention 7 days for debug logs, 30 days for audit logs

## Monitoring and Observability

### CloudWatch Dashboards

**Agent Performance Dashboard:**
- Agent response time (p50, p99)
- Tool invocation count by tool
- Error rate by component
- Guardrails activation count

**Ingestion Dashboard:**
- Ingestion success/failure rate
- Records processed per run
- GitHub API rate limit remaining
- Data store write latency

### Alarms

**Critical Alarms (PagerDuty):**
- Agent error rate > 5%
- Ingestion failure 2 consecutive runs
- Neptune connection errors
- OpenSearch query failures > 10%

**Warning Alarms (Email):**
- Lambda throttling
- GitHub API rate limit < 100 remaining
- DynamoDB read/write capacity > 80%

### Tracing

**AWS X-Ray:**
- Trace agent requests end-to-end
- Identify slow tool calls
- Visualize service map

## Future Enhancements

### Phase 2 Features

1. **Multi-Repository Recommendations:** Compare issues across multiple repos
2. **Skill Profiling:** Learn user skills from past contributions
3. **PR Success Prediction:** ML model to predict PR acceptance probability
4. **Automated Code Generation:** Generate code snippets for issue fixes
5. **Slack/Discord Integration:** Notify users in their preferred channels

### Technical Improvements

1. **GraphQL API:** Replace REST with GraphQL for flexible queries
2. **WebSocket Support:** Real-time updates for agent responses
3. **Multi-Region Deployment:** Global latency reduction
4. **Advanced Caching:** Redis for frequently accessed data
5. **A/B Testing Framework:** Test different agent prompts and tool configurations
  