import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'

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
        body: JSON.stringify({ action: 'list', enabledOnly: false })
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
        console.log(`Loaded ${repos.length} repositories from backend`)
      } else {
        console.error('Failed to fetch repositories:', data.error)
        // Fallback to mock data
        setRepositories(getMockRepositories())
        setFilteredRepos(getMockRepositories())
      }
    } catch (error) {
      console.error('Error fetching repositories:', error)
      // Fallback to mock data
      setRepositories(getMockRepositories())
      setFilteredRepos(getMockRepositories())
    }
  }

  const handleRepoClick = (repoFullName) => {
    navigate(`/repo/${encodeURIComponent(repoFullName)}`)
  }

  const handleOnboardClick = () => {
    setShowOnboardModal(true)
  }

  return (
    <div className="min-h-screen bg-[#F5F1ED]">
      {/* Header */}
      <header className="border-b border-[#D8D3CC] bg-[#F5F1ED] sticky top-0 z-50">
        <div className="max-w-[1400px] mx-auto px-8 py-5 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-7 h-7 bg-black rounded-sm flex items-center justify-center">
              <span className="text-white font-bold text-xs">CC</span>
            </div>
            <span className="font-semibold text-[15px] tracking-tight">ContribConnect</span>
          </div>
          <div className="flex items-center gap-4">
            <div className="relative">
              <input
                type="text"
                placeholder="Search..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-[280px] px-4 py-2 pr-10 border border-[#D8D3CC] rounded-md bg-white text-[13px] placeholder-[#999] focus:outline-none focus:border-[#FF5722]"
              />
              {searchQuery ? (
                <button
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-[#999] hover:text-[#333]"
                  onClick={() => setSearchQuery('')}
                >
                  ✕
                </button>
              ) : (
                <span className="absolute right-3 top-1/2 -translate-y-1/2 text-[#999] text-[11px] font-mono">⌘K</span>
              )}
            </div>
            <button 
              className="bg-[#FF5722] hover:bg-[#E64A19] text-white px-5 py-2 rounded-md text-[13px] font-medium"
              onClick={handleOnboardClick}
            >
              Add Repository
            </button>
          </div>
        </div>
      </header>

      {/* Hero Section */}
      <section className="max-w-[1400px] mx-auto px-8 pt-16 pb-12">
        <div className="max-w-[720px]">
          <h1 className="text-[48px] leading-[1.1] font-bold mb-6 tracking-[-0.02em]">
            Find the right contributors<br />
            for your open source project.
          </h1>
          <p className="text-[16px] leading-[1.7] text-[#666] mb-8 max-w-[560px]">
            Discover expert maintainers and contributors. Get insights on who to ask for code reviews, 
            technical guidance, and collaboration opportunities.
          </p>
          
          {/* Stats */}
          <div className="flex gap-12">
            <div>
              <div className="text-[28px] font-bold leading-none mb-1.5">{repositories.length}</div>
              <div className="text-[12px] text-[#888] uppercase tracking-wide">Repositories</div>
            </div>
            <div>
              <div className="text-[28px] font-bold leading-none mb-1.5">{repositories.reduce((sum, r) => sum + (r.stars || 0), 0).toLocaleString()}</div>
              <div className="text-[12px] text-[#888] uppercase tracking-wide">Total Stars</div>
            </div>
            <div>
              <div className="text-[28px] font-bold leading-none mb-1.5">{new Set(repositories.map(r => r.language)).size}</div>
              <div className="text-[12px] text-[#888] uppercase tracking-wide">Languages</div>
            </div>
          </div>
        </div>
      </section>

      {/* Main Content */}
      <main className="max-w-[1400px] mx-auto px-8 pb-24">
        <div className="flex justify-between items-baseline mb-6">
          <div>
            <h2 className="text-[20px] font-semibold mb-1">
              {searchQuery ? 'Search Results' : 'Repositories'}
            </h2>
            <p className="text-[13px] text-[#888]">
              {searchQuery ? `${filteredRepos.length} results found` : `Browse ${filteredRepos.length} indexed repositories`}
            </p>
          </div>
        </div>

        {/* Repository Grid */}
        {loading ? (
          <div className="flex flex-col items-center justify-center py-32">
            <div className="w-9 h-9 border-2 border-[#D8D3CC] border-t-black rounded-full animate-spin mb-4"></div>
            <p className="text-[#888] text-[13px]">Loading repositories...</p>
          </div>
        ) : filteredRepos.length === 0 ? (
          <div className="text-center py-32">
            <div className="text-5xl mb-5">🔍</div>
            <h3 className="text-[22px] font-semibold mb-2">No repositories found</h3>
            <p className="text-[#888] text-[14px] mb-7">Try a different search term or add a new repository</p>
            <button 
              className="bg-[#FF5722] hover:bg-[#E64A19] text-white px-6 py-3 rounded-md text-[13px] font-medium"
              onClick={handleOnboardClick}
            >
              Add Repository
            </button>
          </div>
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
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
    <div 
      className="bg-white border border-[#D8D3CC] rounded-lg p-6 cursor-pointer hover:border-[#B8B3AC] hover:shadow-sm group transition-all"
      onClick={onClick}
    >
      {/* Repo name */}
      <div className="flex items-start justify-between mb-3">
        <h3 className="font-semibold text-[16px] leading-tight group-hover:text-[#FF5722] flex-1 pr-2">
          {repo.full_name}
        </h3>
        {repo.status && (
          <div className={`text-[10px] px-2 py-1 rounded font-medium flex-shrink-0 ${
            repo.status === 'success' 
              ? 'bg-[#E8F5E9] text-[#2E7D32]' 
              : 'bg-[#FFF3E0] text-[#E65100]'
          }`}>
            {repo.status === 'success' ? '✓' : '⏳'}
          </div>
        )}
      </div>

      {/* Description */}
      <p className="text-[13px] text-[#666] leading-[1.6] mb-5 line-clamp-2 min-h-[2.6rem]">
        {repo.description}
      </p>

      {/* Meta info */}
      <div className="flex items-center gap-4 text-[12px] text-[#888] mb-3">
        <div className="flex items-center gap-1.5">
          <span 
            className="w-2.5 h-2.5 rounded-full" 
            style={{ backgroundColor: getLanguageColor(repo.language) }}
          ></span>
          <span>{repo.language}</span>
        </div>
        <div className="flex items-center gap-1.5">
          <span className="text-[#FFB300]">★</span>
          <span className="font-medium">{repo.stars.toLocaleString()}</span>
        </div>
      </div>

      {/* Topics */}
      {repo.topics && repo.topics.length > 0 && (
        <div className="flex gap-1.5 flex-wrap">
          {repo.topics.slice(0, 3).map((topic, i) => (
            <span key={i} className="text-[11px] px-2.5 py-1 bg-[#E8E4DF] text-[#555] rounded-full">
              {topic}
            </span>
          ))}
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

      console.log('Repository added successfully:', addData)

      // Repository added successfully, trigger ingestion via Lambda
      try {
        const ingestResponse = await fetch('https://n46ncnxcm8.execute-api.us-east-1.amazonaws.com/api/agent/chat', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            message: `Please ingest the repository ${owner}/${cleanRepo} for analysis`,
            sessionId: `ingest-${Date.now()}`
          })
        })
        
        if (ingestResponse.ok) {
          setSuccess(true)
          setTimeout(() => {
            onSuccess()
            onClose()
          }, 2000)
        } else {
          setSuccess(true) // Still show success since repo was added
          setTimeout(() => {
            onSuccess()
            onClose()
          }, 2000)
        }
      } catch (ingestError) {
        console.log('Ingestion trigger failed, but repository was added successfully')
        setSuccess(true)
        setTimeout(() => {
          onSuccess()
          onClose()
        }, 2000)
      }
    } catch (err) {
      setError('Failed to onboard repository. Please try again.')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="fixed inset-0 bg-black/30 flex items-center justify-center z-50 p-5" onClick={onClose}>
      <div className="bg-[#F5F1ED] border border-[#D8D3CC] rounded-lg max-w-[520px] w-full shadow-2xl" onClick={(e) => e.stopPropagation()}>
        <div className="flex justify-between items-center px-7 py-6 border-b border-[#D8D3CC]">
          <h2 className="text-[17px] font-semibold">Add Repository</h2>
          <button 
            className="w-7 h-7 rounded-sm hover:bg-[#E8E4DF] flex items-center justify-center text-[#888] hover:text-black text-lg"
            onClick={onClose}
          >
            ✕
          </button>
        </div>

        {success ? (
          <div className="px-7 py-12 text-center">
            <div className="w-16 h-16 bg-[#E8F5E9] text-[#2E7D32] border border-[#A5D6A7] rounded-lg flex items-center justify-center text-3xl mx-auto mb-5">
              ✓
            </div>
            <h3 className="text-[17px] font-semibold mb-2">Repository Added!</h3>
            <p className="text-[13px] text-[#666] leading-relaxed">Your repository is being processed and will appear in the list shortly.</p>
          </div>
        ) : (
          <form onSubmit={handleSubmit} className="px-7 py-6">
            <div className="mb-6">
              <label className="block mb-2.5 text-[13px] font-medium">GitHub Repository URL</label>
              <input
                type="text"
                placeholder="https://github.com/owner/repository"
                value={repoUrl}
                onChange={(e) => setRepoUrl(e.target.value)}
                required
                disabled={loading}
                className="w-full px-4 py-3 border border-[#D8D3CC] rounded-md bg-white text-[14px] placeholder-[#999] focus:outline-none focus:border-[#FF5722] disabled:bg-[#E8E4DF] disabled:text-[#888]"
              />
              <small className="block mt-2 text-[12px] text-[#888] leading-relaxed">Enter the full GitHub URL of your open source repository</small>
            </div>

            {error && (
              <div className="bg-[#FFEBEE] border border-[#FFCDD2] text-[#C62828] px-4 py-3 rounded-md text-[13px] mb-5 leading-relaxed">
                {error}
              </div>
            )}

            <div className="flex gap-3 justify-end">
              <button 
                type="button" 
                onClick={onClose} 
                disabled={loading}
                className="px-5 py-2.5 bg-white border border-[#D8D3CC] text-[#333] rounded-md text-[13px] font-medium hover:bg-[#E8E4DF] disabled:opacity-50"
              >
                Cancel
              </button>
              <button 
                type="submit" 
                disabled={loading}
                className="px-5 py-2.5 bg-[#FF5722] hover:bg-[#E64A19] text-white rounded-md text-[13px] font-medium disabled:opacity-50"
              >
                {loading ? 'Processing...' : 'Add Repository'}
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
