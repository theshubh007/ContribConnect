# Next Steps: Verify ALL Contributors Scraping

## ✅ Deployment Status
- Lambda function deployed successfully
- Ingestion started in background
- Expected completion: 3-5 minutes

---

## 🔍 Step 1: Monitor Real-Time Progress (Optional)

Watch the ingestion happen in real-time:

```powershell
.\check-ingestion-progress.ps1
```

**What to look for:**
- `Fetching ALL contributors for RooCodeInc/Roo-Code (this may take a while)...`
- `Fetching page 1...`
- `Fetching page 2...`
- `Fetching page 3...`
- `Found 257 total contributors`
- `Processed 50/257 contributors...`
- `Processed 100/257 contributors...`
- `Processed 150/257 contributors...`
- `Processed 200/257 contributors...`
- `Processed 250/257 contributors...`
- `Ingested 251 contributors (6 bots skipped)`

**Press Ctrl+C to exit when done**

---

## ⏰ Step 2: Wait for Completion

The ingestion takes **3-5 minutes** for RooCodeInc/Roo-Code.

You can:
- Wait 5 minutes, then proceed to Step 3
- Or monitor CloudWatch logs in real-time (Step 1)

---

## ✅ Step 3: Verify Results (After 5 minutes)

Run the verification script:

```powershell
.\verify-contributors.ps1
```

**Expected Output:**
```
✓ Total user nodes found: 251
✓ CONTRIBUTES_TO edges for RooCodeInc/Roo-Code: 251

Sample contributors:
  - mrubens : 1854 contributions
  - saoudrizwan : 962 contributions
  - cte : 587 contributions
  - daniel-lxs : 211 contributions
  - hannesrudolph : 129 contributions
  ...

✅ SUCCESS! All contributors scraped!
```

---

## 📊 Step 4: Compare Before vs After

### Before (Top 50 only):
- Contributors scraped: **50**
- Missing: 207 contributors (80% of contributors!)

### After (ALL contributors):
- Contributors scraped: **251** (257 total - 6 bots)
- Coverage: **100%** of real contributors

### Improvement:
- **+201 contributors** (+402% increase!)
- Complete contributor graph
- Better expert identification
- More accurate code ownership

---

## 🔧 Troubleshooting

### If you see fewer than 250 contributors:

1. **Check CloudWatch Logs:**
   ```powershell
   .\check-ingestion-progress.ps1
   ```
   Look for errors or timeout messages

2. **Check for Rate Limiting:**
   - Look for "Rate limited. Waiting X seconds..." messages
   - This is normal and handled automatically

3. **Check for Timeout:**
   - Look for "⚠️ Contributor processing timeout" message
   - If found, increase timeout in Lambda settings

4. **Re-run Ingestion:**
   ```powershell
   aws lambda invoke --function-name cc-ingest-dev --region us-east-1 response.json
   ```

---

## 🎯 Step 5: Test the Graph Queries

Once verified, test that the graph queries work with all contributors:

### Query 1: Get Top Contributors
```powershell
aws dynamodb scan `
    --table-name cc-edges-dev `
    --filter-expression "edgeType = :type AND toId = :repo" `
    --expression-attribute-values '{":type":{"S":"CONTRIBUTES_TO"},":repo":{"S":"repo#RooCodeInc/Roo-Code"}}' `
    --region us-east-1
```

### Query 2: Find a Specific Contributor
```powershell
aws dynamodb get-item `
    --table-name cc-nodes-dev `
    --key '{"nodeId":{"S":"user#mrubens"}}' `
    --region us-east-1
```

### Query 3: Count All Contributors
```powershell
aws dynamodb scan `
    --table-name cc-nodes-dev `
    --filter-expression "nodeType = :type" `
    --expression-attribute-values '{":type":{"S":"user"}}' `
    --select COUNT `
    --region us-east-1
```

---

## 📈 Step 6: View in CloudWatch (Optional)

Open CloudWatch Logs in browser:
```
https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#logsV2:log-groups/log-group/$252Faws$252Flambda$252Fcc-ingest-dev
```

Look for the latest log stream and verify:
- Pagination messages (page 1, 2, 3)
- Progress updates (50, 100, 150, 200, 250)
- Final count: "Ingested 251 contributors (6 bots skipped)"

---

## 🚀 Step 7: Test with Frontend (Optional)

If you have the frontend deployed, test queries like:
- "Who are the top contributors to Roo-Code?"
- "Show me all contributors with more than 10 contributions"
- "Who should review changes to the authentication module?"

The AI should now have access to ALL 251 contributors instead of just 50!

---

## 📝 Quick Command Reference

| Action | Command |
|--------|---------|
| Monitor logs in real-time | `.\check-ingestion-progress.ps1` |
| Verify contributor count | `.\verify-contributors.ps1` |
| Re-run ingestion | `aws lambda invoke --function-name cc-ingest-dev --region us-east-1 response.json` |
| View CloudWatch logs | Open browser link above |
| Count users in DB | `aws dynamodb scan --table-name cc-nodes-dev --filter-expression "nodeType = :type" --expression-attribute-values '{":type":{"S":"user"}}' --select COUNT --region us-east-1` |

---

## ✅ Success Criteria

- [ ] CloudWatch logs show "Found 257 total contributors"
- [ ] CloudWatch logs show "Ingested 251 contributors (6 bots skipped)"
- [ ] DynamoDB has 251 user nodes
- [ ] DynamoDB has 251 CONTRIBUTES_TO edges for RooCodeInc/Roo-Code
- [ ] No timeout or error messages in logs
- [ ] Execution completed in 3-5 minutes

---

## 🎉 What's Next?

Once verified:
1. ✅ All contributors are now in the graph
2. ✅ Better expert identification
3. ✅ More accurate code ownership
4. ✅ Complete contributor network

You can now:
- Query the full contributor graph
- Identify experts across all contribution levels
- Build more accurate contributor recommendations
- Analyze the complete contributor network

---

## 📞 Need Help?

If you encounter issues:
1. Check CloudWatch logs for error messages
2. Verify GitHub token is valid in Secrets Manager
3. Check DynamoDB tables are accessible
4. Ensure Lambda has correct IAM permissions

**Current Status:** Ingestion running in background (started at deployment)
**Next Action:** Wait 5 minutes, then run `.\verify-contributors.ps1`
