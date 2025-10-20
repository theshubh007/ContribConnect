# ContribConnect Architecture

## System Overview

ContribConnect is a GitHub repository analysis platform that builds a knowledge graph of contributors, pull requests, issues, and code files to help identify experts and facilitate collaboration.

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Frontend (React)                         │
│                    Hosted on S3 + CloudFront                     │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             │ HTTPS
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                      API Gateway (REST)                          │
└────────────┬────────────────────────────┬────────────────────────┘
             │                            │
             │                            │
             ▼                            ▼
┌────────────────────────┐   ┌────────────────────────────────────┐
│   Agent Proxy Lambda   │   │      Graph Tool Lambda             │
│   (AI Chat Interface)  │   │   (Query Graph Database)           │
└────────────┬───────────┘   └────────────┬───────────────────────┘
             │                            │
             │                            │
             ▼                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    DynamoDB Graph Database                       │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │ Nodes Table  │  │ Edges Table  │  │ Repos Table  │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
└─────────────────────────────────────────────────────────────────┘
                             ▲
                             │
                             │ Writes Data
                             │
┌─────────────────────────────────────────────────────────────────┐
│                      Ingest Lambda                               │
│              (Scheduled via EventBridge)                         │
│                                                                  │
│  Fetches data from GitHub API and populates graph database      │
└────────────┬────────────────────────────────────────────────────┘
             │
             │ GitHub API Calls
             ▼
┌─────────────────────────────────────────────────────────────────┐
│                         GitHub API                               │
│                    (api.github.com)                              │
└─────────────────────────────────────────────────────────────────┘
```

---

## Data Ingestion Pipeline (Ingest Lambda)

### **Purpose**
The Ingest Lambda is the core data collection component that scrapes GitHub repositories and builds a knowledge graph in DynamoDB.

### **Trigger**
- Scheduled execution via AWS EventBridge (e.g., daily)
- Manual invocation via AWS Lambda console or CLI
- API Gateway endpoint (for on-demand ingestion)

### **Data Sources**
- GitHub REST API v3
- Authenticated with GitHub Personal Access Token (stored in AWS Secrets Manager)

---

## Detailed Scraping Logic

The Ingest Lambda (`lambda/ingest/lambda_function.py`) orchestrates all data collection from GitHub. Here's exactly what happens:

### **Execution Flow**

1. **Initialization**
   - Retrieves GitHub token from AWS Secrets Manager (`cc-github-token`)
   - Queries `cc-repos-dev` table for enabled repositories
   - Processes up to 5 repositories per run (hackathon limit)

2. **Per-Repository Processing**
   - Each repository is processed sequentially
   - Raw data is backed up to S3 at `github/{org}/{repo}/{type}/{date}/`
   - Statistics tracked: contributors, PRs, issues, files, errors

3. **Error Handling**
   - Rate limit detection with automatic retry and backoff
   - 404 errors logged but don't stop processing
   - Failed repositories marked with error status in repos table

---

### **1. Repository Information**

**API Endpoint:** `GET /repos/{owner}/{repo}`

**Data Collected:**
```json
{
  "name": "Roo-Code",
  "owner": "RooCodeInc",
  "url": "https://github.com/RooCodeInc/Roo-Code",
  "description": "AI-powered code assistant",
  "stars": 1234,
  "topics": ["ai", "code-assistant", "vscode"],
  "language": "TypeScript"
}
```

**Processing:**
- Creates a single `repo` node in DynamoDB
- Extracts metadata: name, owner, description, stars, topics, language
- Saves raw response to S3: `github/{org}/{repo}/repo/{date}/repo.json`

**Graph Structure:**
- **Node Type:** `repo`
- **Node ID:** `repo#RooCodeInc/Roo-Code`
- **Purpose:** Central node representing the repository

---

### **2. Contributors (MOST IMPORTANT)**

**API Endpoint:** `GET /repos/{owner}/{repo}/contributors?per_page=100`

