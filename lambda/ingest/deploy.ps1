# Deploy Ingest Lambda with Dependencies

Write-Host "Deploying Ingest Lambda..." -ForegroundColor Cyan

# Create temp directory
$tempDir = "lambda_package"
if (Test-Path $tempDir) {
    Remove-Item -Recurse -Force $tempDir
}
New-Item -ItemType Directory -Path $tempDir | Out-Null

# Install dependencies
Write-Host "Installing dependencies..." -ForegroundColor Yellow
pip install requests -t $tempDir

# Copy Lambda function
Copy-Item lambda_function.py $tempDir/

# Create zip
Write-Host "Creating deployment package..." -ForegroundColor Yellow
Compress-Archive -Path "$tempDir\*" -DestinationPath ingest-deploy.zip -Force

# Deploy to Lambda
Write-Host "Uploading to Lambda..." -ForegroundColor Yellow
aws lambda update-function-code --function-name cc-ingest-dev --zip-file fileb://ingest-deploy.zip

# Cleanup
Remove-Item -Recurse -Force $tempDir

Write-Host "✅ Deployment complete!" -ForegroundColor Green
