"""
ContribConnect Graph Tool Lambda Function
Queries DynamoDB graph using adjacency list pattern for code ownership and relationships
"""

import json
import os
import sys
import boto3
import time
from typing import Dict, List, Any, Optional
from boto3.dynamodb.conditions import Key, Attr

# Add common directory to path for logger import
sys.path.insert(0, '/opt/python')  # Lambda layer path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'common'))

try:
    from logger import StructuredLogger, log_execution
except ImportError:
    # Fallback if logger not available
    class StructuredLogger:
        def __init__(self, *args, **kwargs): pass
        def info(self, msg, **kwargs): print(f"INFO: {msg}")
        def error(self, msg, **kwargs): print(f"ERROR: {msg}")
        def tool_invocation(self, **kwargs): print(f"TOOL: {kwargs}")
    
    def log_execution(component):
        def decorator(func):
            return func
        return decorator

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')

# Environment variables
NODES_TABLE = os.environ.get('NODES_TABLE', 'cc-nodes-dev')
EDGES_TABLE = os.environ.get('EDGES_TABLE', 'cc-edges-dev')

# DynamoDB tables
nodes_table = dynamodb.Table(NODES_TABLE)
edges_table = dynamodb.Table(EDGES_TABLE)


def get_node(node_id: str) -> Optional[Dict]:
    """Get a node by ID"""
    try:
        response = nodes_table.get_item(Key={'nodeId': node_id})
        return response.get('Item')
    except Exception as e:
        print(f"Error getting node {node_id}: {e}")
        return None


def get_outgoing_edges(from_id: str, edge_type: Optional[str] = None) -> List[Dict]:
    """Get all outgoing edges from a node"""
    try:
        if edge_type:
            response = edges_table.query(
                KeyConditionExpression=Key('fromId').eq(from_id) & Key('toIdEdgeType').begins_with(f"#{edge_type}")
            )
        else:
            response = edges_table.query(
                KeyConditionExpression=Key('fromId').eq(from_id)
            )
        return response.get('Items', [])
    except Exception as e:
        print(f"Error getting outgoing edges for {from_id}: {e}")
        return []


def get_incoming_edges(to_id: str, edge_type: Optional[str] = None) -> List[Dict]:
    """Get all incoming edges to a node using GSI"""
    try:
        response = edges_table.query(
            IndexName='ReverseEdgeIndex',
            KeyConditionExpression=Key('toId').eq(to_id)
        )
        edges = response.get('Items', [])
        
        # Filter by edge type if specified
        if edge_type:
            edges = [e for e in edges if e.get('edgeType') == edge_type]
        
        return edges
    except Exception as e:
        print(f"Error getting incoming edges for {to_id}: {e}")
        return []


def check_github_issues(repo: str, label: str = None, query: str = None) -> Dict[str, Any]:
    """Check GitHub API for actual issues with specific labels or general search"""
    import urllib.request
    import urllib.error
    import json
    
    try:
        if label:
            # Search by specific label
            url = f"https://api.github.com/repos/{repo}/issues?labels={label}&state=open&per_page=10"
        elif query:
            # Search by query terms
            url = f"https://api.github.com/search/issues?q=repo:{repo}+state:open+{query}&per_page=10"
        else:
            # Get recent open issues
            url = f"https://api.github.com/repos/{repo}/issues?state=open&per_page=10&sort=created&direction=desc"
        
        req = urllib.request.Request(url)
        req.add_header('Accept', 'application/vnd.github.v3+json')
        req.add_header('User-Agent', 'ContribConnect/1.0')
        
        with urllib.request.urlopen(req, timeout=10) as response:
            if response.status == 200:
                data = json.loads(response.read().decode())
                
                # Handle search API response format
                if 'items' in data:
                    issues = data['items']
                else:
                    issues = data
                
                # Filter out pull requests (they appear in issues API)
                issues = [issue for issue in issues if 'pull_request' not in issue]
                
                return {
                    'found': len(issues) > 0,
                    'count': len(issues),
                    'issues': [
                        {
                            'number': issue['number'],
                            'title': issue['title'],
                            'url': issue['html_url'],
                            'labels': [l['name'] for l in issue.get('labels', [])],
                            'created_at': issue['created_at'],
                            'comments': issue.get('comments', 0),
                            'assignee': issue.get('assignee', {}).get('login') if issue.get('assignee') else None
                        }
                        for issue in issues[:5]  # Return first 5 issues
                    ]
                }
    except Exception as e:
        print(f"Error checking GitHub issues: {e}")
    
    return {'found': False, 'count': 0, 'issues': []}


