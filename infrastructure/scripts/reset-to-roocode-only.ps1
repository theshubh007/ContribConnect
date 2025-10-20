# Reset Repository Configuration - Keep Only RooCode
# Removes all repositories and keeps only RooCodeInc/Roo-Code

param(
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1",
    [string]$AwsProfile = "default"
)

$ErrorActionPreference = "Stop"

$TableName = "cc-repos-$Environment"

Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Reset to RooCode Only" -ForegroundColor Cyan
Write-Host "Table: $TableName" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: List all current repositories
Write-Host "Step 1: Fetching all repositories..." -ForegroundColor Yellow
$result = aws dynamodb scan --table-name $TableName --region $AwsRegion --profile $AwsProfile 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Could not scan table. Make sure the table exists." -ForegroundColor Red
    Write-Host "Run: .\manage-repositories.ps1 -Action init" -ForegroundColor Yellow
    exit 1
}

$scanResult = $result | ConvertFrom-Json
$items = $scanResult.Items

if ($items.Count -eq 0) {
    Write-Host "No repositories found in table" -ForegroundColor Yellow
} else {
    Write-Host "Found $($items.Count) repositories" -ForegroundColor Cyan
    Write-Host ""
    
    # Step 2: Delete all repositories
    Write-Host "Step 2: Removing all repositories..." -ForegroundColor Yellow
    
    foreach ($item in $items) {
        $org = $item.org.S
        $repo = $item.repo.S
        
        Write-Host "  Removing $org/$repo..." -ForegroundColor Gray
        
        $key = @{
            org = @{S = $org}
            repo = @{S = $repo}
        } | ConvertTo-Json -Compress
        
        aws dynamodb delete-item --table-name $TableName --key $key --region $AwsRegion --profile $AwsProfile
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    ✓ Removed" -ForegroundColor Green
        } else {
            Write-Host "    ✗ Failed to remove" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "Step 3: Adding RooCodeInc/Roo-Code..." -ForegroundColor Yellow

# Step 3: Add RooCode repository
$rooCodeItem = @{
    org = @{S = "RooCodeInc"}
    repo = @{S = "Roo-Code"}
    enabled = @{BOOL = $true}
    topics = @{L = @(
        @{S = "ai"},
        @{S = "code-assistant"},
        @{S = "vscode-extension"},
        @{S = "typescript"}
    )}
    minStars = @{N = "0"}
    description = @{S = "AI-powered code assistant for developers"}
    language = @{S = "TypeScript"}
    ingestCursor = @{S = "2024-01-01T00:00:00Z"}
    lastIngestAt = @{S = ""}
    ingestStatus = @{S = "pending"}
    createdAt = @{S = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")}
    updatedAt = @{S = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")}
}

$itemJson = $rooCodeItem | ConvertTo-Json -Depth 10 -Compress

aws dynamodb put-item --table-name $TableName --item $itemJson --region $AwsRegion --profile $AwsProfile

if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ RooCodeInc/Roo-Code added successfully!" -ForegroundColor Green
} else {
    Write-Host "  ✗ Failed to add RooCodeInc/Roo-Code" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Step 4: Verifying configuration..." -ForegroundColor Yellow

# Step 4: Verify
$verifyResult = aws dynamodb scan --table-name $TableName --region $AwsRegion --profile $AwsProfile | ConvertFrom-Json

Write-Host ""
Write-Host "Current repositories in table:" -ForegroundColor Cyan
foreach ($item in $verifyResult.Items) {
    $enabled = if ($item.enabled.BOOL) { "ENABLED" } else { "DISABLED" }
    $color = if ($item.enabled.BOOL) { "Green" } else { "Gray" }
    Write-Host "  - $($item.org.S)/$($item.repo.S) [$enabled]" -ForegroundColor $color
}

Write-Host ""
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Reset Complete!" -ForegroundColor Green
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Run ingestion to populate data:" -ForegroundColor White
Write-Host "   aws lambda invoke --function-name cc-ingest-dev response.json --profile $AwsProfile" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Check ingestion status:" -ForegroundColor White
Write-Host "   .\manage-repositories.ps1 -Action list" -ForegroundColor Gray
Write-Host ""
