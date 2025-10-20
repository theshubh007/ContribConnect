# Delete all repos except RooCode - Using temp file approach
param(
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1",
    [string]$AwsProfile = "default"
)

$TableName = "cc-repos-$Environment"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Delete All Repos Except RooCode" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Scan table
Write-Host "Scanning table..." -ForegroundColor Yellow
$scanResult = aws dynamodb scan --table-name $TableName --region $AwsRegion --profile $AwsProfile | ConvertFrom-Json

Write-Host "Found $($scanResult.Items.Count) repositories" -ForegroundColor Cyan
Write-Host ""

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
    
    # Create temp JSON file with proper formatting
    $tempFile = [System.IO.Path]::GetTempFileName()
    $keyObject = @{
        org = @{S = $org}
        repo = @{S = $repo}
    }
    
    # Write to temp file with proper JSON
    $keyObject | ConvertTo-Json -Depth 10 | Out-File -FilePath $tempFile -Encoding utf8
    
    # Delete using file
    aws dynamodb delete-item `
        --table-name $TableName `
        --key file://$tempFile `
        --region $AwsRegion `
        --profile $AwsProfile 2>&1 | Out-Null
    
    # Clean up temp file
    Remove-Item $tempFile -ErrorAction SilentlyContinue
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  SUCCESS" -ForegroundColor Green
        $deletedCount++
    } else {
        Write-Host "  FAILED" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deleted: $deletedCount | Kept: $keptCount" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Verify
Write-Host "Verifying..." -ForegroundColor Yellow
$finalResult = aws dynamodb scan --table-name $TableName --region $AwsRegion --profile $AwsProfile | ConvertFrom-Json

Write-Host "Remaining repositories:" -ForegroundColor Cyan
foreach ($item in $finalResult.Items) {
    Write-Host "  - $($item.org.S)/$($item.repo.S)" -ForegroundColor Green
}

Write-Host ""
if ($finalResult.Items.Count -eq 1) {
    Write-Host "SUCCESS! Only RooCodeInc/Roo-Code remains." -ForegroundColor Green
} else {
    Write-Host "Found $($finalResult.Items.Count) repositories (expected 1)" -ForegroundColor Yellow
}
Write-Host ""
