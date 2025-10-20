# Implementation Plan: Scrape ALL Contributors

## Overview
Update the ingestion Lambda to fetch ALL contributors from a repository instead of limiting to the top 50. This will provide a complete contributor graph for better analysis and insights.

## Current State
- The ingest Lambda currently fetches up to 100 contributors via `per_page=100` parameter
- Only processes the first 50 contributors: `for contributor in contributors[:50]`
- Single API call approach (no pagination)

## Target State
- Fetch ALL contributors using GitHub API pagination
- Handle repositories with 100+ contributors (like Roo-Code with 257 contributors)
- Implement proper pagination with Link headers
- Add rate limiting protection between pages
- Update statistics tracking

## Implementation Steps

### 1. Update `github_request` Function to Support Pagination
**File:** `lambda/ingest/lambda_function.py`

**Changes:**
- Add optional `paginate` parameter to `github_request` function
- Parse GitHub's `Link` header to detect next page
- Return list of all results when pagination is enabled
- Add delay between paginated requests (0.5 seconds)

**Pseudocode:**
```python
def github_request(url: str, token: str, params: Optional[Dict] = None, paginate: bool = False) -> Dict | List:
    if not paginate:
        # Current single-request logic
        return response.json()
    
    # Pagination logic
    all_results = []
    current_url = url
    
    while current_url:
        response = requests.get(current_url, headers=headers, params=params)
        
        if response.status_code == 200:
            data = response.json()
            all_results.extend(data if isinstance(data, list) else [data])
            
            # Check for next page in Link header
            link_header = response.headers.get('Link', '')
            current_url = parse_next_link(link_header)
            
            if current_url:
                time.sleep(0.5)  # Rate limiting
        else:
            # Handle errors (rate limit, 404, etc.)
            break
    
    return all_results
```

### 2. Add Helper Function to Parse Link Headers
**File:** `lambda/ingest/lambda_function.py`

**Changes:**
- Create new function `parse_next_link(link_header: str) -> Optional[str]`
- Parse GitHub's Link header format: `<url>; rel="next"`
- Return next URL or None if no more pages

**Example:**
```python
def parse_next_link(link_header: str) -> Optional[str]:
    """
    Parse GitHub Link header to find next page URL
    Example: '<https://api.github.com/repos/...?page=2>; rel="next"'
    """
    if not link_header:
        return None
    
    links = link_header.split(',')
    for link in links:
        if 'rel="next"' in link:
            # Extract URL between < and >
            url = link[link.find('<')+1:link.find('>')]
            return url
    
    return None
```

### 3. Update Contributor Fetching Logic
**File:** `lambda/ingest/lambda_function.py`
**Function:** `ingest_repository`

**Changes:**
- Remove the `[:50]` slice that limits contributors
- Use paginated `github_request` call
- Add progress logging every 50 contributors
- Filter bots BEFORE processing (not just 'User' type check)
- Add small delay every 10 contributors to avoid rate limits

**Current Code (lines ~168-195):**
```python
contributors_url = f"https://api.github.com/repos/{org}/{repo}/contributors"
contributors = github_request(contributors_url, token, {'per_page': 100})

if isinstance(contributors, list):
    for contributor in contributors[:50]:  # Top 50 contributors
        user_login = contributor.get('login')
        if not user_login or contributor.get('type') != 'User':
            continue
```

**New Code:**
```python
contributors_url = f"https://api.github.com/repos/{org}/{repo}/contributors"
print(f"Fetching ALL contributors (this may take a while)...")
contributors = github_request(contributors_url, token, {'per_page': 100}, paginate=True)

if isinstance(contributors, list):
    print(f"Found {len(contributors)} total contributors")
    
    contributor_count = 0
    for contributor in contributors:  # ALL contributors
        user_login = contributor.get('login')
        
        # Skip bots and invalid users
        if not user_login or contributor.get('type') != 'User':
            continue
        
        contributor_count += 1
        
        # Progress logging every 50 contributors
        if contributor_count % 50 == 0:
            print(f"  Processed {contributor_count} contributors...")
        
        # Rate limiting every 10 contributors
        if contributor_count % 10 == 0:
            time.sleep(0.3)
```

### 4. Update Statistics Tracking
**File:** `lambda/ingest/lambda_function.py`

**Changes:**
- Track total contributors found vs processed
- Add `bots_skipped` counter to stats
- Update final logging to show complete numbers

**Example:**
```python
stats = {
    'contributors': 0,
    'contributors_total': 0,  # NEW: Total found
    'bots_skipped': 0,        # NEW: Bots filtered out
    'issues': 0,
    'prs': 0,
    'users': 0,
    'files': 0,
    'errors': []
}
```

### 5. Update Architecture Documentation
**File:** `ARCHITECTURE.md`

