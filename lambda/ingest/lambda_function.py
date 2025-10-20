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


def check_rate_limit(token: str) -> Dict:
    """Check remaining GitHub API rate limit"""
    headers = {
        'Authorization': f'token {token}',
        'Accept': 'application/vnd.github.v3+json'
    }
    try:
        response = requests.get('https://api.github.com/rate_limit', headers=headers)
        if response.status_code == 200:
            data = response.json()
            remaining = data['resources']['core']['remaining']
            limit = data['resources']['core']['limit']
            reset_time = data['resources']['core']['reset']
            
            return {
                'remaining': remaining,
                'limit': limit,
                'reset_time': reset_time,
                'percentage': (remaining / limit) * 100 if limit > 0 else 0
            }
    except Exception as e:
        print(f"Error checking rate limit: {e}")
    
    return {'remaining': 5000, 'limit': 5000, 'reset_time': 0, 'percentage': 100}


def wait_if_rate_limited(token: str, min_remaining: int = 100):
    """Wait if rate limit is too low"""
    rate_limit = check_rate_limit(token)
    
    print(f"Rate limit: {rate_limit['remaining']}/{rate_limit['limit']} ({rate_limit['percentage']:.1f}%)")
    
    if rate_limit['remaining'] < min_remaining:
        wait_time = rate_limit['reset_time'] - int(time.time())
        if wait_time > 0:
            print(f"⚠️ Rate limit low ({rate_limit['remaining']} remaining)")
            print(f"   Waiting {wait_time} seconds until reset...")
            time.sleep(wait_time + 10)


def parse_next_link(link_header: str) -> Optional[str]:
    """
    Parse GitHub Link header to find next page URL
    Example: '<https://api.github.com/repos/...?page=2>; rel="next"'
    """
    if not link_header:
        return None
    
    links = link_header.split(',')
    for link in links:
        if 'rel="next"' in link:
            # Extract URL between < and >
            start = link.find('<')
            end = link.find('>')
            if start != -1 and end != -1:
                return link[start + 1:end]
    
    return None


def github_request(url: str, token: str, params: Optional[Dict] = None, paginate: bool = False) -> Any:
    """Make authenticated GitHub API request with rate limit handling and optional pagination"""
    headers = {
        'Authorization': f'token {token}',
        'Accept': 'application/vnd.github.v3+json'
    }
    
    # If pagination is not requested, use original single-request logic
    if not paginate:
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
    
    # Pagination logic for fetching all pages
    all_results = []
    current_url = url
    page_count = 0
    max_retries = 3
    
    while current_url:
        page_count += 1
        print(f"  Fetching page {page_count}...")
        
        for attempt in range(max_retries):
            response = requests.get(current_url, headers=headers, params=params if page_count == 1 else None)
            
            if response.status_code == 200:
                data = response.json()
                if isinstance(data, list):
                    all_results.extend(data)
                else:
                    all_results.append(data)
                
                # Check for next page in Link header
                link_header = response.headers.get('Link', '')
                current_url = parse_next_link(link_header)
                
                # Rate limiting between pages
                if current_url:
                    time.sleep(0.5)
                
                break  # Success, exit retry loop
                
            elif response.status_code == 403 and 'rate limit' in response.text.lower():
                reset_time = int(response.headers.get('X-RateLimit-Reset', 0))
                wait_time = max(reset_time - int(time.time()), 60)
                print(f"Rate limited. Waiting {wait_time} seconds...")
                time.sleep(wait_time)
            elif response.status_code == 404:
                print(f"Resource not found: {current_url}")
                return all_results
            else:
                print(f"GitHub API error: {response.status_code} - {response.text}")
                if attempt < max_retries - 1:
                    time.sleep(2 ** attempt)
                else:
                    print(f"Failed to fetch page {page_count} after {max_retries} attempts")
                    return all_results
    
    return all_results


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


