# Quick Status Check
# Shows current ingestion status at a glance

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "ContribConnect Ingestion Status" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Check Lambda function status
Write-Host "Lambda Function Status:" -ForegroundColor Yellow
$lambdaStatus = aws lambda get-function --function-name cc-ingest-dev --region us-east-1 2>$null | ConvertFrom-Json
if ($lambdaStatus) {
    Write-Host "  ✓ Function: cc-ingest-dev" -ForegroundColor Green
    Write-Host "  ✓ State: $($lambdaStatus.Configuration.State)" -ForegroundColor Green
    Write-Host "  ✓ Last Modified: $($lambdaStatus.Configuration.LastModified)" -ForegroundColor Green
} else {
    Write-Host "  ✗ Lambda function not found" -ForegroundColor Red
}
Write-Host ""

# Check DynamoDB tables
Write-Host "DynamoDB Tables:" -ForegroundColor Yellow

# Count nodes
$nodeCount = aws dynamodb scan --table-name cc-nodes-dev --select COUNT --region us-east-1 2>$null | ConvertFrom-Json
if ($nodeCount) {
    Write-Host "  ✓ Nodes: $($nodeCount.Count) total" -ForegroundColor Green
} else {
    Write-Host "  ✗ Nodes table error" -ForegroundColor Red
}

# Count edges
$edgeCount = aws dynamodb scan --table-name cc-edges-dev --select COUNT --region us-east-1 2>$null | ConvertFrom-Json
if ($edgeCount) {
    Write-Host "  ✓ Edges: $($edgeCount.Count) total" -ForegroundColor Green
} else {
    Write-Host "  ✗ Edges table error" -ForegroundColor Red
}

# Count users specifically
$userCount = aws dynamodb scan `
    --table-name cc-nodes-dev `
    --filter-expression "nodeType = :type" `
    --expression-attribute-values '{":type":{"S":"user"}}' `
    --select COUNT `
    --region us-east-1 2>$null | ConvertFrom-Json

if ($userCount) {
    Write-Host "  ✓ Users: $($userCount.Count) contributors" -ForegroundColor Green
} else {
    Write-Host "  ✗ User count error" -ForegroundColor Red
}

# Count CONTRIBUTES_TO edges for RooCodeInc/Roo-Code
$contributorEdges = aws dynamodb scan `
    --table-name cc-edges-dev `
    --filter-expression "edgeType = :type AND toId = :repo" `
    --expression-attribute-values '{":type":{"S":"CONTRIBUTES_TO"},":repo":{"S":"repo#RooCodeInc/Roo-Code"}}' `
    --select COUNT `
    --region us-east-1 2>$null | ConvertFrom-Json

if ($contributorEdges) {
    Write-Host "  ✓ RooCode Contributors: $($contributorEdges.Count)" -ForegroundColor Green
} else {
    Write-Host "  ✗ Contributor edges error" -ForegroundColor Red
}

Write-Host ""

# Status interpretation
Write-Host "Status Interpretation:" -ForegroundColor Yellow
if ($contributorEdges.Count -ge 250) {
    Write-Host "  SUCCESS! All contributors scraped (251 expected)" -ForegroundColor Green
    Write-Host "  Pagination working correctly!" -ForegroundColor Green
} elseif ($contributorEdges.Count -ge 50 -and $contributorEdges.Count -lt 250) {
    Write-Host "  PARTIAL: $($contributorEdges.Count) contributors found" -ForegroundColor Yellow
    Write-Host "  Ingestion may still be running..." -ForegroundColor Yellow
    Write-Host "  Wait 2-3 more minutes and run this script again" -ForegroundColor Yellow
} elseif ($contributorEdges.Count -gt 0 -and $contributorEdges.Count -lt 50) {
    Write-Host "  STARTING: Ingestion in progress..." -ForegroundColor Yellow
    Write-Host "  Wait 3-5 minutes and run this script again" -ForegroundColor Yellow
} elseif ($contributorEdges.Count -eq 0) {
    Write-Host "  PENDING: Ingestion not started or just started" -ForegroundColor Yellow
    Write-Host "  Wait 1-2 minutes and run this script again" -ForegroundColor Yellow
} else {
    Write-Host "  UNKNOWN: Unable to determine status" -ForegroundColor Red
}

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Quick Actions:" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "  Monitor logs:  .\check-ingestion-progress.ps1"
Write-Host "  Full verify:   .\verify-contributors.ps1"
Write-Host "  Re-run ingest: aws lambda invoke --function-name cc-ingest-dev --region us-east-1 response.json"
Write-Host ""
