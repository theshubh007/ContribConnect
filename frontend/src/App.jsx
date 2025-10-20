import { BrowserRouter as Router, Routes, Route } from 'react-router-dom'
import HomePage from './pages/HomePage'
import RepoDetailPage from './pages/RepoDetailPage'

function App() {
  return (
    <Router>
      <Routes>
        <Route path="/" element={<HomePage />} />
        <Route path="/repo/:repoName" element={<RepoDetailPage />} />
      </Routes>
    </Router>
  )
}

export default App
