# Simple checkpoint manager using temp files for JSON
param(
    [Parameter(Mandatory=$false)]
    [string]$Action = "check",
    
    [Parameter(Mandatory=$false)]
    [int]$PRNumber = 0,
    
    [Parameter(Mandatory=$false)]
    [string]$Org = "RooCodeInc",
    
    [Parameter(Mandatory=$false)]
    [string]$Repo = "Roo-Code",
    
    [Parameter(Mandatory=$false)]
    [string]$Environment = "dev"
)

$tableName = "cc-repos-$Environment"

Write-Host "=========================================="
Write-Host "Checkpoint Manager: $Action"
Write-Host "Repository: $Org/$Repo"
Write-Host "=========================================="

$keyFile = [System.IO.Path]::GetTempFileName()
$valuesFile = [System.IO.Path]::GetTempFileName()

try {
    $keyJson = @{
        org = @{ S = $Org }
        repo = @{ S = $Repo }
    } | ConvertTo-Json -Compress
    
    [System.IO.File]::WriteAllText($keyFile, $keyJson, [System.Text.UTF8Encoding]::new($false))
    
    if ($Action -eq "check") {
        Write-Host "`nFetching current checkpoint..."
        $result = aws dynamodb get-item --table-name $tableName --key "file://$keyFile" --region us-east-1 | ConvertFrom-Json
        
        if ($result.Item) {
            $lastPR = $result.Item.lastProcessedPR.N
            $lastCheckpoint = $result.Item.lastCheckpointAt.S
            
            if ($lastPR) {
                Write-Host "Current checkpoint: PR #$lastPR"
                Write-Host "Last updated: $lastCheckpoint"
                Write-Host "Next run will skip PRs >= #$lastPR and resume from PR #$($lastPR - 1)"
            } else {
                Write-Host "No checkpoint found (will start from newest PR)"
            }
        } else {
            Write-Host "Repository not found in table"
        }
    }
    elseif ($Action -eq "set") {
        if ($PRNumber -le 0) {
            Write-Host "Error: Please specify -PRNumber"
            exit 1
        }
        
        Write-Host "`nSetting checkpoint to PR #$PRNumber..."
        
        $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.ffffffK")
        $valuesJson = @{
            ":pr" = @{ N = $PRNumber.ToString() }
            ":now" = @{ S = $now }
        } | ConvertTo-Json -Compress
        
        [System.IO.File]::WriteAllText($valuesFile, $valuesJson, [System.Text.UTF8Encoding]::new($false))
        
        aws dynamodb update-item --table-name $tableName --key "file://$keyFile" --update-expression "SET lastProcessedPR = :pr, lastCheckpointAt = :now" --expression-attribute-values "file://$valuesFile" --region us-east-1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Checkpoint updated successfully"
            Write-Host "Next run will skip PRs >= #$PRNumber and resume from PR #$($PRNumber - 1)"
        } else {
            Write-Host "Failed to update checkpoint"
        }
    }
    elseif ($Action -eq "reset") {
        Write-Host "`nResetting checkpoint..."
        
        $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.ffffffK")
        $valuesJson = @{
            ":pr" = @{ N = "0" }
            ":now" = @{ S = $now }
        } | ConvertTo-Json -Compress
        
        [System.IO.File]::WriteAllText($valuesFile, $valuesJson, [System.Text.UTF8Encoding]::new($false))
        
        aws dynamodb update-item --table-name $tableName --key "file://$keyFile" --update-expression "SET lastProcessedPR = :pr, lastCheckpointAt = :now" --expression-attribute-values "file://$valuesFile" --region us-east-1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Checkpoint reset successfully"
        } else {
            Write-Host "Failed to reset checkpoint"
        }
    }
    else {
        Write-Host "Invalid action: $Action (valid: check, set, reset)"
    }
}
finally {
    if (Test-Path $keyFile) { Remove-Item $keyFile -Force }
    if (Test-Path $valuesFile) { Remove-Item $valuesFile -Force }
}

Write-Host "`n=========================================="
Write-Host "Usage:"
Write-Host "  .\lambda\checkpoint-manager.ps1 -Action check"
Write-Host "  .\lambda\checkpoint-manager.ps1 -Action set -PRNumber 8700"
Write-Host "  .\lambda\checkpoint-manager.ps1 -Action reset"
Write-Host "=========================================="
