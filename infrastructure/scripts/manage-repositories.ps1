# Repository Configuration Management Script
# Manages repository configurations in DynamoDB cc-repos table

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("add", "remove", "list", "enable", "disable", "init")]
    [string]$Action,
    
    [string]$Owner = "",
    [string]$Repo = "",
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1",
    [string]$AwsProfile = "default",
    [string[]]$Topics = @(),
    [int]$MinStars = 0
)

$ErrorActionPreference = "Stop"

# Get table name
$TableName = "cc-repos-$Environment"

Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Repository Configuration Management" -ForegroundColor Cyan
Write-Host "Action: $Action" -ForegroundColor Cyan
Write-Host "Table: $TableName" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""

function Initialize-ReposTable {
    Write-Host "Checking if table exists..." -ForegroundColor Yellow
    
    $TableExists = aws dynamodb describe-table --table-name $TableName --region $AwsRegion --profile $AwsProfile 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Table does not exist. Creating..." -ForegroundColor Yellow
        
        # Create table
        aws dynamodb create-table `
            --table-name $TableName `
            --attribute-definitions `
                AttributeName=org,AttributeType=S `
                AttributeName=repo,AttributeType=S `
            --key-schema `
                AttributeName=org,KeyType=HASH `
                AttributeName=repo,KeyType=RANGE `
            --billing-mode PAY_PER_REQUEST `
            --region $AwsRegion `
            --profile $AwsProfile
        
        Write-Host "Waiting for table to be active..." -ForegroundColor Yellow
        aws dynamodb wait table-exists --table-name $TableName --region $AwsRegion --profile $AwsProfile
        
        Write-Host "Table created successfully!" -ForegroundColor Green
    } else {
        Write-Host "Table already exists" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "Adding sample repositories..." -ForegroundColor Yellow
    
    # Sample repositories
    $SampleRepos = @(
        @{
            org = "RooCodeInc"
            repo = "Roo-Code"
            enabled = $true
            topics = @("ai", "code-assistant", "vscode-extension")
            minStars = 0
            description = "AI-powered code assistant"
        },
        @{
            org = "facebook"
            repo = "react"
            enabled = $true
            topics = @("javascript", "react", "frontend")
            minStars = 100
            description = "A declarative, efficient, and flexible JavaScript library"
        },
        @{
            org = "microsoft"
            repo = "vscode"
            enabled = $false
            topics = @("typescript", "editor", "ide")
            minStars = 100
            description = "Visual Studio Code"
        }
    )
    
    foreach ($sampleRepo in $SampleRepos) {
        $item = @{
            org = @{S = $sampleRepo.org}
            repo = @{S = $sampleRepo.repo}
            enabled = @{BOOL = $sampleRepo.enabled}
            topics = @{L = @($sampleRepo.topics | ForEach-Object { @{S = $_} })}
            minStars = @{N = $sampleRepo.minStars.ToString()}
            description = @{S = $sampleRepo.description}
            ingestCursor = @{S = "2024-01-01T00:00:00Z"}
            lastIngestAt = @{S = ""}
            ingestStatus = @{S = "pending"}
            createdAt = @{S = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")}
            updatedAt = @{S = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")}
        }
        
        $itemJson = $item | ConvertTo-Json -Depth 10 -Compress
        
        Write-Host "  Adding $($sampleRepo.org)/$($sampleRepo.repo)..."
        aws dynamodb put-item --table-name $TableName --item $itemJson --region $AwsRegion --profile $AwsProfile
    }
    
    Write-Host ""
    Write-Host "Sample repositories added successfully!" -ForegroundColor Green
}

function Add-Repository {
    param(
        [string]$Owner,
        [string]$Repo,
        [string[]]$Topics,
        [int]$MinStars
    )
    
    if (-not $Owner -or -not $Repo) {
        Write-Host "Error: Owner and Repo are required for add action" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Validating repository access..." -ForegroundColor Yellow
    
    # Check if repository exists and is accessible
    $repoInfo = gh api "repos/$Owner/$Repo" 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Cannot access repository $Owner/$Repo" -ForegroundColor Red
        Write-Host "Make sure the repository exists and you have access" -ForegroundColor Yellow
        exit 1
    }
    
    $repoData = $repoInfo | ConvertFrom-Json
    
    Write-Host "Repository found:" -ForegroundColor Green
    Write-Host "  Name: $($repoData.full_name)"
    Write-Host "  Description: $($repoData.description)"
    Write-Host "  Stars: $($repoData.stargazers_count)"
    Write-Host "  Language: $($repoData.language)"
    Write-Host ""
    
    # Prepare item
    $topicsList = if ($Topics.Count -gt 0) {
        @{L = @($Topics | ForEach-Object { @{S = $_} })}
    } else {
        @{L = @($repoData.topics | ForEach-Object { @{S = $_} })}
    }
    
    $item = @{
        org = @{S = $Owner}
        repo = @{S = $Repo}
        enabled = @{BOOL = $true}
        topics = $topicsList
        minStars = @{N = $MinStars.ToString()}
        description = @{S = $repoData.description}
        stars = @{N = $repoData.stargazers_count.ToString()}
        language = @{S = $repoData.language}
        ingestCursor = @{S = "2024-01-01T00:00:00Z"}
        lastIngestAt = @{S = ""}
        ingestStatus = @{S = "pending"}
        createdAt = @{S = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")}
        updatedAt = @{S = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")}
    }
    
    $itemJson = $item | ConvertTo-Json -Depth 10 -Compress
    
    Write-Host "Adding repository to DynamoDB..." -ForegroundColor Yellow
    aws dynamodb put-item --table-name $TableName --item $itemJson --region $AwsRegion --profile $AwsProfile
    
    Write-Host ""
    Write-Host "Repository $Owner/$Repo added successfully!" -ForegroundColor Green
}

function Remove-Repository {
    param(
        [string]$Owner,
        [string]$Repo
    )
    
    if (-not $Owner -or -not $Repo) {
        Write-Host "Error: Owner and Repo are required for remove action" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Removing repository $Owner/$Repo..." -ForegroundColor Yellow
    
    $key = @{
        org = @{S = $Owner}
        repo = @{S = $Repo}
    } | ConvertTo-Json -Compress
    
    aws dynamodb delete-item --table-name $TableName --key $key --region $AwsRegion --profile $AwsProfile
    
    Write-Host ""
    Write-Host "Repository $Owner/$Repo removed successfully!" -ForegroundColor Green
}

function Enable-Repository {
    param(
        [string]$Owner,
        [string]$Repo
    )
    
    if (-not $Owner -or -not $Repo) {
        Write-Host "Error: Owner and Repo are required for enable action" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Enabling repository $Owner/$Repo..." -ForegroundColor Yellow
    
    $key = @{
        org = @{S = $Owner}
        repo = @{S = $Repo}
    } | ConvertTo-Json -Compress
    
    $updateExpression = "SET enabled = :enabled, updatedAt = :updatedAt"
    $expressionValues = @{
        ":enabled" = @{BOOL = $true}
        ":updatedAt" = @{S = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")}
    } | ConvertTo-Json -Compress
    
    aws dynamodb update-item --table-name $TableName --key $key --update-expression $updateExpression --expression-attribute-values $expressionValues --region $AwsRegion --profile $AwsProfile
    
    Write-Host ""
    Write-Host "Repository $Owner/$Repo enabled successfully!" -ForegroundColor Green
}

function Disable-Repository {
    param(
        [string]$Owner,
        [string]$Repo
    )
    
    if (-not $Owner -or -not $Repo) {
        Write-Host "Error: Owner and Repo are required for disable action" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Disabling repository $Owner/$Repo..." -ForegroundColor Yellow
    
    $key = @{
        org = @{S = $Owner}
        repo = @{S = $Repo}
    } | ConvertTo-Json -Compress
    
    $updateExpression = "SET enabled = :enabled, updatedAt = :updatedAt"
    $expressionValues = @{
        ":enabled" = @{BOOL = $false}
        ":updatedAt" = @{S = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")}
    } | ConvertTo-Json -Compress
    
    aws dynamodb update-item --table-name $TableName --key $key --update-expression $updateExpression --expression-attribute-values $expressionValues --region $AwsRegion --profile $AwsProfile
    
    Write-Host ""
    Write-Host "Repository $Owner/$Repo disabled successfully!" -ForegroundColor Green
}

function List-Repositories {
    Write-Host "Fetching repositories from DynamoDB..." -ForegroundColor Yellow
    Write-Host ""
    
    $result = aws dynamodb scan --table-name $TableName --region $AwsRegion --profile $AwsProfile | ConvertFrom-Json
    
    if ($result.Items.Count -eq 0) {
        Write-Host "No repositories found" -ForegroundColor Yellow
        return
    }
    
    Write-Host "Found $($result.Items.Count) repositories:" -ForegroundColor Green
    Write-Host ""
    
    $repos = @()
    foreach ($item in $result.Items) {
        $repos += [PSCustomObject]@{
            Repository = "$($item.org.S)/$($item.repo.S)"
            Enabled = $item.enabled.BOOL
            Stars = if ($item.stars) { $item.stars.N } else { "N/A" }
            Language = if ($item.language) { $item.language.S } else { "N/A" }
            Status = $item.ingestStatus.S
            LastIngest = if ($item.lastIngestAt.S) { $item.lastIngestAt.S } else { "Never" }
        }
    }
    
    $repos | Format-Table -AutoSize
    
    Write-Host ""
    Write-Host "Enabled repositories: $($repos | Where-Object { $_.Enabled } | Measure-Object | Select-Object -ExpandProperty Count)" -ForegroundColor Cyan
    Write-Host "Disabled repositories: $($repos | Where-Object { -not $_.Enabled } | Measure-Object | Select-Object -ExpandProperty Count)" -ForegroundColor Cyan
}

# Execute action
switch ($Action) {
    "init" {
        Initialize-ReposTable
    }
    "add" {
        Add-Repository -Owner $Owner -Repo $Repo -Topics $Topics -MinStars $MinStars
    }
    "remove" {
        Remove-Repository -Owner $Owner -Repo $Repo
    }
    "enable" {
        Enable-Repository -Owner $Owner -Repo $Repo
    }
    "disable" {
        Disable-Repository -Owner $Owner -Repo $Repo
    }
    "list" {
        List-Repositories
    }
}

Write-Host ""
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Operation Complete!" -ForegroundColor Green
Write-Host "===========================================" -ForegroundColor Cyan
