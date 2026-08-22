import { useEffect, useRef, useState } from 'react'
import { Markdown } from './Markdown'
import { Button, Callout, LiveDot, Notice, Pulse, Surface, cx } from '../ui'
import { send } from '../lib/bridge'
import type { Msg, Suggestion, TranscriptLine } from '../lib/types'

/** Within this far of the end still counts as "following along". */
const NEAR_BOTTOM = 60

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

/**
 * Something said out loud, in the conversation where you can read it.
 *
 * Deliberately not the same shape as a message you typed. Spoken words are
 * heard, not asked — they may be wrong, they were not addressed to Companion,
 * and half of them are the other person's. A quiet outlined bubble says "this
 * is what I heard" without competing with the answers.
 *
 * Your side sits right, theirs left, matching where their typed equivalents
 * would be.
 */
function Spoken({ line }: { line: TranscriptLine }) {
  const mine = line.speaker === 'me'

  return (
    <div className={cx('flex', mine ? 'justify-end' : 'justify-start')}>
      <div
        data-surface="well"
        className={cx(
          'selectable max-w-[var(--bubble-max)] rounded-lg border px-2.5 py-1.5',
          line.live ? 'border-line' : 'border-line-strong',
        )}
      >
        <span className="mb-0.5 flex items-center gap-1.5 text-2xs font-medium uppercase tracking-caps text-muted">
          {line.live && <LiveDot />}
          {line.who}
        </span>
        <span className={cx('block text-sm leading-snug', line.live ? 'text-muted' : 'text-ink')}>
          {line.text}
        </span>
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
  transcript,
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
  /** What is being heard right now. Empty unless listening. */
  transcript: TranscriptLine[]
  onDismissSuggestion: () => void
}) {
  const bottom = useRef<HTMLDivElement>(null)
  const list = useRef<HTMLDivElement>(null)

  // Follow the answer as it streams in — but only while you are already at the
  // bottom. `streaming` ticks many times a second, so without this, scrolling
  // up to re-read something snapped you back down within a frame.
  useEffect(() => {
    const box = list.current
    if (!box) return
    const distanceFromBottom = box.scrollHeight - box.scrollTop - box.clientHeight
    if (distanceFromBottom > NEAR_BOTTOM) return
    bottom.current?.scrollIntoView({ block: 'end' })
  }, [messages.length, streaming, busy, error, transcript.length])

  const empty = messages.length === 0 && !streaming && !busy && transcript.length === 0

  return (
    <div ref={list} className="min-h-0 flex-1 space-y-2.5 overflow-y-auto px-3 py-3">
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

      {/* After the messages, because it is happening now. The live line is
          last and stays faded until the recogniser settles on it. */}
      {transcript.map((line) => (
        <Spoken key={line.id} line={line} />
      ))}

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
