# Force remove all repos except RooCode by scanning and deleting
param(
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1",
    [string]$AwsProfile = "default"
)

$TableName = "cc-repos-$Environment"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Force Remove All Repos Except RooCode" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Scan the table to get all items
Write-Host "Scanning table for all repositories..." -ForegroundColor Yellow
$scanResult = aws dynamodb scan --table-name $TableName --region $AwsRegion --profile $AwsProfile | ConvertFrom-Json

if ($scanResult.Items.Count -eq 0) {
    Write-Host "No repositories found!" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($scanResult.Items.Count) repositories" -ForegroundColor Cyan
Write-Host ""

# Step 2: Delete each item except RooCode
$deletedCount = 0
$keptCount = 0

foreach ($item in $scanResult.Items) {
    $org = $item.org.S
    $repo = $item.repo.S
    $fullName = "$org/$repo"
    
    # Skip RooCode
    if ($org -eq "RooCodeInc" -and $repo -eq "Roo-Code") {
        Write-Host "KEEPING: $fullName" -ForegroundColor Green
        $keptCount++
        continue
    }
    
    Write-Host "DELETING: $fullName..." -ForegroundColor Yellow
    
    # Build the key as proper JSON string
    $keyJson = "{`"org`":{`"S`":`"$org`"},`"repo`":{`"S`":`"$repo`"}}"
    
    # Delete the item
    $deleteResult = aws dynamodb delete-item `
        --table-name $TableName `
        --key $keyJson `
        --region $AwsRegion `
        --profile $AwsProfile 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  SUCCESS: Deleted $fullName" -ForegroundColor Green
        $deletedCount++
    } else {
        Write-Host "  ERROR: Failed to delete $fullName" -ForegroundColor Red
        Write-Host "  $deleteResult" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Deleted: $deletedCount repositories" -ForegroundColor Yellow
Write-Host "  Kept: $keptCount repositories" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 3: Verify final state
Write-Host "Verifying final state..." -ForegroundColor Yellow
Write-Host ""

$finalResult = aws dynamodb scan --table-name $TableName --region $AwsRegion --profile $AwsProfile | ConvertFrom-Json

Write-Host "Remaining repositories:" -ForegroundColor Cyan
foreach ($item in $finalResult.Items) {
    Write-Host "  - $($item.org.S)/$($item.repo.S)" -ForegroundColor Green
}

Write-Host ""
if ($finalResult.Items.Count -eq 1) {
    Write-Host "SUCCESS! Only RooCodeInc/Roo-Code remains." -ForegroundColor Green
} else {
    Write-Host "WARNING: Expected 1 repository, found $($finalResult.Items.Count)" -ForegroundColor Yellow
}
Write-Host ""
