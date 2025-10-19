"""
ContribConnect GitHub Tool Lambda Function
Handles GitHub operations like creating PRs, requesting reviewers, and managing issues
"""

import json
import os
import boto3
import requests
from typing import Dict, List, Any, Optional
import time

# Initialize AWS clients
secrets_manager = boto3.client('secretsmanager')

# Environment variables
GITHUB_TOKEN_SECRET = os.environ.get('GITHUB_TOKEN_SECRET', 'cc-github-token')


def get_github_token() -> str:
    """Retrieve GitHub token from Secrets Manager"""
    try:
        response = secrets_manager.get_secret_value(SecretId=GITHUB_TOKEN_SECRET)
        secret = json.loads(response['SecretString'])
        return secret.get('token', '')
    except Exception as e:
        print(f"Warning: Could not retrieve GitHub token: {e}")
        return os.environ.get('GITHUB_TOKEN', '')


def github_request(method: str, url: str, token: str, data: Optional[Dict] = None) -> Dict:
    """Make authenticated GitHub API request with rate limit handling"""
    headers = {
        'Authorization': f'token {token}',
        'Accept': 'application/vnd.github.v3+json',
        'Content-Type': 'application/json'
    }
    
    max_retries = 3
    for attempt in range(max_retries):
        if method.upper() == 'GET':
            response = requests.get(url, headers=headers)
        elif method.upper() == 'POST':
            response = requests.post(url, headers=headers, json=data)
        elif method.upper() == 'PATCH':
            response = requests.patch(url, headers=headers, json=data)
        else:
            raise ValueError(f"Unsupported HTTP method: {method}")
        
        if response.status_code in [200, 201]:
            return response.json()
        elif response.status_code == 403 and 'rate limit' in response.text.lower():
            reset_time = int(response.headers.get('X-RateLimit-Reset', 0))
            wait_time = max(reset_time - int(time.time()), 60)
            print(f"Rate limited. Waiting {wait_time} seconds...")
            time.sleep(wait_time)
        elif response.status_code == 404:
            print(f"Resource not found: {url}")
            return {'error': 'Resource not found', 'status_code': 404}
        elif response.status_code == 422:
            print(f"Validation error: {response.text}")
            return {'error': 'Validation error', 'details': response.json(), 'status_code': 422}
        else:
            print(f"GitHub API error: {response.status_code} - {response.text}")
            if attempt < max_retries - 1:
                time.sleep(2 ** attempt)
            else:
                return {'error': f'GitHub API request failed: {response.status_code}', 'details': response.text}
    
    return {'error': 'Max retries exceeded'}


def create_pr(org: str, repo: str, title: str, body: str, head_branch: str, base_branch: str = 'main', draft: bool = True, token: str = '') -> Dict[str, Any]:
    """Create a pull request"""
    print(f"Creating PR in {org}/{repo}: {title}")
    
    url = f"https://api.github.com/repos/{org}/{repo}/pulls"
    
    pr_data = {
        'title': title,
        'body': body,
        'head': head_branch,
        'base': base_branch,
        'draft': draft
    }
    
    result = github_request('POST', url, token, pr_data)
    
    if 'error' in result:
        return {
            'success': False,
            'error': result['error'],
            'details': result.get('details', '')
        }
    
    return {
        'success': True,
        'pr': {
            'number': result.get('number'),
            'url': result.get('html_url'),
            'title': result.get('title'),
            'state': result.get('state'),
            'draft': result.get('draft'),
            'head': result.get('head', {}).get('ref'),
            'base': result.get('base', {}).get('ref')
        }
    }


def request_reviewers(org: str, repo: str, pr_number: int, reviewers: List[str], team_reviewers: List[str] = None, token: str = '') -> Dict[str, Any]:
    """Request reviewers for a pull request"""
    print(f"Requesting reviewers for PR #{pr_number} in {org}/{repo}: {reviewers}")
    
    url = f"https://api.github.com/repos/{org}/{repo}/pulls/{pr_number}/requested_reviewers"
    
    review_data = {
        'reviewers': reviewers
    }
    
    if team_reviewers:
        review_data['team_reviewers'] = team_reviewers
    
    result = github_request('POST', url, token, review_data)
    
    if 'error' in result:
        return {
            'success': False,
            'error': result['error'],
            'details': result.get('details', '')
        }
    
    return {
        'success': True,
        'requested_reviewers': [r.get('login') for r in result.get('requested_reviewers', [])],
        'requested_team_reviewers': [t.get('name') for t in result.get('requested_team_reviewers', [])]
    }


