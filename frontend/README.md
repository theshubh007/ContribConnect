# ContribConnect Frontend

Modern React application for discovering and contributing to open source projects.

## Features

### 🏠 Homepage
- **Repository Discovery**: Browse all available open source repositories
- **Smart Search**: Search by repository name, language, or topics
- **Repository Cards**: View stars, language, topics, and status at a glance
- **Onboarding Flow**: Add new repositories with automatic scraping

### 📊 Repository Detail Page
- **Contributor Network Graph**: 
  - Hierarchical view showing organizational structure
  - Network view showing contributor connections
  - Interactive D3.js visualizations
- **AI Chat Assistant**:
  - Ask about contributors and experts
  - Find good first issues
  - Get PR review recommendations
  - Learn how to contribute

## Getting Started

### Install Dependencies

```bash
npm install
```

### Development

```bash
npm run dev
```

Visit http://localhost:5173

### Build for Production

```bash
npm run build
```

### Deploy to S3

```powershell
# From frontend directory
.\deploy.ps1
```

## Project Structure

```
frontend/
├── src/
│   ├── pages/
│   │   ├── HomePage.jsx          # Repository listing & search
│   │   ├── HomePage.css
│   │   ├── RepoDetailPage.jsx    # Contributor graph & chat
│   │   └── RepoDetailPage.css
│   ├── ContributorGraph.jsx      # D3.js graph visualization
│   ├── ContributorGraph.css
│   ├── App.jsx                   # Router setup
│   ├── App.css
│   └── main.jsx
├── deploy.ps1                    # Deployment script
└── package.json
```

## User Flows

### Flow 1: Browse and Explore
1. User lands on homepage
2. Sees list of available repositories
3. Can search/filter repositories
4. Clicks on a repository
5. Views contributor graph and can chat with AI

### Flow 2: Onboard New Repository
1. User searches for a repository
2. Repository not found in results
3. Clicks "Onboard Your Repository"
4. Enters GitHub URL
5. System scrapes and processes repository
6. Repository appears in list once ready

## API Integration

### Endpoints Used

- `POST /api/repos/list` - Get all repositories
- `POST /api/repos/add` - Add new repository
- `POST /api/scraper` - Trigger repository scraping
- `POST /api/agent/chat` - Chat with AI assistant

## Technologies

- **React 18** - UI framework
- **React Router 6** - Client-side routing
- **D3.js** - Data visualization
- **Vite** - Build tool
- **AWS S3** - Static hosting
- **CloudFront** - CDN

## Environment Variables

Create `.env` file:

```env
VITE_API_URL=https://your-api-gateway-url.amazonaws.com
```

## Deployment

The application is deployed to AWS S3 with CloudFront CDN:

1. Build creates optimized production bundle
2. Files are synced to S3 bucket
3. CloudFront cache is invalidated
4. Users access via CloudFront URL

## Browser Support

- Chrome (latest)
- Firefox (latest)
- Safari (latest)
- Edge (latest)

## Contributing

1. Create feature branch
2. Make changes
3. Test locally
4. Submit pull request

## License

MIT
