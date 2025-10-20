# Implementation Plan: Scrape ALL Pull Requests with Full Details

## Overview
Integrate comprehensive PR scraping into the ingestion Lambda to fetch ALL PRs with comments, reviews, files, and contributor details while managing GitHub API rate limits efficiently.

## Current State Analysis

### Current PR Scraping (Limited):
- Fetches only **30 PRs** (out of 50 requested)
- **1 API call** for PR list
- **30 API calls** for PR files (1 per PR)
- **Total: ~31 API calls per repo**
- **Data:** Basic PR info + top 10 files per PR
- **Missing:** Comments, reviews, reviewers, labels, all files

### Proposed PR Scraping (Comprehensive):
- Fetch **ALL PRs** (paginated)
- For each PR:
  - PR details (already have)
  - Comments (1 API call)
  - Review comments (1 API call)
  - Reviews (1 API call)
  - Files (1 API call)
  - Labels, assignees, reviewers (included in PR details)
- **Total: ~4-5 API calls per PR**

### API Rate Limit Analysis:
- **GitHub API Limit:** 5,000 requests/hour (authenticated)
- **Current Usage:** ~35 calls per repo (3 contributors pages + 1 PR list + 31 PR files)
- **Proposed Usage:** ~4-5 calls per PR × number of PRs

**Example for RooCodeInc/Roo-Code:**
- Assume 500 PRs total
- 500 PRs × 5 calls = **2,500 API calls**
- **Time:** ~25 minutes (with rate limiting)
- **Fits within:** 5,000/hour limit ✅

---

## Implementation Strategy

### Phase 1: Separate Ingestion Jobs
Create **two separate ingestion modes** to manage rate limits:

1. **Contributor Ingestion** (Fast - runs daily)
   - Scrapes ALL contributors
   - Scrapes basic repo info
   - **~3-5 API calls per repo**
   - **Time:** 1-2 minutes

2. **PR Ingestion** (Slow - runs weekly or on-demand)
   - Scrapes ALL PRs with full details
   - Comments, reviews, files
   - **~2,500 API calls per repo**
   - **Time:** 20-30 minutes

### Phase 2: Incremental PR Updates
- Track last PR scraped (cursor/timestamp)
- Only fetch new/updated PRs since last run
- Reduces API calls by 90% after initial scrape

---

## Detailed Implementation Plan

### 1. Add Ingestion Mode Parameter

**File:** `lambda/ingest/lambda_function.py`

Add mode parameter to control what gets scraped:

```python
def ingest_repository(org: str, repo: str, token: str, cursor: str, mode: str = 'contributors') -> Dict:
    """
    Ingest data for a single repository
    
    Args:
        mode: 'contributors' | 'prs' | 'full'
            - contributors: Only scrape contributors (fast)
            - prs: Only scrape PRs with full details (slow)
            - full: Scrape everything (very slow)
    """
```

### 2. Implement Comprehensive PR Scraping

**New Function:** `scrape_pull_requests_comprehensive()`

```python
def scrape_pull_requests_comprehensive(org: str, repo: str, token: str, repo_id: str) -> Dict:
    """
    Scrape ALL pull requests with full details
    
    Returns:
        stats: {
            'prs_total': int,
            'prs_processed': int,
            'comments': int,
            'reviews': int,
            'files': int,
            'api_calls': int
        }
    """
```

**Data to Scrape:**

1. **PR Basic Info** (from list API)
   - number, title, body, state, merged, draft
   - created_at, updated_at, closed_at, merged_at
   - author, merged_by
   - base_branch, head_branch
   - additions, deletions, changed_files, commits
   - labels, assignees, requested_reviewers, milestone

2. **PR Comments** (issue comments)
   - author, body, created_at, url

3. **PR Review Comments** (code comments)
   - author, body, path, line, position, created_at

4. **PR Reviews**
   - reviewer, state (APPROVED/CHANGES_REQUESTED/COMMENTED)
   - body, submitted_at

5. **PR Files**
   - filename, status, additions, deletions, patch

### 3. Update DynamoDB Schema

**New Node Types:**