**Data Collected:**
```json
{
  "login": "sebmarkbage",
  "html_url": "https://github.com/sebmarkbage",
  "avatar_url": "https://avatars.githubusercontent.com/u/...",
  "contributions": 14,
  "type": "User"
}
```

**Processing:**
- Fetches ALL contributors using GitHub API pagination (100 per page)
- Filters to only `type: "User"` (excludes bots like `github-actions[bot]`, `renovate[bot]`)
- Processes ALL contributors (with safety limit of 1000 max)
- Creates one `user` node per contributor
- Creates one `CONTRIBUTES_TO` edge per contributor → repo relationship
- Stores contribution count in edge properties
- Progress logging every 50 contributors
- Rate limiting: 0.3 second delay every 10 contributors
- Timeout protection: 5 minutes max for contributor processing

**Limits:** ALL contributors (paginated), max 1000 per repository (safety limit)

**Graph Structure:**
- **Node Type:** `user`
- **Node ID:** `user#sebmarkbage`
- **Edge:** `user#sebmarkbage` --[CONTRIBUTES_TO]--> `repo#RooCodeInc/Roo-Code`
- **Edge Properties:** `{contributions: 14}`

**Purpose:** 
- Identifies key contributors
- Powers "Who are the top contributors?" queries
- Enables contributor network visualization

**Why This Matters:**
This is the foundation of the contributor graph. The contribution count determines who the "experts" are for a repository.

---

### **3. Pull Requests**

**API Endpoint:** `GET /repos/{owner}/{repo}/pulls?state=all&per_page=50`

**Data Collected:**
```json
{
  "number": 123,
  "title": "Add new feature",
  "body": "Description of changes...",
  "state": "open",
  "merged": false,
  "created_at": "2025-01-15T10:30:00Z",
  "html_url": "https://github.com/RooCodeInc/Roo-Code/pull/123",
  "additions": 150,
  "deletions": 45,
  "user": {
    "login": "sebmarkbage",
    "html_url": "https://github.com/sebmarkbage",
    "avatar_url": "..."
  }
}
```

**Processing:**
- Fetches up to 50 PRs (all states: open, closed, merged)
- Processes 30 most recent PRs
- For each PR:
  1. Creates `pull_request` node with metadata
  2. Truncates body to 500 characters (for storage efficiency)
  3. Creates or updates `user` node for PR author
  4. Creates `AUTHORED` edge from user to PR
  5. Creates `IN_REPO` edge from PR to repository
  6. Triggers file fetching (see next section)
  7. Saves raw PR data to S3: `github/{org}/{repo}/prs/{date}/pr-{number}.json`
  8. Sleeps 0.5 seconds between PRs (rate limiting)

**Error Handling:**
- Skips PRs with missing user data
- Logs warnings for PRs without login information
- Continues processing remaining PRs on individual failures

**Limits:** 30 most recent PRs per repository

**Graph Structure:**
- **Node Type:** `pull_request`
- **Node ID:** `pr#RooCodeInc/Roo-Code#123`
- **Edges:**
  - `user#sebmarkbage` --[AUTHORED]--> `pr#RooCodeInc/Roo-Code#123`
  - `pr#RooCodeInc/Roo-Code#123` --[IN_REPO]--> `repo#RooCodeInc/Roo-Code`

**Purpose:**
- Tracks contribution activity
- Identifies PR authors
- Links PRs to files they modify
- Provides context for code changes (additions/deletions)

---

### **4. PR Files (Code Ownership)**

**API Endpoint:** `GET /repos/{owner}/{repo}/pulls/{pr_number}/files?per_page=20`

**Data Collected:**
```json
{
  "filename": "src/components/Button.tsx",
  "status": "modified",
  "additions": 25,
  "deletions": 10,
  "changes": 35
}
```

**Processing:**
- Called for each PR processed in step 3
- Fetches up to 20 files per PR
- Processes top 10 most changed files
- For each file:
  1. Creates `file` node with path and directory
  2. Extracts directory from path (e.g., `src/components` from `src/components/Button.tsx`)
  3. Creates `TOUCHES` edge from PR to file
  4. Stores additions/deletions in edge properties
