# Requirements Document

## Introduction

ContribConnect is an AI-powered agent system that helps developers discover good-first issues in open-source repositories and draft pull requests that are likely to pass review. The system continuously ingests repository signals (issues, PRs, CODEOWNERS, labels, files), builds a knowledge graph and vector index, and uses Amazon Bedrock AgentCore with Nova models to provide intelligent recommendations and automated PR drafting capabilities.

The system addresses the challenge of OSS onboarding by combining graph-based relationship analysis, vector search for semantic matching, and agentic workflows to guide developers toward meaningful contributions with high acceptance probability.

## Requirements

### Requirement 1: User Authentication and Authorization

**User Story:** As a developer, I want to securely sign in to ContribConnect so that I can access personalized recommendations and manage my contributions.

#### Acceptance Criteria

1. WHEN a user visits the application THEN the system SHALL present a sign-in interface using Amazon Cognito
2. WHEN a user completes authentication THEN the system SHALL issue JWT tokens for API access
3. IF a user is not authenticated THEN the system SHALL redirect them to the Cognito Hosted UI
4. WHEN a user's session expires THEN the system SHALL prompt for re-authentication
5. WHEN a user signs in THEN the system SHALL support optional GitHub OIDC integration for social login

### Requirement 2: Repository Data Ingestion

**User Story:** As the system, I want to continuously ingest repository data from GitHub so that I can maintain up-to-date knowledge about issues, PRs, and code structure.

#### Acceptance Criteria

1. WHEN the nightly schedule triggers THEN the system SHALL fetch issues, PRs, files, and metadata from configured GitHub repositories
2. WHEN fetching GitHub data THEN the system SHALL store raw JSON payloads in S3 with organized date-based paths
3. WHEN processing repository data THEN the system SHALL extract relationships between users, modules, files, issues, and PRs
4. WHEN ingestion completes THEN the system SHALL update DynamoDB cursors to track ingestion progress
5. IF GitHub API rate limits are reached THEN the system SHALL handle errors gracefully and resume on next schedule
6. WHEN new data is ingested THEN the system SHALL update both the Neptune knowledge graph and OpenSearch vector index

### Requirement 3: Knowledge Graph Construction

**User Story:** As the system, I want to build and maintain a property graph of repository relationships so that I can understand contributor patterns and module ownership.

#### Acceptance Criteria

1. WHEN ingesting repository data THEN the system SHALL create nodes for Repo, Module, User, Issue, PR, File, and Label entities
2. WHEN processing PRs THEN the system SHALL create edges representing AUTHORED, REVIEWED, TOUCHES, FIXES, HAS_LABEL, OWNS, and IN_REPO relationships
3. WHEN storing graph data THEN the system SHALL use Neptune Serverless with openCypher query language
4. WHEN updating the graph THEN the system SHALL use MERGE operations to avoid duplicate nodes
5. WHEN querying the graph THEN the system SHALL support openCypher queries via HTTPS endpoint

### Requirement 4: Vector Search Index

**User Story:** As the system, I want to maintain a vector index of documentation and code changes so that I can perform semantic similarity searches.

#### Acceptance Criteria

1. WHEN ingesting documentation THEN the system SHALL chunk docs, READMEs, issues, and PR comments into searchable segments
2. WHEN creating embeddings THEN the system SHALL use Amazon Titan Text Embeddings (v2 with 1024 dimensions or G1 with 1536 dimensions)
3. WHEN storing vectors THEN the system SHALL index them in OpenSearch Serverless with vector search collection type
4. WHEN performing searches THEN the system SHALL return top-K results with relevance scores
5. WHEN indexing documents THEN the system SHALL store metadata including repo, type, title, body, URL, and timestamp

### Requirement 5: AI Agent with Tool Use

**User Story:** As a developer, I want to interact with an AI agent that can reason about repositories and execute actions so that I can get intelligent recommendations and automated assistance.

#### Acceptance Criteria

1. WHEN a user submits a query THEN the system SHALL process it using Amazon Bedrock AgentCore with Nova models via Converse API
2. WHEN the agent needs information THEN the system SHALL invoke appropriate tools (search, graph, GitHub, Q Business)
3. WHEN the agent generates responses THEN the system SHALL apply Bedrock Guardrails for safety filtering
4. WHEN tool calls are made THEN the system SHALL execute them via Lambda functions and return structured results
5. WHEN the agent completes reasoning THEN the system SHALL return a coherent response with citations and action links

### Requirement 6: Issue Discovery and Recommendation

**User Story:** As a developer, I want to discover good-first issues that match my skills and interests so that I can make meaningful contributions to open-source projects.

#### Acceptance Criteria

1. WHEN a user requests issue recommendations THEN the system SHALL query the knowledge graph for issues with appropriate labels
2. WHEN filtering issues THEN the system SHALL consider module ownership, contributor history, and issue complexity
3. WHEN ranking issues THEN the system SHALL use vector similarity to match user skills and interests
4. WHEN presenting issues THEN the system SHALL include title, description, labels, repository, and estimated difficulty
5. WHEN an issue is recommended THEN the system SHALL explain why it's a good match based on graph and vector analysis

### Requirement 7: Automated PR Drafting

