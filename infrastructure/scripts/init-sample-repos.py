#!/usr/bin/env python3
"""
Initialize sample repository configurations in DynamoDB cc-repos table.
This script adds sample open-source repositories for ContribConnect to ingest.
"""

import boto3
import sys
from datetime import datetime

def init_sample_repos(environment='dev', region='us-east-1', profile='default'):
    """Initialize sample repositories in DynamoDB."""
    
    # Configure boto3 session
    session = boto3.Session(profile_name=profile, region_name=region)
    dynamodb = session.resource('dynamodb')
    
    table_name = f'cc-repos-{environment}'
    table = dynamodb.Table(table_name)
    
    # Sample repositories with good-first-issue labels
    sample_repos = [
        {
            'org': 'facebook',
            'repo': 'react',
            'enabled': True,
            'topics': ['javascript', 'react', 'frontend', 'ui'],
            'minStars': 100000,
            'ingestCursor': '2024-01-01T00:00:00Z',
            'lastIngestAt': '',
            'ingestStatus': 'pending',
            'description': 'A declarative, efficient, and flexible JavaScript library for building user interfaces'
        },
        {
            'org': 'microsoft',
            'repo': 'vscode',
            'enabled': True,
            'topics': ['typescript', 'editor', 'ide', 'electron'],
            'minStars': 50000,
            'ingestCursor': '2024-01-01T00:00:00Z',
            'lastIngestAt': '',
            'ingestStatus': 'pending',
            'description': 'Visual Studio Code - Open Source code editor'
        },
        {
            'org': 'tensorflow',
            'repo': 'tensorflow',
            'enabled': True,
            'topics': ['python', 'machine-learning', 'deep-learning', 'ai'],
            'minStars': 50000,
            'ingestCursor': '2024-01-01T00:00:00Z',
            'lastIngestAt': '',
            'ingestStatus': 'pending',
            'description': 'An Open Source Machine Learning Framework for Everyone'
        },
        {
            'org': 'kubernetes',
            'repo': 'kubernetes',
            'enabled': True,
            'topics': ['go', 'containers', 'orchestration', 'cloud-native'],
            'minStars': 50000,
            'ingestCursor': '2024-01-01T00:00:00Z',
            'lastIngestAt': '',
            'ingestStatus': 'pending',
            'description': 'Production-Grade Container Orchestration'
        },
        {
            'org': 'rust-lang',
            'repo': 'rust',
            'enabled': True,
            'topics': ['rust', 'systems-programming', 'compiler'],
            'minStars': 30000,
            'ingestCursor': '2024-01-01T00:00:00Z',
            'lastIngestAt': '',
            'ingestStatus': 'pending',
            'description': 'Empowering everyone to build reliable and efficient software'
        },
        {
            'org': 'django',
            'repo': 'django',
            'enabled': True,
            'topics': ['python', 'web-framework', 'backend'],
            'minStars': 20000,
            'ingestCursor': '2024-01-01T00:00:00Z',
            'lastIngestAt': '',
            'ingestStatus': 'pending',
            'description': 'The Web framework for perfectionists with deadlines'
        },
        {
            'org': 'nodejs',
            'repo': 'node',
            'enabled': True,
            'topics': ['javascript', 'nodejs', 'runtime'],
            'minStars': 50000,
            'ingestCursor': '2024-01-01T00:00:00Z',
            'lastIngestAt': '',
            'ingestStatus': 'pending',
            'description': 'Node.js JavaScript runtime'
        },
        {
            'org': 'vuejs',
            'repo': 'vue',
            'enabled': True,
            'topics': ['javascript', 'vue', 'frontend', 'framework'],
            'minStars': 40000,
            'ingestCursor': '2024-01-01T00:00:00Z',
            'lastIngestAt': '',
            'ingestStatus': 'pending',
            'description': 'The Progressive JavaScript Framework'
        }
    ]
    
    print(f"Initializing sample repositories in table: {table_name}")
    print(f"Region: {region}")
    print(f"Profile: {profile}")
    print("-" * 60)
    
    success_count = 0
    error_count = 0
    
    for repo_config in sample_repos:
        try:
            table.put_item(Item=repo_config)
            print(f"✓ Added: {repo_config['org']}/{repo_config['repo']}")
            success_count += 1
        except Exception as e:
            print(f"✗ Failed to add {repo_config['org']}/{repo_config['repo']}: {str(e)}")
            error_count += 1
    
    print("-" * 60)
    print(f"Summary: {success_count} repositories added, {error_count} errors")
    
    if error_count > 0:
        return 1
    return 0

if __name__ == '__main__':
    # Parse command line arguments
    environment = sys.argv[1] if len(sys.argv) > 1 else 'dev'
    region = sys.argv[2] if len(sys.argv) > 2 else 'us-east-1'
    profile = sys.argv[3] if len(sys.argv) > 3 else 'default'
    
    print("=" * 60)
    print("ContribConnect - Initialize Sample Repositories")
    print("=" * 60)
    
    exit_code = init_sample_repos(environment, region, profile)
    sys.exit(exit_code)
