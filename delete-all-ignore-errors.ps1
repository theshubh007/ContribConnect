# Delete all repos except RooCode - ignore AWS CLI JSON warnings
param(
    [string]$Environment = "dev",
    [string]$AwsProfile = "default"
)

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Deleting All Repos Except RooCode" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$repos = @(
    @{Owner="facebook"; Repo="react"},
    @{Owner="vercel"; Repo="next.js"},
    @{Owner="tailwindlabs"; Repo="tailwindcss"},
    @{Owner="angular"; Repo="angular"},
    @{Owner="nodejs"; Repo="node"},
    @{Owner="vuejs"; Repo="vue"},
    @{Owner="microsoft"; Repo="vscode"}
)

foreach ($repo in $repos) {
    Write-Host "Deleting $($repo.Owner)/$($repo.Repo)..." -ForegroundColor Yellow
    
    # Use the manage-repositories script which works despite showing errors
    & ".\infrastructure\scripts\manage-repositories.ps1" `
        -Action remove `
        -Owner $repo.Owner `
        -Repo $repo.Repo `
        -Environment $Environment `
        -AwsProfile $AwsProfile 2>&1 | Out-Null
    
    Write-Host "  Done" -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Verifying Results" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

& ".\infrastructure\scripts\manage-repositories.ps1" -Action list -Environment $Environment -AwsProfile $AwsProfile

Write-Host ""
