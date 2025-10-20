# Verify All Contributors Were Scraped
# This script checks DynamoDB to count contributors

Write-Host "==========================================="
Write-Host "Verifying Contributor Scraping"
Write-Host "==========================================="
Write-Host ""

Write-Host "Step 1: Counting total user nodes in DynamoDB..."
Write-Host ""

# Count all user nodes
$userCount = aws dynamodb scan `
    --table-name cc-nodes-dev `
    --filter-expression "nodeType = :type" `
    --expression-attribute-values '{":type":{"S":"user"}}' `
    --select COUNT `
    --region us-east-1 | ConvertFrom-Json

Write-Host "✓ Total user nodes found: $($userCount.Count)" -ForegroundColor Green
Write-Host ""

Write-Host "Step 2: Counting CONTRIBUTES_TO edges..."
Write-Host ""

# Count CONTRIBUTES_TO edges for RooCodeInc/Roo-Code
$edgeCount = aws dynamodb scan `
    --table-name cc-edges-dev `
    --filter-expression "edgeType = :type AND toId = :repo" `
    --expression-attribute-values '{":type":{"S":"CONTRIBUTES_TO"},":repo":{"S":"repo#RooCodeInc/Roo-Code"}}' `
    --select COUNT `
    --region us-east-1 | ConvertFrom-Json

Write-Host "✓ CONTRIBUTES_TO edges for RooCodeInc/Roo-Code: $($edgeCount.Count)" -ForegroundColor Green
Write-Host ""

Write-Host "Step 3: Fetching top 10 contributors..."
Write-Host ""

# Get sample of contributors with their contribution counts
$contributors = aws dynamodb scan `
    --table-name cc-edges-dev `
    --filter-expression "edgeType = :type AND toId = :repo" `
    --expression-attribute-values '{":type":{"S":"CONTRIBUTES_TO"},":repo":{"S":"repo#RooCodeInc/Roo-Code"}}' `
    --max-items 10 `
    --region us-east-1 | ConvertFrom-Json

Write-Host "Sample contributors:" -ForegroundColor Cyan
foreach ($item in $contributors.Items) {
    $username = $item.fromId.S -replace "user#", ""
    $contributions = $item.properties.M.contributions.N
    Write-Host "  - $username : $contributions contributions"
}

Write-Host ""
Write-Host "==========================================="
Write-Host "Expected Results for RooCodeInc/Roo-Code:"
Write-Host "==========================================="
Write-Host "Total Contributors: 257 (6 bots filtered out = 251 processed)"
Write-Host "CONTRIBUTES_TO Edges: 251"
Write-Host ""

if ($edgeCount.Count -ge 250) {
    Write-Host "✅ SUCCESS! All contributors scraped!" -ForegroundColor Green
} elseif ($edgeCount.Count -ge 50) {
    Write-Host "⚠️  Partial scraping: $($edgeCount.Count) contributors" -ForegroundColor Yellow
    Write-Host "   Expected: 251 contributors" -ForegroundColor Yellow
    Write-Host "   Check CloudWatch logs for errors" -ForegroundColor Yellow
} else {
    Write-Host "❌ ERROR: Only $($edgeCount.Count) contributors found" -ForegroundColor Red
    Write-Host "   Expected: 251 contributors" -ForegroundColor Red
    Write-Host "   Check CloudWatch logs for errors" -ForegroundColor Red
}

Write-Host ""
Write-Host "To view detailed logs:"
Write-Host ".\check-ingestion-progress.ps1"
