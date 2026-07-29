import { useState } from 'react'
import { sum } from './utils/sum'

function App() {
  const [count, setCount] = useState(0)

  return (
    <div>
      <h1>vite-vitest-yarn fixture</h1>
      <button onClick={() => setCount((c) => sum(c, 1))}>count is {count}</button>
    </div>
  )
}

export default App