def get_last_processed_pr(org: str, repo: str) -> int:
    """Get the last processed PR number from DynamoDB checkpoint"""
    print(f"🔍 DEBUG: get_last_processed_pr called for {org}/{repo}")
    try:
        print(f"🔍 DEBUG: Querying repos_table with key: org={org}, repo={repo}")
        response = repos_table.get_item(Key={'org': org, 'repo': repo})
        print(f"🔍 DEBUG: get_item response: {response}")
        if 'Item' in response:
            last_pr = response['Item'].get('lastProcessedPR', 0)
            print(f"🔍 DEBUG: Found lastProcessedPR = {last_pr}")
            return last_pr
        else:
            print(f"🔍 DEBUG: No item found for {org}/{repo}")
    except Exception as e:
        print(f"❌ ERROR getting checkpoint: {e}")
        import traceback
        traceback.print_exc()
    print(f"🔍 DEBUG: Returning 0 (no checkpoint)")
    return 0


def update_checkpoint(org: str, repo: str, pr_number: int):
    """Update the checkpoint with the last processed PR"""
    try:
        print(f"DEBUG: Updating checkpoint for {org}/{repo} to PR #{pr_number}")
        response = repos_table.update_item(
            Key={'org': org, 'repo': repo},
            UpdateExpression='SET lastProcessedPR = :pr, lastCheckpointAt = :now',
            ExpressionAttributeValues={
                ':pr': pr_number,
                ':now': datetime.now(timezone.utc).isoformat()
            },
            ReturnValues='ALL_NEW'
        )
        print(f"DEBUG: Checkpoint updated successfully: {response.get('Attributes', {}).get('lastProcessedPR')}")
    except Exception as e:
        print(f"Error updating checkpoint: {e}")
        import traceback
        traceback.print_exc()


