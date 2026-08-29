import { useEffect, useState } from 'react'
import { Header } from './components/Header'
import { MessageList } from './components/MessageList'
import { Composer } from './components/Composer'
import { SettingsSheet } from './components/SettingsSheet'
import { AwarenessBar } from './components/AwarenessBar'
import { ComposerControls } from './components/ComposerControls'
import { listen, send } from './lib/bridge'
import { useTypewriter } from './lib/useTypewriter'
import type { StatePayload, TranscriptLine } from './lib/types'

export function App() {
  const [state, setState] = useState<StatePayload | null>(null)
  const {
    shown: streaming,
    push: pushStreaming,
    reset: resetStreaming,
    flush: flushStreaming,
    setActive: setStreamingActive,
  } = useTypewriter()
  const [tool, setTool] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [errorCode, setErrorCode] = useState('')
  const [showHistory, setShowHistory] = useState(false)
  const [showSettings, setShowSettings] = useState(false)
  const [focusToken, setFocusToken] = useState(0)
  const [levels, setLevels] = useState({ me: 0, them: 0 })
  const [captureError, setCaptureError] = useState('')
  const [transcript, setTranscript] = useState<TranscriptLine[]>([])
  const [screen, setScreen] = useState('')
  const [screenshot, setScreenshot] = useState<'capturing' | 'ready' | 'failed' | 'none'>('none')
  // Which spoken line a reply was requested for. The tapped bubble's control
  // pulses until the run ends, so the wait has a visible anchor — the
  // "Thinking" row at the bottom says something is happening, not for whom.
  const [replyingTo, setReplyingTo] = useState<string | null>(null)

  useEffect(() => {
    const stop = listen((payload) => {
      switch (payload.type) {
        case 'state':
          setState(payload)
          setBusy(payload.busy)
          if (payload.listening.active) setCaptureError('')
          // The finished answer now lives in `messages`; keeping the streamed
          // copy too would show it twice.
          resetStreaming()
          setTool(null)
          break
        case 'delta':
          setError('')
          setErrorCode('')
          pushStreaming(payload.text)
          break
        case 'tool':
          setTool(payload.name)
          break
        case 'busy':
          setBusy(payload.busy)
          // Keeps the draw loop alive across the gaps between chunks.
          setStreamingActive(payload.busy)
          if (payload.busy) setError('')
          break
        case 'done':
          setBusy(false)
          setTool(null)
          // Every run ends in `done` — answer, error, cancel, or a missing
          // agent — so this is the one place the reply anchor can be cleared
          // without leaving it pulsing forever on a failed run.
          setReplyingTo(null)
          // Stop pacing the moment the run ends — waiting out the animation
          // after the answer is complete would just be a delay.
          flushStreaming()
          if (payload.isError && payload.message) {
            setError(payload.message)
            setErrorCode(payload.code ?? '')
          }
          break
        case 'focus':
          setFocusToken((token) => token + 1)
          break
        case 'levels':
          setLevels({ me: payload.me, them: payload.them })
          break
        case 'captureError':
          setCaptureError(payload.message)
          break
        case 'openSettings':
          setShowSettings(true)
          break
        case 'messages':
          // A line settling mid-call. Only the messages change, so the rest of
          // the state is left alone.
          setState((current) => (current ? { ...current, messages: payload.messages } : current))
          break
        case 'transcript':
          setTranscript(payload.entries)
          break
        case 'screen':
          setScreen([payload.app, payload.detail].filter(Boolean).join(' · '))
          break
        case 'screenshot':
          setScreenshot(payload.state)
          if (payload.state === 'failed' && payload.message) setCaptureError(payload.message)
          break
      }
    })

    send({ type: 'ready' })
    return stop
  }, [pushStreaming, resetStreaming, flushStreaming, setStreamingActive])

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
    return <div className="grid h-full place-items-center bg-well text-sm text-muted">Loading…</div>
  }

  return (
    <div className="relative flex h-full flex-col bg-well">
      <Header
        repository={state.repository}
        hasRepository={state.hasRepository}
        conversations={state.conversations}
        currentId={state.currentId}
        canExport={state.messages.length > 0}
        historyOpen={showHistory}
        settingsOpen={showSettings}
        onChat={() => {
          setShowSettings(false)
          setShowHistory(false)
        }}
        onHistoryOpenChange={setShowHistory}
        onSettings={() => setShowSettings((open) => !open)}
      />

      <AwarenessBar
        listening={state.listening}
        levels={levels}
        error={captureError}
        screen={screen}
        watching={state.watchingScreen}
        suggestionsEnabled={state.settings.suggestionsEnabled}
        onSuggestionsChange={(value) =>
          send({
            type: 'updateSettings',
            agent: state.settings.agent,
            agentPath: state.settings.agentPath,
            permission: state.settings.permission,
            systemPrompt: state.settings.systemPrompt,
            suggestionsEnabled: value,
          })
        }
      />

      {showSettings ? (
        <SettingsSheet
          settings={state.settings}
          watchingActive={state.watchingScreen}
          agent={state.agent}
          repository={state.repository}
          hasRepository={state.hasRepository}
          permissions={state.permissions}
          inputDevices={state.inputDevices}
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
            errorCode={errorCode}
            agentFound={state.agent.found}
            agentTitle={state.agent.title}
            transcript={transcript}
            replyingTo={replyingTo}
            onReplyPending={setReplyingTo}
          />
          <Composer
            busy={busy}
            disabled={!state.agent.found}
            focusToken={focusToken}
            controls={
              <ComposerControls
                settings={state.settings}
                agent={state.agent}
                repository={state.repository}
                listening={state.listening}
                permissions={state.permissions}
                screenshot={screenshot}
                onOpenPermissions={() => setShowSettings(true)}
              />
            }
          />
        </>
      )}
    </div>
  )
}