def find_reviewers(issue_labels: List[str], repo: str) -> Dict[str, Any]:
    """Find potential reviewers based on issue labels and expertise"""
    print(f"Finding reviewers for labels {issue_labels} in {repo}")
    
    reviewers = []
    label_experts = {}
    
    # Handle "good first issue" specifically - check GitHub directly
    if issue_labels and any('good first issue' in label.lower() for label in issue_labels):
        print(f"Checking GitHub for good first issues in {repo}")
        github_issues = check_github_issues(repo, "good first issue")
        
        # Get top contributors as potential mentors
        contributors_result = get_top_contributors(repo, 3)
        mentors = []
        if contributors_result.get('contributors'):
            for contributor in contributors_result['contributors'][:3]:
                mentors.append({
                    'login': contributor['login'],
                    'url': contributor['url'],
                    'contributions': contributor['contributions'],
                    'role': 'mentor'
                })
        
        # If no good first issues, check for other relevant issues
        alternative_suggestions = []
        if not github_issues['found']:
            # Check for beginner-friendly labels
            beginner_labels = ['help wanted', 'easy', 'beginner', 'documentation', 'bug', 'enhancement']
            for label in beginner_labels:
                alt_issues = check_github_issues(repo, label=label)
                if alt_issues['found']:
                    alternative_suggestions.append({
                        'label': label,
                        'count': alt_issues['count'],
                        'issues': alt_issues['issues'][:3]  # Show top 3
                    })
            
            # If still no labeled issues, get recent open issues
            if not alternative_suggestions:
                recent_issues = check_github_issues(repo)
                if recent_issues['found']:
                    alternative_suggestions.append({
                        'label': 'recent issues',
                        'count': recent_issues['count'],
                        'issues': recent_issues['issues'][:5]
                    })
        
        return {
            'labels': issue_labels,
            'repository': repo,
            'githubIssuesFound': github_issues['found'],
            'issueCount': github_issues['count'],
            'issues': github_issues['issues'],
            'alternativeSuggestions': alternative_suggestions,
            'mentors': mentors,
            'message': f"Found {github_issues['count']} good first issues" if github_issues['found'] else "No good first issues currently available",
            'suggestion': 'Check back later or look for other beginner-friendly issues' if not github_issues['found'] else 'These issues are great for getting started!',
            'contributionIdeas': [
                'Documentation improvements (README, comments, guides)',
                'Bug fixes for small, well-defined issues',
                'Adding tests for existing functionality',
                'Code formatting and style improvements',
                'Translation and localization',
                'Example code and tutorials'
            ] if not github_issues['found'] else []
        }
    
    # Always provide general reviewers based on top contributors
    print(f"Getting top contributors as potential reviewers for {repo}")
    
    # Get top contributors as reviewers
    contributors_result = get_top_contributors(repo, 5)
    if contributors_result.get('contributors'):
        # Convert contributors to reviewers format
        for contributor in contributors_result['contributors']:
            reviewers.append({
                'login': contributor['login'],
                'url': contributor['url'],
                'contributions': contributor['contributions'],
                'expertise': ['general contributor'],
                'reason': f"Top contributor with {contributor['contributions']} contributions"
            })
    
    # If specific labels provided, try to find label-specific experts
    if issue_labels and issue_labels != ['good first issue']:
        for label in issue_labels:
            label_id = f"label#{repo}#{label}"
            
            # Find issues with this label
            label_edges = get_incoming_edges(label_id, 'HAS_LABEL')
            
            # Find users who worked on similar issues
            user_counts = {}
            for edge in label_edges[:20]:
                issue_id = edge['fromId']
                
                # Find who authored this issue
                issue_edges = get_incoming_edges(issue_id, 'AUTHORED')
                for issue_edge in issue_edges:
                    user_id = issue_edge['fromId']
                    user_counts[user_id] = user_counts.get(user_id, 0) + 1
            
            # Get top contributors for this label
            top_users = sorted(user_counts.items(), key=lambda x: x[1], reverse=True)[:3]
            
            label_experts[label] = []
            for user_id, count in top_users:
                user_node = get_node(user_id)
                if user_node and user_node.get('nodeType') == 'user':
                    expert = {
                        'login': user_node['data'].get('login'),
                        'url': user_node['data'].get('url'),
                        'issueCount': count,
                        'expertise': label
                    }
                    label_experts[label].append(expert)
    
    return {
        'labels': issue_labels or [],
        'repository': repo,
        'suggestedReviewers': reviewers[:5],
        'labelExperts': label_experts,
        'note': 'Based on contribution history' if reviewers else 'No contributor data available yet'
    }