def scrape_pull_requests_comprehensive(org: str, repo: str, token: str, repo_id: str) -> Dict:
    """
    Scrape ALL pull requests with full details (comments, reviews, files)
    Supports resume from last checkpoint
    
    Returns:
        stats: Dictionary with scraping statistics
    """
    print(f"\n{'='*60}")
    print(f"Starting Comprehensive PR Scraping for {org}/{repo}")
    print(f"{'='*60}")
    
    # Get last checkpoint
    last_processed_pr = get_last_processed_pr(org, repo)
    if last_processed_pr > 0:
        print(f"📍 Resuming from checkpoint: PR #{last_processed_pr}")
        print(f"   Will skip PRs >= #{last_processed_pr} and continue from PR #{last_processed_pr - 1}")
    else:
        print(f"📍 No checkpoint found - starting from newest PR")
    
    stats = {
        'prs_total': 0,
        'prs_processed': 0,
        'prs_skipped': 0,
        'comments': 0,
        'review_comments': 0,
        'reviews': 0,
        'files': 0,
        'api_calls': 0,
        'errors': [],
        'last_pr_processed': 0
    }
    
    # Check initial rate limit
    wait_if_rate_limited(token, min_remaining=500)
    
    # Fetch ALL PRs with pagination
    print("\n📥 Fetching ALL Pull Requests...")
    all_prs = []
    page = 1
    
    while True:
        pr_url = f"https://api.github.com/repos/{org}/{repo}/pulls"
        params = {'state': 'all', 'per_page': 100, 'page': page, 'sort': 'created', 'direction': 'desc'}
        
        prs = github_request(pr_url, token, params)
        stats['api_calls'] += 1
        
        if not isinstance(prs, list) or len(prs) == 0:
            break
        
        all_prs.extend(prs)
        print(f"  Page {page}: {len(prs)} PRs (total: {len(all_prs)})")
        
        if len(prs) < 100:
            break
        
        page += 1
        time.sleep(0.5)
    
    stats['prs_total'] = len(all_prs)
    print(f"\n✓ Found {stats['prs_total']} total PRs")
    
    # Process each PR
    for idx, pr in enumerate(all_prs, 1):
        try:
            pr_number = pr.get('number')
            if not pr_number:
                continue
            
            # Skip if already processed (resume logic)
            # PRs are in descending order (newest first), so skip if pr_number >= last_processed_pr
            if last_processed_pr > 0 and pr_number >= last_processed_pr:
                stats['prs_skipped'] += 1
                if stats['prs_skipped'] % 100 == 0:
                    print(f"  Skipped {stats['prs_skipped']} already-processed PRs...")
                continue
            
            print(f"\n[{idx}/{stats['prs_total']}] Processing PR #{pr_number}: {pr.get('title', '')[:50]}...")
            
            pr_id = f"pr#{org}/{repo}#{pr_number}"
            
            # Get user info
            user_data = pr.get('user')
            if not user_data or not user_data.get('login'):
                print(f"  ⚠️ Skipping PR #{pr_number} - no user data")
                continue
            
            user_login = user_data.get('login')
            user_id = f"user#{user_login}"
            
            # Create PR node with comprehensive data
            pr_node_data = {
                'number': pr_number,
                'title': pr.get('title'),
                'body': (pr.get('body') or '')[:1000],  # Limit to 1000 chars
                'state': pr.get('state'),
                'merged': pr.get('merged', False),
                'draft': pr.get('draft', False),
                'created_at': pr.get('created_at'),
                'updated_at': pr.get('updated_at'),
                'closed_at': pr.get('closed_at'),
                'merged_at': pr.get('merged_at'),
                'url': pr.get('html_url'),
                'additions': pr.get('additions', 0),
                'deletions': pr.get('deletions', 0),
                'changed_files': pr.get('changed_files', 0),
                'commits': pr.get('commits', 0),
                'base_branch': pr.get('base', {}).get('ref'),
                'head_branch': pr.get('head', {}).get('ref')
            }
            
            upsert_node(pr_id, 'pull_request', pr_node_data)
            
            # Create user node
            upsert_node(user_id, 'user', {
                'login': user_login,
                'url': user_data.get('html_url'),
                'avatarUrl': user_data.get('avatar_url'),
                'type': 'contributor'
            })
            
            # Create edges
            upsert_edge(user_id, pr_id, 'AUTHORED', {'createdAt': pr.get('created_at')})
            upsert_edge(pr_id, repo_id, 'IN_REPO')
            
            # Fetch PR comments
            comments_url = f"https://api.github.com/repos/{org}/{repo}/issues/{pr_number}/comments"
            comments = github_request(comments_url, token, {'per_page': 100})
            stats['api_calls'] += 1
            
            if isinstance(comments, list):
                for comment in comments:
                    comment_author = comment.get('user', {}).get('login')
                    if comment_author:
                        comment_id = f"comment#{org}/{repo}#pr#{pr_number}#comment#{comment.get('id')}"
                        upsert_node(comment_id, 'pr_comment', {
                            'pr_number': pr_number,
                            'author': comment_author,
                            'body': (comment.get('body') or '')[:500],
                            'created_at': comment.get('created_at'),
                            'url': comment.get('html_url')
                        })
                        upsert_edge(f"user#{comment_author}", comment_id, 'COMMENTED')
                        upsert_edge(comment_id, pr_id, 'ON_PR')
                        stats['comments'] += 1
            
            # Fetch PR reviews
            reviews_url = f"https://api.github.com/repos/{org}/{repo}/pulls/{pr_number}/reviews"
            reviews = github_request(reviews_url, token, {'per_page': 100})
            stats['api_calls'] += 1
            
            if isinstance(reviews, list):
                for review in reviews:
                    reviewer = review.get('user', {}).get('login')
                    if reviewer:
                        review_id = f"review#{org}/{repo}#pr#{pr_number}#review#{review.get('id')}"
                        upsert_node(review_id, 'pr_review', {
                            'pr_number': pr_number,
                            'reviewer': reviewer,
                            'state': review.get('state'),
                            'body': (review.get('body') or '')[:500],
                            'submitted_at': review.get('submitted_at')
                        })
                        upsert_edge(f"user#{reviewer}", review_id, 'REVIEWED')
                        upsert_edge(review_id, pr_id, 'REVIEWS_PR')
                        stats['reviews'] += 1
            
            # Fetch PR files
            files_url = f"https://api.github.com/repos/{org}/{repo}/pulls/{pr_number}/files"
            files = github_request(files_url, token, {'per_page': 100})
            stats['api_calls'] += 1
            
            if isinstance(files, list):
                for file_data in files:
                    filename = file_data.get('filename')
                    if filename:
                        file_id = f"file#{org}/{repo}#{filename}"
                        upsert_node(file_id, 'file', {
                            'path': filename,
                            'directory': '/'.join(filename.split('/')[:-1]) if '/' in filename else ''
                        })
                        upsert_edge(pr_id, file_id, 'TOUCHES', {
                            'additions': file_data.get('additions', 0),
                            'deletions': file_data.get('deletions', 0),
                            'status': file_data.get('status')
                        })
                        stats['files'] += 1
            
            stats['prs_processed'] += 1
            stats['last_pr_processed'] = pr_number  # Track the lowest PR number processed
            
            # Save checkpoint every 10 PRs
            if stats['prs_processed'] % 10 == 0:
                print(f"  Progress: {stats['prs_processed']}/{stats['prs_total']} PRs")
                print(f"  Stats: {stats['comments']} comments, {stats['reviews']} reviews, {stats['files']} files")
                update_checkpoint(org, repo, pr_number)
                print(f"  💾 Checkpoint saved at PR #{pr_number}")
                wait_if_rate_limited(token, min_remaining=100)
            
        except Exception as e:
            print(f"  ❌ Error processing PR #{pr.get('number', 'unknown')}: {e}")
            stats['errors'].append(f"PR #{pr.get('number')}: {str(e)}")
            continue
    
    # Save final checkpoint
    if stats['prs_processed'] > 0 and 'last_pr_processed' in stats:
        last_pr = stats['last_pr_processed']
        update_checkpoint(org, repo, last_pr)
        print(f"\n💾 Final checkpoint saved at PR #{last_pr}")
    
    print(f"\n{'='*60}")
    print(f"PR Scraping Complete!")
    print(f"{'='*60}")
    print(f"PRs processed: {stats['prs_processed']}/{stats['prs_total']}")
    print(f"PRs skipped (already done): {stats['prs_skipped']}")
    print(f"Comments: {stats['comments']}")
    print(f"Reviews: {stats['reviews']}")
    print(f"Files: {stats['files']}")
    print(f"API calls: {stats['api_calls']}")
    print(f"Errors: {len(stats['errors'])}")
    
    return stats


