import { useEffect, useRef, useState } from 'react'
import { Markdown } from './Markdown'
import { Button, Callout, Notice, Pulse, Surface } from '../ui'
import { send } from '../lib/bridge'
import type { Msg, Suggestion } from '../lib/types'

function Answer({ text }: { text: string }) {
  return (
    <Surface level="card">
      <div className="px-3 py-2.5">
        <Markdown text={text} />
      </div>
    </Surface>
  )
}

function Bubble({ message }: { message: Msg }) {
  if (message.role !== 'user') return <Answer text={message.text} />

  return (
    <div className="flex justify-end">
      <div className="selectable max-w-[var(--bubble-max)] whitespace-pre-wrap break-words rounded-lg bg-accent px-3 py-2 font-medium text-accent-fg">
        {message.text}
      </div>
    </div>
  )
}

function Working({ tool }: { tool: string | null }) {
  const [seconds, setSeconds] = useState(0)

  // A bare "Thinking" gives no way to tell a slow answer from a hung one.
  useEffect(() => {
    const timer = setInterval(() => setSeconds((s) => s + 1), 1000)
    return () => clearInterval(timer)
  }, [])

  return (
    <div className="flex items-center gap-2 px-1 py-0.5 text-sm text-muted">
      <Pulse />
      <span>{tool ? `Reading — ${tool}` : 'Thinking'}</span>
      {seconds > 2 && <span className="tabular-nums text-faint">{seconds}s</span>}
    </div>
  )
}

export function MessageList({
  messages,
  streaming,
  busy,
  tool,
  error,
  errorCode,
  agentFound,
  agentTitle,
  suggestion,
  onDismissSuggestion,
}: {
  messages: Msg[]
  streaming: string
  busy: boolean
  tool: string | null
  error: string
  errorCode: string
  agentFound: boolean
  agentTitle: string
  suggestion: Suggestion | null
  onDismissSuggestion: () => void
}) {
  const bottom = useRef<HTMLDivElement>(null)

  // Follow the answer as it streams in.
  useEffect(() => {
    bottom.current?.scrollIntoView({ block: 'end' })
  }, [messages.length, streaming, busy, error])

  const empty = messages.length === 0 && !streaming && !busy

  return (
    <div className="min-h-0 flex-1 space-y-2.5 overflow-y-auto px-3 py-3">
      {!agentFound && (
        <Notice tone="danger">
          {agentTitle} was not found. Install it, or set the path in Settings. Companion drives the
          CLI you already signed in to, so there is no API key to add.
        </Notice>
      )}

      {empty && agentFound && (
        <p className="px-1 py-6 text-sm leading-relaxed text-muted">
          Ask about the code in this repo. Answers stay on your screen and never reach a shared one.
        </p>
      )}

      {messages.map((message) => (
        <Bubble key={message.id} message={message} />
      ))}

      {suggestion && (
        <Callout
          title="Noticed"
          action={
            <Button variant="ghost" size="xs" tight onClick={onDismissSuggestion}>
              Dismiss
            </Button>
          }
        >
          <Markdown text={suggestion.text} />
        </Callout>
      )}

      {streaming && <Answer text={streaming} />}
      {busy && !streaming && <Working tool={tool} />}

      {error && (
        <Notice tone="danger">
          <p>{error}</p>
          {/* Signing in only happens in the CLI's interactive session, so the
              button opens a terminal there rather than pretending to do it. */}
          {errorCode === 'expiredLogin' && (
            <div className="mt-2">
              <Button size="sm" onClick={() => send({ type: 'signIn' })}>
                Open terminal to sign in
              </Button>
            </div>
          )}
        </Notice>
      )}

      <div ref={bottom} />
    </div>
  )
}
