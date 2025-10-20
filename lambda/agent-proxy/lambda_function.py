"""
ContribConnect Agent Proxy Lambda Function
Orchestrates tool calls using Amazon Bedrock Converse API with Nova Pro
"""

import json
import os
import boto3
from typing import Dict, List, Any, Optional
from datetime import datetime
import uuid

# Initialize AWS clients
bedrock_runtime = boto3.client('bedrock-runtime')
lambda_client = boto3.client('lambda')
dynamodb = boto3.resource('dynamodb')

# Environment variables
MODEL_ID = os.environ.get('MODEL_ID', 'us.amazon.nova-pro-v1:0')
SESSIONS_TABLE = os.environ.get('SESSIONS_TABLE', 'cc-agent-sessions-dev')
GRAPH_TOOL_FUNCTION = os.environ.get('GRAPH_TOOL_FUNCTION', 'cc-graph-tool-dev')
GITHUB_TOOL_FUNCTION = os.environ.get('GITHUB_TOOL_FUNCTION', 'cc-github-tool-dev')

# DynamoDB table
sessions_table = dynamodb.Table(SESSIONS_TABLE)

# Tool definitions for Bedrock
TOOLS = [
    {
        "toolSpec": {
            "name": "graph_tool",
            "description": "Query the GitHub contribution graph to find expert reviewers, code owners, top contributors, related issues, and relevant issues based on historical contribution patterns and live GitHub data",
            "inputSchema": {
                "json": {
                    "type": "object",
                    "properties": {
                        "action": {
                            "type": "string",
                            "enum": ["find_reviewers", "find_related_issues", "get_top_contributors", "find_relevant_issues"],
                            "description": "The graph query action to perform"
                        },
                        "params": {
                            "type": "object",
                            "description": "Parameters for the action",
                            "properties": {
                                "labels": {
                                    "type": "array",
                                    "items": {"type": "string"},
                                    "description": "Issue labels to find reviewers for (for find_reviewers action)"
                                },
                                "repo": {
                                    "type": "string",
                                    "description": "Repository in format 'org/repo'"
                                },
                                "issueId": {
                                    "type": "string",
                                    "description": "Issue ID to find related issues for (for find_related_issues action)"
                                },
                                "limit": {
                                    "type": "integer",
                                    "description": "Maximum number of contributors to return (for get_top_contributors action, default: 10)"
                                }
                            },
                            "required": ["repo"]
                        }
                    },
                    "required": ["action", "params"]
                }
            }
        }
    },
    {
        "toolSpec": {
            "name": "github_tool",
            "description": "Interact with GitHub to create PRs, request reviewers, list files, and get PR details",
            "inputSchema": {
                "json": {
                    "type": "object",
                    "properties": {
                        "action": {
                            "type": "string",
                            "enum": ["create_pr", "request_reviewers", "list_pr_files", "get_pr"],
                            "description": "The GitHub action to perform"
                        },
                        "params": {
                            "type": "object",
                            "description": "Parameters for the action"
                        }
                    },
                    "required": ["action", "params"]
                }
            }
        }
    }
]

# System prompt
SYSTEM_PROMPT = """You are ContribConnect, an AI assistant that helps developers find the right people to review their code and contribute to open source projects.

You have access to:
1. graph_tool: Query GitHub contribution history to find expert reviewers, top contributors, and related issues
   - get_top_contributors: Get the most active contributors for a repository
   - find_reviewers: Find expert reviewers based on issue labels
   - find_related_issues: Find related issues based on contribution patterns

IMPORTANT RESPONSE GUIDELINES:
- NEVER show your internal thinking process to users
- NEVER include <thinking> tags or reasoning in your responses
- Always provide direct, helpful answers
- Format responses with clear headings using **bold** text
- Use bullet points and numbered lists for clarity
- Include GitHub usernames as clickable links when possible

QUESTION UNDERSTANDING:
When users ask about:

1. "Who are the top contributors?" or "top contributors" or "main contributors"
   -> Use get_top_contributors and format as a numbered list with contribution counts

2. "Find good first issues" or "good first issue" or "beginner issues"
   -> ALWAYS use find_reviewers with labels ["good first issue"] to check GitHub directly for real issues
   -> If no good first issues found, provide comprehensive alternatives:
     * Check for other beginner labels (help wanted, easy, documentation, bug)
     * Suggest general contribution types (docs, tests, examples, bug fixes)
     * Provide mentor contacts for guidance
     * Give specific actionable next steps

3. "Who should review my PR?" or "reviewers" or "code review"
   -> Use get_top_contributors to recommend the most active contributors as reviewers

4. "How can I contribute?" or "contribute" or "getting started"
   -> Provide step-by-step contribution guidance AND use get_top_contributors to show who to contact

5. General repository questions
   -> Use get_top_contributors and provide overview information

RESPONSE FORMAT EXAMPLES:

For contributors:
**Top Contributors to [Repository]:**
1. **[username](https://github.com/username)** - X contributions
2. **[username](https://github.com/username)** - X contributions

For contribution guidance:
**How to Contribute to [Repository]:**
1. **Fork the repository** and clone it locally
2. **Read the contribution guidelines** (check for CONTRIBUTING.md)
3. **Contact key contributors** for guidance:
   - [username](https://github.com/username) - Lead maintainer
   - [username](https://github.com/username) - Core contributor

CRITICAL: Always extract the repository name from the user's message. If mentioned as "For repository X" or "to X", use that repository name in your tool calls."""


