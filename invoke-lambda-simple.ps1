# Simple Lambda invocation
Write-Host "Invoking Lambda..." -ForegroundColor Cyan

# Invoke with inline payload
aws lambda invoke `
    --function-name cc-ingest-dev `
    --cli-binary-format raw-in-base64-out `
    --payload '{"mode":"prs"}' `
    --region us-east-1 `
    response.json

Write-Host "`nResponse:" -ForegroundColor Yellow
type response.json

Write-Host "`n`nMonitor logs:" -ForegroundColor Cyan
Write-Host "aws logs tail /aws/lambda/cc-ingest-dev --follow --region us-east-1"
