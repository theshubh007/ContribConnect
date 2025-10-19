# ContribConnect Monitoring Guide

This guide explains how to set up and use CloudWatch monitoring for ContribConnect.

## Overview

The monitoring setup includes:
- **CloudWatch Dashboards**: Visual monitoring of agent performance and ingestion metrics
- **CloudWatch Alarms**: Automated alerts for critical errors and warnings
- **Structured Logging**: JSON-formatted logs for easy querying with CloudWatch Logs Insights
- **Custom Metrics**: Application-specific metrics tracked via metric filters

## Quick Start

### 1. Deploy Monitoring Infrastructure

Run the setup script to create all monitoring resources:

```powershell
.\infrastructure\scripts\setup-cloudwatch-monitoring.ps1 `
    -Environment dev `
    -AwsRegion us-east-1 `
    -AwsProfile default `
    -AlarmEmail your-email@example.com
```

**Parameters:**
- `Environment`: Environment name (dev/prod)
- `AwsRegion`: AWS region (default: us-east-1)
- `AwsProfile`: AWS CLI profile (default: default)
- `AlarmEmail`: Email address for alarm notifications (optional)

### 2. Confirm SNS Subscription

If you provided an email address, check your inbox and confirm the SNS subscription to receive alarm notifications.

### 3. View Dashboards

Access your dashboards in the AWS Console:
- [Agent Performance Dashboard](https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:)
- [Ingestion Metrics Dashboard](https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:)

## Dashboards

### Agent Performance Dashboard

**Metrics Tracked:**
- **Agent Response Time**: Average and p99 latency for agent requests
- **Tool Invocation Count**: Number of invocations per tool (stacked view)
- **Error Rate**: Lambda errors and throttles
- **Tool Invocations by Status**: Success/error breakdown by tool
- **Lambda Concurrency**: Current concurrent executions
- **Guardrails Activations**: Count of content filtering events

**Use Cases:**
- Monitor agent performance and identify slow tools
- Track error rates and investigate failures
- Verify guardrails are working correctly
- Identify scaling issues (high concurrency)

### Ingestion Metrics Dashboard

**Metrics Tracked:**
- **Ingestion Success/Failure Rate**: Count of successful vs failed ingestion runs
- **Records Processed Per Hour**: Total records ingested over time
- **Ingestion Duration**: Average and maximum execution time
- **GitHub API Rate Limit**: Remaining API calls
- **DynamoDB Write Capacity**: Consumed write capacity units
- **Ingestion Errors**: Error count over time

**Use Cases:**
- Monitor nightly ingestion jobs
- Track GitHub API rate limit usage
- Identify DynamoDB capacity issues
- Investigate ingestion failures

## Alarms

### Critical Alarms (Immediate Action Required)

#### 1. Agent Error Rate > 5%
- **Metric**: Lambda Errors
- **Threshold**: 5 errors in 5 minutes
- **Evaluation**: 2 consecutive periods
- **Action**: Check agent-proxy logs for error details

#### 2. Ingestion Failures
- **Metric**: Lambda Errors (cc-ingest function)
- **Threshold**: 1 error in 1 hour
- **Evaluation**: 2 consecutive periods
- **Action**: Check ingestion logs, verify GitHub token, check DynamoDB capacity

### Warning Alarms (Monitor and Investigate)

#### 3. Lambda Throttling
- **Metric**: Lambda Throttles
- **Threshold**: 10 throttles in 5 minutes
- **Action**: Increase reserved concurrency or optimize function performance

#### 4. DynamoDB High Capacity Usage
- **Metric**: ConsumedWriteCapacityUnits
- **Threshold**: 800 units in 5 minutes
- **Action**: Consider switching to provisioned capacity or optimize write patterns

## Structured Logging

### Log Format

All Lambda functions use structured JSON logging:

```json
{
  "timestamp": "2025-10-19T12:34:56.789Z",
  "request_id": "abc-123-def",
  "level": "INFO",
  "component": "github-tool",
  "message": "Tool invocation: github.create_pr",
  "tool_name": "github",
  "action": "create_pr",
  "duration_ms": 234.5,
  "status": "success",
  "pr_number": 123
}
```

### Using the Logger in Lambda Functions

Import and use the structured logger:

```python
from logger import StructuredLogger, log_execution

@log_execution("github-tool")
def lambda_handler(event, context):
    log = StructuredLogger("github-tool", context.request_id)
    
    # Simple log
    log.info("Processing request", repo="owner/repo")
    
    # Tool invocation log
    log.tool_invocation(
        tool_name="github",
        action="create_pr",
        duration_ms=234.5,
        status="success",
        pr_number=123
    )
    
    # Error log
    log.error("Failed to create PR", error="Rate limit exceeded")
    
    return {"statusCode": 200}
```

