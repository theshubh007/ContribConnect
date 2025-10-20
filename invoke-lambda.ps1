# Invoke Lambda to scrape PRs
Write-Host "Invoking Lambda to scrape PRs..." -ForegroundColor Cyan

# Create payload file with ASCII encoding
'{"mode":"prs"}' | Out-File -FilePath "payload.json" -Encoding ASCII -NoNewline

# Invoke Lambda
Write-Host "Running AWS Lambda invoke..." -ForegroundColor Yellow
aws lambda invoke --function-name cc-ingest-dev --cli-binary-format raw-in-base64-out --payload file://payload.json --region us-east-1 response.json

Write-Host "`n=== Response ===" -ForegroundColor Cyan
Get-Content response.json

Write-Host "`n=== Monitor logs with ===" -ForegroundColor Yellow
Write-Host "aws logs tail /aws/lambda/cc-ingest-dev --follow --region us-east-1" -ForegroundColor White
