"""
Secrets Manager utility for ContribConnect Lambda functions
Provides caching and easy retrieval of secrets
"""

import json
import os
import boto3
from typing import Dict, Optional
from functools import lru_cache

# Initialize Secrets Manager client
secrets_client = boto3.client('secretsmanager')

# Cache for secrets (in-memory for Lambda container reuse)
_secrets_cache = {}


@lru_cache(maxsize=10)
def get_secret(secret_name: str, use_cache: bool = True) -> Optional[Dict]:
    """
    Retrieve a secret from AWS Secrets Manager
    
    Args:
        secret_name: Name of the secret to retrieve
        use_cache: Whether to use in-memory cache (default: True)
    
    Returns:
        Dictionary containing the secret value, or None if not found
    
    Example:
        secret = get_secret('cc-github-token-dev')
        github_token = secret.get('token')
    """
    
    # Check cache first
    if use_cache and secret_name in _secrets_cache:
        return _secrets_cache[secret_name]
    
    try:
        response = secrets_client.get_secret_value(SecretId=secret_name)
        
        # Parse secret string as JSON
        if 'SecretString' in response:
            secret_value = json.loads(response['SecretString'])
        else:
            # Binary secret (not typically used)
            secret_value = response['SecretBinary']
        
        # Cache the secret
        if use_cache:
            _secrets_cache[secret_name] = secret_value
        
        return secret_value
        
    except secrets_client.exceptions.ResourceNotFoundException:
        print(f"Secret {secret_name} not found")
        return None
    except secrets_client.exceptions.InvalidRequestException as e:
        print(f"Invalid request for secret {secret_name}: {e}")
        return None
    except secrets_client.exceptions.InvalidParameterException as e:
        print(f"Invalid parameter for secret {secret_name}: {e}")
        return None
    except Exception as e:
        print(f"Error retrieving secret {secret_name}: {e}")
        return None


def get_github_token(environment: str = "dev") -> Optional[str]:
    """
    Retrieve GitHub token from Secrets Manager
    
    Args:
        environment: Environment name (dev/prod)
    
    Returns:
        GitHub token string, or None if not found
    
    Example:
        token = get_github_token('dev')
        headers = {'Authorization': f'token {token}'}
    """
    secret_name = os.environ.get('GITHUB_TOKEN_SECRET', f'cc-github-token-{environment}')
    secret = get_secret(secret_name)
    
    if secret:
        return secret.get('token')
    
    # Fallback to environment variable
    return os.environ.get('GITHUB_TOKEN')


def get_api_key(environment: str = "dev") -> Optional[str]:
    """
    Retrieve API key from Secrets Manager
    
    Args:
        environment: Environment name (dev/prod)
    
    Returns:
        API key string, or None if not found
    
    Example:
        api_key = get_api_key('dev')
        if request_api_key == api_key:
            # Authorized
    """
    secret_name = os.environ.get('API_KEY_SECRET', f'cc-api-key-{environment}')
    secret = get_secret(secret_name)
    
    if secret:
        return secret.get('key')
    
    # Fallback to environment variable
    return os.environ.get('API_KEY')


def validate_api_key(provided_key: str, environment: str = "dev") -> bool:
    """
    Validate an API key against the stored secret
    
    Args:
        provided_key: API key provided by the client
        environment: Environment name (dev/prod)
    
    Returns:
        True if valid, False otherwise
    
    Example:
        if validate_api_key(event['headers'].get('x-api-key'), 'dev'):
            # Process request
        else:
            return {'statusCode': 401, 'body': 'Unauthorized'}
    """
    expected_key = get_api_key(environment)
    
    if not expected_key:
        print("Warning: No API key configured")
        return False
    
    return provided_key == expected_key


def clear_cache():
    """Clear the secrets cache (useful for testing or forced refresh)"""
    global _secrets_cache
    _secrets_cache.clear()
    get_secret.cache_clear()


# Example usage in Lambda function:
"""
from secrets import get_github_token, validate_api_key

def lambda_handler(event, context):
    # Validate API key
    api_key = event.get('headers', {}).get('x-api-key', '')
    if not validate_api_key(api_key, 'dev'):
        return {
            'statusCode': 401,
            'body': json.dumps({'error': 'Unauthorized'})
        }
    
    # Get GitHub token
    github_token = get_github_token('dev')
    if not github_token:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'GitHub token not configured'})
        }
    
    # Use token for GitHub API calls
    headers = {'Authorization': f'token {github_token}'}
    response = requests.get('https://api.github.com/user', headers=headers)
    
    return {
        'statusCode': 200,
        'body': json.dumps({'user': response.json()})
    }
"""
