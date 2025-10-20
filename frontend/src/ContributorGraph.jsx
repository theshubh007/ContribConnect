import { useEffect, useRef, useState } from 'react'
import * as d3 from 'd3'

const API_URL = 'https://n46ncnxcm8.execute-api.us-east-1.amazonaws.com/api/agent/chat'

function ContributorGraph({ repository = 'RooCodeInc/Roo-Code' }) {
  const svgRef = useRef()
  const [graphData, setGraphData] = useState(null)
  const [loading, setLoading] = useState(false)
  const [sessionId] = useState(() => `graph-${Date.now()}`)
  const [viewMode, setViewMode] = useState('hierarchy') // 'hierarchy' or 'network'
  const [stats, setStats] = useState({ repos: 0, contributors: 0, date: '' })
  const [selectedContributor, setSelectedContributor] = useState(null)

  const fetchGraphData = async () => {
    setLoading(true)
    try {
      const response = await fetch(API_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: `Find all expert reviewers and contributors for ${repository}`,
          sessionId: sessionId
        })
      })

      const data = await response.json()

      // Parse response to extract contributor data
      // For demo, create mock data structure
      const mockData = generateMockGraphData(repository)
      setGraphData(mockData)
    } catch (error) {
      console.error('Error fetching graph data:', error)
      // Use mock data on error
      setGraphData(generateMockGraphData(repository))
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchGraphData()
  }, [repository])

  useEffect(() => {
    if (!graphData || !svgRef.current) return

    // Clear previous graph
    d3.select(svgRef.current).selectAll('*').remove()

    if (viewMode === 'hierarchy') {
      renderHierarchyView()
    } else {
      renderNetworkView()
    }

  }, [graphData, viewMode])

  const renderHierarchyView = () => {
    const width = 1000
    const height = 600
    const margin = { top: 40, right: 40, bottom: 40, left: 40 }

    const svg = d3.select(svgRef.current)
      .attr('width', width)
      .attr('height', height)
      .attr('viewBox', [0, 0, width, height])

    // Create hierarchy from data
    const hierarchy = d3.hierarchy(graphData.hierarchy)
    const treeLayout = d3.tree()
      .size([width - margin.left - margin.right, height - margin.top - margin.bottom])
      .separation((a, b) => (a.parent === b.parent ? 1 : 1.2))

    treeLayout(hierarchy)

    const g = svg.append('g')
      .attr('transform', `translate(${margin.left},${margin.top})`)

    // Draw links
    g.selectAll('.link')
      .data(hierarchy.links())
      .join('path')
      .attr('class', 'link')
      .attr('d', d3.linkVertical()
        .x(d => d.x)
        .y(d => d.y))
      .attr('fill', 'none')
      .attr('stroke', '#cbd5e0')
      .attr('stroke-width', 2)

    // Draw nodes
    const nodes = g.selectAll('.node')
      .data(hierarchy.descendants())
      .join('g')
      .attr('class', 'node')
      .attr('transform', d => `translate(${d.x},${d.y})`)

    // Node backgrounds
    nodes.append('rect')
      .attr('x', -60)
      .attr('y', -25)
      .attr('width', 120)
      .attr('height', 50)
      .attr('rx', 8)
      .attr('fill', d => {
        if (d.depth === 0) return '#667eea'
        if (d.data.type === 'maintainer') return '#f59e0b'
        return '#10b981'
      })
      .attr('stroke', '#fff')
      .attr('stroke-width', 2)
      .style('cursor', 'pointer')
      .on('mouseover', function () {
        d3.select(this).attr('stroke-width', 3)
      })
      .on('mouseout', function () {
        d3.select(this).attr('stroke-width', 2)
      })
      .on('click', (event, d) => {
        if (d.data.type !== 'repo') {
          setSelectedContributor(d.data)
        }
      })

    // Node labels (name)
    nodes.append('text')
      .attr('dy', -5)
      .attr('text-anchor', 'middle')
      .attr('font-size', '12px')
      .attr('font-weight', '600')
      .attr('fill', 'white')
      .text(d => d.data.name)

    // Node labels (contributions)
    nodes.append('text')
      .attr('dy', 10)
      .attr('text-anchor', 'middle')
      .attr('font-size', '10px')
      .attr('fill', 'rgba(255,255,255,0.8)')
      .text(d => d.data.contributions ? `${d.data.contributions} contributions` : '')

    // Add tooltips
    nodes.append('title')
      .text(d => `${d.data.name}\n${d.data.type || 'repository'}\n${d.data.contributions || 0} contributions`)
  }

  const renderNetworkView = () => {
    const width = 1000
    const height = 600

    const svg = d3.select(svgRef.current)
      .attr('width', width)
      .attr('height', height)
      .attr('viewBox', [0, 0, width, height])

    // Create force simulation
    const simulation = d3.forceSimulation(graphData.nodes)
      .force('link', d3.forceLink(graphData.links).id(d => d.id).distance(150))
      .force('charge', d3.forceManyBody().strength(-400))
      .force('center', d3.forceCenter(width / 2, height / 2))
      .force('collision', d3.forceCollide().radius(40))

    // Create links
    const link = svg.append('g')
      .selectAll('line')
      .data(graphData.links)
      .join('line')
      .attr('stroke', '#cbd5e0')
      .attr('stroke-opacity', 0.6)
      .attr('stroke-width', d => Math.sqrt(d.value) * 2)

    // Create nodes
    const node = svg.append('g')
      .selectAll('g')
      .data(graphData.nodes)
      .join('g')
      .call(drag(simulation))
      .style('cursor', 'pointer')

    // Add circles
    node.append('circle')
      .attr('r', d => d.type === 'repo' ? 25 : 18)
      .attr('fill', d => {
        if (d.type === 'repo') return '#667eea'
        if (d.type === 'maintainer') return '#f59e0b'
        return '#10b981'
      })
      .attr('stroke', '#fff')
      .attr('stroke-width', 3)
      .on('click', (event, d) => {
        if (d.type !== 'repo') {
          setSelectedContributor(d)
        }
      })

    // Add labels
    node.append('text')
      .text(d => d.name)
      .attr('x', 0)
      .attr('y', 35)
      .attr('text-anchor', 'middle')
      .attr('font-size', '11px')
      .attr('font-weight', '600')
      .attr('fill', '#333')

    // Add contribution count
    node.append('text')
      .text(d => d.contributions ? `${d.contributions}` : '')
      .attr('x', 0)
      .attr('y', 5)
      .attr('text-anchor', 'middle')
      .attr('font-size', '10px')
      .attr('font-weight', 'bold')
      .attr('fill', 'white')

    // Add tooltips
    node.append('title')
      .text(d => `${d.name}\n${d.contributions || 0} contributions`)

    // Update positions on simulation tick
    simulation.on('tick', () => {
      link
        .attr('x1', d => d.source.x)
        .attr('y1', d => d.source.y)
        .attr('x2', d => d.target.x)
        .attr('y2', d => d.target.y)

      node.attr('transform', d => `translate(${d.x},${d.y})`)
    })

    // Drag behavior
    function drag(simulation) {
      function dragstarted(event) {
        if (!event.active) simulation.alphaTarget(0.3).restart()
        event.subject.fx = event.subject.x
        event.subject.fy = event.subject.y
      }

      function dragged(event) {
        event.subject.fx = event.x
        event.subject.fy = event.y
      }

      function dragended(event) {
        if (!event.active) simulation.alphaTarget(0)
        event.subject.fx = null
        event.subject.fy = null
      }

      return d3.drag()
        .on('start', dragstarted)
        .on('drag', dragged)
        .on('end', dragended)
    }
  }

  // Get sorted contributors list
  const getContributorsList = () => {
    if (!graphData?.nodes) return []
    return graphData.nodes
      .filter(node => node.type !== 'repo')
      .sort((a, b) => (b.contributions || 0) - (a.contributions || 0))
  }

  return (
    <div className="space-y-6">
      {/* Stats Cards */}
      <div className="grid grid-cols-3 gap-4">
        <div className="bg-white border border-[#D8D3CC] rounded-lg px-5 py-4">
          <div className="text-[11px] text-[#888] mb-1.5 uppercase tracking-wide">Contributors</div>
          <div className="text-[28px] font-bold leading-none">{graphData?.nodes?.filter(n => n.type !== 'repo').length || 0}</div>
        </div>
        <div className="bg-white border border-[#D8D3CC] rounded-lg px-5 py-4">
          <div className="text-[11px] text-[#888] mb-1.5 uppercase tracking-wide">Maintainers</div>
          <div className="text-[28px] font-bold leading-none">{graphData?.nodes?.filter(n => n.type === 'maintainer').length || 0}</div>
        </div>
        <div className="bg-white border border-[#D8D3CC] rounded-lg px-5 py-4">
          <div className="text-[11px] text-[#888] mb-1.5 uppercase tracking-wide">Last Updated</div>
          <div className="text-[13px] font-semibold">{stats.date || 'May 4, 2025'}</div>
        </div>
      </div>

      {/* Two Column Layout: Graph on Left, Contributors on Right */}
      <div className="grid grid-cols-[1fr_400px] gap-6">
        {/* Network Visualization - Left Side */}
        <div className="bg-white border border-[#D8D3CC] rounded-lg overflow-hidden">
          <div className="px-6 py-5 border-b border-[#D8D3CC]">
            <div className="flex justify-between items-center mb-4">
              <div>
                <h3 className="text-[15px] font-semibold">Network Visualization</h3>
                <p className="text-[12px] text-[#888] mt-1">Explore contributor relationships</p>
              </div>
              <div className="flex gap-2">
                <button
                  className={`px-4 py-2 rounded-md text-[12px] font-medium transition-colors ${viewMode === 'hierarchy'
                    ? 'bg-black text-white'
                    : 'bg-[#F5F1ED] text-[#333] hover:bg-[#E8E4DF]'
                    }`}
                  onClick={() => setViewMode('hierarchy')}
                >
                  Hierarchy
                </button>
                <button
                  className={`px-4 py-2 rounded-md text-[12px] font-medium transition-colors ${viewMode === 'network'
                    ? 'bg-black text-white'
                    : 'bg-[#F5F1ED] text-[#333] hover:bg-[#E8E4DF]'
                    }`}
                  onClick={() => setViewMode('network')}
                >
                  Network
                </button>
              </div>
            </div>

            {/* Legend */}
            <div className="flex items-center gap-5 text-[12px]">
              <span className="text-[#888] font-medium">Legend:</span>
              <div className="flex items-center gap-2">
                <span className="w-3 h-3 rounded-full bg-[#667eea]"></span>
                <span className="text-[#555]">Repository</span>
              </div>
              <div className="flex items-center gap-2">
                <span className="w-3 h-3 rounded-full bg-[#f59e0b]"></span>
                <span className="text-[#555]">Maintainer</span>
              </div>
              <div className="flex items-center gap-2">
                <span className="w-3 h-3 rounded-full bg-[#10b981]"></span>
                <span className="text-[#555]">Contributor</span>
              </div>
            </div>
          </div>

          {loading ? (
            <div className="flex flex-col items-center justify-center h-[600px] bg-[#FAFAF8]">
              <div className="w-9 h-9 border-2 border-[#D8D3CC] border-t-black rounded-full animate-spin mb-4"></div>
              <p className="text-[13px] text-[#888]">Loading network...</p>
            </div>
          ) : (
            <div className="p-8 bg-[#FAFAF8]">
              <svg
                ref={svgRef}
                className="w-full h-[600px] bg-white rounded-lg border border-[#D8D3CC]"
              ></svg>
            </div>
          )}
        </div>

        {/* Contributors List - Right Side */}
        <div className="bg-white border border-[#D8D3CC] rounded-lg overflow-hidden h-fit">
          <div className="px-6 py-5 border-b border-[#D8D3CC]">
            <h3 className="text-[15px] font-semibold">Top Contributors</h3>
            <p className="text-[12px] text-[#888] mt-1">Key people who contribute to this repository</p>
          </div>
          <div className="divide-y divide-[#E8E4DF] max-h-[680px] overflow-y-auto">
            {loading ? (
              <div className="flex items-center justify-center py-12">
                <div className="w-8 h-8 border-2 border-[#D8D3CC] border-t-black rounded-full animate-spin"></div>
              </div>
            ) : (
              getContributorsList().slice(0, 8).map((contributor, idx) => (
                <div
                  key={idx}
                  className="px-6 py-4 hover:bg-[#FAFAF8] transition-colors cursor-pointer"
                  onClick={() => setSelectedContributor(contributor)}
                >
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-3">
                      <div className={`w-10 h-10 rounded-full flex items-center justify-center text-white font-semibold text-[13px] ${contributor.type === 'maintainer' ? 'bg-[#f59e0b]' : 'bg-[#10b981]'
                        }`}>
                        {contributor.name.substring(0, 2).toUpperCase()}
                      </div>
                      <div>
                        <div className="font-medium text-[14px]">{contributor.name}</div>
                        <div className="text-[12px] text-[#888] capitalize">{contributor.type}</div>
                      </div>
                    </div>
                    <div className="text-right">
                      <div className="font-semibold text-[14px]">{contributor.contributions}</div>
                      <div className="text-[11px] text-[#888]">contributions</div>
                    </div>
                  </div>
                </div>
              ))
            )}
          </div>
        </div>
      </div>

      {/* Contributor Detail Modal */}
      {selectedContributor && (
        <div
          className="fixed inset-0 bg-black/50 flex items-center justify-center z-[60] p-4"
          onClick={() => setSelectedContributor(null)}
        >
          <div
            className="bg-white rounded-2xl shadow-2xl max-w-md w-full overflow-hidden max-h-[85vh] overflow-y-auto"
            onClick={(e) => e.stopPropagation()}
          >
            {/* Modal Header */}
            <div className="relative h-32 bg-gradient-to-br from-[#667eea] to-[#764ba2] p-6">
              <button
                onClick={() => setSelectedContributor(null)}
                className="absolute top-4 right-4 w-8 h-8 rounded-full bg-white/20 hover:bg-white/30 flex items-center justify-center text-white transition-colors"
              >
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
              <div className="absolute -bottom-12 left-6">
                <div className={`w-24 h-24 rounded-full border-4 border-white flex items-center justify-center text-white font-bold text-2xl shadow-lg ${selectedContributor.type === 'maintainer' ? 'bg-[#f59e0b]' : 'bg-[#10b981]'
                  }`}>
                  {selectedContributor.name.substring(0, 2).toUpperCase()}
                </div>
              </div>
            </div>

            {/* Modal Body */}
            <div className="pt-16 px-6 pb-6">
              <div className="mb-6">
                <h2 className="text-2xl font-bold mb-1">{selectedContributor.name}</h2>
                <div className="flex items-center gap-2">
                  <span className={`px-3 py-1 rounded-full text-[11px] font-medium uppercase tracking-wide ${selectedContributor.type === 'maintainer'
                    ? 'bg-[#FFF3E0] text-[#f59e0b]'
                    : 'bg-[#E8F5E9] text-[#10b981]'
                    }`}>
                    {selectedContributor.type}
                  </span>
                  <span className="text-[13px] text-[#888]">
                    {selectedContributor.contributions} contributions
                  </span>
                </div>
              </div>

              {/* Details Grid */}
              <div className="space-y-4">
                <div className="flex items-start gap-3 p-4 bg-[#F5F1ED] rounded-lg">
                  <svg className="w-5 h-5 text-[#666] mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
                  </svg>
                  <div className="flex-1">
                    <div className="text-[11px] text-[#888] uppercase tracking-wide mb-1">GitHub Profile</div>
                    <a
                      href={`https://github.com/${selectedContributor.name}`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="text-[14px] text-[#667eea] hover:underline font-medium"
                    >
                      @{selectedContributor.name}
                    </a>
                  </div>
                </div>

                <div className="flex items-start gap-3 p-4 bg-[#F5F1ED] rounded-lg">
                  <svg className="w-5 h-5 text-[#666] mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
                  </svg>
                  <div className="flex-1">
                    <div className="text-[11px] text-[#888] uppercase tracking-wide mb-1">Email</div>
                    <div className="text-[14px] text-[#333]">
                      {selectedContributor.email || `${selectedContributor.name}@users.noreply.github.com`}
                    </div>
                  </div>
                </div>

                <div className="flex items-start gap-3 p-4 bg-[#F5F1ED] rounded-lg">
                  <svg className="w-5 h-5 text-[#666] mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
                  </svg>
                  <div className="flex-1">
                    <div className="text-[11px] text-[#888] uppercase tracking-wide mb-1">Activity</div>
                    <div className="text-[14px] text-[#333]">
                      {selectedContributor.contributions} total contributions
                    </div>
                  </div>
                </div>

                <div className="flex items-start gap-3 p-4 bg-[#F5F1ED] rounded-lg">
                  <svg className="w-5 h-5 text-[#666] mt-0.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" />
                  </svg>
                  <div className="flex-1">
                    <div className="text-[11px] text-[#888] uppercase tracking-wide mb-1">Expertise</div>
                    <div className="flex flex-wrap gap-2 mt-2">
                      {(selectedContributor.expertise || ['JavaScript', 'React', 'Node.js']).map((skill, idx) => (
                        <span key={idx} className="px-2 py-1 bg-white border border-[#D8D3CC] rounded text-[11px] text-[#555]">
                          {skill}
                        </span>
                      ))}
                    </div>
                  </div>
                </div>
              </div>

              {/* Action Buttons */}
              <div className="flex gap-3 mt-6">
                <a
                  href={`https://github.com/${selectedContributor.name}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex-1 bg-black hover:bg-[#333] text-white px-4 py-3 rounded-lg text-[13px] font-medium text-center transition-colors"
                >
                  View GitHub Profile
                </a>
                <button
                  onClick={() => setSelectedContributor(null)}
                  className="px-6 py-3 bg-[#F5F1ED] hover:bg-[#E8E4DF] text-[#333] rounded-lg text-[13px] font-medium transition-colors"
                >
                  Close
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

// Generate mock graph data for demonstration
function generateMockGraphData(repo) {
  const [org, repoName] = repo.split('/')

  // Network view data
  const nodes = [
    { id: 'repo', name: repoName, type: 'repo' },
    {
      id: 'user1',
      name: 'sebmarkbage',
      type: 'maintainer',
      contributions: 14,
      email: 'sebastian@react.dev',
      expertise: ['React', 'JavaScript', 'Compiler Design']
    },
    {
      id: 'user2',
      name: 'josephsavona',
      type: 'maintainer',
      contributions: 3,
      email: 'joe@react.dev',
      expertise: ['React', 'GraphQL', 'Relay']
    },
    {
      id: 'user3',
      name: 'eps1lon',
      type: 'contributor',
      contributions: 1,
      expertise: ['TypeScript', 'Testing', 'React']
    },
    {
      id: 'user4',
      name: 'gaearon',
      type: 'maintainer',
      contributions: 8,
      email: 'dan@react.dev',
      expertise: ['React', 'Redux', 'JavaScript']
    },
    {
      id: 'user5',
      name: 'sophiebits',
      type: 'contributor',
      contributions: 5,
      expertise: ['React', 'Performance', 'Web APIs']
    },
    {
      id: 'user6',
      name: 'acdlite',
      type: 'contributor',
      contributions: 6,
      expertise: ['React', 'Concurrent Mode', 'Hooks']
    },
    {
      id: 'user7',
      name: 'rickhanlonii',
      type: 'contributor',
      contributions: 4,
      expertise: ['React Native', 'Testing', 'DevTools']
    },
    {
      id: 'user8',
      name: 'kassens',
      type: 'contributor',
      contributions: 2,
      expertise: ['React', 'Build Tools', 'Infrastructure']
    },
  ]

  const links = [
    { source: 'user1', target: 'repo', value: 14 },
    { source: 'user2', target: 'repo', value: 3 },
    { source: 'user3', target: 'repo', value: 1 },
    { source: 'user4', target: 'repo', value: 8 },
    { source: 'user5', target: 'repo', value: 5 },
    { source: 'user6', target: 'repo', value: 6 },
    { source: 'user7', target: 'repo', value: 4 },
    { source: 'user8', target: 'repo', value: 2 },
    { source: 'user1', target: 'user2', value: 2 },
    { source: 'user1', target: 'user4', value: 3 },
    { source: 'user4', target: 'user5', value: 2 },
    { source: 'user5', target: 'user6', value: 1 },
  ]

  // Hierarchy view data
  const hierarchy = {
    name: repoName,
    type: 'repo',
    contributions: 0,
    children: [
      {
        name: 'sebmarkbage',
        type: 'maintainer',
        contributions: 14,
        email: 'sebastian@react.dev',
        expertise: ['React', 'JavaScript', 'Compiler Design'],
        children: [
          {
            name: 'josephsavona',
            type: 'contributor',
            contributions: 3,
            email: 'joe@react.dev',
            expertise: ['React', 'GraphQL', 'Relay']
          },
          {
            name: 'kassens',
            type: 'contributor',
            contributions: 2,
            expertise: ['React', 'Build Tools', 'Infrastructure']
          }
        ]
      },
      {
        name: 'gaearon',
        type: 'maintainer',
        contributions: 8,
        email: 'dan@react.dev',
        expertise: ['React', 'Redux', 'JavaScript'],
        children: [
          {
            name: 'sophiebits',
            type: 'contributor',
            contributions: 5,
            expertise: ['React', 'Performance', 'Web APIs']
          },
          {
            name: 'acdlite',
            type: 'contributor',
            contributions: 6,
            expertise: ['React', 'Concurrent Mode', 'Hooks']
          }
        ]
      },
      {
        name: 'rickhanlonii',
        type: 'maintainer',
        contributions: 4,
        expertise: ['React Native', 'Testing', 'DevTools'],
        children: [
          {
            name: 'eps1lon',
            type: 'contributor',
            contributions: 1,
            expertise: ['TypeScript', 'Testing', 'React']
          }
        ]
      }
    ]
  }

  return { nodes, links, hierarchy }
}

export default ContributorGraph
