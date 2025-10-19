"""
ContribConnect Data Ingestion Lambda Function
Fetches GitHub data and populates DynamoDB graph with adjacency list pattern
"""

import json
import os
import boto3
import requests
from datetime import datetime, timezone
from typing import Dict, List, Any, Optional
import time

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')
secrets_manager = boto3.client('secretsmanager')

# Environment variables
NODES_TABLE = os.environ.get('NODES_TABLE', 'cc-nodes-dev')
EDGES_TABLE = os.environ.get('EDGES_TABLE', 'cc-edges-dev')
REPOS_TABLE = os.environ.get('REPOS_TABLE', 'cc-repos-dev')
RAW_BUCKET = os.environ.get('RAW_BUCKET', '')
GITHUB_TOKEN_SECRET = os.environ.get('GITHUB_TOKEN_SECRET', 'cc-github-token')

# DynamoDB tables
nodes_table = dynamodb.Table(NODES_TABLE)
edges_table = dynamodb.Table(EDGES_TABLE)
repos_table = dynamodb.Table(REPOS_TABLE)


def get_github_token() -> str:
    """Retrieve GitHub token from Secrets Manager"""
    try:
        response = secrets_manager.get_secret_value(SecretId=GITHUB_TOKEN_SECRET)
        secret = json.loads(response['SecretString'])
        return secret.get('token', '')
    except Exception as e:
        print(f"Warning: Could not retrieve GitHub token: {e}")
        return os.environ.get('GITHUB_TOKEN', '')


def github_request(url: str, token: str, params: Optional[Dict] = None) -> Dict:
    """Make authenticated GitHub API request with rate limit handling"""
    headers = {
        'Authorization': f'token {token}',
        'Accept': 'application/vnd.github.v3+json'
    }
    
    max_retries = 3
    for attempt in range(max_retries):
        response = requests.get(url, headers=headers, params=params)
        
        if response.status_code == 200:
            return response.json()
        elif response.status_code == 403 and 'rate limit' in response.text.lower():
            reset_time = int(response.headers.get('X-RateLimit-Reset', 0))
            wait_time = max(reset_time - int(time.time()), 60)
            print(f"Rate limited. Waiting {wait_time} seconds...")
            time.sleep(wait_time)
        elif response.status_code == 404:
            print(f"Resource not found: {url}")
            return {}
        else:
            print(f"GitHub API error: {response.status_code} - {response.text}")
            if attempt < max_retries - 1:
                time.sleep(2 ** attempt)
            else:
                raise Exception(f"GitHub API request failed: {response.status_code}")
    
    return {}


def save_to_s3(data: Any, key: str) -> None:
    """Save raw data to S3"""
    if not RAW_BUCKET:
        return
    
    try:
        s3.put_object(
            Bucket=RAW_BUCKET,
            Key=key,
            Body=json.dumps(data, default=str),
            ContentType='application/json'
        )
    except Exception as e:
        print(f"Error saving to S3: {e}")


def upsert_node(node_id: str, node_type: str, data: Dict) -> None:
    """Upsert a node in DynamoDB"""
    try:
        nodes_table.put_item(
            Item={
                'nodeId': node_id,
                'nodeType': node_type,
                'data': data,
                'updatedAt': datetime.now(timezone.utc).isoformat()
            }
        )
    except Exception as e:
        print(f"Error upserting node {node_id}: {e}")


def upsert_edge(from_id: str, to_id: str, edge_type: str, properties: Optional[Dict] = None) -> None:
    """Upsert an edge in DynamoDB"""
    try:
        edges_table.put_item(
            Item={
                'fromId': from_id,
                'toIdEdgeType': f"{to_id}#{edge_type}",
                'toId': to_id,
                'fromIdEdgeType': f"{from_id}#{edge_type}",
                'edgeType': edge_type,
                'properties': properties or {},
                'updatedAt': datetime.now(timezone.utc).isoformat()
            }
        )
    except Exception as e:
        print(f"Error upserting edge {from_id} -> {to_id}: {e}")


