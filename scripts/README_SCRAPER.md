# Comprehensive GitHub Scraper

This standalone Python script provides advanced GitHub scraping capabilities beyond what the Lambda function can do.

## Features

✅ **Incremental Updates** - Fetch only data updated since a specific date  
✅ **Special Files** - Parse CODEOWNERS, CONTRIBUTING.md, package.json  
✅ **Linked Issues** - Extract issue references from PR bodies  
✅ **Full File Trees** - Get complete repository structure  
✅ **Comments** - Fetch issue and PR comments  
✅ **No Timeouts** - Run as long as needed locally  

## Setup

1. **Set GitHub Token**:
```powershell
$env:GITHUB_TOKEN = "your_github_token_here"
```

2. **Install Dependencies**:
```powershell
pip install requests boto3
```

3. **Configure AWS** (optional, for DynamoDB integration):
```powershell
aws configure
```

## Usage

### Full Repository Scrape

```powershell
python scripts/comprehensive_scraper.py RooCodeInc/Roo-Code
```

This will create two files:
- `RooCodeInc_Roo-Code_full_scrape.json` - Complete repository data
- `RooCodeInc_Roo-Code_incremental.json` - Updates from last 7 days

### Custom Usage

```python
from scripts.comprehensive_scraper import ComprehensiveGitHubScraper

# Initialize
scraper = ComprehensiveGitHubScraper(github_token="your_token")

# Full scrape
data = scraper.scrape_repository_full("RooCodeInc", "Roo-Code")
scraper.save_to_json(data, "output.json")

# Incremental update (since specific date)
since = "2025-10-01T00:00:00Z"
updates = scraper.incremental_update("RooCodeInc", "Roo-Code", since)
scraper.save_to_json(updates, "updates.json")

# Get special files only
special_files = scraper.get_special_files("RooCodeInc", "Roo-Code")
print(special_files["codeowners_parsed"])
```

## What Data is Collected

### Full Scrape
- **Contributors**: All contributors with contribution counts
- **Issues**: All issues with labels, authors, state
- **Pull Requests**: All PRs with linked issues, files changed
- **Special Files**: CODEOWNERS, CONTRIBUTING.md, package.json

### Incremental Update
- **Updated Issues**: Only issues modified since `last_update`
- **Updated PRs**: Only PRs modified since `last_update`
- **Files Changed**: Files touched in updated PRs

## Output Format

```json
{
  "repository": "RooCodeInc/Roo-Code",
  "contributors": [
    {
      "login": "username",
      "contributions": 123,
      "avatar_url": "https://..."
    }
  ],
  "issues": [...],
  "pull_requests": [
    {
      "number": 42,
      "title": "Fix bug",
      "linked_issues": [15, 23],
      "files": [...]
    }
  ],
  "special_files": {
    "codeowners_parsed": {
      "*.ts": ["user1", "user2"]
    },
    "package_json": {...}
  },
  "metadata": {
    "scraped_at": "2025-10-19T...",
    "total_contributors": 47,
    "processing_time_seconds": 45.2
  }
}
```

## Advantages Over Lambda

| Feature | Lambda | Standalone Script |
|---------|--------|-------------------|
| Timeout | 15 minutes | Unlimited |
| Memory | 512 MB | System memory |
| Rate Limits | Must handle carefully | Can wait indefinitely |
| Special Files | ❌ | ✅ |
| Incremental Updates | ❌ | ✅ |
| Linked Issues | ❌ | ✅ |
| Local Testing | ❌ | ✅ |

## Next Steps

1. **Deploy the Lambda bug fix** (for basic ingestion)
2. **Run this script** for comprehensive data collection
3. **Import the JSON** into your system as needed

## Troubleshooting

**Rate Limit Errors**:
- The script automatically handles rate limits
- With authentication: 5,000 requests/hour
- Without: Only 60 requests/hour

**Missing Data**:
- Check that your GitHub token has the right permissions
- Ensure the repository is public or you have access

**AWS Errors**:
- Make sure AWS credentials are configured
- Check that DynamoDB tables exist
