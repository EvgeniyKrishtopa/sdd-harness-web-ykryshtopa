import { sum } from '../utils/sum'

export default function Home() {
  return (
    <main>
      <h1>next-jest-pnpm fixture</h1>
      <p>2 + 3 = {sum(2, 3)}</p>
    </main>
  )
}