def ingest_repository(org: str, repo: str, token: str, cursor: str) -> Dict:
    """Ingest data for a single repository"""
    print(f"Ingesting {org}/{repo}...")
    
    repo_id = f"repo#{org}/{repo}"
    stats = {
        'contributors': 0,
        'issues': 0,
        'prs': 0,
        'users': 0,
        'files': 0,
        'errors': []
    }
    
    date_path = datetime.now(timezone.utc).strftime('%Y/%m/%d')
    
    # Fetch repository info
    repo_url = f"https://api.github.com/repos/{org}/{repo}"
    repo_data = github_request(repo_url, token)
    
    if not repo_data:
        stats['errors'].append(f"Could not fetch repo data for {org}/{repo}")
        return stats
    
    # Create repo node
    upsert_node(
        repo_id,
        'repo',
        {
            'name': repo_data.get('name'),
            'owner': repo_data.get('owner', {}).get('login'),
            'url': repo_data.get('html_url'),
            'description': repo_data.get('description'),
            'stars': repo_data.get('stargazers_count', 0),
            'topics': repo_data.get('topics', []),
            'language': repo_data.get('language')
        }
    )
    
    # Save raw repo data to S3
    save_to_s3(repo_data, f"github/{org}/{repo}/repo/{date_path}/repo.json")
    
    # 1. FETCH CONTRIBUTORS (MOST IMPORTANT FOR GRAPH)
    print(f"Fetching contributors for {org}/{repo}...")
    contributors_url = f"https://api.github.com/repos/{org}/{repo}/contributors"
    contributors = github_request(contributors_url, token, {'per_page': 100})
    
    if isinstance(contributors, list):
        for contributor in contributors[:50]:  # Top 50 contributors
            user_login = contributor.get('login')
            if not user_login or contributor.get('type') != 'User':
                continue
                
            user_id = f"user#{user_login}"
            contributions = contributor.get('contributions', 0)
            
            # Create user node with contribution count
            upsert_node(
                user_id,
                'user',
                {
                    'login': user_login,
                    'url': contributor.get('html_url'),
                    'avatarUrl': contributor.get('avatar_url'),
                    'contributions': contributions,
                    'type': 'contributor'
                }
            )
            
            # Create CONTRIBUTES_TO edge
            upsert_edge(
                user_id,
                repo_id,
                'CONTRIBUTES_TO',
                {'contributions': contributions}
            )
            
            stats['contributors'] += 1
        
        print(f"Ingested {stats['contributors']} contributors")
    
    # 2. FETCH PULL REQUESTS
    print(f"Fetching pull requests for {org}/{repo}...")
    prs_url = f"https://api.github.com/repos/{org}/{repo}/pulls"
    prs = github_request(prs_url, token, {'state': 'all', 'per_page': 50})
    
    if isinstance(prs, list):
        for pr in prs[:30]:  # Limit to 30 PRs
            try:
                pr_number = pr.get('number')
                if not pr_number:
                    continue
                    
                pr_id = f"pr#{org}/{repo}#{pr_number}"
                
                # Safely get user info
                user_data = pr.get('user')
                if not user_data:
                    print(f"  ⚠️  PR #{pr_number} has no user data, skipping")
                    continue
                
                user_login = user_data.get('login')
                if not user_login:
                    print(f"  ⚠️  PR #{pr_number} user has no login, skipping")
                    continue
                
                user_id = f"user#{user_login}"
            
            # Create PR node
            upsert_node(
                pr_id,
                'pull_request',
                {
                    'number': pr_number,
                    'title': pr.get('title'),
                    'body': pr.get('body', '')[:500],
                    'state': pr.get('state'),
                    'merged': pr.get('merged', False),
                    'createdAt': pr.get('created_at'),
                    'url': pr.get('html_url'),
                    'additions': pr.get('additions', 0),
                    'deletions': pr.get('deletions', 0)
                }
            )
            
            # Create user node if not exists
            if user_login:
                upsert_node(
                    user_id,
                    'user',
                    {
                        'login': user_login,
                        'url': user_data.get('html_url'),
                        'avatarUrl': user_data.get('avatar_url'),
                        'type': 'contributor'
                    }
                )
                
                # Create AUTHORED edge
                upsert_edge(user_id, pr_id, 'AUTHORED', {'createdAt': pr.get('created_at')})
            
            # Create IN_REPO edge
            upsert_edge(pr_id, repo_id, 'IN_REPO')
            
            # Fetch PR files to create TOUCHES edges
            files_url = f"https://api.github.com/repos/{org}/{repo}/pulls/{pr_number}/files"
            files = github_request(files_url, token, {'per_page': 20})
            
            if isinstance(files, list):
                for file_data in files[:10]:  # Limit to 10 files per PR
                    filename = file_data.get('filename')
                    file_id = f"file#{org}/{repo}#{filename}"
                    
                    # Create file node
                    upsert_node(
                        file_id,
                        'file',
                        {
                            'path': filename,
                            'directory': '/'.join(filename.split('/')[:-1]) if '/' in filename else ''
                        }
                    )
                    
                    # Create TOUCHES edge
                    upsert_edge(
                        pr_id,
                        file_id,
                        'TOUCHES',
                        {
                            'additions': file_data.get('additions', 0),
                            'deletions': file_data.get('deletions', 0)
                        }
                    )
                    
                    stats['files'] += 1
                
                stats['prs'] += 1
                save_to_s3(pr, f"github/{org}/{repo}/prs/{date_path}/pr-{pr_number}.json")
                
                time.sleep(0.5)  # Rate limiting
            except Exception as e:
                print(f"  ❌ Error processing PR #{pr.get('number', 'unknown')}: {e}")
                import traceback
                traceback.print_exc()
                continue
    
    # 3. FETCH ISSUES (separate from PRs)
    print(f"Fetching issues for {org}/{repo}...")
    issues_url = f"https://api.github.com/repos/{org}/{repo}/issues"
    issues = github_request(issues_url, token, {'state': 'all', 'per_page': 50})
    
    if isinstance(issues, list):
        for issue in issues[:30]:  # Limit to 30 issues
            # Skip pull requests (they appear in issues endpoint too)
            if 'pull_request' in issue:
                continue
                
            issue_number = issue.get('number')
            if not issue_number:
                continue
                
            issue_id = f"issue#{org}/{repo}#{issue_number}"
            
            # Safely get user info
            user_data = issue.get('user')
            if not user_data:
                continue
            
            user_login = user_data.get('login')
            if not user_login:
                continue
                
            user_id = f"user#{user_login}"
            
            # Create issue node
            upsert_node(
                issue_id,
                'issue',
                {
                    'number': issue_number,
                    'title': issue.get('title'),
                    'body': issue.get('body', '')[:500],
                    'state': issue.get('state'),
                    'labels': [label.get('name') for label in issue.get('labels', [])],
                    'createdAt': issue.get('created_at'),
                    'url': issue.get('html_url'),
                    'comments': issue.get('comments', 0)
                }
            )
            
            # Create user node
            if user_login:
                upsert_node(
                    user_id,
                    'user',
                    {
                        'login': user_login,
                        'url': user_data.get('html_url'),
                        'avatarUrl': user_data.get('avatar_url'),
                        'type': 'contributor'
                    }
                )
                
                # Create AUTHORED edge
                upsert_edge(user_id, issue_id, 'AUTHORED', {'createdAt': issue.get('created_at')})
            
            # Create IN_REPO edge
            upsert_edge(issue_id, repo_id, 'IN_REPO')
            
            # Create HAS_LABEL edges
            for label in issue.get('labels', []):
                label_name = label.get('name')
                label_id = f"label#{org}/{repo}#{label_name}"
                upsert_node(label_id, 'label', {'name': label_name, 'color': label.get('color')})
                upsert_edge(issue_id, label_id, 'HAS_LABEL')
            
            stats['issues'] += 1
            save_to_s3(issue, f"github/{org}/{repo}/issues/{date_path}/issue-{issue_number}.json")
    
    print(f"Ingestion complete for {org}/{repo}:")
    print(f"  - {stats['contributors']} contributors")
    print(f"  - {stats['prs']} pull requests")
    print(f"  - {stats['issues']} issues")
    print(f"  - {stats['files']} files")
    
    return stats


