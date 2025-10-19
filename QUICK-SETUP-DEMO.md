# Quick Setup for Demo - RooCodeInc/Roo-Code Only

This guide sets up ContribConnect to scrape only RooCodeInc/Roo-Code to avoid GitHub API rate limits.

## Step 1: Configure Repositories

Disable large repos and enable only Roo-Code:

```powershell
.\infrastructure\scripts\configure-repos-for-demo.ps1 -Environment dev
```

This will:
- ✓ Enable RooCodeInc/Roo-Code
- ✗ Disable facebook/react (too many contributors)
- ✗ Disable microsoft/vscode (too many contributors)

## Step 2: Deploy Updated Ingest Lambda

```powershell
.\lambda\redeploy-ingest.ps1 -Environment dev
```

## Step 3: Trigger Ingestion

Scrape RooCodeInc/Roo-Code data:

```powershell
aws lambda invoke --function-name cc-ingest-dev --region us-east-1 response.json
Get-Content response.json | ConvertFrom-Json | ConvertTo-Json -Depth 10
```

**Expected output:**
```json
{
  "message": "Ingestion complete",
  "results": [
    {
      "repo": "RooCodeInc/Roo-Code",
      "status": "success",
      "stats": {
        "contributors": 15,
        "prs": 30,
        "issues": 25,
        "files": 100
      }
    }
  ]
}
```

## Step 4: Verify Data in DynamoDB

Check that contributor data was scraped:

```powershell
# Check for contributor nodes
aws dynamodb scan --table-name cc-nodes-dev --filter-expression "nodeType = :type" --expression-attribute-values '{":type":{"S":"user"}}' --max-items 5 --region us-east-1

# Check for CONTRIBUTES_TO edges
aws dynamodb scan --table-name cc-edges-dev --filter-expression "edgeType = :type" --expression-attribute-values '{":type":{"S":"CONTRIBUTES_TO"}}' --max-items 5 --region us-east-1
```

## Step 5: Test Locally

```powershell
cd frontend
npm run dev
```

Visit http://localhost:5173

You should see:
- Only RooCodeInc/Roo-Code in the repository list
- Click on it to see the contributor graph
- Ask AI: "Who are the top contributors?"

## Step 6: Deploy Frontend

Once everything works locally:

```powershell
cd frontend
npm run build
.\deploy.ps1
```

## API Rate Limits

### GitHub API Limits
- **Authenticated**: 5,000 requests/hour
- **Unauthenticated**: 60 requests/hour

### Estimated API Calls for Roo-Code
- Repository info: 1 call
- Contributors: 1 call
- Pull requests: 1 call
- PR files (30 PRs × 1 call): 30 calls
- Issues: 1 call
- **Total**: ~35 calls

This leaves plenty of room for multiple ingestion runs!

### For Large Repos (facebook/react)
- Contributors: 1 call (but 1000+ contributors)
- Pull requests: 1 call (but 10000+ PRs)
- PR files (50 PRs × 1 call): 50 calls
- **Total**: ~100+ calls per ingestion

## Monitoring API Usage

Check remaining rate limit:

```powershell
# Get your GitHub token
$token = "your-github-token"

# Check rate limit
$headers = @{
    "Authorization" = "token $token"
    "Accept" = "application/vnd.github.v3+json"
}

Invoke-RestMethod -Uri "https://api.github.com/rate_limit" -Headers $headers | ConvertTo-Json -Depth 10
```

**Output:**
```json
{
  "rate": {
    "limit": 5000,
    "remaining": 4965,
    "reset": 1729350000
  }
}
```

## Adding More Repositories Later

When you want to add more repos:

```powershell
# Enable a repository
.\infrastructure\scripts\manage-repositories.ps1 -Action enable -Owner "owner" -Repo "repo" -Environment dev

# Or add a new one
.\infrastructure\scripts\manage-repositories.ps1 -Action add -Owner "owner" -Repo "repo" -Environment dev
```

## Troubleshooting

### Issue: Rate limit exceeded

**Solution:** Wait for rate limit to reset (shown in `reset` timestamp) or use a different GitHub token.

### Issue: No data in graph

**Solution:** 
1. Check ingestion completed successfully
2. Verify DynamoDB has data
3. Check CloudWatch logs for errors

```powershell
aws logs tail /aws/lambda/cc-ingest-dev --follow
```

### Issue: Contributors not showing

**Solution:** Make sure you deployed the updated ingest Lambda:

```powershell
.\lambda\redeploy-ingest.ps1 -Environment dev
```

## Cost Estimate

For RooCodeInc/Roo-Code only:
- **DynamoDB**: ~$0.01/month (minimal reads/writes)
- **S3**: ~$0.01/month (small data storage)
- **Lambda**: Free tier (< 1M requests)
- **GitHub API**: Free (within rate limits)

**Total**: < $1/month

## Next Steps

1. ✅ Configure repos (only Roo-Code)
2. ✅ Deploy updated Lambda
3. ✅ Trigger ingestion
4. ✅ Verify data
5. ✅ Test locally
6. ✅ Deploy frontend
7. 🎉 Demo ready!
