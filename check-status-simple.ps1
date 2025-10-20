# Simple Status Check - No special characters
Write-Host ""
Write-Host "Checking ContribConnect Status..." -ForegroundColor Cyan
Write-Host ""

# Count CONTRIBUTES_TO edges for RooCodeInc/Roo-Code
Write-Host "Counting contributors for RooCodeInc/Roo-Code..."
$result = aws dynamodb scan --table-name cc-edges-dev --filter-expression "edgeType = :type AND toId = :repo" --expression-attribute-values "{`":type`":{`"S`":`"CONTRIBUTES_TO`"},`":repo`":{`"S`":`"repo#RooCodeInc/Roo-Code`"}}" --select COUNT --region us-east-1 | ConvertFrom-Json

if ($result) {
    $count = $result.Count
    Write-Host ""
    Write-Host "Contributors found: $count" -ForegroundColor Green
    Write-Host ""
    
    if ($count -ge 250) {
        Write-Host "SUCCESS! All contributors scraped!" -ForegroundColor Green
        Write-Host "Expected: 251 contributors" -ForegroundColor Green
        Write-Host "Found: $count contributors" -ForegroundColor Green
    } elseif ($count -ge 50) {
        Write-Host "PARTIAL: Ingestion may still be running" -ForegroundColor Yellow
        Write-Host "Expected: 251 contributors" -ForegroundColor Yellow
        Write-Host "Found: $count contributors" -ForegroundColor Yellow
        Write-Host "Wait 2-3 more minutes and run again" -ForegroundColor Yellow
    } elseif ($count -gt 0) {
        Write-Host "STARTING: Ingestion in progress" -ForegroundColor Yellow
        Write-Host "Found: $count contributors so far" -ForegroundColor Yellow
        Write-Host "Wait 3-5 minutes and run again" -ForegroundColor Yellow
    } else {
        Write-Host "PENDING: Ingestion not started yet" -ForegroundColor Yellow
        Write-Host "Wait 1-2 minutes and run again" -ForegroundColor Yellow
    }
} else {
    Write-Host "ERROR: Could not query DynamoDB" -ForegroundColor Red
}

Write-Host ""
