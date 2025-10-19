"""
ContribConnect Repository Manager Lambda Function
Manages repository configurations in DynamoDB
"""

import json
import os
import boto3
import requests
from datetime import datetime
from typing import Dict, List, Any, Optional

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')

# Environment variables
REPOS_TABLE = os.environ.get('REPOS_TABLE', 'cc-repos-dev')
GITHUB_TOKEN = os.environ.get('GITHUB_TOKEN', '')

# DynamoDB table
repos_table = dynamodb.Table(REPOS_TABLE)


def validate_github_repo(owner: str, repo: str) -> Optional[Dict]:
    """Validate that a GitHub repository exists and is accessible"""
    url = f"https://api.github.com/repos/{owner}/{repo}"
    headers = {}
    
    if GITHUB_TOKEN:
        headers['Authorization'] = f'token {GITHUB_TOKEN}'
    
    try:
        response = requests.get(url, headers=headers, timeout=10)
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        print(f"Error validating repository: {e}")
        return None


def add_repository(owner: str, repo: str, topics: List[str] = None, 
                   min_stars: int = 0, enabled: bool = True) -> Dict:
    """Add a repository to the configuration"""
    
    # Validate repository
    repo_data = validate_github_repo(owner, repo)
    if not repo_data:
        return {
            'success': False,
            'error': f'Repository {owner}/{repo} not found or not accessible'
        }
    
    # Check star count
    stars = repo_data.get('stargazers_count', 0)
    if stars < min_stars:
        return {
            'success': False,
            'error': f'Repository has {stars} stars, minimum required is {min_stars}'
        }
    
    # Prepare item
    now = datetime.utcnow().isoformat() + 'Z'
    item = {
        'org': owner,
        'repo': repo,
        'enabled': enabled,
        'topics': topics or repo_data.get('topics', []),
        'minStars': min_stars,
        'description': repo_data.get('description', ''),
        'stars': stars,
        'language': repo_data.get('language', ''),
        'defaultBranch': repo_data.get('default_branch', 'main'),
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
            'stars': stars,
            'language': repo_data.get('language'),
            'enabled': enabled
        }
    except Exception as e:
        return {
            'success': False,
            'error': f'Failed to store repository: {str(e)}'
        }


def remove_repository(owner: str, repo: str) -> Dict:
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


def update_repository_status(owner: str, repo: str, enabled: bool) -> Dict:
    """Enable or disable a repository"""
    try:
        repos_table.update_item(
            Key={
                'org': owner,
                'repo': repo
            },
            UpdateExpression='SET enabled = :enabled, updatedAt = :updatedAt',
            ExpressionAttributeValues={
                ':enabled': enabled,
                ':updatedAt': datetime.utcnow().isoformat() + 'Z'
            }
        )
        return {
            'success': True,
            'repository': f'{owner}/{repo}',
            'enabled': enabled
        }
    except Exception as e:
        return {
            'success': False,
            'error': f'Failed to update repository: {str(e)}'
        }


def list_repositories(enabled_only: bool = False) -> Dict:
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
        
        # Format response
        repositories = []
        for item in items:
            repositories.append({
                'repository': f"{item['org']}/{item['repo']}",
                'enabled': item.get('enabled', False),
                'stars': item.get('stars', 0),
                'language': item.get('language', ''),
                'topics': item.get('topics', []),
                'ingestStatus': item.get('ingestStatus', 'unknown'),
                'lastIngestAt': item.get('lastIngestAt', '')
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


def get_repository(owner: str, repo: str) -> Dict:
    """Get details for a specific repository"""
    try:
        response = repos_table.get_item(
            Key={
                'org': owner,
                'repo': repo
            }
        )
        
        item = response.get('Item')
        if not item:
            return {
                'success': False,
                'error': f'Repository {owner}/{repo} not found'
            }
        
        return {
            'success': True,
            'repository': {
                'org': item['org'],
                'repo': item['repo'],
                'enabled': item.get('enabled', False),
                'stars': item.get('stars', 0),
                'language': item.get('language', ''),
                'topics': item.get('topics', []),
                'description': item.get('description', ''),
                'ingestCursor': item.get('ingestCursor', ''),
                'lastIngestAt': item.get('lastIngestAt', ''),
                'ingestStatus': item.get('ingestStatus', 'unknown'),
                'createdAt': item.get('createdAt', ''),
                'updatedAt': item.get('updatedAt', '')
            }
        }
    except Exception as e:
        return {
            'success': False,
            'error': f'Failed to get repository: {str(e)}'
        }


def lambda_handler(event, context):
    """Main Lambda handler"""
    print(f"Repository manager request: {json.dumps(event)}")
    
    try:
        # Parse request
        body = event.get('body', '{}')
        if isinstance(body, str):
            body = json.loads(body)
        
        action = body.get('action')
        owner = body.get('owner', '')
        repo = body.get('repo', '')
        
        if action == 'add':
            topics = body.get('topics', [])
            min_stars = body.get('minStars', 0)
            enabled = body.get('enabled', True)
            
            if not owner or not repo:
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'owner and repo are required'})
                }
            
            result = add_repository(owner, repo, topics, min_stars, enabled)
            
        elif action == 'remove':
            if not owner or not repo:
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'owner and repo are required'})
                }
            
            result = remove_repository(owner, repo)
            
        elif action == 'enable':
            if not owner or not repo:
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'owner and repo are required'})
                }
            
            result = update_repository_status(owner, repo, True)
            
        elif action == 'disable':
            if not owner or not repo:
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'owner and repo are required'})
                }
            
            result = update_repository_status(owner, repo, False)
            
        elif action == 'list':
            enabled_only = body.get('enabledOnly', False)
            result = list_repositories(enabled_only)
            
        elif action == 'get':
            if not owner or not repo:
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'owner and repo are required'})
                }
            
            result = get_repository(owner, repo)
            
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'Invalid action',
                    'validActions': ['add', 'remove', 'enable', 'disable', 'list', 'get']
                })
            }
        
        status_code = 200 if result.get('success') else 400
        
        return {
            'statusCode': status_code,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(result)
        }
        
    except Exception as e:
        print(f"Error processing request: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': f'Internal server error: {str(e)}'})
        }
