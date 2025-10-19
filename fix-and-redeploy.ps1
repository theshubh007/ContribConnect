# Fix and Redeploy Script

param(
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1"
)

Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Fix and Redeploy Ingestion" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Redeploy fixed Lambda
Write-Host "Step 1: Deploying fixed Lambda..." -ForegroundColor Yellow
.\lambda\redeploy-ingest.ps1 -Environment $Environment

Write-Host ""
Write-Host "Step 2: Configuring repositories..." -ForegroundColor Yellow

# Get current repos
Write-Host "Fetching current repositories..."
$repos = aws dynamodb scan --table-name "cc-repos-$Environment" --region $AwsRegion | ConvertFrom-Json

if ($repos.Items) {
    Write-Host "Found $($repos.Items.Count) repositories"
    
    # Disable all except Roo-Code
    foreach ($item in $repos.Items) {
        $org = $item.org.S
        $repo = $item.repo.S
        
        if ($org -eq "RooCodeInc" -and $repo -eq "Roo-Code") {
            Write-Host "  ✓ Enabling $org/$repo" -ForegroundColor Green
            
            $key = @{
                org = @{S = $org}
                repo = @{S = $repo}
            } | ConvertTo-Json -Compress
            
            $updateExpression = "SET enabled = :enabled"
            $expressionValues = @{
                ":enabled" = @{BOOL = $true}
            } | ConvertTo-Json -Compress
            
            aws dynamodb update-item --table-name "cc-repos-$Environment" --key $key --update-expression $updateExpression --expression-attribute-values $expressionValues --region $AwsRegion
        } else {
            Write-Host "  ✗ Disabling $org/$repo" -ForegroundColor Gray
            
            $key = @{
                org = @{S = $org}
                repo = @{S = $repo}
            } | ConvertTo-Json -Compress
            
            $updateExpression = "SET enabled = :enabled"
            $expressionValues = @{
                ":enabled" = @{BOOL = $false}
            } | ConvertTo-Json -Compress
            
            aws dynamodb update-item --table-name "cc-repos-$Environment" --key $key --update-expression $updateExpression --expression-attribute-values $expressionValues --region $AwsRegion
        }
    }
}

# Make sure Roo-Code exists
Write-Host ""
Write-Host "Ensuring RooCodeInc/Roo-Code exists..."
$key = @{
    org = @{S = "RooCodeInc"}
    repo = @{S = "Roo-Code"}
} | ConvertTo-Json -Compress

$ErrorActionPreference = "Continue"
$exists = aws dynamodb get-item --table-name "cc-repos-$Environment" --key $key --region $AwsRegion 2>&1
$ErrorActionPreference = "Stop"

if ($LASTEXITCODE -ne 0 -or -not $exists) {
    Write-Host "Adding RooCodeInc/Roo-Code..."
    
    $item = @{
        org = @{S = "RooCodeInc"}
        repo = @{S = "Roo-Code"}
        enabled = @{BOOL = $true}
        topics = @{L = @(@{S = "ai"}, @{S = "code-assistant"}, @{S = "vscode"})}
        minStars = @{N = "0"}
        description = @{S = "AI-powered code assistant"}
        ingestCursor = @{S = "2024-01-01T00:00:00Z"}
        lastIngestAt = @{S = ""}
        ingestStatus = @{S = "pending"}
        createdAt = @{S = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")}
        updatedAt = @{S = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")}
    } | ConvertTo-Json -Compress
    
    aws dynamodb put-item --table-name "cc-repos-$Environment" --item $item --region $AwsRegion
}

Write-Host ""
Write-Host "Step 3: Triggering ingestion..." -ForegroundColor Yellow
Write-Host "This will take 2-3 minutes for RooCodeInc/Roo-Code only..."

aws lambda invoke --function-name "cc-ingest-$Environment" --invocation-type Event --region $AwsRegion response.json

Write-Host ""
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Complete!" -ForegroundColor Green
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Ingestion started in background."
Write-Host "Check progress at: https://console.aws.amazon.com/cloudwatch/home?region=$AwsRegion#logsV2:log-groups/log-group/`$252Faws`$252Flambda`$252Fcc-ingest-$Environment"
Write-Host ""
Write-Host "Or check DynamoDB in 3 minutes:"
Write-Host "  aws dynamodb scan --table-name cc-nodes-$Environment --filter-expression `"nodeType = :type`" --expression-attribute-values '{`":type`":{`"S`":`"user`"}}' --max-items 5 --region $AwsRegion"
