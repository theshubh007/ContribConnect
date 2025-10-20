"""
ContribConnect Repository Manager Lambda Function
Manages repository configurations in DynamoDB
"""

import json
import os
import boto3
from datetime import datetime
from decimal import Decimal


class DecimalEncoder(json.JSONEncoder):
    """Custom JSON encoder to handle Decimal types from DynamoDB"""
    def default(self, obj):
        if isinstance(obj, Decimal):
            return int(obj) if obj % 1 == 0 else float(obj)
        return super(DecimalEncoder, self).default(obj)

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')

# Environment variables
REPOS_TABLE = os.environ.get('REPOS_TABLE', 'cc-repos-dev')

# DynamoDB table
repos_table = dynamodb.Table(REPOS_TABLE)


def add_repository(owner: str, repo: str, enabled: bool = True) -> dict:
    """Add a repository to the configuration"""
    
    # Prepare item with basic data
    now = datetime.utcnow().isoformat() + 'Z'
    item = {
        'org': owner,
        'repo': repo,
        'enabled': enabled,
        'topics': [],
        'description': f'{owner}/{repo} repository',
        'stars': 0,
        'language': 'Unknown',
        'defaultBranch': 'main',
        'ingestCursor': '2024-01-01T00:00:00Z',
        'lastIngestAt': '',
        'ingestStatus': 'pending',
        'createdAt': now,
        'updatedAt': now
    }
    
    # Store in DynamoDB
    try:
        repos_table.put_item(Item=item)
        return {
            'success': True,
            'repository': f'{owner}/{repo}',
            'enabled': enabled,
            'message': 'Repository added successfully'
        }
    except Exception as e:
        return {
            'success': False,
            'error': f'Failed to store repository: {str(e)}'
        }


def list_repositories(enabled_only: bool = False) -> dict:
    """List all repositories"""
    try:
        if enabled_only:
            response = repos_table.scan(
                FilterExpression='enabled = :enabled',
                ExpressionAttributeValues={':enabled': True}
            )
        else:
            response = repos_table.scan()
        
        items = response.get('Items', [])
        
        # Format response and handle Decimal types
        repositories = []
        for item in items:
            repositories.append({
                'repository': f"{item['org']}/{item['repo']}",
                'enabled': bool(item.get('enabled', False)),
                'stars': int(item.get('stars', 0)) if isinstance(item.get('stars'), Decimal) else item.get('stars', 0),
                'language': str(item.get('language', '')),
                'topics': list(item.get('topics', [])),
                'description': str(item.get('description', '')),
                'ingestStatus': str(item.get('ingestStatus', 'unknown')),
                'lastIngestAt': str(item.get('lastIngestAt', ''))
            })
        
        return {
            'success': True,
            'count': len(repositories),
            'repositories': repositories
        }
    except Exception as e:
        return {
            'success': False,
            'error': f'Failed to list repositories: {str(e)}'
        }


def remove_repository(owner: str, repo: str) -> dict:
    """Remove a repository from the configuration"""
    try:
        repos_table.delete_item(
            Key={
                'org': owner,
                'repo': repo
            }
        )
        return {
            'success': True,
            'repository': f'{owner}/{repo}',
            'message': 'Repository removed'
        }
    except Exception as e:
        return {
            'success': False,
            'error': f'Failed to remove repository: {str(e)}'
        }


def lambda_handler(event, context):
    """Main Lambda handler"""
    print(f"Repository manager request: {json.dumps(event)}")
    
    try:
        # Parse request - handle both API Gateway and direct invocation
        if 'body' in event:
            body = event.get('body', '{}')
            if isinstance(body, str):
                body = json.loads(body)
        else:
            body = event
        
        action = body.get('action')
        owner = body.get('owner', '')
        repo = body.get('repo', '')
        
        print(f"Action: {action}, Owner: {owner}, Repo: {repo}")
        
        if action == 'add':
            if not owner or not repo:
                return {
                    'statusCode': 400,
                    'headers': {
                        'Content-Type': 'application/json',
                        'Access-Control-Allow-Origin': '*'
                    },
                    'body': json.dumps({'success': False, 'error': 'owner and repo are required'})
                }
            
            enabled = body.get('enabled', True)
            result = add_repository(owner, repo, enabled)
            
        elif action == 'list':
            enabled_only = body.get('enabledOnly', False)
            result = list_repositories(enabled_only)
            
        elif action == 'remove':
            if not owner or not repo:
                return {
                    'statusCode': 400,
                    'headers': {
                        'Content-Type': 'application/json',
                        'Access-Control-Allow-Origin': '*'
                    },
                    'body': json.dumps({'success': False, 'error': 'owner and repo are required'})
                }
            
            result = remove_repository(owner, repo)
            
        else:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'success': False,
                    'error': 'Invalid action',
                    'validActions': ['add', 'list', 'remove']
                })
            }
        
        status_code = 200 if result.get('success') else 400
        
        return {
            'statusCode': status_code,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(result, cls=DecimalEncoder)
        }
        
    except Exception as e:
        print(f"Error processing request: {e}")
        import traceback
        traceback.print_exc()
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'success': False, 'error': f'Internal server error: {str(e)}'}, cls=DecimalEncoder)
        }