def find_related_issues(issue_id: str, repo: str) -> Dict[str, Any]:
    """Find issues related to a given issue by labels"""
    print(f"Finding related issues for {issue_id} in {repo}")
    
    # Get the issue node
    issue_node = get_node(issue_id)
    if not issue_node:
        # Return helpful guidance when no specific issue found
        return {
            'error': f'Issue {issue_id} not found',
            'suggestion': f'Try browsing the GitHub issues page for {repo} to find related issues',
            'repository': repo,
            'helpfulTips': [
                'Check the repository\'s GitHub Issues tab',
                'Look for issues with similar labels or topics',
                'Search for keywords related to your problem',
                'Consider asking the maintainers for guidance'
            ]
        }
    
    issue_data = issue_node.get('data', {})
    issue_labels = issue_data.get('labels', [])
    
    related_issues = []
    
    # Find issues with similar labels
    for label in issue_labels:
        label_id = f"label#{repo}#{label}"
        
        # Get issues with this label
        label_edges = get_incoming_edges(label_id, 'HAS_LABEL')
        
        for edge in label_edges[:10]:
            related_issue_id = edge['fromId']
            
            # Skip the original issue
            if related_issue_id == issue_id:
                continue
            
            related_issue_node = get_node(related_issue_id)
            if related_issue_node:
                related_data = related_issue_node.get('data', {})
                
                # Calculate similarity score
                shared_labels = set(issue_labels) & set(related_data.get('labels', []))
                similarity_score = len(shared_labels) / max(len(issue_labels), 1)
                
                related_issues.append({
                    'issueId': related_issue_id,
                    'number': related_data.get('number'),
                    'title': related_data.get('title'),
                    'state': related_data.get('state'),
                    'url': related_data.get('url'),
                    'labels': related_data.get('labels', []),
                    'sharedLabels': list(shared_labels),
                    'similarityScore': similarity_score
                })
    
    # Sort by similarity score
    related_issues.sort(key=lambda x: x['similarityScore'], reverse=True)
    
    # Remove duplicates
    seen = set()
    unique_issues = []
    for issue in related_issues:
        if issue['issueId'] not in seen:
            seen.add(issue['issueId'])
            unique_issues.append(issue)
    
    return {
        'originalIssue': {
            'issueId': issue_id,
            'number': issue_data.get('number'),
            'title': issue_data.get('title'),
            'labels': issue_labels
        },
        'relatedIssues': unique_issues[:10],
        'repository': repo,
        'totalFound': len(unique_issues)
    }


def get_top_contributors(repo: str, limit: int = 10) -> Dict[str, Any]:
    """Get top contributors for a repository"""
    print(f"Getting top contributors for {repo}")
    
    repo_id = f"repo#{repo}"
    
    # Get all CONTRIBUTES_TO edges pointing to this repo
    edges = get_incoming_edges(repo_id, 'CONTRIBUTES_TO')
    
    contributors = []
    
    # If no edges found, return mock data for demo
    if not edges:
        print(f"No contributor edges found for {repo}, returning mock data")
        mock_contributors = [
            {'userId': 'user#mrubens', 'login': 'mrubens', 'url': 'https://github.com/mrubens', 'avatarUrl': '', 'contributions': 1854},
            {'userId': 'user#saoudrizwan', 'login': 'saoudrizwan', 'url': 'https://github.com/saoudrizwan', 'avatarUrl': '', 'contributions': 962},
            {'userId': 'user#cte', 'login': 'cte', 'url': 'https://github.com/cte', 'avatarUrl': '', 'contributions': 587},
            {'userId': 'user#daniel-lxs', 'login': 'daniel-lxs', 'url': 'https://github.com/daniel-lxs', 'avatarUrl': '', 'contributions': 211},
            {'userId': 'user#hannesrudolph', 'login': 'hannesrudolph', 'url': 'https://github.com/hannesrudolph', 'avatarUrl': '', 'contributions': 129}
        ]
        return {
            'repository': repo,
            'contributors': mock_contributors[:limit],
            'total': len(mock_contributors),
            'note': 'Mock data - run ingestion to get real data'
        }
    
    for edge in edges:
        user_id = edge['fromId']
        user_node = get_node(user_id)
        
        if user_node:
            user_data = user_node.get('data', {})
            contributions = edge.get('properties', {}).get('contributions', 0)
            
            # Convert Decimal to int for JSON serialization
            if hasattr(contributions, '__int__'):
                contributions = int(contributions)
            
            contributors.append({
                'userId': user_id,
                'login': user_data.get('login'),
                'url': user_data.get('url'),
                'avatarUrl': user_data.get('avatarUrl'),
                'contributions': contributions
            })
    
    # Sort by contributions
    contributors.sort(key=lambda x: x['contributions'], reverse=True)
    
    return {
        'repository': repo,
        'contributors': contributors[:limit],
        'total': len(contributors)
    }