def list_pr_files(org: str, repo: str, pr_number: int, token: str = '') -> Dict[str, Any]:
    """List files changed in a pull request"""
    print(f"Listing files for PR #{pr_number} in {org}/{repo}")
    
    url = f"https://api.github.com/repos/{org}/{repo}/pulls/{pr_number}/files"
    
    result = github_request('GET', url, token)
    
    if 'error' in result:
        return {
            'success': False,
            'error': result['error'],
            'details': result.get('details', '')
        }
    
    # Extract file information
    files = []
    for file_data in result:
        files.append({
            'filename': file_data.get('filename'),
            'status': file_data.get('status'),
            'additions': file_data.get('additions', 0),
            'deletions': file_data.get('deletions', 0),
            'changes': file_data.get('changes', 0)
        })
    
    return {
        'success': True,
        'files': files,
        'total_files': len(files)
    }


def get_pr(org: str, repo: str, pr_number: int, token: str = '') -> Dict[str, Any]:
    """Get pull request details"""
    print(f"Getting PR #{pr_number} in {org}/{repo}")
    
    url = f"https://api.github.com/repos/{org}/{repo}/pulls/{pr_number}"
    
    result = github_request('GET', url, token)
    
    if 'error' in result:
        return {
            'success': False,
            'error': result['error'],
            'details': result.get('details', '')
        }
    
    return {
        'success': True,
        'pr': {
            'number': result.get('number'),
            'title': result.get('title'),
            'body': result.get('body'),
            'state': result.get('state'),
            'draft': result.get('draft'),
            'url': result.get('html_url'),
            'head': result.get('head', {}).get('ref'),
            'base': result.get('base', {}).get('ref'),
            'author': result.get('user', {}).get('login'),
            'created_at': result.get('created_at'),
            'updated_at': result.get('updated_at')
        }
    }


def lambda_handler(event, context):
    """Main Lambda handler"""
    print(f"GitHub tool request: {json.dumps(event)}")
    
    try:
        # Get GitHub token
        token = get_github_token()
        if not token:
            return {
                'statusCode': 500,
                'body': json.dumps({'error': 'GitHub token not configured'})
            }
        
        # Parse request
        body = event.get('body', '{}')
        if isinstance(body, str):
            body = json.loads(body)
        
        action = body.get('action')
        params = body.get('params', {})
        
        if action == 'create_pr':
            org = params.get('org', '')
            repo = params.get('repo', '')
            title = params.get('title', '')
            body_text = params.get('body', '')
            head_branch = params.get('head_branch', '')
            base_branch = params.get('base_branch', 'main')
            draft = params.get('draft', True)
            
            if not all([org, repo, title, head_branch]):
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'org, repo, title, and head_branch parameters required'})
                }
            
            result = create_pr(org, repo, title, body_text, head_branch, base_branch, draft, token)
            
        elif action == 'request_reviewers':
            org = params.get('org', '')
            repo = params.get('repo', '')
            pr_number = params.get('pr_number', 0)
            reviewers = params.get('reviewers', [])
            team_reviewers = params.get('team_reviewers', [])
            
            if not all([org, repo, pr_number, reviewers]):
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'org, repo, pr_number, and reviewers parameters required'})
                }
            
            result = request_reviewers(org, repo, pr_number, reviewers, team_reviewers, token)
            
        elif action == 'list_pr_files':
            org = params.get('org', '')
            repo = params.get('repo', '')
            pr_number = params.get('pr_number', 0)
            
            if not all([org, repo, pr_number]):
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'org, repo, and pr_number parameters required'})
                }
            
            result = list_pr_files(org, repo, pr_number, token)
            
        elif action == 'get_pr':
            org = params.get('org', '')
            repo = params.get('repo', '')
            pr_number = params.get('pr_number', 0)
            
            if not all([org, repo, pr_number]):
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'org, repo, and pr_number parameters required'})
                }
            
            result = get_pr(org, repo, pr_number, token)
            
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'Invalid action',
                    'validActions': ['create_pr', 'request_reviewers', 'list_pr_files', 'get_pr']
                })
            }
        
        return {
            'statusCode': 200,
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
