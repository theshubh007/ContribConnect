# Simple delete all repos except RooCode - using exact same pattern as manage-repositories.ps1
param(
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1",
    [string]$AwsProfile = "default"
)

$TableName = "cc-repos-$Environment"

Write-Host ""
Write-Host "Deleting all repos except RooCodeInc/Roo-Code..." -ForegroundColor Cyan
Write-Host ""

# List of repos to delete
$reposToDelete = @(
    @{Owner="facebook"; Repo="react"},
    @{Owner="vercel"; Repo="next.js"},
    @{Owner="tailwindlabs"; Repo="tailwindcss"},
    @{Owner="angular"; Repo="angular"},
    @{Owner="nodejs"; Repo="node"},
    @{Owner="vuejs"; Repo="vue"},
    @{Owner="microsoft"; Repo="vscode"}
)

$successCount = 0
$failCount = 0

foreach ($repoInfo in $reposToDelete) {
    $Owner = $repoInfo.Owner
    $Repo = $repoInfo.Repo
    
    Write-Host "Deleting $Owner/$Repo..." -ForegroundColor Yellow
    
    # Use EXACT same pattern as manage-repositories.ps1
    $key = @{
        org = @{S = $Owner}
        repo = @{S = $Repo}
    } | ConvertTo-Json -Compress
    
    aws dynamodb delete-item --table-name $TableName --key $key --region $AwsRegion --profile $AwsProfile
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  SUCCESS" -ForegroundColor Green
        $successCount++
    } else {
        Write-Host "  FAILED" -ForegroundColor Red
        $failCount++
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Results: $successCount deleted, $failCount failed" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Verify
Write-Host "Verifying remaining repositories..." -ForegroundColor Yellow
& ".\infrastructure\scripts\manage-repositories.ps1" -Action list -Environment $Environment -AwsProfile $AwsProfile
