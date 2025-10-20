# Check and manage PR scraping checkpoint
param(
    [Parameter(Mandatory=$false)]
    [string]$Org = "RooCodeInc",
    
    [Parameter(Mandatory=$false)]
    [string]$Repo = "Roo-Code",
    
    [Parameter(Mandatory=$false)]
    [string]$Environment = "dev",
    
    [Parameter(Mandatory=$false)]
    [int]$SetCheckpoint = -1
)

$tableName = "cc-repos-$Environment"

Write-Host "=========================================="
Write-Host "Checkpoint Manager for $Org/$Repo"
Write-Host "=========================================="

# Get current checkpoint
Write-Host "`nFetching current checkpoint..."
$keyJson = '{"org":{"S":"' + $Org + '"},"repo":{"S":"' + $Repo + '"}}'
$item = aws dynamodb get-item --table-name $tableName --key $keyJson --region us-east-1 | ConvertFrom-Json

if ($item.Item) {
    $lastProcessedPR = $item.Item.lastProcessedPR.N
    $lastCheckpointAt = $item.Item.lastCheckpointAt.S
    
    if ($lastProcessedPR) {
        Write-Host "✓ Current checkpoint: PR #$lastProcessedPR"
        Write-Host "  Last updated: $lastCheckpointAt"
    } else {
        Write-Host "⚠️  No checkpoint found (will start from PR #1)"
    }
    
    # Show all fields
    Write-Host "`nAll fields in repos table:"
    $item.Item.PSObject.Properties | ForEach-Object {
        Write-Host "  - $($_.Name)"
    }
} else {
    Write-Host "❌ Repository not found in table"
    exit 1
}

# Set checkpoint if requested
if ($SetCheckpoint -ge 0) {
    Write-Host "`n=========================================="
    Write-Host "Setting checkpoint to PR #$SetCheckpoint"
    Write-Host "=========================================="
    
    $updateExpression = "SET lastProcessedPR = :pr, lastCheckpointAt = :now"
    $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.ffffffzzz")
    $valuesJson = '{":pr":{"N":"' + $SetCheckpoint + '"},":now":{"S":"' + $now + '"}}'
    
    aws dynamodb update-item `
        --table-name $tableName `
        --key $keyJson `
        --update-expression $updateExpression `
        --expression-attribute-values $valuesJson `
        --region us-east-1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Checkpoint updated successfully"
        Write-Host "  Next run will resume from PR #$($SetCheckpoint + 1)"
    } else {
        Write-Host "❌ Failed to update checkpoint"
    }
}

Write-Host "`n=========================================="
Write-Host "Usage Examples:"
Write-Host "=========================================="
Write-Host "Check current checkpoint:"
Write-Host "  .\lambda\check-checkpoint.ps1"
Write-Host ""
Write-Host "Set checkpoint to PR #150:"
Write-Host "  .\lambda\check-checkpoint.ps1 -SetCheckpoint 150"
Write-Host ""
Write-Host "Reset checkpoint (start from beginning):"
Write-Host "  .\lambda\check-checkpoint.ps1 -SetCheckpoint 0"
Write-Host "=========================================="