- 0.5 second delay between PR file requests (rate limiting)

**Limits:** 10 files per PR (top 10 changed files)

**Graph Structure:**
- **Node Type:** `file`
- **Node ID:** `file#RooCodeInc/Roo-Code#src/components/Button.tsx`
- **Edge:** `pr#RooCodeInc/Roo-Code#123` --[TOUCHES]--> `file#RooCodeInc/Roo-Code#src/components/Button.tsx`
- **Edge Properties:** `{additions: 25, deletions: 10}`

**Purpose:**
- **Code Ownership:** Identifies which contributors work on which files
- **Expert Identification:** "Who should review changes to Button.tsx?"
- **Area Expertise:** Maps contributors to code areas

**Graph Traversal for Expertise:**
```
user → AUTHORED → PR → TOUCHES → file
```
This path allows queries like: "Find all users who have authored PRs that touch file X"

---

### **5. Issues**

**API Endpoint:** `GET /repos/{owner}/{repo}/issues?state=all&per_page=50`

**Data Collected:**
```json
{
  "number": 456,
  "title": "Bug: App crashes on startup",
  "body": "Steps to reproduce...",
  "state": "open",
  "labels": [
    {"name": "bug", "color": "d73a4a"},
    {"name": "good first issue", "color": "7057ff"}
  ],
  "created_at": "2025-01-20T14:00:00Z",
  "html_url": "https://github.com/RooCodeInc/Roo-Code/issues/456",
  "comments": 5,
  "user": {
    "login": "gaearon",
    "html_url": "https://github.com/gaearon"
  }
}
```

