# Setup CloudWatch Monitoring for ContribConnect
# Creates dashboards, alarms, and log retention policies

param(
    [string]$Environment = "dev",
    [string]$AwsRegion = "us-east-1",
    [string]$AwsProfile = "default",
    [string]$AlarmEmail = ""
)

$ErrorActionPreference = "Stop"

Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "Setup CloudWatch Monitoring" -ForegroundColor Cyan
Write-Host "Environment: $Environment" -ForegroundColor Cyan
Write-Host "Region: $AwsRegion" -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan

# Get AWS Account ID
$AwsAccountId = aws sts get-caller-identity --profile $AwsProfile --query Account --output text

Write-Host ""
Write-Host "Step 1: Configure Log Groups and Retention" -ForegroundColor Yellow
Write-Host "-------------------------------------------"

# Define log groups with retention policies
$LogGroups = @(
    @{Name="/aws/lambda/cc-agent-proxy-$Environment"; Retention=7},
    @{Name="/aws/lambda/cc-github-tool-$Environment"; Retention=7},
    @{Name="/aws/lambda/cc-graph-tool-$Environment"; Retention=7},
    @{Name="/aws/lambda/cc-kb-tool-$Environment"; Retention=7},
    @{Name="/aws/lambda/cc-qbiz-tool-$Environment"; Retention=7},
    @{Name="/aws/lambda/cc-ingest-$Environment"; Retention=30},
    @{Name="/aws/apigateway/cc-api-$Environment"; Retention=7}
)

foreach ($LogGroup in $LogGroups) {
    Write-Host "Configuring log group: $($LogGroup.Name)"
    
    # Check if log group exists
    $LogGroupExists = aws logs describe-log-groups --log-group-name-prefix $LogGroup.Name --region $AwsRegion --profile $AwsProfile --query "logGroups[?logGroupName=='$($LogGroup.Name)'].logGroupName" --output text
    
    if (-not $LogGroupExists) {
        Write-Host "  Creating log group..." -ForegroundColor Green
        aws logs create-log-group --log-group-name $LogGroup.Name --region $AwsRegion --profile $AwsProfile
    } else {
        Write-Host "  Log group already exists" -ForegroundColor Gray
    }
    
    # Set retention policy
    Write-Host "  Setting retention to $($LogGroup.Retention) days"
    aws logs put-retention-policy --log-group-name $LogGroup.Name --retention-in-days $LogGroup.Retention --region $AwsRegion --profile $AwsProfile
}

Write-Host ""
Write-Host "Step 2: Create Agent Performance Dashboard" -ForegroundColor Yellow
Write-Host "-------------------------------------------"

# Create Agent Performance Dashboard
$AgentDashboard = @"
{
    "widgets": [
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/Lambda", "Duration", {"stat": "Average", "label": "Avg Response Time"}],
                    ["...", {"stat": "p99", "label": "p99 Response Time"}]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "$AwsRegion",
                "title": "Agent Response Time",
                "period": 300,
                "yAxis": {
                    "left": {
                        "label": "Milliseconds"
                    }
                }
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/Lambda", "Invocations", {"stat": "Sum", "label": "agent-proxy"}],
                    ["...", {"stat": "Sum", "label": "github-tool"}],
                    ["...", {"stat": "Sum", "label": "graph-tool"}],
                    ["...", {"stat": "Sum", "label": "kb-tool"}],
                    ["...", {"stat": "Sum", "label": "qbiz-tool"}]
                ],
                "view": "timeSeries",
                "stacked": true,
                "region": "$AwsRegion",
                "title": "Tool Invocation Count",
                "period": 300
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/Lambda", "Errors", {"stat": "Sum", "label": "Errors"}],
                    [".", "Throttles", {"stat": "Sum", "label": "Throttles"}]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "$AwsRegion",
                "title": "Error Rate",
                "period": 300,
                "yAxis": {
                    "left": {
                        "min": 0
                    }
                }
            }
        },
        {
            "type": "log",
            "properties": {
                "query": "SOURCE '/aws/lambda/cc-agent-proxy-$Environment'\n| fields @timestamp, toolName, latencyMs, status\n| filter ispresent(toolName)\n| stats count() by toolName, status",
                "region": "$AwsRegion",
                "title": "Tool Invocations by Status",
                "stacked": false
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/Lambda", "ConcurrentExecutions", {"stat": "Maximum"}]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "$AwsRegion",
                "title": "Lambda Concurrency",
                "period": 60
            }
        },
        {
            "type": "log",
            "properties": {
                "query": "SOURCE '/aws/lambda/cc-agent-proxy-$Environment'\n| fields @timestamp, @message\n| filter @message like /guardrail/\n| stats count() as GuardrailActivations by bin(5m)",
                "region": "$AwsRegion",
                "title": "Guardrails Activations",
                "stacked": false
            }
        }
    ]
}
"@

$AgentDashboardFile = "agent-dashboard-$Environment.json"
$AgentDashboard | Out-File -FilePath $AgentDashboardFile -Encoding utf8

