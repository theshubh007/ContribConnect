import { useState, useEffect } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import ContributorGraph from '../ContributorGraph'
import './RepoDetailPage.css'

const API_URL = 'https://n46ncnxcm8.execute-api.us-east-1.amazonaws.com/api/agent/chat'

function RepoDetailPage() {
  const { repoName } = useParams()
  const navigate = useNavigate()
  const [messages, setMessages] = useState([])
  const [input, setInput] = useState('')
  const [loading, setLoading] = useState(false)
  const [sessionId] = useState(() => `session-${Date.now()}`)
  const [repoInfo, setRepoInfo] = useState(null)

  const decodedRepoName = decodeURIComponent(repoName)

  useEffect(() => {
    // Fetch repository info
    fetchRepoInfo()
  }, [repoName])

  const fetchRepoInfo = async () => {
    try {
      const [owner, repo] = decodedRepoName.split('/')
      // Mock data for now
      setRepoInfo({
        full_name: decodedRepoName,
        description: 'Repository description',
        stars: 1234,
        language: 'TypeScript'
      })
    } catch (error) {
      console.error('Error fetching repo info:', error)
    }
  }

  const sendMessage = async (e) => {
    e.preventDefault()
    if (!input.trim() || loading) return

    const userMessage = input.trim()
    setInput('')
    setMessages(prev => [...prev, { role: 'user', content: userMessage }])
    setLoading(true)

    try {
      const response = await fetch(API_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: `For repository ${decodedRepoName}: ${userMessage}`,
          sessionId: sessionId
        })
      })

      const data = await response.json()

      if (data.response) {
        setMessages(prev => [...prev, { role: 'assistant', content: data.response }])
      } else {
        setMessages(prev => [...prev, { role: 'assistant', content: 'Sorry, I encountered an error.' }])
      }
    } catch (error) {
      console.error('Error:', error)
      setMessages(prev => [...prev, { role: 'assistant', content: 'Failed to connect to the server.' }])
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="repo-detail-page">
      {/* Header */}
      <header className="repo-header">
        <button className="back-btn" onClick={() => navigate('/')}>
          ← Back to Repositories
        </button>
        <div className="repo-title">
          <h1>{decodedRepoName}</h1>
          {repoInfo && (
            <div className="repo-meta">
              <span className="meta-item">⭐ {repoInfo.stars.toLocaleString()} stars</span>
              <span className="meta-item">💻 {repoInfo.language}</span>
            </div>
          )}
        </div>
      </header>

      {/* Main Content */}
      <div className="repo-content">
        {/* Contributor Graph */}
        <section className="graph-section">
          <ContributorGraph repository={decodedRepoName} />
        </section>

        {/* Chat Assistant */}
        <section className="chat-section">
          <div className="chat-header">
            <h2>💬 AI Assistant</h2>
            <p>Ask about contributors, issues, or how to contribute</p>
          </div>

          <div className="chat-container">
            <div className="messages">
              {messages.length === 0 && (
                <div className="welcome">
                  <h3>👋 Hi! I'm your AI assistant</h3>
                  <p>I can help you with:</p>
                  <div className="examples">
                    <button
                      className="example-btn"
                      onClick={() => setInput('Who are the top contributors?')}
                    >
                      Who are the top contributors?
                    </button>
                    <button
                      className="example-btn"
                      onClick={() => setInput('Find good first issues')}
                    >
                      Find good first issues
                    </button>
                    <button
                      className="example-btn"
                      onClick={() => setInput('Who should review my PR?')}
                    >
                      Who should review my PR?
                    </button>
                    <button
                      className="example-btn"
                      onClick={() => setInput('How can I contribute?')}
                    >
                      How can I contribute?
                    </button>
                  </div>
                </div>
              )}

              {messages.map((msg, idx) => (
                <div key={idx} className={`message ${msg.role}`}>
                  <div className="message-avatar">
                    {msg.role === 'user' ? '👤' : '🤖'}
                  </div>
                  <div className="message-content">
                    {msg.content.split('\n').map((line, i) => (
                      <p key={i}>{line}</p>
                    ))}
                  </div>
                </div>
              ))}

              {loading && (
                <div className="message assistant">
                  <div className="message-avatar">🤖</div>
                  <div className="message-content loading">
                    <span className="dot"></span>
                    <span className="dot"></span>
                    <span className="dot"></span>
                  </div>
                </div>
              )}
            </div>

            <form className="input-form" onSubmit={sendMessage}>
              <input
                type="text"
                value={input}
                onChange={(e) => setInput(e.target.value)}
                placeholder="Ask me anything about this repository..."
                disabled={loading}
              />
              <button type="submit" disabled={loading || !input.trim()}>
                {loading ? '⏳' : '➤'}
              </button>
            </form>
          </div>
        </section>
      </div>
    </div>
  )
}

export default RepoDetailPage
