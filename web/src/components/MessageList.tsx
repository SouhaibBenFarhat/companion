import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import { Markdown } from './Markdown'
import { Button, Callout, LiveDot, Notice, Pulse, Surface, cx } from '../ui'
import { send } from '../lib/bridge'
import type { Msg, TranscriptLine } from '../lib/types'

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
  if (message.role === 'noticed') {
    return (
      <Callout
        title="Noticed"
        action={
          <Button
            variant="ghost"
            size="xs"
            tight
            onClick={() => send({ type: 'dismissMessage', id: message.id })}
          >
            Dismiss
          </Button>
        }
      >
        <Markdown text={message.text} />
      </Callout>
    )
  }

  // Said out loud, so it is labelled and quieter than something typed. It is
  // the record of the call, not a turn in the chat.
  if (message.role === 'spokenByUser' || message.role === 'spokenByCall') {
    return (
      <Spoken
        line={{
          id: message.id,
          speaker: message.role === 'spokenByUser' ? 'me' : 'them',
          who: message.role === 'spokenByUser' ? 'You' : 'The call',
          text: message.text,
          live: false,
          at: 0,
        }}
      />
    )
  }

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
  transcript,
}: {
  messages: Msg[]
  streaming: string
  busy: boolean
  tool: string | null
  error: string
  errorCode: string
  agentFound: boolean
  agentTitle: string
  /** What is being heard right now. Empty unless listening. */
  transcript: TranscriptLine[]
}) {
  const bottom = useRef<HTMLDivElement>(null)
  const list = useRef<HTMLDivElement>(null)

  // The live line only. Everything settled is a message, including a note,
  // so it already sits where it happened.
  const timeline = transcript

  // Whether to keep following. Recorded when YOU scroll, never when new
  // content arrives.
  //
  // Measuring the distance inside the effect was wrong: by the time it runs,
  // the new bubble has already been laid out and pushed everything up, so the
  // distance is large and it concluded you had scrolled away — on every single
  // line. Following stopped the moment the call got going.
  const following = useRef(true)

  // Every content change, including the live line being revised in place —
  // hence the text, not just the count.
  const tail = timeline.at(-1)
  const signature = `${messages.length}:${streaming.length}:${busy}:${error}:${timeline.length}:${tail?.text ?? ''}`

  useLayoutEffect(() => {
    if (!following.current) return
    // Instant, not smooth: a call produces a line every few seconds, and
    // animations queue up behind each other until the panel is visibly behind.
    bottom.current?.scrollIntoView({ block: 'end' })
  }, [signature])

  const empty =
    messages.length === 0 && !streaming && !busy && transcript.length === 0



  return (
    <div
      ref={list}
      onScroll={(event) => {
        const box = event.currentTarget
        following.current = box.scrollHeight - box.scrollTop - box.clientHeight <= NEAR_BOTTOM
      }}
      className="min-h-0 flex-1 space-y-2.5 overflow-y-auto px-3 py-3"
    >
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

      {/* After the messages, because it is happening now. */}
      {timeline.map((line) => (
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