Write-Host "Creating Agent Performance Dashboard..."
aws cloudwatch put-dashboard --dashboard-name "cc-agent-performance-$Environment" --dashboard-body "file://$AgentDashboardFile" --region $AwsRegion --profile $AwsProfile

Remove-Item $AgentDashboardFile
Write-Host "Dashboard created: cc-agent-performance-$Environment" -ForegroundColor Green

Write-Host ""
Write-Host "Step 3: Create Ingestion Metrics Dashboard" -ForegroundColor Yellow
Write-Host "-------------------------------------------"

# Create Ingestion Dashboard
$IngestionDashboard = @"
{
    "widgets": [
        {
            "type": "log",
            "properties": {
                "query": "SOURCE '/aws/lambda/cc-ingest-$Environment'\n| fields @timestamp, repo, status\n| filter ispresent(repo)\n| stats count() by status",
                "region": "$AwsRegion",
                "title": "Ingestion Success/Failure Rate",
                "stacked": false
            }
        },
        {
            "type": "log",
            "properties": {
                "query": "SOURCE '/aws/lambda/cc-ingest-$Environment'\n| fields @timestamp, recordsProcessed\n| filter ispresent(recordsProcessed)\n| stats sum(recordsProcessed) as TotalRecords by bin(1h)",
                "region": "$AwsRegion",
                "title": "Records Processed Per Hour",
                "stacked": false
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/Lambda", "Duration", {"stat": "Average", "label": "Avg Duration"}],
                    ["...", {"stat": "Maximum", "label": "Max Duration"}]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "$AwsRegion",
                "title": "Ingestion Duration",
                "period": 3600,
                "yAxis": {
                    "left": {
                        "label": "Milliseconds"
                    }
                }
            }
        },
        {
            "type": "log",
            "properties": {
                "query": "SOURCE '/aws/lambda/cc-ingest-$Environment'\n| fields @timestamp, githubRateLimitRemaining\n| filter ispresent(githubRateLimitRemaining)\n| stats min(githubRateLimitRemaining) as MinRateLimit by bin(1h)",
                "region": "$AwsRegion",
                "title": "GitHub API Rate Limit Remaining",
                "stacked": false
            }
        },
        {
            "type": "metric",
            "properties": {
                "metrics": [
                    ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", {"stat": "Sum"}]
                ],
                "view": "timeSeries",
                "stacked": false,
                "region": "$AwsRegion",
                "title": "DynamoDB Write Capacity",
                "period": 300
            }
        },
        {
            "type": "log",
            "properties": {
                "query": "SOURCE '/aws/lambda/cc-ingest-$Environment'\n| fields @timestamp, @message\n| filter @message like /ERROR/\n| stats count() as ErrorCount by bin(1h)",
                "region": "$AwsRegion",
                "title": "Ingestion Errors",
                "stacked": false
            }
        }
    ]
}
"@

$IngestionDashboardFile = "ingestion-dashboard-$Environment.json"
$IngestionDashboard | Out-File -FilePath $IngestionDashboardFile -Encoding utf8

Write-Host "Creating Ingestion Metrics Dashboard..."
aws cloudwatch put-dashboard --dashboard-name "cc-ingestion-metrics-$Environment" --dashboard-body "file://$IngestionDashboardFile" --region $AwsRegion --profile $AwsProfile

Remove-Item $IngestionDashboardFile
Write-Host "Dashboard created: cc-ingestion-metrics-$Environment" -ForegroundColor Green

Write-Host ""
Write-Host "Step 4: Create CloudWatch Alarms" -ForegroundColor Yellow
Write-Host "-------------------------------------------"

# Create SNS topic for alarms if email provided
if ($AlarmEmail) {
    Write-Host "Creating SNS topic for alarm notifications..."
    
    $TopicArn = aws sns create-topic --name "cc-alarms-$Environment" --region $AwsRegion --profile $AwsProfile --query 'TopicArn' --output text
    
    Write-Host "SNS Topic ARN: $TopicArn"
    
    # Subscribe email to topic
    Write-Host "Subscribing $AlarmEmail to SNS topic..."
    aws sns subscribe --topic-arn $TopicArn --protocol email --notification-endpoint $AlarmEmail --region $AwsRegion --profile $AwsProfile
    
    Write-Host "Please check your email and confirm the subscription!" -ForegroundColor Yellow
} else {
    Write-Host "No alarm email provided. Skipping SNS topic creation." -ForegroundColor Gray
    Write-Host "To enable email notifications, run with -AlarmEmail parameter" -ForegroundColor Gray
    $TopicArn = $null
}

# Critical Alarm: Agent Error Rate > 5%
Write-Host ""
Write-Host "Creating alarm: Agent Error Rate > 5%"
aws cloudwatch put-metric-alarm --alarm-name "cc-agent-error-rate-$Environment" --alarm-description "Agent error rate exceeds 5%" --metric-name Errors --namespace AWS/Lambda --statistic Sum --period 300 --threshold 5 --comparison-operator GreaterThanThreshold --evaluation-periods 2 --treat-missing-data notBreaching --region $AwsRegion --profile $AwsProfile $(if ($TopicArn) { "--alarm-actions $TopicArn" })

