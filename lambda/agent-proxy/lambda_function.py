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
            "description": "Query the GitHub contribution graph to find expert reviewers, code owners, top contributors, and related issues based on historical contribution patterns",
            "inputSchema": {
                "json": {
                    "type": "object",
                    "properties": {
                        "action": {
                            "type": "string",
                            "enum": ["find_reviewers", "find_related_issues", "get_top_contributors"],
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
2. github_tool: Create PRs, request reviewers, and manage GitHub operations

When helping users:
- Always ask for the repository name (org/repo format) if not provided
- Use graph_tool to find expert reviewers based on issue labels or contribution history
- Use get_top_contributors to show the most active contributors in a repository
- Provide specific, actionable recommendations with GitHub usernames
- Be concise and helpful

Remember: You're helping developers connect with the right people to review their work."""


def invoke_tool(tool_name: str, tool_input: Dict) -> Dict:
    """Invoke a tool Lambda function"""
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
        # Invoke the Lambda function
        response = lambda_client.invoke(
            FunctionName=function_name,
            InvocationType='RequestResponse',
            Payload=json.dumps({'body': json.dumps(tool_input)})
        )
        
        # Parse response
        payload = json.loads(response['Payload'].read())
        
        if payload.get('statusCode') == 200:
            body = json.loads(payload['body'])
            return body
        else:
            return {'error': f'Tool invocation failed: {payload}'}
            
    except Exception as e:
        print(f"Error invoking tool {tool_name}: {e}")
        return {'error': str(e)}


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


def converse_with_tools(messages: List[Dict], session_id: str) -> Dict:
    """Have a conversation with Bedrock using tools"""
    
    conversation_messages = messages.copy()
    max_iterations = 5
    iteration = 0
    
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
                    "maxTokens": 2048,
                    "temperature": 0.7,
                    "topP": 0.9
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
        # Parse request
        body = event.get('body', '{}')
        if isinstance(body, str):
            body = json.loads(body)
        
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