```python
# PR Comment Node
{
    'nodeId': 'comment#org/repo#pr#123#comment#456',
    'nodeType': 'pr_comment',
    'data': {
        'pr_number': 123,
        'comment_id': 456,
        'author': 'username',
        'body': 'comment text',
        'created_at': '2025-01-15T10:30:00Z',
        'url': 'https://github.com/...'
    }
}

# PR Review Node
{
    'nodeId': 'review#org/repo#pr#123#review#789',
    'nodeType': 'pr_review',
    'data': {
        'pr_number': 123,
        'review_id': 789,
        'reviewer': 'username',
        'state': 'APPROVED',
        'body': 'LGTM',
        'submitted_at': '2025-01-15T11:00:00Z'
    }
}
```

**New Edge Types:**

```python
# User → Comment: COMMENTED
# User → Review: REVIEWED
# Comment → PR: ON_PR
# Review → PR: REVIEWS_PR
# User → PR: REQUESTED_REVIEW (for requested reviewers)
# User → PR: ASSIGNED (for assignees)
```

### 4. Implement Pagination for PRs

```python
def fetch_all_prs_paginated(org: str, repo: str, token: str) -> List[Dict]:
    """
    Fetch ALL PRs using pagination
    
    Returns list of all PRs (could be 500+)
    """
    all_prs = []
    page = 1
    per_page = 100
    
    while True:
        url = f"https://api.github.com/repos/{org}/{repo}/pulls"
        params = {
            'state': 'all',
            'per_page': per_page,
            'page': page,
            'sort': 'created',
            'direction': 'desc'
        }
        
        prs = github_request(url, token, params)
        
        if not prs or len(prs) == 0:
            break
            
        all_prs.extend(prs)
        print(f"  Fetched page {page}: {len(prs)} PRs (total: {len(all_prs)})")
        
        if len(prs) < per_page:
            break
            
        page += 1
        time.sleep(0.5)  # Rate limiting
    
    return all_prs
```

### 5. Implement Rate Limit Management

```python
def check_rate_limit(token: str) -> Dict:
    """Check remaining GitHub API rate limit"""
    headers = {
        'Authorization': f'token {token}',
        'Accept': 'application/vnd.github.v3+json'
    }
    response = requests.get('https://api.github.com/rate_limit', headers=headers)
    data = response.json()
    
    remaining = data['resources']['core']['remaining']
    limit = data['resources']['core']['limit']
    reset_time = data['resources']['core']['reset']
    
    return {
        'remaining': remaining,
        'limit': limit,
        'reset_time': reset_time,
        'percentage': (remaining / limit) * 100
    }

def wait_if_rate_limited(token: str, min_remaining: int = 100):
    """Wait if rate limit is too low"""
    rate_limit = check_rate_limit(token)
    
    if rate_limit['remaining'] < min_remaining:
        wait_time = rate_limit['reset_time'] - int(time.time())
        print(f"⚠️ Rate limit low ({rate_limit['remaining']} remaining)")
        print(f"   Waiting {wait_time} seconds until reset...")
        time.sleep(wait_time + 10)
```

### 6. Implement Incremental Updates

**Track Last Scrape:**

```python
# Store in repos table
{
    'org': 'RooCodeInc',
    'repo': 'Roo-Code',
    'lastPRScrape': '2025-10-19T00:00:00Z',
    'lastPRNumber': 1234,
    'totalPRsScraped': 500
}

# Only fetch PRs updated since last scrape
def fetch_new_prs_only(org: str, repo: str, token: str, since: str) -> List[Dict]:
    """Fetch only PRs updated since last scrape"""
    params = {
        'state': 'all',
        'sort': 'updated',
        'direction': 'desc',
        'since': since  # ISO 8601 timestamp
    }
```

---

## Implementation Steps

### Step 1: Add Mode Parameter to Lambda Handler

```python
def lambda_handler(event, context):
    # Get mode from event
    mode = event.get('mode', 'contributors')  # Default to contributors only
    
    # Valid modes: 'contributors', 'prs', 'full'
    if mode not in ['contributors', 'prs', 'full']:
        return {'statusCode': 400, 'body': 'Invalid mode'}
```

