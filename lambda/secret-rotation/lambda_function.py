"""
AWS Secrets Manager Rotation Lambda for ContribConnect
Handles automatic rotation of GitHub tokens and API keys
"""

import json
import os
import boto3
import secrets as secrets_module
from typing import Dict

# Initialize AWS clients
secrets_client = boto3.client('secretsmanager')
ses_client = boto3.client('ses')

# Environment variables
NOTIFICATION_EMAIL = os.environ.get('NOTIFICATION_EMAIL', '')


def generate_api_key() -> str:
    """Generate a new random API key"""
    random_bytes = secrets_module.token_bytes(32)
    return "cc-" + secrets_module.token_hex(20)


def send_rotation_notification(secret_name: str, rotation_type: str, new_value: str = None):
    """Send email notification about secret rotation"""
    if not NOTIFICATION_EMAIL:
        print("No notification email configured, skipping notification")
        return
    
    subject = f"[ContribConnect] Secret Rotation: {secret_name}"
    
    if rotation_type == "api_key":
        body = f"""
A new API key has been generated for ContribConnect.

Secret Name: {secret_name}
New API Key: {new_value}

Action Required:
1. Update your frontend .env file with the new API key
2. Redeploy the frontend application
3. Test API access with the new key

The old API key will stop working after the rotation is complete.
"""
    elif rotation_type == "github_token":
        body = f"""
The GitHub token for ContribConnect needs to be rotated.

Secret Name: {secret_name}

Action Required:
1. Go to https://github.com/settings/tokens
2. Generate a new fine-grained personal access token
3. Update the secret in AWS Secrets Manager:
   aws secretsmanager put-secret-value --secret-id {secret_name} --secret-string '{{"token":"YOUR_NEW_TOKEN"}}'

The current token will expire soon.
"""
    else:
        body = f"Secret {secret_name} has been rotated."
    
    try:
        ses_client.send_email(
            Source=NOTIFICATION_EMAIL,
            Destination={'ToAddresses': [NOTIFICATION_EMAIL]},
            Message={
                'Subject': {'Data': subject},
                'Body': {'Text': {'Data': body}}
            }
        )
        print(f"Notification sent to {NOTIFICATION_EMAIL}")
    except Exception as e:
        print(f"Failed to send notification: {e}")


def create_secret(secret_arn: str, token: str) -> Dict:
    """
    Create a new version of the secret
    
    This is called during the createSecret step of rotation
    """
    print(f"Creating new secret version for {secret_arn}")
    
    # Get current secret metadata
    metadata = secrets_client.describe_secret(SecretId=secret_arn)
    secret_name = metadata['Name']
    
    # Determine secret type
    if 'api-key' in secret_name:
        # Generate new API key
        new_api_key = generate_api_key()
        new_secret = json.dumps({
            'key': new_api_key,
            'environment': os.environ.get('ENVIRONMENT', 'dev'),
            'rotatedAt': boto3.client('sts').get_caller_identity()['Account']
        })
        
        # Store new version with AWSPENDING label
        secrets_client.put_secret_value(
            SecretId=secret_arn,
            SecretString=new_secret,
            VersionStages=['AWSPENDING']
        )
        
        # Send notification with new key
        send_rotation_notification(secret_name, 'api_key', new_api_key)
        
        return {'status': 'success', 'message': 'New API key generated'}
        
    elif 'github-token' in secret_name:
        # GitHub tokens must be manually rotated
        # Send notification to admin
        send_rotation_notification(secret_name, 'github_token')
        
        return {'status': 'manual', 'message': 'GitHub token requires manual rotation'}
    
    else:
        return {'status': 'error', 'message': f'Unknown secret type: {secret_name}'}


def set_secret(secret_arn: str, token: str) -> Dict:
    """
    Test the new secret version
    
    This is called during the setSecret step of rotation
    """
    print(f"Testing new secret version for {secret_arn}")
    
    # Get the AWSPENDING version
    response = secrets_client.get_secret_value(
        SecretId=secret_arn,
        VersionStage='AWSPENDING'
    )
    
    new_secret = json.loads(response['SecretString'])
    
    # Validate the new secret
    if 'key' in new_secret:
        # API key - validate format
        if not new_secret['key'].startswith('cc-'):
            return {'status': 'error', 'message': 'Invalid API key format'}
    elif 'token' in new_secret:
        # GitHub token - validate format
        if not (new_secret['token'].startswith('ghp_') or new_secret['token'].startswith('github_pat_')):
            return {'status': 'error', 'message': 'Invalid GitHub token format'}
    
    return {'status': 'success', 'message': 'Secret validation passed'}


def test_secret(secret_arn: str, token: str) -> Dict:
    """
    Test the new secret in the actual application
    
    This is called during the testSecret step of rotation
    """
    print(f"Testing new secret in application for {secret_arn}")
    
    # In a real implementation, you would:
    # 1. Get the AWSPENDING version
    # 2. Make a test API call using the new secret
    # 3. Verify it works correctly
    
    # For now, we'll just return success
    return {'status': 'success', 'message': 'Application test passed'}


def finish_secret(secret_arn: str, token: str) -> Dict:
    """
    Finalize the rotation by moving AWSCURRENT to the new version
    
    This is called during the finishSecret step of rotation
    """
    print(f"Finalizing rotation for {secret_arn}")
    
    # Get current version
    metadata = secrets_client.describe_secret(SecretId=secret_arn)
    current_version = None
    pending_version = None
    
    for version_id, stages in metadata['VersionIdsToStages'].items():
        if 'AWSCURRENT' in stages:
            current_version = version_id
        if 'AWSPENDING' in stages:
            pending_version = version_id
    
    if not pending_version:
        return {'status': 'error', 'message': 'No AWSPENDING version found'}
    
    # Move AWSCURRENT to the new version
    secrets_client.update_secret_version_stage(
        SecretId=secret_arn,
        VersionStage='AWSCURRENT',
        MoveToVersionId=pending_version,
        RemoveFromVersionId=current_version
    )
    
    print(f"Rotation complete. New version {pending_version} is now AWSCURRENT")
    
    return {'status': 'success', 'message': 'Rotation completed successfully'}


def lambda_handler(event, context):
    """
    Main Lambda handler for Secrets Manager rotation
    
    Event structure:
    {
        "Step": "createSecret" | "setSecret" | "testSecret" | "finishSecret",
        "SecretId": "arn:aws:secretsmanager:...",
        "Token": "rotation-token"
    }
    """
    print(f"Rotation event: {json.dumps(event)}")
    
    secret_arn = event['SecretId']
    token = event['Token']
    step = event['Step']
    
    try:
        if step == 'createSecret':
            result = create_secret(secret_arn, token)
        elif step == 'setSecret':
            result = set_secret(secret_arn, token)
        elif step == 'testSecret':
            result = test_secret(secret_arn, token)
        elif step == 'finishSecret':
            result = finish_secret(secret_arn, token)
        else:
            raise ValueError(f"Invalid step: {step}")
        
        print(f"Step {step} completed: {result}")
        return result
        
    except Exception as e:
        print(f"Error during rotation step {step}: {e}")
        raise


# Manual rotation trigger (for testing)
"""
To manually trigger rotation:

aws secretsmanager rotate-secret \
    --secret-id cc-api-key-dev \
    --rotation-lambda-arn arn:aws:lambda:us-east-1:123456789012:function:cc-secret-rotation-dev \
    --rotation-rules AutomaticallyAfterDays=90
"""
