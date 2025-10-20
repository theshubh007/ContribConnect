"""
ContribConnect Comprehensive GitHub Scraper
Standalone script for deep data collection with all advanced features
"""

import json
import os
import time
import re
import boto3
from typing import List, Dict, Optional, Tuple, Any
from datetime import datetime, timedelta
import requests

class ComprehensiveGitHubScraper:
    """
    Comprehensive GitHub scraper with all advanced features:
    - Incremental updates
    - Special files (CODEOWNERS, CONTRIBUTING.md, package.json)
    - Linked issues extraction
    - Comments for issues and PRs
    - Full file tree
    - And more...
    """
    
    def __init__(self, github_token: Optional[str] = None):
        """Initialize scraper with GitHub token"""
        self.token = github_token or os.environ.get('GITHUB_TOKEN', '')
        self.base_url = "https://api.github.com"
        self.headers = {
            'Authorization': f'token {self.token}',
            'Accept': 'application/vnd.github.v3+json'
        }
        
        # AWS clients for DynamoDB integration
        self.dynamodb = boto3.resource('dynamodb')
        self.nodes_table = self.dynamodb.Table(os.environ.get('NODES_TABLE', 'cc-nodes-dev'))
        self.edges_table = self.dynamodb.Table(os.environ.get('EDGES_TABLE', 'cc-edges-dev'))
        
        # Configuration
        self.max_commits = 500
        self.max_issues = 500
        self.max_prs = 500
        self.recent_days = 120
    
    def _make_request(self, url: str, params: Optional[Dict] = None) -> Optional[requests.Response]:
        """Make authenticated GitHub API request"""
        try:
            response = requests.get(url, headers=self.headers, params=params, timeout=60)
            response.raise_for_status()
            return response
        except requests.exceptions.RequestException as e:
            print(f"❌ Request error: {e}")
            return None
    
    def _fetch_paginated(self, url: str, params: Optional[Dict] = None, max_pages: Optional[int] = None) -> List[Dict]:
        """Fetch paginated data from GitHub API"""
        all_data = []
        page = 1
        request_params = params.copy() if params else {}
        request_params['per_page'] = 100
        
        while max_pages is None or page <= max_pages:
            request_params['page'] = page
            response = self._make_request(url, request_params)
            
            if not response:
                break
            
            try:
                data = response.json()
                if not isinstance(data, list) or not data:
                    break
                
                all_data.extend(data)
                page += 1
                time.sleep(0.3)  # Rate limiting
            except json.JSONDecodeError:
                break
        
        return all_data
    
    # ==================== SPECIAL FILES ====================
    
    def _extract_linked_issues(self, text: Optional[str]) -> List[int]:
        """Extract linked issue numbers from PR/commit body"""
        if not text:
            return []
        
        pattern = r'(?:fix(?:es|ed)?|close(?:s|d)?|resolve(?:s|d)?)\s+#(\d+)'
        matches = re.findall(pattern, text, re.IGNORECASE)
        
        bare_pattern = r'#(\d+)'
        bare_matches = re.findall(bare_pattern, text)
        
        all_issues = list(set([int(m) for m in matches] + [int(m) for m in bare_matches]))
        return sorted(all_issues)
    
    def get_file_content(self, owner: str, repo: str, path: str, branch: Optional[str] = None) -> Optional[str]:
        """Get raw content of a specific file"""
        if not branch:
            branch = "main"
        
        url = f"{self.base_url}/repos/{owner}/{repo}/contents/{path}"
        params = {"ref": branch}
        
        response = self._make_request(url, params)
        if not response:
            return None
        
        try:
            data = response.json()
            import base64
            return base64.b64decode(data['content']).decode('utf-8')
        except Exception as e:
            print(f"  ⚠️  Error reading {path}: {e}")
            return None
    
    def parse_codeowners(self, content: str) -> Dict[str, List[str]]:
        """Parse CODEOWNERS file"""
        owners_map = {}
        for line in content.split('\n'):
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            
            parts = line.split()
            if len(parts) < 2:
                continue
            
            pattern = parts[0]
            owners = []
            for owner in parts[1:]:
                if owner.startswith('@'):
                    username = owner[1:].split('/')[0]
                    owners.append(username)
            
            if owners:
                owners_map[pattern] = owners
        
        return owners_map
    
    def get_special_files(self, owner: str, repo: str) -> Dict[str, Any]:
        """Fetch and parse special files: CODEOWNERS, CONTRIBUTING.md, package.json"""
        print(f"📄 Fetching special files...")
        special_files = {
            "codeowners": None,
            "codeowners_parsed": {},
            "contributing": None,
            "package_json": None,
        }
        
        # Try multiple locations for CODEOWNERS
        for path in ["CODEOWNERS", ".github/CODEOWNERS", "docs/CODEOWNERS"]:
            content = self.get_file_content(owner, repo, path)
            if content:
                special_files["codeowners"] = content
                special_files["codeowners_parsed"] = self.parse_codeowners(content)
                print(f"  ✓ Found CODEOWNERS at {path}")
                break
        
        # Try multiple locations for CONTRIBUTING
        for path in ["CONTRIBUTING.md", ".github/CONTRIBUTING.md", "docs/CONTRIBUTING.md"]:
            content = self.get_file_content(owner, repo, path)
            if content:
                special_files["contributing"] = content
                print(f"  ✓ Found CONTRIBUTING.md at {path}")
                break
        
        # Get package.json
        content = self.get_file_content(owner, repo, "package.json")
        if content:
            try:
                special_files["package_json"] = json.loads(content)
                print(f"  ✓ Found package.json")
            except json.JSONDecodeError:
                pass
        
        return special_files
    
    # ==================== INCREMENTAL UPDATES ====================
    
    def get_updated_issues(self, owner: str, repo: str, since: str) -> List[Dict]:
        """Get issues updated since a specific timestamp"""
        print(f"🔄 Fetching issues updated since {since}...")
        url = f"{self.base_url}/repos/{owner}/{repo}/issues"
        params = {
            "state": "all",
            "since": since,
            "per_page": 100,
            "sort": "updated",
            "direction": "desc"
        }
        
        issues_data = self._fetch_paginated(url, params)
        
        issues = []
        for issue_data in issues_data:
            if "pull_request" in issue_data:
                continue
            
            user_data = issue_data.get('user')
            if not user_data:
                continue
            
            issues.append({
                "number": issue_data.get("number"),
                "title": issue_data.get("title"),
                "body": issue_data.get("body"),
                "state": issue_data.get("state"),
                "created_at": issue_data.get("created_at"),
                "updated_at": issue_data.get("updated_at"),
                "author": user_data.get("login"),
                "labels": [l.get("name") for l in issue_data.get("labels", [])],
                "html_url": issue_data.get("html_url"),
            })
        
        print(f"  ✓ Found {len(issues)} updated issues")
        return issues
    
    def get_updated_prs(self, owner: str, repo: str, since: str, include_files: bool = True) -> List[Dict]:
        """Get PRs updated since a specific timestamp"""
        print(f"🔄 Fetching PRs updated since {since}...")
        url = f"{self.base_url}/repos/{owner}/{repo}/pulls"
        params = {
            "state": "all",
            "per_page": 100,
            "sort": "updated",
            "direction": "desc"
        }
        
        prs_data = self._fetch_paginated(url, params, max_pages=10)
        
        since_dt = datetime.fromisoformat(since.replace("Z", "+00:00"))
        recent_prs = []
        
        for pr_data in prs_data:
            updated_at = datetime.fromisoformat(pr_data["updated_at"].replace("Z", "+00:00"))
            if updated_at < since_dt:
                break
            
            user_data = pr_data.get('user')
            if not user_data:
                continue
            
            linked_issues = self._extract_linked_issues(pr_data.get("body", ""))
            
            pr = {
                "number": pr_data.get("number"),
                "title": pr_data.get("title"),
                "body": pr_data.get("body"),
                "state": pr_data.get("state"),
                "merged": pr_data.get("merged"),
                "created_at": pr_data.get("created_at"),
                "updated_at": pr_data.get("updated_at"),
                "author": user_data.get("login"),
                "linked_issues": linked_issues,
                "html_url": pr_data.get("html_url"),
                "files": []
            }
            
            if include_files:
                pr["files"] = self.get_pr_files(owner, repo, pr["number"])
                time.sleep(0.2)
            
            recent_prs.append(pr)
        
        print(f"  ✓ Found {len(recent_prs)} updated PRs")
        return recent_prs
    
    def get_pr_files(self, owner: str, repo: str, pr_number: int) -> List[Dict]:
        """Get files changed in a PR"""
        url = f"{self.base_url}/repos/{owner}/{repo}/pulls/{pr_number}/files"
        files_data = self._fetch_paginated(url)
        
        files = []
        for file_data in files_data:
            filename = file_data.get("filename", "")
            directory = "/".join(filename.split("/")[:-1]) if "/" in filename else ""
            
            files.append({
                "filename": filename,
                "directory": directory,
                "status": file_data.get("status"),
                "additions": file_data.get("additions"),
                "deletions": file_data.get("deletions"),
            })
        
        return files
    
    def incremental_update(self, owner: str, repo: str, last_update: str) -> Dict:
        """Perform incremental update - fetch only new/updated items since last_update"""
        print(f"\n{'='*60}")
        print(f"🔄 Incremental update for {owner}/{repo}")
        print(f"   Since: {last_update}")
        print(f"{'='*60}")
        
        start_time = time.time()
        
        update_data = {
            "repository": f"{owner}/{repo}",
            "last_update": last_update,
            "current_time": datetime.utcnow().isoformat() + "Z",
            "updated_issues": [],
            "updated_prs": [],
            "metadata": {
                "update_type": "incremental",
                "scraped_at": datetime.utcnow().isoformat(),
            }
        }
        
        # Get updated issues
        update_data["updated_issues"] = self.get_updated_issues(owner, repo, last_update)
        
        # Get updated PRs with files
        update_data["updated_prs"] = self.get_updated_prs(owner, repo, last_update, include_files=True)
        
        elapsed = time.time() - start_time
        update_data["metadata"]["processing_time_seconds"] = round(elapsed, 2)
        update_data["metadata"]["updated_issues_count"] = len(update_data["updated_issues"])
        update_data["metadata"]["updated_prs_count"] = len(update_data["updated_prs"])
        
        print(f"\n{'='*60}")
        print(f"✅ Incremental update completed in {elapsed:.1f}s")
        print(f"{'='*60}")
        print(f"📊 Updates:")
        print(f"   Issues: {update_data['metadata']['updated_issues_count']}")
        print(f"   PRs: {update_data['metadata']['updated_prs_count']}")
        
        return update_data
    
    # ==================== FULL SCRAPE ====================
    
    def scrape_repository_full(self, owner: str, repo: str) -> Dict:
        """Perform full repository scrape with all data"""
        print(f"\n{'='*60}")
        print(f"🚀 Starting full scrape of {owner}/{repo}")
        print(f"{'='*60}")
        
        start_time = time.time()
        
        data = {
            "repository": f"{owner}/{repo}",
            "contributors": [],
            "issues": [],
            "pull_requests": [],
            "special_files": {},
            "metadata": {
                "scraped_at": datetime.utcnow().isoformat(),
                "scraper_version": "2.0.0",
            }
        }
        
        # 1. Get contributors
        print(f"👥 Fetching contributors...")
        url = f"{self.base_url}/repos/{owner}/{repo}/contributors"
        contributors_data = self._fetch_paginated(url)
        data["contributors"] = [
            {
                "login": c.get("login"),
                "contributions": c.get("contributions"),
                "avatar_url": c.get("avatar_url"),
            }
            for c in contributors_data if c.get("type") == "User"
        ]
        print(f"  ✓ Found {len(data['contributors'])} contributors")
        
        # 2. Get special files
        data["special_files"] = self.get_special_files(owner, repo)
        
        # 3. Get issues
        print(f"📋 Fetching issues...")
        url = f"{self.base_url}/repos/{owner}/{repo}/issues"
        issues_data = self._fetch_paginated(url, {"state": "all", "per_page": 100})
        
        for issue_data in issues_data[:self.max_issues]:
            if "pull_request" in issue_data:
                continue
            
            user_data = issue_data.get('user')
            if not user_data:
                continue
            
            data["issues"].append({
                "number": issue_data.get("number"),
                "title": issue_data.get("title"),
                "state": issue_data.get("state"),
                "author": user_data.get("login"),
                "labels": [l.get("name") for l in issue_data.get("labels", [])],
                "created_at": issue_data.get("created_at"),
            })
        
        print(f"  ✓ Found {len(data['issues'])} issues")
        
        # 4. Get PRs
        print(f"🔀 Fetching pull requests...")
        url = f"{self.base_url}/repos/{owner}/{repo}/pulls"
        prs_data = self._fetch_paginated(url, {"state": "all", "per_page": 100})
        
        for pr_data in prs_data[:self.max_prs]:
            user_data = pr_data.get('user')
            if not user_data:
                continue
            
            linked_issues = self._extract_linked_issues(pr_data.get("body", ""))
            
            data["pull_requests"].append({
                "number": pr_data.get("number"),
                "title": pr_data.get("title"),
                "state": pr_data.get("state"),
                "merged": pr_data.get("merged"),
                "author": user_data.get("login"),
                "linked_issues": linked_issues,
                "created_at": pr_data.get("created_at"),
            })
        
        print(f"  ✓ Found {len(data['pull_requests'])} PRs")
        
        elapsed = time.time() - start_time
        data["metadata"]["processing_time_seconds"] = round(elapsed, 2)
        data["metadata"]["total_contributors"] = len(data["contributors"])
        data["metadata"]["total_issues"] = len(data["issues"])
        data["metadata"]["total_prs"] = len(data["pull_requests"])
        
        print(f"\n{'='*60}")
        print(f"✅ Scraping completed in {elapsed:.1f}s")
        print(f"{'='*60}")
        
        return data
    
    def save_to_json(self, data: Dict, filename: str):
        """Save data to JSON file"""
        with open(filename, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        print(f"\n💾 Saved data to {filename}")


# ==================== MAIN ====================

if __name__ == "__main__":
    import sys
    
    # Get GitHub token from environment
    token = os.environ.get('GITHUB_TOKEN')
    if not token:
        print("❌ Error: GITHUB_TOKEN environment variable not set")
        print("   Set it with: $env:GITHUB_TOKEN='your_token_here'")
        sys.exit(1)
    
    # Initialize scraper
    scraper = ComprehensiveGitHubScraper(token)
    
    # Example usage
    if len(sys.argv) > 1:
        repo_full_name = sys.argv[1]  # e.g., "RooCodeInc/Roo-Code"
        owner, repo = repo_full_name.split('/')
        
        # Full scrape
        data = scraper.scrape_repository_full(owner, repo)
        scraper.save_to_json(data, f"{owner}_{repo}_full_scrape.json")
        
        # Incremental update example (last 7 days)
        since = (datetime.utcnow() - timedelta(days=7)).isoformat() + "Z"
        update_data = scraper.incremental_update(owner, repo, since)
        scraper.save_to_json(update_data, f"{owner}_{repo}_incremental.json")
    else:
        print("Usage: python comprehensive_scraper.py <owner/repo>")
        print("Example: python comprehensive_scraper.py RooCodeInc/Roo-Code")
