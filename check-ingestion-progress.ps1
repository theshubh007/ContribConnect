# Check Ingestion Progress
# This script monitors CloudWatch logs for the ingestion Lambda

Write-Host "==========================================="
Write-Host "Monitoring Ingestion Progress"
Write-Host "==========================================="
Write-Host ""

# Get the latest log stream
Write-Host "Fetching latest logs from CloudWatch..."
Write-Host ""

# Get logs from the last 10 minutes
$startTime = [int][double]::Parse((Get-Date).AddMinutes(-10).ToString("yyyyMMddHHmmss"))

aws logs tail /aws/lambda/cc-ingest-dev --follow --since 10m --region us-east-1
