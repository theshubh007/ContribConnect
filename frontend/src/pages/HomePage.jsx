import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import './HomePage.css'

const API_URL = 'https://n46ncnxcm8.execute-api.us-east-1.amazonaws.com'

function HomePage() {
  const [repositories, setRepositories] = useState([])
  const [filteredRepos, setFilteredRepos] = useState([])
  const [searchQuery, setSearchQuery] = useState('')
  const [loading, setLoading] = useState(true)
  const [showOnboardModal, setShowOnboardModal] = useState(false)
  const navigate = useNavigate()

  useEffect(() => {
    // Show mock data immediately for fast initial render
    setRepositories(getMockRepositories())
    setFilteredRepos(getMockRepositories())
    setLoading(false)

    // Then fetch real data in background
    fetchRepositories()
  }, [])

  useEffect(() => {
    if (searchQuery.trim() === '') {
      setFilteredRepos(repositories)
    } else {
      const query = searchQuery.toLowerCase()
      const filtered = repositories.filter(repo =>
        repo.full_name.toLowerCase().includes(query) ||
        repo.description?.toLowerCase().includes(query) ||
        repo.language?.toLowerCase().includes(query) ||
        repo.topics?.some(topic => topic.toLowerCase().includes(query))
      )
      setFilteredRepos(filtered)
    }
  }, [searchQuery, repositories])

  const fetchRepositories = async () => {
    try {
      // Fetch from repo-manager Lambda
      const response = await fetch(`${API_URL}/api/repos/list`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'list', enabledOnly: true })
      })

      const data = await response.json()

      if (data.success) {
        // Transform data to match UI needs
        const repos = data.repositories.map(repo => ({
          full_name: repo.repository,
          description: repo.description || 'No description available',
          language: repo.language || 'Unknown',
          stars: repo.stars || 0,
          topics: repo.topics || [],
          status: repo.ingestStatus
        }))
        setRepositories(repos)
        setFilteredRepos(repos)
      }
    } catch (error) {
      console.error('Error fetching repositories:', error)
      // Keep mock data if already showing
    }
  }

  const handleRepoClick = (repoFullName) => {
    navigate(`/repo/${encodeURIComponent(repoFullName)}`)
  }

  const handleOnboardClick = () => {
    setShowOnboardModal(true)
  }

  return (
    <div className="home-page">
      {/* Hero Section */}
      <header className="hero">
        <div className="hero-content">
          <h1>🤝 ContribConnect</h1>
          <p className="hero-subtitle">Discover open source projects and connect with expert contributors</p>

          {/* Search Bar */}
          <div className="search-container">
            <div className="search-box">
              <span className="search-icon">🔍</span>
              <input
                type="text"
                placeholder="Search repositories by name, language, or topic..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="search-input"
              />
              {searchQuery && (
                <button
                  className="clear-search"
                  onClick={() => setSearchQuery('')}
                >
                  ✕
                </button>
              )}
            </div>
          </div>

          {/* Stats */}
          <div className="hero-stats">
            <div className="stat">
              <span className="stat-value">{repositories.length}</span>
              <span className="stat-label">Repositories</span>
            </div>
            <div className="stat">
              <span className="stat-value">{repositories.reduce((sum, r) => sum + (r.stars || 0), 0).toLocaleString()}</span>
              <span className="stat-label">Total Stars</span>
            </div>
            <div className="stat">
              <span className="stat-value">{new Set(repositories.map(r => r.language)).size}</span>
              <span className="stat-label">Languages</span>
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="main-content">
        <div className="content-header">
          <h2>
            {searchQuery ? `Search Results (${filteredRepos.length})` : 'Featured Repositories'}
          </h2>
          <button className="onboard-btn" onClick={handleOnboardClick}>
            ➕ Onboard Your Repository
          </button>
        </div>

        {/* Repository Grid */}
        {loading ? (
          <div className="loading-state">
            <div className="spinner"></div>
            <p>Loading repositories...</p>
          </div>
        ) : filteredRepos.length === 0 ? (
          <div className="empty-state">
            <div className="empty-icon">🔍</div>
            <h3>No repositories found</h3>
            <p>Try a different search term or onboard a new repository</p>
            <button className="onboard-btn-large" onClick={handleOnboardClick}>
              ➕ Onboard Your Repository
            </button>
          </div>
        ) : (
          <div className="repo-grid">
            {filteredRepos.map((repo, index) => (
              <RepoCard
                key={index}
                repo={repo}
                onClick={() => handleRepoClick(repo.full_name)}
              />
            ))}
          </div>
        )}
      </main>

      {/* Onboard Modal */}
      {showOnboardModal && (
        <OnboardModal
          onClose={() => setShowOnboardModal(false)}
          onSuccess={fetchRepositories}
        />
      )}
    </div>
  )
}

