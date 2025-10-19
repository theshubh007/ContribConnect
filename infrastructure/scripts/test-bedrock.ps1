# ContribConnect Bedrock Testing Script
# This script tests Bedrock Knowledge Base and Guardrails functionality

param(
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1",
    [string]$AwsProfile = "default"
)

$ErrorActionPreference = "Continue"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "ContribConnect Bedrock Testing" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Environment: $Environment"
Write-Host "Region: $AwsRegion"
Write-Host "Profile: $AwsProfile"
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Load configuration
$ConfigFile = "infrastructure/.bedrock-config-$Environment.json"
if (-not (Test-Path $ConfigFile)) {
    Write-Host "Error: Configuration file not found: $ConfigFile" -ForegroundColor Red
    Write-Host "Please run setup-bedrock.ps1 first" -ForegroundColor Yellow
    exit 1
}

$Config = Get-Content $ConfigFile | ConvertFrom-Json
$KnowledgeBaseId = $Config.knowledgeBaseId
$GuardrailId = $Config.guardrailId
$GuardrailVersion = $Config.guardrailVersion

Write-Host "Configuration loaded:" -ForegroundColor Green
Write-Host "  Knowledge Base ID: $KnowledgeBaseId"
Write-Host "  Guardrail ID: $GuardrailId"
Write-Host "  Guardrail Version: $GuardrailVersion"
Write-Host ""

$AllTestsPass = $true

# Test 1: Knowledge Base Retrieval
Write-Host "Test 1: Knowledge Base Retrieval" -ForegroundColor Yellow
Write-Host "-" * 60

try {
    Write-Host "Querying: 'How do I contribute to the project?'" -ForegroundColor Cyan
    
    $RetrieveResult = aws bedrock-agent-runtime retrieve `
      --knowledge-base-id $KnowledgeBaseId `
      --retrieval-query "text='How do I contribute to the project?'" `
      --region $AwsRegion `
      --profile $AwsProfile 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        $Results = $RetrieveResult | ConvertFrom-Json
        $ResultCount = $Results.retrievalResults.Count
        
        if ($ResultCount -gt 0) {
            Write-Host "✓ Retrieved $ResultCount results" -ForegroundColor Green
            Write-Host ""
            Write-Host "Sample result:" -ForegroundColor Cyan
            $FirstResult = $Results.retrievalResults[0]
            Write-Host "  Score: $($FirstResult.score)"
            Write-Host "  Content: $($FirstResult.content.text.Substring(0, [Math]::Min(200, $FirstResult.content.text.Length)))..."
            Write-Host ""
        } else {
            Write-Host "✗ No results returned (Knowledge Base may be empty)" -ForegroundColor Yellow
            Write-Host "  Upload documents and sync the Knowledge Base first" -ForegroundColor Yellow
        }
    } else {
        Write-Host "✗ Retrieval failed: $RetrieveResult" -ForegroundColor Red
        $AllTestsPass = $false
    }
} catch {
    Write-Host "✗ Error: $($_.Exception.Message)" -ForegroundColor Red
    $AllTestsPass = $false
}

Write-Host ""

# Test 2: Guardrail - Safe Content
Write-Host "Test 2: Guardrail - Safe Content" -ForegroundColor Yellow
Write-Host "-" * 60

try {
    Write-Host "Testing safe input: 'How do I contribute to open source?'" -ForegroundColor Cyan
    
    $SafeContent = @{
        text = @{
            text = "How do I contribute to open source projects?"
        }
    }
    
    $SafeContentJson = @($SafeContent) | ConvertTo-Json -Depth 10 -Compress
    
    $GuardrailResult = aws bedrock-runtime apply-guardrail `
      --guardrail-identifier $GuardrailId `
      --guardrail-version $GuardrailVersion `
      --source INPUT `
      --content $SafeContentJson `
      --region $AwsRegion `
      --profile $AwsProfile 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        $Result = $GuardrailResult | ConvertFrom-Json
        $Action = $Result.action
        
        if ($Action -eq "NONE") {
            Write-Host "✓ Safe content passed (action: $Action)" -ForegroundColor Green
        } else {
            Write-Host "✗ Safe content was blocked (action: $Action)" -ForegroundColor Red
            $AllTestsPass = $false
        }
    } else {
        Write-Host "✗ Guardrail test failed: $GuardrailResult" -ForegroundColor Red
        $AllTestsPass = $false
    }
} catch {
    Write-Host "✗ Error: $($_.Exception.Message)" -ForegroundColor Red
    $AllTestsPass = $false
}

Write-Host ""

# Test 3: Guardrail - Blocked Topic
Write-Host "Test 3: Guardrail - Blocked Topic" -ForegroundColor Yellow
Write-Host "-" * 60

