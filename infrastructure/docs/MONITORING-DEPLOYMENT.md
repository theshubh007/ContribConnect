# CloudWatch Monitoring Deployment Guide

Quick guide to deploy CloudWatch monitoring for ContribConnect.

## Prerequisites

- AWS CLI configured with appropriate credentials
- PowerShell (Windows) or PowerShell Core (cross-platform)
- Existing Lambda functions deployed (cc-agent-proxy, cc-github-tool, cc-graph-tool, cc-ingest, etc.)

## Deployment Steps

### Step 1: Deploy Monitoring Infrastructure

Run the setup script:

```powershell
cd infrastructure/scripts
.\setup-cloudwatch-monitoring.ps1 -Environment dev -AlarmEmail your-email@example.com
```

This will create:
- 7 log groups with retention policies
- 2 CloudWatch dashboards
- 4 CloudWatch alarms
- 3 custom metric filters

**Expected output:**
```
===========================================
Setup CloudWatch Monitoring
Environment: dev
Region: us-east-1
===========================================

Step 1: Configure Log Groups and Retention
-------------------------------------------
Configuring log group: /aws/lambda/cc-agent-proxy-dev
  Creating log group...
  Setting retention to 7 days
...

Step 2: Create Agent Performance Dashboard
-------------------------------------------
Creating Agent Performance Dashboard...
Dashboard created: cc-agent-performance-dev

Step 3: Create Ingestion Metrics Dashboard
-------------------------------------------
Creating Ingestion Metrics Dashboard...
Dashboard created: cc-ingestion-metrics-dev

Step 4: Create CloudWatch Alarms
-------------------------------------------
Creating SNS topic for alarm notifications...
SNS Topic ARN: arn:aws:sns:us-east-1:123456789012:cc-alarms-dev
...

===========================================
CloudWatch Monitoring Setup Complete!
===========================================
```

### Step 2: Confirm SNS Subscription

Check your email inbox for a subscription confirmation from AWS SNS. Click the confirmation link to start receiving alarm notifications.

### Step 3: Update Lambda Functions with Structured Logging

Copy the logger utility to your Lambda deployment packages:

```powershell
# Copy logger to each Lambda function directory
Copy-Item lambda/common/logger.py lambda/agent-proxy/
Copy-Item lambda/common/logger.py lambda/github-tool/
Copy-Item lambda/common/logger.py lambda/graph-tool/
Copy-Item lambda/common/logger.py lambda/kb-tool/
Copy-Item lambda/common/logger.py lambda/qbiz-tool/
Copy-Item lambda/common/logger.py lambda/ingest/
```

### Step 4: Redeploy Lambda Functions

Redeploy your Lambda functions to include the structured logging:

```powershell
# Example for graph-tool
cd lambda/graph-tool
zip -r function.zip lambda_function.py logger.py
aws lambda update-function-code --function-name cc-graph-tool-dev --zip-file fileb://function.zip
```

Repeat for all Lambda functions.

### Step 5: Verify Monitoring Setup

1. **Check Dashboards**: Navigate to CloudWatch > Dashboards and verify both dashboards are created
2. **Check Alarms**: Navigate to CloudWatch > Alarms and verify all 4 alarms are in "OK" or "Insufficient data" state
3. **Check Log Groups**: Navigate to CloudWatch > Log groups and verify all 7 log groups exist
4. **Test Logging**: Invoke a Lambda function and check that structured JSON logs appear

## Testing the Monitoring

### Test 1: Verify Structured Logging

Invoke the graph-tool Lambda:

```powershell
$payload = '{"body":"{\"action\":\"find_reviewers\",\"params\":{\"labels\":[\"bug\"],\"repo\":\"test/repo\"}}"}'
$payload | Out-File -FilePath test-payload.json -Encoding ascii -NoNewline
aws lambda invoke --function-name cc-graph-tool-dev --payload file://test-payload.json response.json
```

Check the logs:

```powershell
aws logs tail /aws/lambda/cc-graph-tool-dev --follow
```

You should see JSON-formatted logs like:
```json
{"timestamp":"2025-10-19T12:34:56.789Z","request_id":"abc-123","level":"INFO","component":"graph-tool","message":"Processing graph query","action":"find_reviewers"}
```

### Test 2: Verify Dashboards

1. Open the Agent Performance Dashboard
2. Verify metrics are populating (may take a few minutes)
3. Check that the "Tool Invocation Count" widget shows data

### Test 3: Trigger an Alarm

Temporarily lower an alarm threshold to test notifications:

```powershell
aws cloudwatch put-metric-alarm --alarm-name cc-agent-error-rate-dev --threshold 1 --evaluation-periods 1
```

Then trigger an error in a Lambda function and verify you receive an email notification.

**Don't forget to reset the threshold afterwards!**

## Troubleshooting

### Issue: Log groups not created

**Solution**: Lambda functions create log groups automatically on first invocation. Invoke each function at least once.

### Issue: No data in dashboards

**Solution**: 
- Wait 5-10 minutes for metrics to populate
- Verify Lambda functions have been invoked
- Check that log groups contain logs

### Issue: Alarms stuck in "Insufficient data"

**Solution**: This is normal if Lambda functions haven't been invoked yet. The alarms will transition to "OK" once data is available.

### Issue: SNS subscription not confirmed

**Solution**: 
- Check spam folder for confirmation email
- Resend confirmation: `aws sns subscribe --topic-arn <topic-arn> --protocol email --notification-endpoint <email>`

### Issue: Structured logs not appearing

**Solution**:
- Verify logger.py is included in Lambda deployment package
- Check Lambda function imports logger correctly
- Verify Lambda has CloudWatch Logs permissions

## Cost Estimates

**CloudWatch Costs (approximate):**
- Log ingestion: $0.50/GB
- Log storage: $0.03/GB/month
- Dashboard: $3/month per dashboard
- Alarms: $0.10/month per alarm
- Metric filters: Free (first 10)

**Estimated monthly cost for dev environment**: $10-20/month

**Cost optimization tips:**
- Use 7-day retention for debug logs
- Delete old log groups
- Use CloudWatch Logs Insights instead of exporting logs
- Disable dashboards when not actively monitoring

## Next Steps

After deploying monitoring:

1. Review dashboards daily during development
2. Adjust alarm thresholds based on actual usage patterns
3. Create additional custom metrics as needed
4. Set up CloudWatch Logs Insights saved queries
5. Consider enabling AWS X-Ray for distributed tracing (optional task 15.1)

## Additional Resources

- [Full Monitoring Guide](./MONITORING.md)
- [CloudWatch Logs Insights Query Syntax](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html)
- [CloudWatch Pricing](https://aws.amazon.com/cloudwatch/pricing/)
