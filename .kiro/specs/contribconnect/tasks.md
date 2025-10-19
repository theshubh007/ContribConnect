# Implementation Plan

- [x] 1. Set up AWS infrastructure foundation




  - Create DynamoDB tables (cc-nodes, cc-edges, cc-repos, cc-agent-sessions) with appropriate keys and GSIs
  - Create S3 buckets (cc-raw, cc-kb-docs, cc-web) with encryption and versioning
  - Configure IAM roles for Lambda execution with least-privilege policies
  - _Requirements: 2.2, 2.4, 3.3, 10.4, 13.1, 13.4_

- [x] 2. Configure Bedrock services



  - Set up Bedrock Knowledge Base with S3 data source (cc-kb-docs bucket)
  - Configure Titan Text Embeddings G1 (1536-dim) for automatic indexing
  - Create Bedrock Guardrails for content filtering
  - Enable Nova Pro model access (us.amazon.nova-pro-v1:0)
  - _Requirements: 4.2, 4.3, 5.3, 5.5_

- [ ] 3. Set up Amazon Q Business (optional)
  - Create Q Business application with S3 data source
  - Configure anonymous web experience for public access
  - Set up data source sync schedule
  - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5_

- [x] 4. Implement data ingestion Lambda function




  - Create Lambda function (cc-ingest) with Python 3.13 runtime
  - Implement GitHub API client with GraphQL queries for issues, PRs, files, and CODEOWNERS
  - Add S3 write logic for raw JSON storage with date-based partitioning
  - Implement DynamoDB graph node creation (cc-nodes table) for Repo, Module, User, Issue, PR, File, Label entities
  - Implement DynamoDB graph edge creation (cc-edges table) for AUTHORED, REVIEWED, TOUCHES, FIXES, HAS_LABEL, OWNS, IN_REPO relationships
  - Add cursor management in DynamoDB for incremental ingestion
  - Implement Knowledge Base document sync to S3 (README, CONTRIBUTING, docs, issues, PR comments)
  - Add error handling with exponential backoff for GitHub rate limits
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 3.1, 3.2, 3.4, 4.1, 4.5_

- [ ]* 4.1 Write unit tests for ingestion logic
  - Test GitHub API client with mocked responses
  - Test S3 write operations
  - Test DynamoDB batch write operations
  - Test cursor update logic
  - _Requirements: 2.1, 2.2, 2.3, 2.4_

- [x] 5. Set up EventBridge scheduled ingestion




  - Create EventBridge rule with cron expression (nightly 02:00 UTC)
  - Configure rule to trigger cc-ingest Lambda
  - Add retry policy with exponential backoff
  - _Requirements: 11.1, 11.2, 11.4_

- [x] 6. Implement graph-tool Lambda function


  - Create Lambda function (cc-graph-tool) with Python 3.13 runtime
  - Implement DynamoDB query logic for adjacency list pattern (cc-nodes and cc-edges tables)
  - Add query handlers for find_owners (module ownership analysis)
  - Add query handlers for find_reviewers (review history analysis)
  - Add query handlers for find_related_issues (issue relationship traversal)
  - Implement GSI queries for reverse edge lookups
  - Add query timeout handling (10 seconds max)
  - Return structured JSON with results and execution time
  - _Requirements: 3.3, 3.5, 6.2, 7.4_

- [ ]* 6.1 Write unit tests for graph queries
  - Test adjacency list query patterns
  - Test GSI reverse lookups
  - Test timeout handling
  - _Requirements: 3.3, 3.5_

- [ ] 7. Implement kb-tool Lambda function
  - Create Lambda function (cc-kb-tool) with Python 3.13 runtime
  - Implement Bedrock Knowledge Base RetrieveAndGenerate API client
  - Add query handler with topK parameter and repo filters
  - Return results with content, score, source URL, and citations
  - Add error handling for sync-in-progress and timeout scenarios
  - _Requirements: 4.4, 5.2, 6.3_

- [ ] 8. Implement qbiz-tool Lambda function
  - Create Lambda function (cc-qbiz-tool) with Python 3.13 runtime
  - Implement Amazon Q Business Chat API client using boto3
  - Add question handler with topK parameter
  - Return grounded answers with citations and confidence scores
  - Implement fallback to kb-tool if Q Business unavailable
  - _Requirements: 8.1, 8.2, 8.4, 8.5_


- [x] 9. Implement github-tool Lambda function



  - Create Lambda function (cc-github-tool) with Python 3.13 runtime
  - Implement GitHub REST API v3 client for PR operations
  - Add create_pr action handler (draft PR creation with title, body, issue reference)
  - Add request_reviewers action handler (add reviewers to PR)
  - Add list_files action handler (get PR file changes)
  - Add list_issues action handler (query issues with labels)
  - Implement GitHub authentication using fine-grained PAT from Secrets Manager
  - Add rate limit handling with exponential backoff
  - _Requirements: 5.2, 6.1, 7.2, 7.3, 7.5_

- [ ]* 9.1 Write integration tests for GitHub tool
  - Test against test repositories
  - Verify PR creation
  - Test reviewer requests
  - Test rate limit handling
  - _Requirements: 7.2, 7.3, 7.5_

- [x] 10. Implement agent-proxy Lambda function




  - Create Lambda function (cc-agent-proxy) with Python 3.13 runtime
  - Implement Bedrock Converse API client with Nova Pro model
  - Define tool schemas for github-tool, graph-tool, kb-tool, qbiz-tool
  - Add tool invocation orchestration logic (parallel execution when possible)
  - Implement streaming response handling
  - Add Guardrails configuration for input/output filtering
  - Implement session management with DynamoDB (cc-agent-sessions table)
  - Add tool call logging (tool name, request, response, latency, status)
  - Add error handling for model throttling and timeouts
  - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 12.1, 12.2, 12.3_