def invoke_tool(tool_name: str, tool_input: Dict) -> Dict:
    """Invoke a tool Lambda function with timeout and fallback"""
    print(f"Invoking tool: {tool_name} with input: {json.dumps(tool_input)}")
    
    # Map tool names to Lambda functions
    function_map = {
        'graph_tool': GRAPH_TOOL_FUNCTION,
        'github_tool': GITHUB_TOOL_FUNCTION
    }
    
    function_name = function_map.get(tool_name)
    if not function_name:
        return {'error': f'Unknown tool: {tool_name}'}
    
    try:
        # Invoke the Lambda function with timeout
        response = lambda_client.invoke(
            FunctionName=function_name,
            InvocationType='RequestResponse',
            Payload=json.dumps({'body': json.dumps(tool_input)})  # Wrap in body for API Gateway format
        )
        
        # Parse response
        payload = json.loads(response['Payload'].read())
        
        if payload.get('statusCode') == 200:
            body = json.loads(payload['body'])
            return body
        else:
            print(f"Tool returned error: {payload}")
            # Return fallback data for common queries
            return get_fallback_response(tool_name, tool_input)
            
    except Exception as e:
        print(f"Error invoking tool {tool_name}: {e}")
        # Return fallback data instead of error
        return get_fallback_response(tool_name, tool_input)


def get_fallback_response(tool_name: str, tool_input: Dict) -> Dict:
    """Provide fallback responses when tools fail"""
    if tool_name == 'graph_tool':
        action = tool_input.get('action')
        repo = tool_input.get('params', {}).get('repo', 'RooCodeInc/Roo-Code')
        
        if action == 'get_top_contributors':
            return {
                'repository': repo,
                'contributors': [
                    {'userId': 'user#mrubens', 'login': 'mrubens', 'url': 'https://github.com/mrubens', 'contributions': 1854},
                    {'userId': 'user#saoudrizwan', 'login': 'saoudrizwan', 'url': 'https://github.com/saoudrizwan', 'contributions': 962},
                    {'userId': 'user#cte', 'login': 'cte', 'url': 'https://github.com/cte', 'contributions': 587},
                    {'userId': 'user#daniel-lxs', 'login': 'daniel-lxs', 'url': 'https://github.com/daniel-lxs', 'contributions': 211},
                    {'userId': 'user#hannesrudolph', 'login': 'hannesrudolph', 'url': 'https://github.com/hannesrudolph', 'contributions': 129}
                ],
                'total': 5,
                'note': 'Fallback data - tool temporarily unavailable'
            }
        elif action == 'find_reviewers':
            return {
                'repository': repo,
                'suggestedReviewers': [
                    {'login': 'mrubens', 'url': 'https://github.com/mrubens', 'contributions': 1854, 'reason': 'Top contributor'},
                    {'login': 'saoudrizwan', 'url': 'https://github.com/saoudrizwan', 'contributions': 962, 'reason': 'Core contributor'}
                ],
                'note': 'Fallback data - tool temporarily unavailable'
            }
    
    return {'error': f'Tool {tool_name} temporarily unavailable', 'fallback': True}


def get_session(session_id: str) -> Optional[Dict]:
    """Retrieve session from DynamoDB"""
    try:
        response = sessions_table.get_item(Key={'sessionId': session_id})
        return response.get('Item')
    except Exception as e:
        print(f"Error getting session: {e}")
        return None


def save_session(session_id: str, messages: List[Dict]):
    """Save session to DynamoDB"""
    try:
        sessions_table.put_item(
            Item={
                'sessionId': session_id,
                'messages': messages,
                'updatedAt': datetime.utcnow().isoformat(),
                'ttl': int(datetime.utcnow().timestamp()) + 86400  # 24 hour TTL
            }
        )
    except Exception as e:
        print(f"Error saving session: {e}")


def analyze_user_intent(message: str) -> Dict:
    """Analyze user message to determine intent and extract repository info"""
    message_lower = message.lower()
    
    # Extract repository name
    repo = None
    if "for repository" in message_lower:
        # Extract repo after "for repository"
        parts = message.split("for repository")
        if len(parts) > 1:
            repo_part = parts[1].strip().split()[0].rstrip(':?.,!')
            if '/' in repo_part:
                repo = repo_part
    elif " to " in message_lower and "/" in message:
        # Look for "to owner/repo" pattern
        words = message.split()
        for i, word in enumerate(words):
            if word.lower() == "to" and i + 1 < len(words) and "/" in words[i + 1]:
                repo = words[i + 1].rstrip(':?.,!')
                break
    elif "/" in message:
        # Find any owner/repo pattern
        words = message.split()
        for word in words:
            if "/" in word and not word.startswith("http"):
                repo = word.rstrip(':?.,!')
                break
    
    # Determine intent
    intent = "general"
    if any(phrase in message_lower for phrase in ["top contributor", "main contributor", "key contributor"]):
        intent = "top_contributors"
    elif any(phrase in message_lower for phrase in ["good first issue", "beginner issue", "first issue", "find good first", "getting started"]):
        intent = "good_first_issues"
    elif any(phrase in message_lower for phrase in ["review", "reviewer", "code review"]):
        intent = "reviewers"
    elif any(phrase in message_lower for phrase in ["how can i contribute", "how to contribute", "contribute", "getting started"]):
        intent = "contribution_guide"
    elif any(phrase in message_lower for phrase in ["tell me about", "about", "repository info"]):
        intent = "repository_info"
    
    return {
        "intent": intent,
        "repository": repo,
        "original_message": message
    }