@log_execution("graph-tool")
def lambda_handler(event, context):
    """Main Lambda handler with structured logging"""
    request_id = context.request_id if hasattr(context, 'request_id') else ""
    log = StructuredLogger("graph-tool", request_id)
    
    start_time = time.time()
    
    try:
        # Parse request
        body = event.get('body', '{}')
        if isinstance(body, str):
            body = json.loads(body)
        
        action = body.get('action')
        params = body.get('params', {})
        
        log.info(f"Processing graph query", action=action, params=params)
        
        if action == 'get_top_contributors':
            repo = params.get('repo', '')
            limit = params.get('limit', 10)
            
            if not repo:
                log.error("Missing required parameters", action=action, missing="repo")
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'repo parameter required'})
                }
            
            query_start = time.time()
            result = get_top_contributors(repo, limit)
            query_duration = (time.time() - query_start) * 1000
            
            log.tool_invocation(
                tool_name="graph",
                action="get_top_contributors",
                duration_ms=query_duration,
                status="success",
                repo=repo,
                contributors_found=len(result.get('contributors', []))
            )
            
        elif action == 'find_reviewers':
            labels = params.get('labels', [])
            repo = params.get('repo', '')
            
            if not labels or not repo:
                log.error("Missing required parameters", action=action, missing="labels or repo")
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'labels and repo parameters required'})
                }
            
            query_start = time.time()
            result = find_reviewers(labels, repo)
            query_duration = (time.time() - query_start) * 1000
            
            log.tool_invocation(
                tool_name="graph",
                action="find_reviewers",
                duration_ms=query_duration,
                status="success",
                repo=repo,
                labels=labels,
                reviewers_found=len(result.get('reviewers', []))
            )
            
        elif action == 'find_relevant_issues':
            repo = params.get('repo', '')
            topic = params.get('topic', '')
            
            if not repo:
                log.error("Missing required parameters", action=action, missing="repo")
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'repo parameter required'})
                }
            
            query_start = time.time()
            
            # Search for issues related to the topic
            if topic:
                relevant_issues = check_github_issues(repo, query=topic)
            else:
                relevant_issues = check_github_issues(repo)
            
            # Get top contributors as potential helpers
            contributors_result = get_top_contributors(repo, 3)
            helpers = []
            if contributors_result.get('contributors'):
                for contributor in contributors_result['contributors'][:3]:
                    helpers.append({
                        'login': contributor['login'],
                        'url': contributor['url'],
                        'contributions': contributor['contributions']
                    })
            
            query_duration = (time.time() - query_start) * 1000
            
            result = {
                'repository': repo,
                'topic': topic or 'general',
                'issuesFound': relevant_issues['found'],
                'issueCount': relevant_issues['count'],
                'issues': relevant_issues['issues'],
                'helpers': helpers,
                'message': f"Found {relevant_issues['count']} relevant issues" if relevant_issues['found'] else "No specific issues found, but here are some contributors who can help"
            }
            
            log.tool_invocation(
                tool_name="graph",
                action="find_relevant_issues",
                duration_ms=query_duration,
                status="success",
                repo=repo,
                topic=topic,
                issues_found=relevant_issues['count']
            )
            
        elif action == 'find_related_issues':
            issue_id = params.get('issueId', '')
            repo = params.get('repo', '')
            
            if not issue_id or not repo:
                log.error("Missing required parameters", action=action, missing="issueId or repo")
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'issueId and repo parameters required'})
                }
            
            query_start = time.time()
            result = find_related_issues(issue_id, repo)
            query_duration = (time.time() - query_start) * 1000
            
            # Handle both success and error cases
            status = "success" if not result.get('error') else "not_found"
            related_count = len(result.get('relatedIssues', []))
            
            log.tool_invocation(
                tool_name="graph",
                action="find_related_issues",
                duration_ms=query_duration,
                status=status,
                repo=repo,
                issue_id=issue_id,
                related_found=related_count
            )
            
        else:
            log.error("Invalid action", action=action)
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'Invalid action',
                    'validActions': ['get_top_contributors', 'find_reviewers', 'find_related_issues', 'find_relevant_issues']
                })
            }
        
        total_duration = (time.time() - start_time) * 1000
        log.info(f"Request completed successfully", 
                action=action, 
                total_duration_ms=round(total_duration, 2))
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(result)
        }
        
    except Exception as e:
        total_duration = (time.time() - start_time) * 1000
        log.error(f"Request failed: {str(e)}", 
                 action=action if 'action' in locals() else "unknown",
                 duration_ms=round(total_duration, 2),
                 error_type=type(e).__name__)
        return {
            'statusCode': 500,
            'body': json.dumps({'error': f'Internal server error: {str(e)}'})
        }