function RepoCard({ repo, onClick }) {
  return (
    <div className="repo-card" onClick={onClick}>
      <div className="repo-header">
        <h3 className="repo-name">{repo.full_name}</h3>
        <div className="repo-stars">
          ⭐ {repo.stars.toLocaleString()}
        </div>
      </div>

      <p className="repo-description">{repo.description}</p>

      <div className="repo-footer">
        <div className="repo-language">
          <span className="language-dot" style={{ backgroundColor: getLanguageColor(repo.language) }}></span>
          {repo.language}
        </div>

        {repo.topics && repo.topics.length > 0 && (
          <div className="repo-topics">
            {repo.topics.slice(0, 3).map((topic, i) => (
              <span key={i} className="topic-tag">{topic}</span>
            ))}
          </div>
        )}
      </div>

      {repo.status && (
        <div className={`repo-status ${repo.status}`}>
          {repo.status === 'success' ? '✓ Ready' : '⏳ Processing'}
        </div>
      )}
    </div>
  )
}

function OnboardModal({ onClose, onSuccess }) {
  const [repoUrl, setRepoUrl] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState(false)

  const handleSubmit = async (e) => {
    e.preventDefault()
    setError('')
    setLoading(true)

    try {
      // Parse GitHub URL
      const match = repoUrl.match(/github\.com\/([^\/]+)\/([^\/]+)/)
      if (!match) {
        setError('Invalid GitHub URL. Format: https://github.com/owner/repo')
        setLoading(false)
        return
      }

      const [, owner, repo] = match
      const cleanRepo = repo.replace(/\.git$/, '')

      // Add repository
      const addResponse = await fetch(`${API_URL}/api/repos/add`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          action: 'add',
          owner,
          repo: cleanRepo,
          enabled: true
        })
      })

      const addData = await addResponse.json()

      if (!addData.success) {
        setError(addData.error || 'Failed to add repository')
        setLoading(false)
        return
      }

      // Trigger scraping
      const scrapeResponse = await fetch(`${API_URL}/api/scraper`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ owner, repo: cleanRepo })
      })

      const scrapeData = await scrapeResponse.json()

      if (scrapeData.success || scrapeData.status === 'processing') {
        setSuccess(true)
        setTimeout(() => {
          onSuccess()
          onClose()
        }, 2000)
      } else {
        setError('Repository added but scraping failed. It will be processed in the next scheduled run.')
        setTimeout(() => {
          onSuccess()
          onClose()
        }, 3000)
      }
    } catch (err) {
      setError('Failed to onboard repository. Please try again.')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-content" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <h2>🚀 Onboard Your Repository</h2>
          <button className="modal-close" onClick={onClose}>✕</button>
        </div>

        {success ? (
          <div className="success-message">
            <div className="success-icon">✓</div>
            <h3>Repository Onboarded!</h3>
            <p>Your repository is being processed and will appear in the list shortly.</p>
          </div>
        ) : (
          <form onSubmit={handleSubmit}>
            <div className="form-group">
              <label>GitHub Repository URL</label>
              <input
                type="text"
                placeholder="https://github.com/owner/repository"
                value={repoUrl}
                onChange={(e) => setRepoUrl(e.target.value)}
                required
                disabled={loading}
              />
              <small>Enter the full GitHub URL of your open source repository</small>
            </div>

            {error && (
              <div className="error-message">
                ⚠️ {error}
              </div>
            )}

            <div className="modal-actions">
              <button type="button" onClick={onClose} disabled={loading}>
                Cancel
              </button>
              <button type="submit" className="primary" disabled={loading}>
                {loading ? 'Processing...' : 'Onboard Repository'}
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  )
}

function getLanguageColor(language) {
  const colors = {
    JavaScript: '#f1e05a',
    TypeScript: '#2b7489',
    Python: '#3572A5',
    Java: '#b07219',
    Go: '#00ADD8',
    Rust: '#dea584',
    Ruby: '#701516',
    PHP: '#4F5D95',
    C: '#555555',
    'C++': '#f34b7d',
    'C#': '#178600',
    Swift: '#ffac45',
    Kotlin: '#F18E33',
    Dart: '#00B4AB'
  }
  return colors[language] || '#8b949e'
}

function getMockRepositories() {
  return [
    {
      full_name: 'RooCodeInc/Roo-Code',
      description: 'AI-powered code assistant for developers',
      language: 'TypeScript',
      stars: 1234,
      topics: ['ai', 'code-assistant', 'vscode', 'typescript'],
      status: 'success'
    }
  ]
}

export default HomePage
