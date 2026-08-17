import { useEffect, useRef } from 'react'
import { Markdown } from './Markdown'
import type { Msg } from '../lib/types'

function Bubble({ message }: { message: Msg }) {
  if (message.role === 'user') {
    return (
      <div className="flex justify-end">
        <div className="selectable max-w-[85%] rounded-xl rounded-br-sm bg-accent px-3 py-1.5 text-accent-fg break-words whitespace-pre-wrap">
          {message.text}
        </div>
      </div>
    )
  }

  return (
    <div className="rounded-xl rounded-bl-sm border border-line bg-raised px-3 py-2">
      <Markdown text={message.text} />
    </div>
  )
}

function Working({ tool }: { tool: string | null }) {
  return (
    <div className="flex items-center gap-2 px-1 text-[12px] text-muted">
      <span className="inline-block h-1.5 w-1.5 animate-pulse rounded-full bg-accent" />
      {tool ? `Reading — ${tool}` : 'Thinking'}
    </div>
  )
}

export function MessageList({
  messages,
  streaming,
  busy,
  tool,
  error,
  agentFound,
  agentTitle,
}: {
  messages: Msg[]
  streaming: string
  busy: boolean
  tool: string | null
  error: string
  agentFound: boolean
  agentTitle: string
}) {
  const bottom = useRef<HTMLDivElement>(null)

  // Follow the answer as it streams in.
  useEffect(() => {
    bottom.current?.scrollIntoView({ block: 'end' })
  }, [messages.length, streaming, busy, error])

  const empty = messages.length === 0 && !streaming && !busy

  return (
    <div className="flex-1 space-y-2 overflow-y-auto px-3 py-3">
      {!agentFound && (
        <div className="rounded-lg border border-line bg-raised px-3 py-2 text-[12px] text-muted">
          <span className="text-danger">{agentTitle} was not found.</span> Install it, or set the
          path in Settings. Companion drives the CLI you already signed in to, so there is no API
          key to add.
        </div>
      )}

      {empty && agentFound && (
        <div className="px-1 py-6 text-[12px] text-muted">
          Ask about the code in this repo. Answers stay on your screen and never reach a shared one.
        </div>
      )}

      {messages.map((message) => (
        <Bubble key={message.id} message={message} />
      ))}

      {streaming && (
        <div className="rounded-xl rounded-bl-sm border border-line bg-raised px-3 py-2">
          <Markdown text={streaming} />
        </div>
      )}

      {busy && !streaming && <Working tool={tool} />}

      {error && (
        <div className="selectable rounded-lg border border-line bg-raised px-3 py-2 text-[12px] text-danger break-words">
          {error}
        </div>
      )}

      <div ref={bottom} />
    </div>
  )
}
