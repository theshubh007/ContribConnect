# Quick redeploy script for ingest Lambda

param(
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1"
)

Write-Host "Redeploying ingest Lambda..." -ForegroundColor Cyan

# Create deployment package
$TempDir = "lambda/ingest/.package"
if (Test-Path $TempDir) {
    Remove-Item $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

# Install dependencies
pip install requests boto3 -t $TempDir --quiet

# Copy Lambda function
Copy-Item lambda/ingest/lambda_function.py $TempDir/

# Create ZIP
$ZipFile = "lambda/ingest/function.zip"
if (Test-Path $ZipFile) {
    Remove-Item $ZipFile -Force
}
Compress-Archive -Path "$TempDir/*" -DestinationPath $ZipFile -Force
Remove-Item $TempDir -Recurse -Force

# Update Lambda
$FunctionName = "cc-ingest-$Environment"
Write-Host "Updating $FunctionName..." -ForegroundColor Yellow
aws lambda update-function-code --function-name $FunctionName --zip-file "fileb://$ZipFile" --region $AwsRegion

Write-Host "Deployment complete!" -ForegroundColor Green
Write-Host ""
Write-Host "To trigger ingestion manually:"
Write-Host "  aws lambda invoke --function-name $FunctionName --region $AwsRegion response.json"
