# Scraping Logic Fix

## What Was Fixed

The scraping logic has been improved to properly collect contributor data:

### Before
- Only fetched issues
- No contributor information
- No pull request data
- Missing file relationships

### After
- ✅ Fetches **contributors** with contribution counts
- ✅ Fetches **pull requests** with file changes
- ✅ Fetches **issues** (excluding PRs)
- ✅ Creates **CONTRIBUTES_TO** edges for contributors
- ✅ Creates **TOUCHES** edges for files modified in PRs
- ✅ Properly separates issues from PRs

## Deploy the Fix

### Step 1: Redeploy Ingest Lambda

```powershell
.\lambda\redeploy-ingest.ps1 -Environment dev
```

### Step 2: Redeploy Graph-Tool Lambda

```powershell
cd lambda/graph-tool
.\deploy.ps1 -Environment dev
```

### Step 3: Trigger Manual Ingestion

```powershell
# Trigger ingestion for all enabled repositories
aws lambda invoke --function-name cc-ingest-dev --region us-east-1 response.json
Get-Content response.json | ConvertFrom-Json | ConvertTo-Json -Depth 10
```

### Step 4: Verify Data

```powershell
# Check DynamoDB for contributor nodes
aws dynamodb scan --table-name cc-nodes-dev --filter-expression "nodeType = :type" --expression-attribute-values '{":type":{"S":"user"}}' --max-items 5

# Check for CONTRIBUTES_TO edges
aws dynamodb scan --table-name cc-edges-dev --filter-expression "edgeType = :type" --expression-attribute-values '{":type":{"S":"CONTRIBUTES_TO"}}' --max-items 5
```

## New Graph Query

The graph-tool Lambda now supports a new action:

### Get Top Contributors

```json
{
  "action": "get_top_contributors",
  "params": {
    "repo": "facebook/react",
    "limit": 10
  }
}
```

**Response:**
```json
{
  "repository": "facebook/react",
  "contributors": [
    {
      "userId": "user#sebmarkbage",
      "login": "sebmarkbage",
      "url": "https://github.com/sebmarkbage",
      "avatarUrl": "https://avatars.githubusercontent.com/u/...",
      "contributions": 1234
    }
  ],
  "total": 50
}
```

## Testing the Fix

### 1. Test Locally

The UI will now show proper contributor data in the graph visualization.

### 2. Test via API

```powershell
# Get contributors for a repository
$payload = '{"action":"get_top_contributors","params":{"repo":"facebook/react","limit":10}}'
$payload | Out-File -FilePath payload.json -Encoding ascii -NoNewline
aws lambda invoke --function-name cc-graph-tool-dev --payload file://payload.json response.json
Get-Content response.json | ConvertFrom-Json | ConvertTo-Json -Depth 10
```

### 3. Test in UI

1. Go to http://localhost:5173
2. Click on a repository (e.g., "facebook/react")
3. View the contributor graph - should now show actual contributors
4. Ask the AI: "Who are the top contributors?"
5. Should get a proper response with contributor names and stats

## What the AI Can Now Answer

With the improved scraping, the AI assistant can now answer:

- ✅ "Who are the top contributors?"
- ✅ "Show me contributors with more than 10 contributions"
- ✅ "Who worked on authentication files?"
- ✅ "Which contributors are most active?"
- ✅ "Find experts for the auth module"

## Monitoring

Check CloudWatch Logs for ingestion progress:

```powershell
aws logs tail /aws/lambda/cc-ingest-dev --follow
```

Look for log messages like:
```
Fetching contributors for facebook/react...
Ingested 50 contributors
Fetching pull requests for facebook/react...
Ingestion complete for facebook/react:
  - 50 contributors
  - 30 pull requests
  - 30 issues
  - 150 files
```

## Troubleshooting

### Issue: No contributors found

**Solution:** Make sure the repository has been ingested after deploying the fix.

```powershell
# Re-trigger ingestion
aws lambda invoke --function-name cc-ingest-dev response.json
```

### Issue: Graph shows no data

**Solution:** Check DynamoDB tables have data:

```powershell
# Check nodes table
aws dynamodb describe-table --table-name cc-nodes-dev --query 'Table.ItemCount'

# Check edges table
aws dynamodb describe-table --table-name cc-edges-dev --query 'Table.ItemCount'
```

### Issue: GitHub rate limit

**Solution:** The scraper now includes rate limit handling with automatic retries. Check logs:

```powershell
aws logs filter-log-events --log-group-name /aws/lambda/cc-ingest-dev --filter-pattern "rate limit"
```

## Performance

The improved scraper:
- Fetches ~50 contributors per repo
- Fetches ~30 PRs with file changes
- Fetches ~30 issues
- Total time: ~2-3 minutes per repository
- Respects GitHub rate limits (5000 requests/hour)

## Next Steps

1. Deploy the fixes
2. Trigger ingestion for your repositories
3. Test the UI locally
4. Verify contributor data appears in the graph
5. Deploy updated UI to S3

## Cost Impact

- Slightly more API calls to GitHub (within free tier limits)
- More DynamoDB writes (still minimal cost)
- Better data quality = better AI responses!