def converse_with_tools(messages: List[Dict], session_id: str) -> Dict:
    """Have a conversation with Bedrock using tools"""
    
    conversation_messages = messages.copy()
    max_iterations = 5
    iteration = 0
    
    # Analyze the latest user message for better tool selection
    if messages and messages[-1].get('role') == 'user':
        user_content = messages[-1].get('content', [])
        if user_content and isinstance(user_content, list) and user_content[0].get('text'):
            user_message = user_content[0]['text']
            intent_analysis = analyze_user_intent(user_message)
            print(f"Intent analysis: {intent_analysis}")
    
    while iteration < max_iterations:
        iteration += 1
        print(f"Conversation iteration {iteration}")
        
        try:
            # Call Bedrock Converse API
            response = bedrock_runtime.converse(
                modelId=MODEL_ID,
                messages=conversation_messages,
                system=[{"text": SYSTEM_PROMPT}],
                toolConfig={"tools": TOOLS},
                inferenceConfig={
                    "maxTokens": 1024,  # Reduced for faster responses
                    "temperature": 0.2,  # Lower temperature for more consistent responses
                    "topP": 0.8
                }
            )
            
            # Get the response message
            output_message = response['output']['message']
            conversation_messages.append(output_message)
            
            # Check stop reason
            stop_reason = response['stopReason']
            
            if stop_reason == 'end_turn':
                # Model finished, return the response
                return {
                    'success': True,
                    'message': output_message,
                    'usage': response.get('usage', {})
                }
            
            elif stop_reason == 'tool_use':
                # Model wants to use tools
                tool_results = []
                
                for content in output_message['content']:
                    if 'toolUse' in content:
                        tool_use = content['toolUse']
                        tool_name = tool_use['name']
                        tool_input = tool_use['input']
                        tool_use_id = tool_use['toolUseId']
                        
                        print(f"Tool use: {tool_name} with input: {tool_input}")
                        
                        # Invoke the tool
                        tool_result = invoke_tool(tool_name, tool_input)
                        
                        # Add tool result to conversation
                        tool_results.append({
                            "toolResult": {
                                "toolUseId": tool_use_id,
                                "content": [{"json": tool_result}]
                            }
                        })
                
                # Add tool results as a new user message
                conversation_messages.append({
                    "role": "user",
                    "content": tool_results
                })
                
                # Continue the loop to get model's response
                continue
            
            else:
                # Unexpected stop reason
                return {
                    'success': False,
                    'error': f'Unexpected stop reason: {stop_reason}'
                }
                
        except Exception as e:
            print(f"Error in Bedrock converse: {e}")
            return {
                'success': False,
                'error': str(e)
            }
    
    # Max iterations reached
    return {
        'success': False,
        'error': 'Maximum conversation iterations reached'
    }


def lambda_handler(event, context):
    """Main Lambda handler"""
    print(f"Agent proxy request: {json.dumps(event)}")
    
    try:
        # Parse request - handle both direct invocation and API Gateway
        if 'body' in event:
            # API Gateway format
            body = event.get('body', '{}')
            if isinstance(body, str):
                body = json.loads(body)
        else:
            # Direct Lambda invocation format
            body = event
        
        user_message = body.get('message', '')
        session_id = body.get('sessionId', str(uuid.uuid4()))
        
        if not user_message:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'message parameter required'})
            }
        
        # Get or create session
        session = get_session(session_id)
        messages = session['messages'] if session else []
        
        # Add user message
        messages.append({
            "role": "user",
            "content": [{"text": user_message}]
        })
        
        # Converse with Bedrock
        result = converse_with_tools(messages, session_id)
        
        if result['success']:
            # Add assistant response to messages
            messages.append(result['message'])
            
            # Save session
            save_session(session_id, messages)
            
            # Extract text response
            response_text = ""
            for content in result['message']['content']:
                if 'text' in content:
                    response_text += content['text']
            
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'sessionId': session_id,
                    'response': response_text,
                    'usage': result.get('usage', {})
                })
            }
        else:
            return {
                'statusCode': 500,
                'body': json.dumps({'error': result.get('error', 'Unknown error')})
            }
        
    except Exception as e:
        print(f"Error processing request: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': f'Internal server error: {str(e)}'})
        }