def lambda_handler(event, context):
    """Main Lambda handler"""
    print(f"Starting ingestion: {json.dumps(event)}")
    
    # Get GitHub token
    token = get_github_token()
    if not token:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'GitHub token not configured'})
        }
    
    # Get enabled repositories
    try:
        response = repos_table.scan(
            FilterExpression='enabled = :enabled',
            ExpressionAttributeValues={':enabled': True}
        )
        repos = response.get('Items', [])
    except Exception as e:
        print(f"Error fetching repos: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': f'Failed to fetch repos: {str(e)}'})
        }
    
    if not repos:
        print("No enabled repositories found")
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'No repositories to ingest'})
        }
    
    # Ingest each repository
    results = []
    for repo_config in repos[:5]:  # Limit to 5 repos for hackathon
        org = repo_config.get('org')
        repo = repo_config.get('repo')
        cursor = repo_config.get('ingestCursor', '2024-01-01T00:00:00Z')
        
        try:
            stats = ingest_repository(org, repo, token, cursor)
            
            # Update cursor
            repos_table.update_item(
                Key={'org': org, 'repo': repo},
                UpdateExpression='SET lastIngestAt = :now, ingestStatus = :status',
                ExpressionAttributeValues={
                    ':now': datetime.now(timezone.utc).isoformat(),
                    ':status': 'success'
                }
            )
            
            results.append({
                'repo': f"{org}/{repo}",
                'status': 'success',
                'stats': stats
            })
        except Exception as e:
            print(f"Error ingesting {org}/{repo}: {e}")
            results.append({
                'repo': f"{org}/{repo}",
                'status': 'error',
                'error': str(e)
            })
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Ingestion complete',
            'results': results
        })
    }