### Step 2: Implement PR Scraping Function

Create new function `scrape_pull_requests_comprehensive()` with:
- Pagination for ALL PRs
- Fetch comments for each PR
- Fetch reviews for each PR
- Fetch files for each PR
- Create nodes and edges in DynamoDB
- Track API calls and rate limits

### Step 3: Update Ingestion Logic

```python
if mode in ['contributors', 'full']:
    # Scrape contributors (existing logic)
    scrape_contributors(org, repo, token, repo_id)

if mode in ['prs', 'full']:
    # Scrape PRs with full details (new logic)
    pr_stats = scrape_pull_requests_comprehensive(org, repo, token, repo_id)
```

### Step 4: Create Separate Lambda Invocations

**Contributor Ingestion (Daily):**
```bash
aws lambda invoke \
  --function-name cc-ingest-dev \
  --payload '{"mode":"contributors"}' \
  response.json
```

**PR Ingestion (Weekly):**
```bash
aws lambda invoke \
  --function-name cc-ingest-dev \
  --payload '{"mode":"prs"}' \
  response.json
```

### Step 5: Update Lambda Timeout

Current: 5 minutes (300 seconds)
Needed: 15 minutes (900 seconds) for PR scraping

```bash
aws lambda update-function-configuration \
  --function-name cc-ingest-dev \
  --timeout 900
```

---

## API Call Estimation

### For RooCodeInc/Roo-Code (Example):

**Assumptions:**
- 500 total PRs
- Average 5 comments per PR
- Average 3 reviews per PR
- Average 10 files per PR

**API Calls:**
1. PR list (paginated): 5 calls (100 PRs per page)
2. PR comments: 500 calls (1 per PR)
3. PR reviews: 500 calls (1 per PR)
4. PR review comments: 500 calls (1 per PR)
5. PR files: 500 calls (1 per PR)

**Total: ~2,005 API calls**

**Time:** ~20-25 minutes (with rate limiting)
**Rate Limit:** 2,005 / 5,000 = 40% of hourly limit ✅

---

## Testing Plan

### Phase 1: Test with Small Repo
- Test with repo that has < 50 PRs
- Verify all data is scraped correctly
- Check API call count

### Phase 2: Test with RooCodeInc/Roo-Code
- Run in 'prs' mode only
- Monitor API rate limit
- Verify data in DynamoDB

### Phase 3: Incremental Updates
- Run again after 1 day
- Should only fetch new/updated PRs
- Verify much fewer API calls

---

## Deployment Strategy

### Week 1: Initial Full Scrape
- Run 'contributors' mode (daily)
- Run 'prs' mode (once) - full scrape

### Week 2+: Incremental Updates
- Run 'contributors' mode (daily)
- Run 'prs' mode (weekly) - incremental only

---

## Success Criteria

- [ ] Can scrape ALL PRs (not just 30)
- [ ] Fetches comments, reviews, files for each PR
- [ ] Stays within API rate limits
- [ ] Completes within Lambda timeout (15 min)
- [ ] Creates proper nodes and edges in DynamoDB
- [ ] Supports incremental updates
- [ ] Tracks API usage and rate limits

---

## Risks & Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Rate limit exceeded | Scraping fails | Check rate limit before each batch, wait if needed |
| Lambda timeout | Incomplete scrape | Increase timeout to 15 min, implement checkpointing |
| Too much data | DynamoDB costs | Limit PR body/comments to 1000 chars |
| Slow execution | Poor UX | Run as background job, not on page load |

---

## Cost Estimation

**DynamoDB:**
- 500 PRs × 4 nodes each (PR, comments, reviews, files) = 2,000 writes
- Cost: ~$0.01 per run

**Lambda:**
- 20 minutes execution × $0.0000166667/GB-second = ~$0.02 per run

**Total:** ~$0.03 per full PR scrape

---

## Next Steps

1. Review and approve this plan
2. Implement mode parameter
3. Implement comprehensive PR scraping function
4. Test with small repo
5. Deploy and test with RooCodeInc/Roo-Code
6. Set up weekly schedule for PR scraping