**User Story:** As a developer, I want the agent to draft a pull request for me so that I can quickly start contributing with proper structure and context.

#### Acceptance Criteria

1. WHEN a user selects an issue to work on THEN the system SHALL generate a PR plan with proposed changes
2. WHEN drafting a PR THEN the system SHALL use the GitHub API to create a draft pull request
3. WHEN creating a PR THEN the system SHALL include a descriptive title, body with context, and reference to the issue
4. WHEN a PR is created THEN the system SHALL suggest appropriate reviewers based on module ownership and review history
5. WHEN requesting reviewers THEN the system SHALL use the GitHub API to add them to the PR

### Requirement 8: Documentation Retrieval with Amazon Q Business

**User Story:** As a developer, I want the agent to answer questions about repository documentation so that I can understand project conventions and architecture.

#### Acceptance Criteria

1. WHEN a user asks a documentation question THEN the system SHALL query Amazon Q Business with the question
2. WHEN Q Business returns results THEN the system SHALL include citations with source URLs
3. WHEN repository docs are updated THEN the system SHALL sync them to the Q Business S3 data source
4. WHEN presenting answers THEN the system SHALL ground responses in actual documentation content
5. IF Q Business is not available THEN the system SHALL fall back to OpenSearch vector search

### Requirement 9: Static Web Application

**User Story:** As a developer, I want to access ContribConnect through a web interface so that I can interact with the agent and view recommendations.

#### Acceptance Criteria

1. WHEN a user navigates to the application URL THEN the system SHALL serve a React/Vite SPA via CloudFront
2. WHEN serving static assets THEN the system SHALL use S3 with Origin Access Control (OAC) for security
3. WHEN the user interacts with the agent THEN the system SHALL stream responses in real-time
4. WHEN making API calls THEN the system SHALL include the user's JWT token in the Authorization header
5. WHEN the frontend is updated THEN the system SHALL invalidate CloudFront cache

### Requirement 10: API Gateway and Lambda Integration

**User Story:** As the system, I want to expose secure API endpoints so that the frontend can communicate with backend services.

#### Acceptance Criteria

1. WHEN the frontend makes requests THEN the system SHALL route them through API Gateway HTTP API
2. WHEN API Gateway receives a request THEN the system SHALL validate the JWT token from Cognito
3. WHEN routing to tools THEN the system SHALL invoke appropriate Lambda functions (agent-proxy, github-tool, graph-tool, search-tool, qbiz-tool)
4. WHEN Lambda functions execute THEN the system SHALL return structured JSON responses
5. WHEN errors occur THEN the system SHALL return appropriate HTTP status codes and error messages

### Requirement 11: Scheduled Ingestion and Autonomy

**User Story:** As the system, I want to automatically refresh repository data on a schedule so that recommendations stay current without manual intervention.

#### Acceptance Criteria

1. WHEN the schedule is configured THEN the system SHALL trigger ingestion Lambda nightly at 02:00 UTC via EventBridge
2. WHEN ingestion runs THEN the system SHALL process all enabled repositories from the DynamoDB repo list
3. WHEN ingestion completes THEN the system SHALL log success/failure metrics to DynamoDB
4. IF ingestion fails THEN the system SHALL retry with exponential backoff
5. WHEN new repositories are added THEN the system SHALL include them in the next scheduled ingestion

### Requirement 12: Agent Memory and Logging

**User Story:** As the system, I want to maintain session history and tool invocation logs so that I can provide context-aware responses and enable debugging.

#### Acceptance Criteria

1. WHEN a user starts a session THEN the system SHALL create a session record in DynamoDB
2. WHEN tools are invoked THEN the system SHALL log the tool name, request, response, and latency
3. WHEN the agent reasons THEN the system SHALL maintain conversation context across multiple turns
4. WHEN querying session history THEN the system SHALL retrieve logs by sessionId and timestamp
5. WHEN sessions expire THEN the system SHALL archive or delete old session data based on retention policy

### Requirement 13: Security and Access Control

**User Story:** As a system administrator, I want proper IAM roles and security policies so that services can communicate securely with least-privilege access.

#### Acceptance Criteria

1. WHEN Lambda functions execute THEN the system SHALL use IAM roles with scoped permissions for Bedrock, Neptune, OpenSearch, DynamoDB, SES, and GitHub
2. WHEN accessing OpenSearch Serverless THEN the system SHALL enforce encryption, network, and data access policies
3. WHEN accessing Neptune THEN the system SHALL use SigV4 authentication
4. WHEN storing sensitive data THEN the system SHALL use encryption at rest and in transit
5. WHEN handling user tokens THEN the system SHALL validate JWT signatures and expiration

### Requirement 14: Optional Email Notifications

**User Story:** As a developer, I want to receive email notifications about matching issues so that I can stay informed without constantly checking the application.

#### Acceptance Criteria

1. WHEN new matching issues are found THEN the system SHALL optionally send email notifications via Amazon SES
2. WHEN sending emails THEN the system SHALL use a verified sender domain
3. WHEN SES is in sandbox mode THEN the system SHALL only send to verified recipients
4. WHEN production access is granted THEN the system SHALL send to any recipient
5. WHEN users opt out THEN the system SHALL respect their notification preferences
