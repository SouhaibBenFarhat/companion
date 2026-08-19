import { useEffect, useRef, useState } from 'react'
import { Markdown } from './Markdown'
import { Button, Notice, Pulse, Surface } from '../ui'
import { send } from '../lib/bridge'
import type { Msg, Suggestion } from '../lib/types'

function Answer({ text }: { text: string }) {
  return (
    <Surface level="card" className="px-3 py-2.5">
      <Markdown text={text} />
    </Surface>
  )
}

function Bubble({ message }: { message: Msg }) {
  if (message.role === 'user') {
    return (
      <div className="flex justify-end">
        <div className="selectable max-w-[85%] rounded-xl bg-accent px-3 py-2 font-medium break-words whitespace-pre-wrap text-accent-fg">
          {message.text}
        </div>
      </div>
    )
  }
  return <Answer text={message.text} />
}

function Working({ tool }: { tool: string | null }) {
  const [seconds, setSeconds] = useState(0)

  // A bare "Thinking" gives no way to tell a slow answer from a hung one.
  useEffect(() => {
    const timer = setInterval(() => setSeconds((s) => s + 1), 1000)
    return () => clearInterval(timer)
  }, [])

  return (
    <div className="flex items-center gap-2 px-1 py-0.5 text-[12px] text-muted">
      <Pulse />
      <span>{tool ? `Reading — ${tool}` : 'Thinking'}</span>
      {seconds > 2 && <span className="tabular-nums opacity-70">{seconds}s</span>}
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
        <p className="px-1 py-6 text-[12px] leading-relaxed text-muted">
          Ask about the code in this repo. Answers stay on your screen and never reach a shared one.
        </p>
      )}

      {messages.map((message) => (
        <Bubble key={message.id} message={message} />
      ))}

      {/* Marked apart from answers you asked for. Something that arrived
          unprompted has to be visibly different, or it reads as a reply to a
          question you never asked. */}
      {suggestion && (
        <Surface level="card" className="border-l-2 border-accent px-3 py-2.5">
          <div className="mb-1 flex items-center gap-2">
            <span className="text-[10px] font-semibold uppercase tracking-[0.08em] text-accent-text">
              Noticed
            </span>
            <button
              type="button"
              onClick={onDismissSuggestion}
              className="ml-auto text-[11px] text-muted transition-colors hover:text-ink"
            >
              Dismiss
            </button>
          </div>
          <Markdown text={suggestion.text} />
        </Surface>
      )}

      {streaming && <Answer text={streaming} />}
      {busy && !streaming && <Working tool={tool} />}
      {error && (
        <Notice tone="danger">
          <p>{error}</p>
          {/* Signing in only happens in the CLI's interactive session, so the
              button opens a terminal there rather than pretending to do it. */}
          {errorCode === 'expiredLogin' && (
            <Button
              variant="secondary"
              size="sm"
              className="mt-2"
              onClick={() => send({ type: 'signIn' })}
            >
              Open terminal to sign in
            </Button>
          )}
        </Notice>
      )}

      <div ref={bottom} />
    </div>
  )
}
