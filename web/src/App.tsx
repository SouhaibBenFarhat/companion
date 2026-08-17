import { useEffect, useState } from 'react'
import { Header } from './components/Header'
import { MessageList } from './components/MessageList'
import { Composer } from './components/Composer'
import { HistoryMenu } from './components/HistoryMenu'
import { SettingsSheet } from './components/SettingsSheet'
import { listen, send } from './lib/bridge'
import type { StatePayload } from './lib/types'

export function App() {
  const [state, setState] = useState<StatePayload | null>(null)
  const [streaming, setStreaming] = useState('')
  const [tool, setTool] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [showHistory, setShowHistory] = useState(false)
  const [showSettings, setShowSettings] = useState(false)
  const [focusToken, setFocusToken] = useState(0)

  useEffect(() => {
    const stop = listen((payload) => {
      switch (payload.type) {
        case 'state':
          setState(payload)
          setBusy(payload.busy)
          // The finished answer now lives in `messages`; keeping the streamed
          // copy too would show it twice.
          setStreaming('')
          setTool(null)
          break
        case 'delta':
          setError('')
          setStreaming((text) => text + payload.text)
          break
        case 'tool':
          setTool(payload.name)
          break
        case 'busy':
          setBusy(payload.busy)
          if (payload.busy) setError('')
          break
        case 'done':
          setBusy(false)
          setTool(null)
          if (payload.isError && payload.message) setError(payload.message)
          break
        case 'focus':
          setFocusToken((token) => token + 1)
          break
      }
    })

    send({ type: 'ready' })
    return stop
  }, [])

  // Esc hides the panel from anywhere, including mid-answer.
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return
      if (showSettings) setShowSettings(false)
      else if (showHistory) setShowHistory(false)
      else send({ type: 'hide' })
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [showHistory, showSettings])

  if (!state) {
    return <div className="grid h-full place-items-center text-[12px] text-muted">Loading…</div>
  }

  return (
    <div className="relative flex h-full flex-col">
      <Header
        repository={state.repository}
        onHistory={() => setShowHistory((open) => !open)}
        onSettings={() => setShowSettings((open) => !open)}
      />

      {showSettings ? (
        <SettingsSheet
          settings={state.settings}
          agent={state.agent}
          repository={state.repository}
          onClose={() => setShowSettings(false)}
        />
      ) : (
        <>
          <MessageList
            messages={state.messages}
            streaming={streaming}
            busy={busy}
            tool={tool}
            error={error}
            agentFound={state.agent.found}
            agentTitle={state.agent.title}
          />
          <Composer busy={busy} disabled={!state.agent.found} focusToken={focusToken} />
        </>
      )}

      {showHistory && (
        <HistoryMenu
          conversations={state.conversations}
          currentId={state.currentId}
          onClose={() => setShowHistory(false)}
        />
      )}
    </div>
  )
}
