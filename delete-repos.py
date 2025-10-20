#!/usr/bin/env python3
"""
Delete all repositories except RooCodeInc/Roo-Code from DynamoDB
"""

import boto3
import sys

def main():
    # Configuration
    table_name = 'cc-repos-dev'
    region = 'us-east-1'
    
    # Initialize DynamoDB
    dynamodb = boto3.resource('dynamodb', region_name=region)
    table = dynamodb.Table(table_name)
    
    print("\n" + "="*50)
    print("Delete All Repos Except RooCode")
    print("="*50 + "\n")
    
    # Scan table
    print("Scanning table...")
    response = table.scan()
    items = response.get('Items', [])
    
    print(f"Found {len(items)} repositories\n")
    
    deleted_count = 0
    kept_count = 0
    failed_count = 0
    
    for item in items:
        org = item.get('org')
        repo = item.get('repo')
        full_name = f"{org}/{repo}"
        
        # Skip RooCode
        if org == 'RooCodeInc' and repo == 'Roo-Code':
            print(f"✓ KEEPING: {full_name}")
            kept_count += 1
            continue
        
        print(f"  Deleting: {full_name}...", end=' ')
        
        try:
            table.delete_item(
                Key={
                    'org': org,
                    'repo': repo
                }
            )
            print("SUCCESS")
            deleted_count += 1
        except Exception as e:
            print(f"FAILED: {e}")
            failed_count += 1
    
    print("\n" + "="*50)
    print(f"Results:")
    print(f"  Deleted: {deleted_count}")
    print(f"  Kept: {kept_count}")
    print(f"  Failed: {failed_count}")
    print("="*50 + "\n")
    
    # Verify
    print("Verifying remaining repositories...")
    response = table.scan()
    remaining = response.get('Items', [])
    
    print(f"\nRemaining repositories ({len(remaining)}):")
    for item in remaining:
        print(f"  - {item['org']}/{item['repo']}")
    
    if len(remaining) == 1:
        print("\n✓ SUCCESS! Only RooCodeInc/Roo-Code remains.\n")
        return 0
    else:
        print(f"\n⚠ WARNING: Expected 1 repository, found {len(remaining)}\n")
        return 1

if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as e:
        print(f"\n❌ ERROR: {e}\n")
        sys.exit(1)
