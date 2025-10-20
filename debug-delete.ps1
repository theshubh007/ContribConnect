# Debug script to understand the issue
param(
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1",
    [string]$AwsProfile = "default"
)

$TableName = "cc-repos-$Environment"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Debug DynamoDB Delete Issue" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Describe the table to see the key schema
Write-Host "1. Checking table structure..." -ForegroundColor Yellow
$tableInfo = aws dynamodb describe-table --table-name $TableName --region $AwsRegion --profile $AwsProfile | ConvertFrom-Json

Write-Host "Table Key Schema:" -ForegroundColor Cyan
foreach ($key in $tableInfo.Table.KeySchema) {
    Write-Host "  - $($key.AttributeName) ($($key.KeyType))" -ForegroundColor White
}
Write-Host ""

# Step 2: Get one item to see its structure
Write-Host "2. Getting sample item (facebook/react)..." -ForegroundColor Yellow
$sampleKey = '{"org":{"S":"facebook"},"repo":{"S":"react"}}'
Write-Host "Key JSON: $sampleKey" -ForegroundColor Gray

$tempKeyFile = "temp-key.json"
$sampleKey | Out-File -FilePath $tempKeyFile -Encoding utf8 -NoNewline

Write-Host ""
Write-Host "3. Attempting delete with verbose output..." -ForegroundColor Yellow
$deleteOutput = aws dynamodb delete-item `
    --table-name $TableName `
    --key file://$tempKeyFile `
    --region $AwsRegion `
    --profile $AwsProfile `
    --debug 2>&1

Write-Host "Delete output:" -ForegroundColor Cyan
Write-Host $deleteOutput -ForegroundColor Gray

Remove-Item $tempKeyFile -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "4. Trying with manage-repositories.ps1 script..." -ForegroundColor Yellow
& ".\infrastructure\scripts\manage-repositories.ps1" -Action remove -Owner "facebook" -Repo "react" -Environment $Environment -AwsProfile $AwsProfile

Write-Host ""
Write-Host "5. Checking if facebook/react still exists..." -ForegroundColor Yellow
$verifyResult = aws dynamodb scan --table-name $TableName --region $AwsRegion --profile $AwsProfile | ConvertFrom-Json
$facebookReact = $verifyResult.Items | Where-Object { $_.org.S -eq "facebook" -and $_.repo.S -eq "react" }

if ($facebookReact) {
    Write-Host "facebook/react STILL EXISTS" -ForegroundColor Red
} else {
    Write-Host "facebook/react WAS DELETED!" -ForegroundColor Green
}

Write-Host ""
