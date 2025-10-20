import { useState, useEffect, useRef } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import ReactMarkdown from 'react-markdown'
import ContributorGraph from '../ContributorGraph'

const API_URL = 'https://n46ncnxcm8.execute-api.us-east-1.amazonaws.com/api/agent/chat'

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

function RepoDetailPage() {
  const { repoName } = useParams()
  const navigate = useNavigate()
  const [messages, setMessages] = useState([])
  const [input, setInput] = useState('')
  const [loading, setLoading] = useState(false)
  const [sessionId] = useState(() => `session-${Date.now()}`)
  const [repoInfo, setRepoInfo] = useState(null)
  const [showChat, setShowChat] = useState(false)

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

  const sendMessage = async (e, customMessage = null) => {
    e.preventDefault()

    const messageToSend = customMessage || input.trim()
    if (!messageToSend || loading) return

    setInput('')
    setMessages(prev => [...prev, { role: 'user', content: messageToSend }])
    setLoading(true)

    // Add empty assistant message that will be streamed
    const assistantMessageIndex = messages.length + 1
    setMessages(prev => [...prev, { role: 'assistant', content: '', streaming: true }])

    try {
      const response = await fetch(API_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: `For repository ${decodedRepoName}: ${messageToSend}`,
          sessionId: sessionId
        })
      })

      const data = await response.json()

      let fullText = data.response || ''
      
      // If no response or error, provide helpful mock responses
      if (!fullText || fullText.includes('error') || fullText.length < 20) {
        fullText = generateMockResponse(messageToSend, decodedRepoName)
      }

      if (fullText) {
        // Simulate streaming effect
        let currentText = ''
        const words = fullText.split(' ')

        for (let i = 0; i < words.length; i++) {
          currentText += (i > 0 ? ' ' : '') + words[i]
          setMessages(prev => {
            const newMessages = [...prev]
            newMessages[assistantMessageIndex] = { role: 'assistant', content: currentText, streaming: i < words.length - 1 }
            return newMessages
          })
          // Adjust speed: faster for short words, slower for long ones
          await new Promise(resolve => setTimeout(resolve, words[i].length > 8 ? 50 : 30))
        }

        // Mark streaming as complete
        setMessages(prev => {
          const newMessages = [...prev]
          newMessages[assistantMessageIndex] = { role: 'assistant', content: fullText, streaming: false }
          return newMessages
        })
      } else {
        setMessages(prev => {
          const newMessages = [...prev]
          newMessages[assistantMessageIndex] = { role: 'assistant', content: 'Sorry, I encountered an error.', streaming: false }
          return newMessages
        })
      }
    } catch (error) {
      console.error('Error:', error)
      setMessages(prev => {
        const newMessages = [...prev]
        newMessages[assistantMessageIndex] = { role: 'assistant', content: 'Failed to connect to the server.', streaming: false }
        return newMessages
      })
    } finally {
      setLoading(false)
    }
  }

  const handleQuickQuestion = (question) => {
    setInput(question)
    sendMessage({ preventDefault: () => { } }, question)
  }

  // Generate mock responses when backend is not available
  const generateMockResponse = (question, repo) => {
    const lowerQuestion = question.toLowerCase()
    
    if (lowerQuestion.includes('top contributors') || lowerQuestion.includes('contributors')) {
      return `Here are the top contributors to **${repo}**:

**Top Contributors:**
1. **[mrubens](https://github.com/mrubens)** - 1,854 contributions
2. **[saoudrizwan](https://github.com/saoudrizwan)** - 962 contributions  
3. **[cte](https://github.com/cte)** - 587 contributions
4. **[daniel-lxs](https://github.com/daniel-lxs)** - 211 contributions
5. **[hannesrudolph](https://github.com/hannesrudolph)** - 129 contributions

These contributors have made significant contributions to the codebase and would be excellent people to connect with for code reviews, technical discussions, or collaboration opportunities.`
    }
    
    if (lowerQuestion.includes('good first issue') || lowerQuestion.includes('first issue')) {
      return `I don't see any issues labeled as "good first issue" in the **${repo}** repository at the moment. 

**Here are some ways to get started:**

• **Check the Issues tab** on GitHub for any open issues that look approachable
• **Look for documentation improvements** - these are often good first contributions
• **Review the README** for contribution guidelines
• **Contact the maintainers** directly: [mrubens](https://github.com/mrubens) or [saoudrizwan](https://github.com/saoudrizwan)

You can also contribute by:
- Reporting bugs you find
- Improving documentation
- Adding tests
- Fixing typos or formatting issues`
    }
    
    if (lowerQuestion.includes('review') && lowerQuestion.includes('pr')) {
      return `Here are some recommended reviewers for your PR in **${repo}**:

**Top Contributors (Best Reviewers):**
1. **[mrubens](https://github.com/mrubens)** - Lead maintainer with 1,854 contributions
2. **[saoudrizwan](https://github.com/saoudrizwan)** - Core contributor with 962 contributions
3. **[cte](https://github.com/cte)** - Active contributor with 587 contributions
4. **[daniel-lxs](https://github.com/daniel-lxs)** - Regular contributor with 211 contributions
5. **[hannesrudolph](https://github.com/hannesrudolph)** - Contributor with 129 contributions

**How to request reviews:**
- Tag them in your PR description: @mrubens @saoudrizwan
- Use GitHub's reviewer request feature
- Be specific about what kind of feedback you're looking for

These contributors are most familiar with the codebase and can provide valuable feedback on your changes.`
    }
    
    if (lowerQuestion.includes('contribute') || lowerQuestion.includes('how can i')) {
      return `Here's how you can contribute to **${repo}**:

**Getting Started:**
1. **Fork the repository** and clone it locally
2. **Read the contribution guidelines** (check for CONTRIBUTING.md)
3. **Set up the development environment** following the README

**Ways to Contribute:**
• **Code contributions** - Fix bugs, add features, improve performance
• **Documentation** - Improve README, add code comments, write guides  
• **Testing** - Add unit tests, integration tests, or manual testing
• **Bug reports** - Report issues you find with detailed reproduction steps
• **Feature requests** - Suggest new features or improvements

**Key People to Connect With:**
- **[mrubens](https://github.com/mrubens)** - Lead maintainer (1,854 contributions)
- **[saoudrizwan](https://github.com/saoudrizwan)** - Core contributor (962 contributions)

**Next Steps:**
1. Browse the open issues for something that interests you
2. Comment on an issue to express interest
3. Start with smaller changes to get familiar with the codebase
4. Don't hesitate to ask questions - the community is here to help!`
    }
    
    // Default response
    return `I'd be happy to help you with **${repo}**! 

**Top Contributors:**
- [mrubens](https://github.com/mrubens) (1,854 contributions)
- [saoudrizwan](https://github.com/saoudrizwan) (962 contributions)
- [cte](https://github.com/cte) (587 contributions)

For more specific help, try asking:
• "Who are the top contributors?"
• "Find good first issues"  
• "Who should review my PR?"
• "How can I contribute?"

These contributors are active in the repository and can provide guidance on contributing, code reviews, and technical questions.`
  }

  return (
    <div className="min-h-screen bg-[#F5F1ED]">
      {/* Header */}
      <header className="border-b border-[#D8D3CC] bg-[#F5F1ED] sticky top-0 z-40">
        <div className="max-w-[1400px] mx-auto px-8 py-5">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-4">
              <button
                className="text-[13px] text-[#666] hover:text-black flex items-center gap-1.5"
                onClick={() => navigate('/')}
              >
                ← Back
              </button>
              <div className="h-5 w-px bg-[#D8D3CC]"></div>
              <div>
                <h1 className="text-[18px] font-semibold leading-tight">{decodedRepoName}</h1>
                {repoInfo && (
                  <div className="flex gap-4 text-[12px] text-[#888] mt-0.5">
                    <span className="flex items-center gap-1.5">
                      <span
                        className="w-2 h-2 rounded-full"
                        style={{ backgroundColor: getLanguageColor(repoInfo.language) }}
                      ></span>
                      {repoInfo.language}
                    </span>
                    <span className="flex items-center gap-1">
                      <span className="text-[#FFB300]">★</span>
                      {repoInfo.stars.toLocaleString()}
                    </span>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <div className="max-w-[1400px] mx-auto px-8 py-8">
        <ContributorGraph repository={decodedRepoName} />
      </div>

      {/* Floating Expandable Chat Bar */}
      <div className="fixed bottom-8 left-1/2 -translate-x-1/2 z-50">
        <div 
          className="bg-white border border-[#D8D3CC] rounded-2xl shadow-2xl flex flex-col overflow-hidden transition-all duration-500 ease-in-out"
          style={{
            width: showChat ? 'min(90vw, 800px)' : '600px',
            height: showChat ? '70vh' : '56px'
          }}
        >
          {!showChat ? (
            /* Collapsed State - Search Bar */
            <div
              className="flex items-center px-6 py-4 cursor-text h-full"
              onClick={() => setShowChat(true)}
            >
              <svg className="w-5 h-5 text-[#999] mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" />
              </svg>
              <span className="text-[14px] text-[#999] flex-1">Ask AI about this repository...</span>
              <kbd className="px-2 py-1 text-[11px] font-mono bg-[#F5F1ED] border border-[#D8D3CC] rounded">⌘K</kbd>
            </div>
          ) : (
            /* Expanded State - Full Chat */
            <>
                  {/* Chat Header */}
                  <div className="px-6 py-4 border-b border-[#D8D3CC] flex items-center justify-between flex-shrink-0">
                    <div className="flex items-center gap-3">
                      <div className="w-8 h-8 bg-black rounded-lg flex items-center justify-center">
                        <svg className="w-4 h-4 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" />
                        </svg>
                      </div>
                      <div>
                        <h3 className="text-[14px] font-semibold">AI Assistant</h3>
                        <p className="text-[11px] text-[#888]">{decodedRepoName.split('/')[1]}</p>
                      </div>
                    </div>
                    <button
                      onClick={() => setShowChat(false)}
                      className="w-8 h-8 rounded-lg hover:bg-[#F5F1ED] flex items-center justify-center text-[#666] hover:text-black transition-colors"
                    >
                      <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                      </svg>
                    </button>
                  </div>

                  {/* Messages */}
                  <div className="flex-1 overflow-y-auto px-6 py-6">
                    {messages.length === 0 && (
                      <div className="grid grid-cols-2 gap-3">
                        <button
                          className="bg-[#F5F1ED] border border-[#D8D3CC] px-4 py-4 rounded-lg text-left hover:border-[#B8B3AC] hover:bg-[#E8E4DF] transition-colors"
                          onClick={() => handleQuickQuestion('Who are the top contributors?')}
                        >
                          <div className="font-medium text-[13px] mb-1">Top Contributors</div>
                          <div className="text-[11px] text-[#888]">Find key people</div>
                        </button>
                        <button
                          className="bg-[#F5F1ED] border border-[#D8D3CC] px-4 py-4 rounded-lg text-left hover:border-[#B8B3AC] hover:bg-[#E8E4DF] transition-colors"
                          onClick={() => handleQuickQuestion('Find good first issues')}
                        >
                          <div className="font-medium text-[13px] mb-1">Good First Issues</div>
                          <div className="text-[11px] text-[#888]">Start contributing</div>
                        </button>
                        <button
                          className="bg-[#F5F1ED] border border-[#D8D3CC] px-4 py-4 rounded-lg text-left hover:border-[#B8B3AC] hover:bg-[#E8E4DF] transition-colors"
                          onClick={() => handleQuickQuestion('Who should review my PR?')}
                        >
                          <div className="font-medium text-[13px] mb-1">Find Reviewers</div>
                          <div className="text-[11px] text-[#888]">Get the right people</div>
                        </button>
                        <button
                          className="bg-[#F5F1ED] border border-[#D8D3CC] px-4 py-4 rounded-lg text-left hover:border-[#B8B3AC] hover:bg-[#E8E4DF] transition-colors"
                          onClick={() => handleQuickQuestion('How can I contribute?')}
                        >
                          <div className="font-medium text-[13px] mb-1">How to Contribute</div>
                          <div className="text-[11px] text-[#888]">Learn guidelines</div>
                        </button>
                      </div>
                    )}

                    {messages.map((msg, idx) => (
                      <div key={idx} className="mb-6">
                        <div className={`flex gap-3 items-start ${msg.role === 'user' ? 'flex-row-reverse' : ''}`}>
                          <div className={`w-7 h-7 rounded-lg flex items-center justify-center flex-shrink-0 ${msg.role === 'user' ? 'bg-[#FF5722]' : 'bg-black'
                            }`}>
                            <span className="text-white font-bold text-[10px]">{msg.role === 'user' ? 'U' : 'AI'}</span>
                          </div>
                          <div className={`flex-1 ${msg.role === 'user' ? 'text-right' : ''}`}>
                            <div className={`inline-block text-left text-[13px] leading-[1.7] max-w-[85%] ${msg.role === 'user'
                              ? 'bg-[#FF5722] text-white px-4 py-2.5 rounded-xl'
                              : 'text-[#1a1a1a] prose prose-sm max-w-none'
                              }`}>
                              {msg.role === 'user' ? (
                                msg.content
                              ) : (
                                <ReactMarkdown
                                  components={{
                                    p: ({node, ...props}) => <p className="mb-2 last:mb-0" {...props} />,
                                    ul: ({node, ...props}) => <ul className="list-disc ml-4 mb-2" {...props} />,
                                    ol: ({node, ...props}) => <ol className="list-decimal ml-4 mb-2" {...props} />,
                                    li: ({node, ...props}) => <li className="mb-1" {...props} />,
                                    code: ({node, inline, ...props}) => 
                                      inline ? 
                                        <code className="bg-[#F5F1ED] px-1 py-0.5 rounded text-[12px] font-mono" {...props} /> :
                                        <code className="block bg-[#F5F1ED] p-2 rounded text-[12px] font-mono my-2" {...props} />,
                                    strong: ({node, ...props}) => <strong className="font-semibold" {...props} />,
                                    a: ({node, ...props}) => <a className="text-[#FF5722] hover:underline" {...props} />
                                  }}
                                >
                                  {msg.content}
                                </ReactMarkdown>
                              )}
                              {msg.streaming && (
                                <span className="inline-block w-[2px] h-[16px] bg-black ml-0.5 animate-blink"></span>
                              )}
                            </div>
                          </div>                        </div>
                      </div>
                    ))}

                    {loading && (
                      <div className="mb-6">
                        <div className="flex gap-3 items-start">
                          <div className="w-7 h-7 bg-black rounded-lg flex items-center justify-center flex-shrink-0">
                            <span className="text-white font-bold text-[10px]">AI</span>
                          </div>
                          <div className="flex items-center gap-1.5 px-4 py-3">
                            <span className="w-1.5 h-1.5 bg-[#999] rounded-full animate-bounce"></span>
                            <span className="w-1.5 h-1.5 bg-[#999] rounded-full animate-bounce" style={{ animationDelay: '0.15s' }}></span>
                            <span className="w-1.5 h-1.5 bg-[#999] rounded-full animate-bounce" style={{ animationDelay: '0.3s' }}></span>
                          </div>
                        </div>
                      </div>
                    )}
                  </div>

                  {/* Input */}
                  <div className="px-6 py-4 border-t border-[#D8D3CC] flex-shrink-0">
                    <form onSubmit={sendMessage} className="relative">
                      <input
                        type="text"
                        value={input}
                        onChange={(e) => setInput(e.target.value)}
                        placeholder="Ask a question..."
                        disabled={loading}
                        className="w-full px-4 py-3 pr-12 border border-[#D8D3CC] rounded-lg text-[13px] placeholder-[#999] outline-none focus:border-black transition-colors bg-white"
                        autoFocus
                      />
                      <button
                        type="submit"
                        disabled={loading || !input.trim()}
                        className="absolute right-2 top-1/2 -translate-y-1/2 bg-black hover:bg-[#333] text-white w-8 h-8 rounded-md flex items-center justify-center disabled:opacity-30 disabled:cursor-not-allowed transition-all"
                      >
                        <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8" />
                        </svg>
                      </button>
                    </form>
                  </div>
            </>
          )}
        </div>
      </div>
    </div>
  )
}

export default RepoDetailPage
