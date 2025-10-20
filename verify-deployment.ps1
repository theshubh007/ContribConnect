# Verify Frontend Deployment
Write-Host "Checking deployed frontend code..." -ForegroundColor Cyan
Write-Host ""

# Download the deployed JS file
$jsFiles = aws s3 ls s3://cc-web-dev-917343669425/assets/ --region us-east-1 | Select-String "index-.*\.js"

if ($jsFiles) {
    $jsFile = ($jsFiles -split '\s+')[-1]
    Write-Host "Found JS file: $jsFile" -ForegroundColor Green
    
    # Download and check if it contains the new code
    $tempFile = "temp-deployed.js"
    aws s3 cp "s3://cc-web-dev-917343669425/assets/$jsFile" $tempFile --region us-east-1
    
    # Check if the new GRAPH_TOOL_URL is in the file
    $content = Get-Content $tempFile -Raw
    
    if ($content -match "GRAPH_TOOL_URL") {
        Write-Host "✓ New code IS deployed (found GRAPH_TOOL_URL)" -ForegroundColor Green
    } else {
        Write-Host "✗ New code NOT deployed (GRAPH_TOOL_URL not found)" -ForegroundColor Red
        Write-Host "  The old code is still deployed" -ForegroundColor Red
    }
    
    if ($content -match "get_top_contributors") {
        Write-Host "✓ New code IS deployed (found get_top_contributors)" -ForegroundColor Green
    } else {
        Write-Host "✗ New code NOT deployed (get_top_contributors not found)" -ForegroundColor Red
    }
    
    Remove-Item $tempFile -ErrorAction SilentlyContinue
} else {
    Write-Host "✗ Could not find JS file in S3" -ForegroundColor Red
}

Write-Host ""
Write-Host "CloudFront URL: https://d3hw1a5xeaznh4.cloudfront.net"
Write-Host "Direct S3 URL: https://cc-web-dev-917343669425.s3.us-east-1.amazonaws.com/index.html"
Write-Host ""
Write-Host "Try accessing the Direct S3 URL to bypass CloudFront cache"