### Log Retention Policies

- **Debug Logs**: 7 days (agent-proxy, tools, API Gateway)
- **Audit Logs**: 30 days (ingestion pipeline)

## CloudWatch Logs Insights Queries

### Query 1: Tool Performance Analysis

Find average latency by tool:

```
SOURCE '/aws/lambda/cc-agent-proxy-dev'
| fields @timestamp, tool_name, duration_ms
| filter ispresent(tool_name)
| stats avg(duration_ms) as avg_latency, max(duration_ms) as max_latency, count() as invocations by tool_name
| sort avg_latency desc
```

### Query 2: Error Analysis

Find all errors in the last hour:

```
SOURCE '/aws/lambda/cc-agent-proxy-dev'
| fields @timestamp, component, action, error_message
| filter level = "ERROR"
| sort @timestamp desc
| limit 100
```

### Query 3: Ingestion Success Rate

Calculate ingestion success rate:

```
SOURCE '/aws/lambda/cc-ingest-dev'
| fields @timestamp, repo, status
| filter ispresent(repo)
| stats count() as total, sum(status = "success") as successes by bin(1h)
| fields @timestamp, (successes / total * 100) as success_rate
```

### Query 4: GitHub Rate Limit Tracking

Monitor GitHub API rate limit:

```
SOURCE '/aws/lambda/cc-ingest-dev'
| fields @timestamp, githubRateLimitRemaining
| filter ispresent(githubRateLimitRemaining)
| stats min(githubRateLimitRemaining) as min_remaining by bin(1h)
| sort @timestamp desc
```

### Query 5: Guardrail Activations

Track content filtering events:

```
SOURCE '/aws/lambda/cc-agent-proxy-dev'
| fields @timestamp, guardrail_type, message
| filter action like /guardrail/
| stats count() as activations by guardrail_type
```

## Custom Metrics

### Metric Filters

The setup creates three custom metric filters:

1. **ToolInvocations**: Tracks tool usage by tool name and status
2. **GuardrailActivations**: Counts content filtering events
3. **GitHubRateLimit**: Tracks remaining GitHub API calls

### Viewing Custom Metrics

Navigate to CloudWatch > Metrics > ContribConnect namespace to view custom metrics.

## Troubleshooting

### High Error Rate

1. Check the Agent Performance Dashboard for error trends
2. Run CloudWatch Logs Insights query to find error details
3. Check specific Lambda function logs for stack traces
4. Verify IAM permissions and service quotas

### Ingestion Failures

1. Check the Ingestion Metrics Dashboard
2. Verify GitHub token is valid (Secrets Manager)
3. Check GitHub API rate limit remaining
4. Verify DynamoDB tables are accessible
5. Check S3 bucket permissions

### Missing Logs

1. Verify Lambda functions have CloudWatch Logs permissions
2. Check log group names match Lambda function names
3. Verify log retention policies are set correctly

### Alarm Not Triggering

1. Verify SNS subscription is confirmed
2. Check alarm configuration (threshold, evaluation periods)
3. Verify metric data is being published
4. Check alarm state in CloudWatch console

## Cost Optimization

### Log Retention

- Keep debug logs for 7 days only
- Archive audit logs to S3 after 30 days
- Use CloudWatch Logs Insights instead of exporting logs

### Dashboard Optimization

- Use 5-minute periods for most metrics
- Limit log queries to necessary time ranges
- Use metric math to reduce API calls

### Alarm Optimization

- Set appropriate thresholds to avoid false positives
- Use composite alarms to reduce SNS costs
- Batch notifications when possible

## Best Practices

1. **Always use structured logging**: Makes querying and analysis much easier
2. **Include request IDs**: Enables tracing requests across services
3. **Log tool invocations**: Track performance and usage patterns
4. **Set up alarms early**: Catch issues before they impact users
5. **Review dashboards regularly**: Identify trends and optimization opportunities
6. **Use CloudWatch Logs Insights**: More powerful than searching raw logs
7. **Monitor costs**: CloudWatch can get expensive with high log volume

## Additional Resources

- [CloudWatch Logs Insights Query Syntax](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html)
- [CloudWatch Alarms](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html)
- [Lambda Monitoring](https://docs.aws.amazon.com/lambda/latest/dg/monitoring-functions.html)
- [DynamoDB Monitoring](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/monitoring-cloudwatch.html)