# Critical Alarm: Ingestion Failures
Write-Host "Creating alarm: Ingestion Failures"
aws cloudwatch put-metric-alarm --alarm-name "cc-ingestion-failures-$Environment" --alarm-description "Ingestion Lambda function failures" --metric-name Errors --namespace AWS/Lambda --dimensions Name=FunctionName,Value=cc-ingest-$Environment --statistic Sum --period 3600 --threshold 1 --comparison-operator GreaterThanThreshold --evaluation-periods 2 --treat-missing-data notBreaching --region $AwsRegion --profile $AwsProfile $(if ($TopicArn) { "--alarm-actions $TopicArn" })

# Warning Alarm: Lambda Throttling
Write-Host "Creating alarm: Lambda Throttling"
aws cloudwatch put-metric-alarm --alarm-name "cc-lambda-throttles-$Environment" --alarm-description "Lambda functions being throttled" --metric-name Throttles --namespace AWS/Lambda --statistic Sum --period 300 --threshold 10 --comparison-operator GreaterThanThreshold --evaluation-periods 1 --treat-missing-data notBreaching --region $AwsRegion --profile $AwsProfile $(if ($TopicArn) { "--alarm-actions $TopicArn" })

# Warning Alarm: DynamoDB Capacity
Write-Host "Creating alarm: DynamoDB High Capacity Usage"
aws cloudwatch put-metric-alarm --alarm-name "cc-dynamodb-capacity-$Environment" --alarm-description "DynamoDB capacity usage > 80%" --metric-name ConsumedWriteCapacityUnits --namespace AWS/DynamoDB --statistic Sum --period 300 --threshold 800 --comparison-operator GreaterThanThreshold --evaluation-periods 2 --treat-missing-data notBreaching --region $AwsRegion --profile $AwsProfile $(if ($TopicArn) { "--alarm-actions $TopicArn" })

Write-Host ""
Write-Host "Step 5: Create Metric Filters for Custom Metrics" -ForegroundColor Yellow
Write-Host "-------------------------------------------"

# Metric filter for tool invocations
Write-Host "Creating metric filter: Tool Invocations"
$ToolInvocationPattern = '[timestamp, request_id, level, component, action, tool_name, duration, status]'
aws logs put-metric-filter --log-group-name "/aws/lambda/cc-agent-proxy-$Environment" --filter-name "ToolInvocations" --filter-pattern "$ToolInvocationPattern" --metric-transformations "metricName=ToolInvocations,metricNamespace=ContribConnect,metricValue=1,defaultValue=0,dimensions={Tool=`$tool_name,Status=`$status}" --region $AwsRegion --profile $AwsProfile

# Metric filter for guardrail activations
Write-Host "Creating metric filter: Guardrail Activations"
aws logs put-metric-filter --log-group-name "/aws/lambda/cc-agent-proxy-$Environment" --filter-name "GuardrailActivations" --filter-pattern "[timestamp, request_id, level, component, action=guardrail*, ...]" --metric-transformations "metricName=GuardrailActivations,metricNamespace=ContribConnect,metricValue=1,defaultValue=0" --region $AwsRegion --profile $AwsProfile

# Metric filter for GitHub rate limit
Write-Host "Creating metric filter: GitHub Rate Limit"
aws logs put-metric-filter --log-group-name "/aws/lambda/cc-ingest-$Environment" --filter-name "GitHubRateLimit" --filter-pattern "[timestamp, request_id, level, component, action, rate_limit]" --metric-transformations "metricName=GitHubRateLimitRemaining,metricNamespace=ContribConnect,metricValue=`$rate_limit,defaultValue=0" --region $AwsRegion --profile $AwsProfile

Write-Host ""
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host "CloudWatch Monitoring Setup Complete!" -ForegroundColor Green
Write-Host "===========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Created Resources:" -ForegroundColor Cyan
Write-Host "  - Log Groups: $($LogGroups.Count) configured with retention policies"
Write-Host "  - Dashboards:"
Write-Host "    * cc-agent-performance-$Environment"
Write-Host "    * cc-ingestion-metrics-$Environment"
Write-Host "  - Alarms:"
Write-Host "    * cc-agent-error-rate-$Environment"
Write-Host "    * cc-ingestion-failures-$Environment"
Write-Host "    * cc-lambda-throttles-$Environment"
Write-Host "    * cc-dynamodb-capacity-$Environment"
Write-Host "  - Metric Filters: 3 custom metrics"
Write-Host ""
Write-Host "View Dashboards:" -ForegroundColor Yellow
Write-Host "  https://console.aws.amazon.com/cloudwatch/home?region=$AwsRegion#dashboards:"
Write-Host ""
Write-Host "View Alarms:" -ForegroundColor Yellow
Write-Host "  https://console.aws.amazon.com/cloudwatch/home?region=$AwsRegion#alarmsV2:"
Write-Host ""

if ($AlarmEmail) {
    Write-Host "IMPORTANT: Check your email ($AlarmEmail) and confirm the SNS subscription!" -ForegroundColor Yellow
}