**Processing:**
- Fetches up to 50 issues (all states: open, closed)
- **Important:** Filters out pull requests (GitHub's issues endpoint includes PRs)
- Processes 30 most recent issues
- For each issue:
  1. Skips if `pull_request` field exists (it's a PR, not an issue)
  2. Creates `issue` node with metadata
  3. Truncates body to 500 characters
  4. Extracts label names into array
  5. Creates or updates `user` node for issue author
  6. Creates `AUTHORED` edge from user to issue
  7. Creates `IN_REPO` edge from issue to repository
  8. Processes labels (see next section)
  9. Saves raw issue data to S3: `github/{org}/{repo}/issues/{date}/issue-{number}.json`

**Error Handling:**
- Skips issues with missing user data
- Continues processing on individual failures

**Limits:** 30 most recent issues (excludes PRs)

**Graph Structure:**
- **Node Type:** `issue`
- **Node ID:** `issue#RooCodeInc/Roo-Code#456`
- **Edges:**
  - `user#gaearon` --[AUTHORED]--> `issue#RooCodeInc/Roo-Code#456`
  - `issue#RooCodeInc/Roo-Code#456` --[IN_REPO]--> `repo#RooCodeInc/Roo-Code`
  - `issue#RooCodeInc/Roo-Code#456` --[HAS_LABEL]--> `label#RooCodeInc/Roo-Code#bug`

**Purpose:**
- Identifies issue reporters
- Tracks "good first issue" labels for onboarding
- Links issues to relevant contributors
- Provides comment count for engagement metrics

---

### **6. Labels**

**Extracted from Issues** (no separate API call)

**Data Collected:**
```json
{
  "name": "good first issue",
  "color": "7057ff"
}
```

**Processing:**
- Extracted from each issue's `labels` array
- For each label on an issue:
  1. Creates `label` node with name and color
  2. Creates `HAS_LABEL` edge from issue to label
- No separate API call needed (embedded in issue data)

**Graph Structure:**
- **Node Type:** `label`
- **Node ID:** `label#RooCodeInc/Roo-Code#good first issue`
- **Edge:** `issue#RooCodeInc/Roo-Code#456` --[HAS_LABEL]--> `label#RooCodeInc/Roo-Code#good first issue`

**Purpose:**
- Powers "Find good first issues" queries
- Categorizes issues by type (bug, feature, documentation)
- Enables filtering by label in graph queries

**Common Labels Tracked:**
- `good first issue` - Beginner-friendly issues
- `bug` - Bug reports
- `enhancement` - Feature requests
- `documentation` - Documentation improvements
- `help wanted` - Issues seeking contributors

---

## Graph Database Schema

### **Nodes Table** (`cc-nodes-dev`)

| Field | Type | Description |
|-------|------|-------------|
| `nodeId` | String (PK) | Unique identifier (e.g., `user#sebmarkbage`) |
| `nodeType` | String | Type: `repo`, `user`, `pull_request`, `issue`, `file`, `label` |
| `data` | Map | Node-specific data (JSON object) |
| `updatedAt` | String | ISO 8601 timestamp |

**Example Node:**
```json
{
  "nodeId": "user#sebmarkbage",
  "nodeType": "user",
  "data": {
    "login": "sebmarkbage",
    "url": "https://github.com/sebmarkbage",
    "avatarUrl": "https://avatars.githubusercontent.com/u/...",
    "contributions": 14,
    "type": "maintainer"
  },
  "updatedAt": "2025-10-20T00:49:19Z"
}
```

---

### **Edges Table** (`cc-edges-dev`)

| Field | Type | Description |
|-------|------|-------------|
| `fromId` | String (PK) | Source node ID |
| `toIdEdgeType` | String (SK) | Composite: `{toId}#{edgeType}` |
| `toId` | String (GSI PK) | Destination node ID |
| `fromIdEdgeType` | String | Composite: `{fromId}#{edgeType}` |
| `edgeType` | String | Relationship type |
| `properties` | Map | Edge-specific data |
| `updatedAt` | String | ISO 8601 timestamp |

**Edge Types:**
- `CONTRIBUTES_TO` - User → Repository
- `AUTHORED` - User → PR/Issue
- `IN_REPO` - PR/Issue → Repository
- `TOUCHES` - PR → File
- `HAS_LABEL` - Issue → Label

**Example Edge:**
```json
{
  "fromId": "user#sebmarkbage",
  "toIdEdgeType": "repo#RooCodeInc/Roo-Code#CONTRIBUTES_TO",
  "toId": "repo#RooCodeInc/Roo-Code",
  "fromIdEdgeType": "user#sebmarkbage#CONTRIBUTES_TO",
  "edgeType": "CONTRIBUTES_TO",
  "properties": {
    "contributions": 14
  },
  "updatedAt": "2025-10-20T00:49:19Z"
}
```

---

### **Repos Table** (`cc-repos-dev`)

| Field | Type | Description |
|-------|------|-------------|
| `org` | String (PK) | Organization/owner name |
| `repo` | String (SK) | Repository name |
| `enabled` | Boolean | Whether to ingest this repo |
| `topics` | List | Repository topics/tags |
| `minStars` | Number | Minimum stars filter |
| `description` | String | Repository description |
| `stars` | Number | Star count |
| `language` | String | Primary language |
| `ingestCursor` | String | Last ingestion timestamp |
| `lastIngestAt` | String | Last successful ingestion |
| `ingestStatus` | String | Status: `pending`, `success`, `error` |

---

## Complete Data Flow Summary

### **What Gets Scraped (In Order)**

For each enabled repository in `cc-repos-dev`:

1. **Repository Metadata** (1 API call)
   - Basic info: name, description, stars, topics, language
   - Creates: 1 `repo` node

2. **Contributors** (1-10 API calls, paginated)
   - ALL contributors with contribution counts (paginated, 100 per page)
   - Example: RooCodeInc/Roo-Code has 257 contributors = 3 API calls
   - Creates: Up to 1000 `user` nodes + 1000 `CONTRIBUTES_TO` edges (safety limit)

3. **Pull Requests** (1 API call + 30 nested calls)
   - 30 most recent PRs (all states)
   - Creates: Up to 30 `pull_request` nodes + 30 `AUTHORED` edges + 30 `IN_REPO` edges
   - For each PR: Fetches files (see below)

4. **PR Files** (30 API calls, 1 per PR)
   - Top 10 files per PR
   - Creates: Up to 300 `file` nodes + 300 `TOUCHES` edges

5. **Issues** (1 API call)
   - 30 most recent issues (excludes PRs)
   - Creates: Up to 30 `issue` nodes + 30 `AUTHORED` edges + 30 `IN_REPO` edges

6. **Labels** (extracted from issues, no API call)
   - All labels from processed issues
   - Creates: Variable `label` nodes + `HAS_LABEL` edges

**Total API Calls per Repository:** ~35-40 calls (varies by contributor count)
**Total Nodes Created:** ~661 nodes for RooCodeInc/Roo-Code (1 repo + 257 users + 30 PRs + 300 files + 30 issues + labels)
**Total Edges Created:** ~647 edges (257 CONTRIBUTES_TO + 30 AUTHORED + 30 IN_REPO + 300 TOUCHES + 30 HAS_LABEL)

---

## Data Flow

### **Ingestion Flow**

```
1. EventBridge Trigger (Scheduled)
        ↓
2. Ingest Lambda Starts
        ↓
3. Fetch GitHub Token from Secrets Manager
        ↓
4. Query Repos Table for enabled repositories
        ↓
5. For each repository (up to 5):
   ├─ Fetch Repository Info → Create repo node
   ├─ Fetch Contributors → Create user nodes + CONTRIBUTES_TO edges
   ├─ Fetch Pull Requests → Create PR nodes + AUTHORED edges
   │  └─ For each PR:
   │     └─ Fetch PR Files → Create file nodes + TOUCHES edges
   ├─ Fetch Issues → Create issue nodes + AUTHORED edges
   │  └─ Extract Labels → Create label nodes + HAS_LABEL edges
   └─ Update Repos Table with ingestion status
        ↓
6. Save raw data to S3 (backup)
        ↓
7. Return ingestion statistics
```

**Execution Time:** ~2-5 minutes per repository (depending on API rate limits)
**S3 Storage:** Raw JSON responses saved to `github/{org}/{repo}/{type}/{date}/`

### **Query Flow**

```
1. User asks question in Frontend
        ↓
2. Frontend → API Gateway → Agent Proxy Lambda
        ↓
3. Agent Proxy Lambda:
   ├─ Parses user intent
   ├─ Calls Graph Tool Lambda to query DynamoDB
   └─ Sends context to Amazon Bedrock (Claude)
        ↓
4. Graph Tool Lambda:
   ├─ Queries Nodes Table
   ├─ Queries Edges Table (with GSI for reverse lookups)
   └─ Returns graph data
        ↓
5. Bedrock generates natural language response
        ↓
6. Response streamed back to Frontend
```

---

## Implementation Details

### **Key Functions in `lambda/ingest/lambda_function.py`**

1. **`get_github_token()`**
   - Retrieves token from AWS Secrets Manager
   - Falls back to environment variable if Secrets Manager fails
   - Returns empty string if no token found

2. **`github_request(url, token, params)`**
   - Wrapper for all GitHub API calls
   - Handles authentication headers
   - Implements retry logic (max 3 attempts)
   - Detects rate limiting via 403 status + "rate limit" in response
   - Waits until rate limit reset time before retrying
   - Returns empty dict on 404 (resource not found)

3. **`save_to_s3(data, key)`**
   - Backs up raw GitHub responses to S3
   - Skips if `RAW_BUCKET` environment variable not set
   - Converts datetime objects to strings for JSON serialization

4. **`upsert_node(node_id, node_type, data)`**
   - Creates or updates a node in `cc-nodes-dev` table
   - Automatically adds `updatedAt` timestamp
   - Uses `put_item` (overwrites existing nodes)

5. **`upsert_edge(from_id, to_id, edge_type, properties)`**
   - Creates or updates an edge in `cc-edges-dev` table
   - Creates composite keys for efficient querying:
     - `toIdEdgeType` = `{toId}#{edgeType}` (sort key)
     - `fromIdEdgeType` = `{fromId}#{edgeType}` (for reverse lookups)
   - Stores optional properties (e.g., contribution count)

6. **`ingest_repository(org, repo, token, cursor)`**
   - Main orchestration function
   - Processes one repository completely
   - Returns statistics dict with counts and errors
   - Updates `cc-repos-dev` table with ingestion status

7. **`lambda_handler(event, context)`**
   - Entry point for Lambda execution
   - Fetches enabled repositories from `cc-repos-dev`
   - Processes up to 5 repositories
   - Returns summary of all ingestion results

---

## Rate Limiting & Constraints

### **GitHub API Limits**
- **Authenticated:** 5,000 requests/hour
- **Unauthenticated:** 60 requests/hour
- **Strategy:** Exponential backoff with retry logic
- **Rate Limit Detection:** Checks `X-RateLimit-Reset` header
- **Wait Time:** Calculated as `reset_time - current_time` (minimum 60 seconds)

### **Processing Limits** (Optimized for Performance)
- **Repositories:** 5 per ingestion run
- **Contributors:** Top 50 per repository
- **Pull Requests:** 30 most recent per repository
- **Issues:** 30 most recent per repository
- **Files per PR:** 10 most changed files
- **Delay between PR file requests:** 0.5 seconds

### **DynamoDB Limits**
- **On-Demand Billing:** No capacity planning needed
- **Item Size:** Max 400 KB per item
- **Query Performance:** Single-digit millisecond latency

---

## Data Stored in DynamoDB

### **Node Types and Their Data**

| Node Type | ID Format | Data Fields |
|-----------|-----------|-------------|
| `repo` | `repo#{org}/{repo}` | name, owner, url, description, stars, topics, language |
| `user` | `user#{login}` | login, url, avatarUrl, contributions, type |
| `pull_request` | `pr#{org}/{repo}#{number}` | number, title, body (500 chars), state, merged, createdAt, url, additions, deletions |
| `issue` | `issue#{org}/{repo}#{number}` | number, title, body (500 chars), state, labels[], createdAt, url, comments |
| `file` | `file#{org}/{repo}#{path}` | path, directory |
| `label` | `label#{org}/{repo}#{name}` | name, color |

### **Edge Types and Their Properties**

| Edge Type | From → To | Properties |
|-----------|-----------|------------|
| `CONTRIBUTES_TO` | user → repo | contributions (count) |
| `AUTHORED` | user → pr/issue | createdAt (timestamp) |
| `IN_REPO` | pr/issue → repo | (none) |
| `TOUCHES` | pr → file | additions (count), deletions (count) |
| `HAS_LABEL` | issue → label | (none) |

### **Example Graph Queries Enabled**

1. **"Who are the top contributors to repo X?"**
   ```
   Query: Find all edges WHERE edgeType = "CONTRIBUTES_TO" AND toId = "repo#X"
   Sort by: properties.contributions DESC
   ```

2. **"Who should review changes to file Y?"**
   ```
   Query: Find all PRs that TOUCH file Y
   Then: Find all users who AUTHORED those PRs
   Rank by: Number of PRs + total additions/deletions
   ```

3. **"Find good first issues in repo X"**
   ```
   Query: Find all issues IN_REPO X that HAS_LABEL "good first issue"
   Filter by: state = "open"
   ```

---

## What's NOT Being Scraped

To keep the system focused and performant, we intentionally exclude:

- ❌ Commit history (only contributor counts)
- ❌ Code content/diffs (only file paths)
- ❌ PR/Issue comments (only comment counts)
- ❌ Code reviews and review comments
- ❌ Repository forks
- ❌ Stargazers/watchers lists
- ❌ Releases/tags
- ❌ GitHub Actions workflows
- ❌ Wiki content
- ❌ Project boards
- ❌ Discussions
- ❌ Commit messages
- ❌ Branch information
- ❌ Repository settings/permissions

**Why?** These would require significantly more API calls and storage, while providing diminishing returns for the core use case of contributor discovery and code ownership.

---

## Use Cases Enabled

### **1. Contributor Discovery**
- "Who are the top contributors?"
- "Who are the maintainers?"
- Visualize contributor network

### **2. Code Ownership**
- "Who should review changes to file X?"
- "Who is the expert on component Y?"
- Identify file owners by PR history

### **3. Onboarding**
- "Find good first issues"
- "Who can mentor new contributors?"
- Identify approachable maintainers

### **4. Issue Routing**
- "Who should I assign this bug to?"
- "Who works on the authentication module?"
- Route issues to relevant experts

### **5. Collaboration**
- "Who has worked with contributor X?"
- "Find contributors who work on similar areas"
- Build contributor relationships

---

## Security & Privacy

### **Authentication**
- GitHub token stored in AWS Secrets Manager
- Token rotation supported via Lambda
- Least-privilege IAM roles

### **Data Access**
- Only public repository data is accessed
- No private code or sensitive data stored
- Respects GitHub API terms of service

### **Compliance**
- No PII stored beyond public GitHub profiles
- Data retention: 90 days (configurable)
- GDPR-compliant data deletion on request

---

## Performance Optimization

### **Caching Strategy**
- DynamoDB serves as the cache layer
- Data refreshed daily (configurable)
- Stale data acceptable for contributor graphs

### **Query Optimization**
- GSI on Edges Table for reverse lookups
- Composite keys for efficient range queries
- Batch operations for bulk writes

### **Cost Optimization**
- On-demand DynamoDB billing
- S3 Intelligent-Tiering for raw data
- Lambda with ARM64 (Graviton2) for cost savings

---

## Monitoring & Observability

### **Metrics**
- Ingestion success/failure rate
- GitHub API rate limit usage
- DynamoDB read/write capacity
- Lambda execution duration

### **Logging**
- CloudWatch Logs for all Lambda functions
- Structured logging with correlation IDs
- Error tracking with stack traces

### **Alerts**
- Ingestion failures
- GitHub API rate limit exceeded
- DynamoDB throttling
- Lambda timeout errors

---

## Future Enhancements

### **Planned Features**
- [ ] Commit history analysis
- [ ] PR review patterns
- [ ] Contributor sentiment analysis
- [ ] Multi-repository contributor tracking
- [ ] Real-time ingestion via GitHub webhooks
- [ ] ML-based reviewer recommendations

### **Scalability**
- Horizontal scaling via SQS for parallel ingestion
- Multi-region DynamoDB global tables
- CDN caching for frontend assets

---

## Technology Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **Frontend** | React + Vite + Tailwind CSS | User interface |
| **API** | AWS API Gateway | REST API endpoints |
| **Compute** | AWS Lambda (Python 3.12) | Serverless functions |
| **Database** | DynamoDB | Graph database |
| **Storage** | S3 | Raw data backup |
| **Secrets** | AWS Secrets Manager | GitHub token storage |
| **AI** | Amazon Bedrock (Claude) | Natural language processing |
| **Scheduling** | EventBridge | Periodic ingestion |
| **CDN** | CloudFront | Frontend distribution |

---

## Deployment

### **Infrastructure as Code**
- CloudFormation templates
- PowerShell deployment scripts
- Environment-based configuration (dev/prod)

### **CI/CD**
- Manual deployment via scripts
- Lambda function packaging with dependencies
- Frontend build and S3 sync

### **Environments**
- **Development:** `cc-*-dev` resources
- **Production:** `cc-*-prod` resources (future)

---

## Conclusion

ContribConnect's architecture is designed for:
- **Scalability:** Serverless components scale automatically
- **Performance:** DynamoDB provides fast graph queries
- **Cost-Efficiency:** Pay-per-use pricing model
- **Maintainability:** Clear separation of concerns
- **Extensibility:** Easy to add new data sources

The ingestion pipeline focuses on the most valuable data (contributors, PRs, files) to build a knowledge graph that powers intelligent contributor discovery and code ownership insights.