**Changes:**
- Update "Contributors" section to reflect ALL contributors are fetched
- Remove "Top 50 contributors" limit mention
- Add pagination details
- Update API call count estimates

**Sections to Update:**
- Line ~90: "Processes top 50 contributors" → "Processes ALL contributors"
- Line ~95: "Limits: Top 50 contributors" → "Limits: ALL contributors (paginated)"
- Line ~420: Update total API calls calculation
- Line ~421: Update total nodes estimate

### 6. Add Error Handling for Large Repositories
**File:** `lambda/ingest/lambda_function.py`

**Changes:**
- Add timeout protection (max 5 minutes for contributors)
- Add max contributor limit as safety (e.g., 1000 contributors)
- Log warning if hitting limits

**Example:**
```python
MAX_CONTRIBUTORS = 1000  # Safety limit
CONTRIBUTOR_TIMEOUT = 300  # 5 minutes

start_time = time.time()

for contributor in contributors:
    # Check timeout
    if time.time() - start_time > CONTRIBUTOR_TIMEOUT:
        print(f"⚠️ Contributor processing timeout after {contributor_count} contributors")
        stats['errors'].append(f"Timeout after {contributor_count} contributors")
        break
    
    # Check max limit
    if contributor_count >= MAX_CONTRIBUTORS:
        print(f"⚠️ Reached max contributor limit ({MAX_CONTRIBUTORS})")
        stats['errors'].append(f"Max contributor limit reached")
        break
```

## Testing Plan

### Unit Tests
1. Test `parse_next_link` with various Link header formats
2. Test `github_request` pagination with mock responses
3. Test contributor filtering (bots vs users)

### Integration Tests
1. Test with small repo (< 100 contributors)
2. Test with medium repo (100-300 contributors) - Use RooCodeInc/Roo-Code
3. Test with large repo (500+ contributors) - Use facebook/react
4. Test rate limit handling
5. Test timeout protection

### Manual Testing
1. Deploy to dev environment
2. Trigger ingestion for RooCodeInc/Roo-Code
3. Verify all 257 contributors are scraped
4. Check CloudWatch logs for progress messages
5. Query DynamoDB to confirm all contributor nodes exist
6. Verify S3 backup contains all data

## Rollback Plan
If issues occur:
1. Revert to previous Lambda code (git checkout)
2. Redeploy using `fix-and-redeploy.ps1`
3. Previous limit of 50 contributors will be restored

## Performance Impact

### API Calls
- **Before:** 1 API call per repository (100 contributors max)
- **After:** ~3 API calls for RooCodeInc/Roo-Code (257 contributors)
- **Impact:** Minimal - still well under 5,000/hour limit

### Execution Time
- **Before:** ~2-3 minutes per repository
- **After:** ~3-5 minutes per repository (extra 1-2 minutes for pagination)
- **Impact:** Acceptable - Lambda timeout is 15 minutes

### DynamoDB Writes
- **Before:** ~50 contributor nodes + 50 edges per repo
- **After:** ~257 contributor nodes + 257 edges for RooCodeInc/Roo-Code
- **Impact:** Minimal - DynamoDB on-demand handles this easily

### Cost Impact
- **Lambda:** +$0.0001 per execution (negligible)
- **DynamoDB:** +$0.001 per repository (negligible)
- **Total:** < $0.01 per day

## Success Criteria
- [ ] All contributors from RooCodeInc/Roo-Code are scraped (257 expected)
- [ ] Pagination works correctly for repos with 100+ contributors
- [ ] Rate limiting prevents API throttling
- [ ] Execution completes within Lambda timeout (15 min)
- [ ] CloudWatch logs show progress updates
- [ ] DynamoDB contains all contributor nodes
- [ ] Architecture documentation is updated

## Timeline
- Implementation: 30 minutes
- Testing: 20 minutes
- Documentation: 10 minutes
- **Total:** ~1 hour

## Dependencies
- ✅ GitHub API token with sufficient rate limit (5,000/hour) - **ALREADY CONFIGURED**
  - Token stored in AWS Secrets Manager: `cc-github-token`
  - Retrieved via `get_github_token()` function
  - Passed to all `github_request()` calls
  - Fallback to `GITHUB_TOKEN` environment variable if Secrets Manager fails
- ✅ Lambda timeout set to 15 minutes - **ALREADY CONFIGURED**
- ✅ DynamoDB on-demand capacity - **ALREADY ENABLED**

## Notes
- The example code uses PyGithub library, but our Lambda uses `requests` directly
- We'll implement pagination manually using Link headers (GitHub API standard)
- Bot filtering is important - repos like Roo-Code have bots like `github-actions[bot]`, `renovate[bot]`
- Progress logging helps monitor long-running operations in CloudWatch
