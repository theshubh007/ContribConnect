# ContribConnect Prompt Understanding Fixes

## 🎯 Problem Analysis

Based on your test results, the chatbot has these specific issues:

### ✅ Working Correctly:
- **"Who are the top contributors?"** - Returns proper contributor list with counts

### ❌ Not Working Correctly:
- **"Who should review my PR?"** - Shows internal `<thinking>` process instead of clean response
- **"How can I contribute?"** - Returns contributor list instead of contribution guidance  
- **"Find good first issues"** - May not provide appropriate guidance
- **Empty queries** - Returns HTTP 400 instead of helpful message

## 🔧 Root Cause

The AI is not properly understanding user intent and generating appropriate responses for different question types.

## 📝 Files That Need to Be Updated

### 1. **Agent Proxy Lambda** (`lambda/agent-proxy/lambda_function.py`)

**Key Changes Made:**
- ✅ Added intent analysis to understand question types
- ✅ Improved system prompt to prevent `<thinking>` tags in responses
- ✅ Better response formatting guidelines
- ✅ Lower temperature (0.3) for more consistent responses
- ✅ Specific instructions for each question type

**Critical Fix:** The system prompt now explicitly states:
```
IMPORTANT RESPONSE GUIDELINES:
- NEVER show your internal thinking process to users
- NEVER include <thinking> tags or reasoning in your responses
- Always provide direct, helpful answers
```

### 2. **Graph Tool Lambda** (`lambda/graph-tool/lambda_function.py`)

**Key Changes Made:**
- ✅ Improved `find_reviewers` function to always return top contributors as reviewers
- ✅ Better handling of "good first issue" requests
- ✅ More consistent response format
- ✅ Enhanced error messages with helpful suggestions

## 🚀 Deployment Instructions for Your Friend

### Step 1: Update Agent Proxy Lambda
```bash
cd lambda/agent-proxy
zip -r agent-proxy-dev.zip lambda_function.py
aws lambda update-function-code \
    --function-name cc-agent-proxy-dev \
    --zip-file fileb://agent-proxy-dev.zip \
    --region us-east-1
```

### Step 2: Update Graph Tool Lambda  
```bash
cd lambda/graph-tool
zip -r graph-tool-dev.zip lambda_function.py
aws lambda update-function-code \
    --function-name cc-graph-tool-dev \
    --zip-file fileb://graph-tool-dev.zip \
    --region us-east-1
```

### Step 3: Test the Fixes
```bash
# Test PR Review (should no longer show <thinking>)
echo '{"message":"Who should review my PR for RooCodeInc/Roo-Code?","sessionId":"test-pr"}' > test.json
aws lambda invoke --function-name cc-agent-proxy-dev --payload file://test.json response.json
cat response.json

# Test Contribution Guide (should provide actual guidance)
echo '{"message":"How can I contribute to RooCodeInc/Roo-Code?","sessionId":"test-contrib"}' > test.json  
aws lambda invoke --function-name cc-agent-proxy-dev --payload file://test.json response.json
cat response.json
```

## 📊 Expected Results After Fix

### ✅ "Who should review my PR?" Should Return:
```
**Recommended Reviewers for RooCodeInc/Roo-Code:**

1. **[mrubens](https://github.com/mrubens)** - 1,854 contributions
2. **[saoudrizwan](https://github.com/saoudrizwan)** - 962 contributions  
3. **[cte](https://github.com/cte)** - 587 contributions

These contributors are most familiar with the codebase and can provide valuable feedback on your changes.
```

### ✅ "How can I contribute?" Should Return:
```
**How to Contribute to RooCodeInc/Roo-Code:**

1. **Fork the repository** and clone it locally
2. **Read the contribution guidelines** (check for CONTRIBUTING.md)
3. **Set up the development environment** following the README
4. **Contact key contributors** for guidance:
   - [mrubens](https://github.com/mrubens) - Lead maintainer (1,854 contributions)
   - [saoudrizwan](https://github.com/saoudrizwan) - Core contributor (962 contributions)

**Ways to Contribute:**
• Code contributions - Fix bugs, add features
• Documentation - Improve README, add guides
• Testing - Add unit tests, report bugs
• Feature requests - Suggest improvements
```

### ✅ "Find good first issues" Should Return:
```
There are no issues labeled as "good first issue" in the RooCodeInc/Roo-Code repository at the moment.

**Here are some ways to get started:**
• Check the Issues tab on GitHub for approachable issues
• Look for documentation improvements
• Contact the maintainers: [mrubens](https://github.com/mrubens) or [saoudrizwan](https://github.com/saoudrizwan)
• Consider reporting bugs or fixing typos
```

## 🧪 Testing Checklist

After deployment, verify these responses work correctly:

- [ ] **"Who are the top contributors?"** - ✅ Already working
- [ ] **"Who should review my PR?"** - Should show clean reviewer list (no `<thinking>`)
- [ ] **"How can I contribute?"** - Should show contribution steps (not just contributors)
- [ ] **"Find good first issues"** - Should provide helpful guidance
- [ ] **"Tell me about this repository"** - Should show overview with contributors
- [ ] **Empty message** - Should return helpful error message

## 🎯 Success Criteria

After these fixes:
- **No more `<thinking>` tags** in responses
- **Appropriate responses** for each question type  
- **Consistent formatting** with markdown and links
- **Actionable guidance** instead of just data dumps
- **Pass rate should improve from 63% to 85%+**

## 🚨 If Issues Persist

1. **Check CloudWatch Logs:**
   ```bash
   aws logs tail /aws/lambda/cc-agent-proxy-dev --follow
   ```

2. **Verify Environment Variables:**
   - `MODEL_ID`: us.amazon.nova-pro-v1:0
   - `GRAPH_TOOL_FUNCTION`: cc-graph-tool-dev
   - `SESSIONS_TABLE`: cc-agent-sessions-dev

3. **Test Individual Components:**
   ```bash
   # Test graph tool directly
   echo '{"action":"get_top_contributors","params":{"repo":"RooCodeInc/Roo-Code","limit":5}}' > test.json
   aws lambda invoke --function-name cc-graph-tool-dev --payload file://test.json response.json
   ```

## 💡 Key Insight

The main issue was that the AI was showing its internal reasoning process instead of providing clean, user-friendly responses. The fixes ensure that:

1. **Intent is properly analyzed** from user messages
2. **Responses are formatted appropriately** for each question type
3. **No internal processing** is shown to users
4. **Consistent, helpful guidance** is provided

These changes should dramatically improve the user experience and make the chatbot much more useful!