- [ ]* 10.1 Write integration tests for agent orchestration
  - Test tool invocation with mocked tool responses
  - Test multi-turn conversations
  - Test guardrails activation
  - Test session persistence
  - _Requirements: 5.1, 5.2, 5.3, 12.3_

- [x] 11. Set up API Gateway




  - Create API Gateway HTTP API
  - Configure API key requirement for authentication
  - Create route POST /api/agent/chat → cc-agent-proxy Lambda
  - Add CORS configuration for frontend domain
  - Configure throttling (1000 req/sec)
  - Add CloudWatch logging for API requests
  - _Requirements: 10.1, 10.2, 10.3, 10.5_

- [x] 12. Implement React frontend application



  - Initialize Vite + React 18 project
  - Create chat interface component with message history
  - Implement API key authentication (localStorage storage)
  - Add API client with streaming response support (Fetch API)
  - Create issue recommendation display component
  - Create PR draft display component with GitHub links
  - Add citation display for documentation answers
  - Implement error handling and loading states
  - _Requirements: 9.1, 9.3, 9.4, 6.4, 7.1_

- [ ]* 12.1 Write frontend component tests
  - Test chat interface with React Testing Library
  - Test API key handling
  - Test streaming response handling
  - Mock API responses
  - _Requirements: 9.3, 9.4_

- [x] 13. Set up CloudFront distribution



  - Create CloudFront distribution with S3 origin (cc-web bucket)
  - Configure Origin Access Control (OAC) for S3 security
  - Set cache behavior (1 hour TTL for static assets)
  - Configure custom domain (optional)
  - Add SSL certificate (ACM)
  - _Requirements: 9.1, 9.2, 9.5_

- [x] 14. Deploy frontend to S3


  - Build React application (npm run build)
  - Upload build artifacts to cc-web S3 bucket
  - Configure S3 bucket for static website hosting
  - Set bucket policy to allow CloudFront OAC access only
  - Invalidate CloudFront cache after deployment
  - _Requirements: 9.1, 9.2, 9.5_

- [x] 15. Configure CloudWatch monitoring



  - Create CloudWatch dashboard for agent performance (response time, tool invocations, error rate)
  - Create CloudWatch dashboard for ingestion metrics (success rate, records processed, API rate limits)
  - Set up log groups for all Lambda functions with structured logging
  - Create alarms for critical errors (agent error rate > 5%, ingestion failures)
  - Create alarms for warnings (Lambda throttling, DynamoDB capacity)
  - Configure log retention policies (7 days debug, 30 days audit)
  - _Requirements: 11.3, 12.4_

- [ ]* 15.1 Set up AWS X-Ray tracing
  - Enable X-Ray for Lambda functions
  - Configure service map visualization
  - Add custom segments for tool calls
  - _Requirements: 5.4_

- [x] 16. Implement repository configuration management



  - Create DynamoDB table initialization script for cc-repos
  - Add sample repository configurations (org, repo, enabled, topics, minStars)
  - Implement Lambda function or script to add/remove repositories
  - Add validation for repository access and permissions
  - _Requirements: 2.1, 11.2, 11.5_

- [x] 17. Configure Secrets Manager



  - Store GitHub fine-grained PAT in Secrets Manager
  - Store API key for frontend authentication
  - Configure Lambda functions to retrieve secrets at runtime
  - Set up secret rotation policy (90 days for GitHub token)
  - _Requirements: 13.1, 13.5_

- [ ] 18. End-to-end integration testing
  - Test complete user flow: sign in → ask for recommendations → receive issue list
  - Test PR drafting flow: select issue → request PR draft → verify PR created on GitHub
  - Test documentation query flow: ask question → receive answer with citations
  - Test ingestion flow: trigger manual ingestion → verify data in S3/DynamoDB/Knowledge Base
  - Verify cursor updates after ingestion
  - _Requirements: 6.1, 6.4, 6.5, 7.1, 7.2, 7.3, 8.1, 8.2, 11.2, 11.3_

- [ ]* 19. Optional: Implement email notifications with SES
  - Set up Amazon SES with verified sender domain
  - Create Lambda function for email notifications
  - Implement notification preferences in DynamoDB
  - Add EventBridge rule to trigger notifications after ingestion
  - Handle SES sandbox mode restrictions
  - _Requirements: 14.1, 14.2, 14.3, 14.4, 14.5_

- [ ] 20. Performance optimization and load testing
  - Configure Lambda reserved concurrency (100 for agent-proxy)
  - Test with 100 concurrent users using load testing tool
  - Measure end-to-end latency (target p99 < 2 seconds for tool calls)
  - Optimize DynamoDB query patterns if needed
  - Configure CloudFront caching for optimal performance
  - _Requirements: 5.4, 10.4_

- [ ] 21. Security hardening
  - Review and tighten IAM policies for least-privilege access
  - Verify S3 bucket policies (no public access)
  - Test API Gateway authentication and authorization
  - Enable DynamoDB encryption at rest
  - Enable S3 encryption at rest (SSE-S3)
  - Audit CloudTrail logs for security events
  - _Requirements: 13.1, 13.2, 13.3, 13.4, 13.5_

- [ ] 22. Documentation and deployment guide
  - Create deployment guide with step-by-step AWS Console instructions
  - Document environment variables for Lambda functions
  - Create architecture diagram with service connections
  - Document API endpoints and request/response formats
  - Create troubleshooting guide for common issues
  - Document cost estimates and optimization tips
  - _Requirements: All_