def ingest_repository(org: str, repo: str, token: str, cursor: str, mode: str = 'contributors') -> Dict:
    """Ingest data for a single repository"""
    print(f"Ingesting {org}/{repo}...")
    
    repo_id = f"repo#{org}/{repo}"
    stats = {
        'contributors': 0,
        'contributors_total': 0,
        'bots_skipped': 0,
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
    
    # 1. FETCH ALL CONTRIBUTORS (if mode includes contributors)
    if mode in ['contributors', 'full']:
        print(f"Fetching ALL contributors for {org}/{repo} (this may take a while)...")
        contributors_url = f"https://api.github.com/repos/{org}/{repo}/contributors"
        contributors = github_request(contributors_url, token, {'per_page': 100}, paginate=True)
    else:
        contributors = []
    
    if isinstance(contributors, list) and mode in ['contributors', 'full']:
        stats['contributors_total'] = len(contributors)
        print(f"Found {stats['contributors_total']} total contributors")
        
        # Safety limits
        MAX_CONTRIBUTORS = 1000
        CONTRIBUTOR_TIMEOUT = 300  # 5 minutes
        start_time = time.time()
        
        for contributor in contributors:
            # Check timeout
            if time.time() - start_time > CONTRIBUTOR_TIMEOUT:
                print(f"⚠️ Contributor processing timeout after {stats['contributors']} contributors")
                stats['errors'].append(f"Timeout after {stats['contributors']} contributors")
                break
            
            # Check max limit
            if stats['contributors'] >= MAX_CONTRIBUTORS:
                print(f"⚠️ Reached max contributor limit ({MAX_CONTRIBUTORS})")
                stats['errors'].append(f"Max contributor limit reached")
                break
            
            user_login = contributor.get('login')
            
            # Skip bots and invalid users
            if not user_login:
                continue
            
            if contributor.get('type') != 'User':
                stats['bots_skipped'] += 1
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
            
            # Progress logging every 50 contributors
            if stats['contributors'] % 50 == 0:
                print(f"  Processed {stats['contributors']}/{stats['contributors_total']} contributors...")
            
            # Rate limiting every 10 contributors
            if stats['contributors'] % 10 == 0:
                time.sleep(0.3)
        
        print(f"Ingested {stats['contributors']} contributors ({stats['bots_skipped']} bots skipped)")
    
    # 2. FETCH PULL REQUESTS
    if mode in ['prs', 'full']:
        # Use comprehensive PR scraping
        pr_stats = scrape_pull_requests_comprehensive(org, repo, token, repo_id)
        stats.update(pr_stats)
    elif mode == 'contributors':
        # Skip PR scraping in contributors-only mode
        print("Skipping PR scraping (contributors-only mode)")
    else:
        # Legacy: Basic PR scraping (for backward compatibility)
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
    print(f"  - {stats['contributors']}/{stats['contributors_total']} contributors processed ({stats['bots_skipped']} bots skipped)")
    print(f"  - {stats['prs']} pull requests")
    print(f"  - {stats['issues']} issues")
    print(f"  - {stats['files']} files")
    
    return stats


def lambda_handler(event, context):
    """Main Lambda handler"""
    print(f"Starting ingestion: {json.dumps(event)}")
    
    # Get ingestion mode from event
    mode = event.get('mode', 'contributors')  # Default to contributors only
    print(f"Ingestion mode: {mode}")
    
    # Validate mode
    if mode not in ['contributors', 'prs', 'full']:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': f'Invalid mode: {mode}. Must be contributors, prs, or full'})
        }
    
    # Get GitHub token
    token = get_github_token()
    if not token:
        print("Warning: No GitHub token found, using environment variable")
        token = os.environ.get('GITHUB_TOKEN', '')
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
        # If repos table is empty or doesn't exist, use default repo
        repos = [{
            'org': 'RooCodeInc',
            'repo': 'Roo-Code',
            'enabled': True
        }]
        print("Using default repository: RooCodeInc/Roo-Code")
    
    if not repos:
        print("No enabled repositories found, adding default")
        # Add default repository
        try:
            repos_table.put_item(
                Item={
                    'org': 'RooCodeInc',
                    'repo': 'Roo-Code',
                    'enabled': True,
                    'description': 'AI-powered code assistant for developers',
                    'language': 'TypeScript',
                    'stars': 1234,
                    'topics': ['ai', 'code-assistant', 'vscode', 'typescript'],
                    'ingestStatus': 'pending',
                    'createdAt': datetime.now(timezone.utc).isoformat()
                }
            )
            repos = [{'org': 'RooCodeInc', 'repo': 'Roo-Code', 'enabled': True}]
        except Exception as e:
            print(f"Error adding default repo: {e}")
            return {
                'statusCode': 200,
                'body': json.dumps({'message': 'No repositories to ingest and could not add default'})
            }
    
    # Ingest each repository
    results = []
    for repo_config in repos[:5]:  # Limit to 5 repos for hackathon
        org = repo_config.get('org')
        repo = repo_config.get('repo')
        cursor = repo_config.get('ingestCursor', '2024-01-01T00:00:00Z')
        
        try:
            stats = ingest_repository(org, repo, token, cursor, mode)
            
            # Update cursor
            try:
                repos_table.update_item(
                    Key={'org': org, 'repo': repo},
                    UpdateExpression='SET lastIngestAt = :now, ingestStatus = :status',
                    ExpressionAttributeValues={
                        ':now': datetime.now(timezone.utc).isoformat(),
                        ':status': 'success'
                    }
                )
            except Exception as update_error:
                print(f"Error updating repo status: {update_error}")
            
            results.append({
                'repo': f"{org}/{repo}",
                'status': 'success',
                'stats': stats
            })
        except Exception as e:
            print(f"Error ingesting {org}/{repo}: {e}")
            # Try to update status to error
            try:
                repos_table.update_item(
                    Key={'org': org, 'repo': repo},
                    UpdateExpression='SET lastIngestAt = :now, ingestStatus = :status, lastError = :error',
                    ExpressionAttributeValues={
                        ':now': datetime.now(timezone.utc).isoformat(),
                        ':status': 'error',
                        ':error': str(e)
                    }
                )
            except Exception as update_error:
                print(f"Error updating repo error status: {update_error}")
            
            results.append({
                'repo': f"{org}/{repo}",
                'status': 'error',
                'error': str(e)
            })
    
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'message': 'Ingestion complete',
            'results': results,
            'totalProcessed': len(results),
            'successful': len([r for r in results if r['status'] == 'success']),
            'failed': len([r for r in results if r['status'] == 'error'])
        })
    }
