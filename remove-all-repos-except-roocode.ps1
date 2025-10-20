# Remove all repositories except RooCode
param(
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1",
    [string]$AwsProfile = "default"
)

$TableName = "cc-repos-$Environment"

Write-Host ""
Write-Host "Removing all repositories except RooCodeInc/Roo-Code..." -ForegroundColor Yellow
Write-Host ""

# List of repos to remove (based on your current list)
$reposToRemove = @(
    @{org="facebook"; repo="react"},
    @{org="vercel"; repo="next.js"},
    @{org="tailwindlabs"; repo="tailwindcss"},
    @{org="angular"; repo="angular"},
    @{org="nodejs"; repo="node"},
    @{org="vuejs"; repo="vue"},
    @{org="microsoft"; repo="vscode"}
)

foreach ($repoInfo in $reposToRemove) {
    $org = $repoInfo.org
    $repo = $repoInfo.repo
    
    Write-Host "Removing $org/$repo..." -ForegroundColor Gray
    
    $key = @{
        org = @{S = $org}
        repo = @{S = $repo}
    } | ConvertTo-Json -Compress
    
    aws dynamodb delete-item --table-name $TableName --key $key --region $AwsRegion --profile $AwsProfile 2>&1 | Out-Null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Removed successfully" -ForegroundColor Green
    } else {
        Write-Host "  Failed or not found" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Done! Verifying..." -ForegroundColor Cyan
Write-Host ""

# Verify
& ".\infrastructure\scripts\manage-repositories.ps1" -Action list -Environment $Environment -AwsProfile $AwsProfile

Write-Host ""
Write-Host "Complete! Only RooCodeInc/Roo-Code should remain." -ForegroundColor Green
Write-Host ""