try {
    Write-Host "Testing blocked topic: 'Tell me about politics'" -ForegroundColor Cyan
    
    $BlockedContent = @{
        text = @{
            text = "Tell me about the upcoming elections and who I should vote for"
        }
    }
    
    $BlockedContentJson = @($BlockedContent) | ConvertTo-Json -Depth 10 -Compress
    
    $GuardrailResult = aws bedrock-runtime apply-guardrail `
      --guardrail-identifier $GuardrailId `
      --guardrail-version $GuardrailVersion `
      --source INPUT `
      --content $BlockedContentJson `
      --region $AwsRegion `
      --profile $AwsProfile 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        $Result = $GuardrailResult | ConvertFrom-Json
        $Action = $Result.action
        
        if ($Action -eq "GUARDRAIL_INTERVENED") {
            Write-Host "✓ Blocked content was filtered (action: $Action)" -ForegroundColor Green
        } else {
            Write-Host "⚠ Blocked content was not filtered (action: $Action)" -ForegroundColor Yellow
            Write-Host "  This may be expected depending on guardrail sensitivity" -ForegroundColor Yellow
        }
    } else {
        Write-Host "✗ Guardrail test failed: $GuardrailResult" -ForegroundColor Red
        $AllTestsPass = $false
    }
} catch {
    Write-Host "✗ Error: $($_.Exception.Message)" -ForegroundColor Red
    $AllTestsPass = $false
}

Write-Host ""

# Test 4: Nova Model Access
Write-Host "Test 4: Nova Model Access" -ForegroundColor Yellow
Write-Host "-" * 60

try {
    Write-Host "Checking Nova Pro model access..." -ForegroundColor Cyan
    
    $Models = aws bedrock list-foundation-models `
      --region $AwsRegion `
      --profile $AwsProfile `
      --query "modelSummaries[?contains(modelId, 'nova-pro')].{id:modelId,status:modelLifecycle.status}" `
      --output json 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        $ModelList = $Models | ConvertFrom-Json
        
        if ($ModelList.Count -gt 0) {
            Write-Host "✓ Nova Pro model is available" -ForegroundColor Green
            foreach ($model in $ModelList) {
                Write-Host "  - $($model.id) (status: $($model.status))"
            }
        } else {
            Write-Host "✗ Nova Pro model not found" -ForegroundColor Red
            Write-Host "  Enable model access in Bedrock Console" -ForegroundColor Yellow
            $AllTestsPass = $false
        }
    } else {
        Write-Host "✗ Failed to list models: $Models" -ForegroundColor Red
        $AllTestsPass = $false
    }
} catch {
    Write-Host "✗ Error: $($_.Exception.Message)" -ForegroundColor Red
    $AllTestsPass = $false
}

Write-Host ""

# Test 5: Knowledge Base Data Source Status
Write-Host "Test 5: Knowledge Base Data Source Status" -ForegroundColor Yellow
Write-Host "-" * 60

try {
    Write-Host "Checking data source status..." -ForegroundColor Cyan
    
    $DataSources = aws bedrock-agent list-data-sources `
      --knowledge-base-id $KnowledgeBaseId `
      --region $AwsRegion `
      --profile $AwsProfile `
      --query "dataSourceSummaries[*].{name:name,id:dataSourceId,status:status}" `
      --output json 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        $DataSourceList = $DataSources | ConvertFrom-Json
        
        if ($DataSourceList.Count -gt 0) {
            Write-Host "✓ Found $($DataSourceList.Count) data source(s)" -ForegroundColor Green
            foreach ($ds in $DataSourceList) {
                Write-Host "  - $($ds.name) (status: $($ds.status))"
            }
        } else {
            Write-Host "⚠ No data sources configured" -ForegroundColor Yellow
            Write-Host "  Create a data source to enable document ingestion" -ForegroundColor Yellow
        }
    } else {
        Write-Host "✗ Failed to list data sources: $DataSources" -ForegroundColor Red
        $AllTestsPass = $false
    }
} catch {
    Write-Host "✗ Error: $($_.Exception.Message)" -ForegroundColor Red
    $AllTestsPass = $false
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan

if ($AllTestsPass) {
    Write-Host "All critical tests passed! ✓" -ForegroundColor Green
    Write-Host ""
    Write-Host "Bedrock services are configured correctly."
    Write-Host "You can proceed with Lambda function deployment."
    exit 0
} else {
    Write-Host "Some tests failed! ✗" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please review the errors above and:"
    Write-Host "1. Check Bedrock service configuration"
    Write-Host "2. Verify model access is enabled"
    Write-Host "3. Ensure Knowledge Base has documents"
    Write-Host "4. Review guardrail settings"
    exit 1
}
