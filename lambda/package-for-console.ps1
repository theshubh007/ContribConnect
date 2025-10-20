# Package Lambda function for AWS Console upload
param(
    [Parameter(Mandatory=$false)]
    [string]$LambdaName = "ingest"
)

Write-Host "=========================================="
Write-Host "Packaging Lambda: $LambdaName"
Write-Host "=========================================="

$lambdaDir = "lambda/$LambdaName"
$zipFile = "lambda/$LambdaName-deployment.zip"

# Check if lambda directory exists
if (-not (Test-Path $lambdaDir)) {
    Write-Host "Error: Lambda directory not found: $lambdaDir"
    exit 1
}

# Remove old zip if exists
if (Test-Path $zipFile) {
    Write-Host "Removing old zip file..."
    Remove-Item $zipFile -Force
}

# Change to lambda directory
Push-Location $lambdaDir

try {
    # Install dependencies if requirements.txt exists
    if (Test-Path "requirements.txt") {
        Write-Host "`nInstalling dependencies..."
        pip install -r requirements.txt -t . --upgrade --quiet
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Warning: Some dependencies may have failed to install"
        }
    }
    
    # Create zip file with all contents
    Write-Host "`nCreating deployment package..."
    
    # Get all files except __pycache__ and .pyc files
    $files = Get-ChildItem -Recurse -File | Where-Object {
        $_.FullName -notmatch '__pycache__' -and
        $_.Extension -ne '.pyc' -and
        $_.Name -ne 'package.zip' -and
        $_.Name -notmatch '-deployment.zip'
    }
    
    Write-Host "Packaging $($files.Count) files..."
    
    # Use Compress-Archive to create zip
    $zipPath = "../../$zipFile"
    Compress-Archive -Path * -DestinationPath $zipPath -Force
    
    Pop-Location
    
    # Get file size
    $zipSize = (Get-Item $zipFile).Length / 1MB
    
    Write-Host "`n=========================================="
    Write-Host "Package created successfully!"
    Write-Host "=========================================="
    Write-Host "File: $zipFile"
    Write-Host "Size: $([math]::Round($zipSize, 2)) MB"
    Write-Host ""
    Write-Host "To upload via AWS Console:"
    Write-Host "1. Go to AWS Lambda Console"
    Write-Host "2. Select function: cc-$LambdaName-dev"
    Write-Host "3. Click 'Upload from' -> '.zip file'"
    Write-Host "4. Select: $zipFile"
    Write-Host "5. Click 'Save'"
    Write-Host ""
    Write-Host "Note: If file is > 50MB, you'll need to upload to S3 first"
    Write-Host "=========================================="
    
} catch {
    Pop-Location
    Write-Host "Error creating package: $_"
    exit 1
}
