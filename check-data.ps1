Write-Host "=== ContribConnect Data Check ===" -ForegroundColor Cyan
Write-Host ""

# Nodes
Write-Host "📦 NODES TABLE:" -ForegroundColor Yellow
$nodesCount = aws dynamodb scan --table-name cc-nodes-dev --select COUNT --query 'Count' --output text
Write-Host "  Total nodes: $nodesCount"

# Use file-based approach for complex JSON
$userFilter = @'
{
  ":type": {"S": "user"}
}
'@
$userFilter | Out-File -FilePath "temp-user.json" -Encoding utf8
$userCount = aws dynamodb scan --table-name cc-nodes-dev --filter-expression "nodeType = :type" --expression-attribute-values file://temp-user.json --select COUNT --query 'Count' --output text
Write-Host "  Users: $userCount"

$repoFilter = @'
{
  ":type": {"S": "repo"}
}
'@
$repoFilter | Out-File -FilePath "temp-repo.json" -Encoding utf8
$repoCount = aws dynamodb scan --table-name cc-nodes-dev --filter-expression "nodeType = :type" --expression-attribute-values file://temp-repo.json --select COUNT --query 'Count' --output text
Write-Host "  Repos: $repoCount"

$prFilter = @'
{
  ":type": {"S": "pull_request"}
}
'@
$prFilter | Out-File -FilePath "temp-pr.json" -Encoding utf8
$prCount = aws dynamodb scan --table-name cc-nodes-dev --filter-expression "nodeType = :type" --expression-attribute-values file://temp-pr.json --select COUNT --query 'Count' --output text
Write-Host "  Pull Requests: $prCount"

$issueFilter = @'
{
  ":type": {"S": "issue"}
}
'@
$issueFilter | Out-File -FilePath "temp-issue.json" -Encoding utf8
$issueCount = aws dynamodb scan --table-name cc-nodes-dev --filter-expression "nodeType = :type" --expression-attribute-values file://temp-issue.json --select COUNT --query 'Count' --output text
Write-Host "  Issues: $issueCount"

Write-Host ""

# Edges
Write-Host "🔗 EDGES TABLE:" -ForegroundColor Yellow
$edgesCount = aws dynamodb scan --table-name cc-edges-dev --select COUNT --query 'Count' --output text
Write-Host "  Total edges: $edgesCount"

$contribFilter = @'
{
  ":type": {"S": "CONTRIBUTES_TO"}
}
'@
$contribFilter | Out-File -FilePath "temp-contrib.json" -Encoding utf8
$contribEdges = aws dynamodb scan --table-name cc-edges-dev --filter-expression "edgeType = :type" --expression-attribute-values file://temp-contrib.json --select COUNT --query 'Count' --output text
Write-Host "  CONTRIBUTES_TO edges: $contribEdges"

Write-Host ""

# Repos
Write-Host "📚 REPOS TABLE:" -ForegroundColor Yellow
$reposTotal = aws dynamodb scan --table-name cc-repos-dev --select COUNT --query 'Count' --output text
Write-Host "  Total repos configured: $reposTotal"

$enabledFilter = @'
{
  ":val": {"BOOL": true}
}
'@
$enabledFilter | Out-File -FilePath "temp-enabled.json" -Encoding utf8
$enabledRepos = aws dynamodb scan --table-name cc-repos-dev --filter-expression "enabled = :val" --expression-attribute-values file://temp-enabled.json --select COUNT --query 'Count' --output text
Write-Host "  Enabled repos: $enabledRepos"

Write-Host ""
Write-Host "=== Checking RooCodeInc/Roo-Code ===" -ForegroundColor Cyan

# Check if RooCode data exists
$rooFilter = @'
{
  ":repo": {"S": "RooCodeInc/Roo-Code"}
}
'@
$rooFilter | Out-File -FilePath "temp-roo.json" -Encoding utf8
$rooCodeEdges = aws dynamodb scan --table-name cc-edges-dev --filter-expression "contains(toId, :repo)" --expression-attribute-values file://temp-roo.json --select COUNT --query 'Count' --output text
Write-Host "  RooCode edges found: $rooCodeEdges"

# Check repo node
$rooKey = @'
{
  "nodeId": {"S": "repo#RooCodeInc/Roo-Code"}
}
'@
$rooKey | Out-File -FilePath "temp-roo-key.json" -Encoding utf8
Write-Host ""
Write-Host "  Checking repo node..." -ForegroundColor Gray
$rooNode = aws dynamodb get-item --table-name cc-nodes-dev --key file://temp-roo-key.json --query 'Item' --output json
if ($rooNode -eq "null" -or $rooNode -eq $null) {
    Write-Host "  ❌ RooCodeInc/Roo-Code node NOT FOUND in database" -ForegroundColor Red
    Write-Host "  This means the data hasn't been ingested yet!" -ForegroundColor Yellow
} else {
    Write-Host "  ✅ RooCodeInc/Roo-Code node exists" -ForegroundColor Green
}

# Cleanup temp files
Remove-Item temp-*.json -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
if ($rooCodeEdges -eq "0") {
    Write-Host "⚠️  RooCodeInc/Roo-Code has NO data ingested yet!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To ingest data, run:" -ForegroundColor White
    Write-Host "  aws lambda invoke --function-name cc-ingest-dev --payload '{}' response.json" -ForegroundColor Cyan
    Write-Host "  cat response.json" -ForegroundColor Cyan
} else {
    Write-Host "✅ RooCodeInc/Roo-Code has data!" -ForegroundColor Green
}
Write-Host ""
