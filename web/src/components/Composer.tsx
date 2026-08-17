import { useEffect, useRef } from 'react'
import { send } from '../lib/bridge'

export function Composer({
  busy,
  disabled,
  focusToken,
}: {
  busy: boolean
  disabled: boolean
  /** Changes whenever the panel is summoned, so the input takes focus again. */
  focusToken: number
}) {
  const input = useRef<HTMLTextAreaElement>(null)

  useEffect(() => {
    input.current?.focus()
  }, [focusToken, busy])

  // Grow with the text, up to a point — a tall input would eat the answer.
  const resize = () => {
    const element = input.current
    if (!element) return
    element.style.height = 'auto'
    element.style.height = `${Math.min(element.scrollHeight, 140)}px`
  }

  const submit = () => {
    const element = input.current
    if (!element) return
    const text = element.value.trim()
    if (!text || busy || disabled) return

    send({ type: 'ask', text })
    element.value = ''
    resize()
  }

  return (
    <div className="shrink-0 border-t border-line p-2">
      <div className="flex items-end gap-2 rounded-xl border border-line bg-raised px-2.5 py-1.5">
        <textarea
          ref={input}
          rows={1}
          disabled={disabled}
          onInput={resize}
          onKeyDown={(event) => {
            if (event.key === 'Enter' && !event.shiftKey) {
              event.preventDefault()
              submit()
            }
          }}
          placeholder={disabled ? 'No agent found' : 'Ask about this repo…'}
          className="selectable max-h-[140px] min-h-[20px] flex-1 resize-none bg-transparent leading-snug text-ink outline-none placeholder:text-muted disabled:cursor-not-allowed"
        />

        {busy ? (
          <button
            type="button"
            onClick={() => send({ type: 'cancel' })}
            className="shrink-0 rounded-md px-2 py-0.5 text-[12px] text-muted transition-colors hover:bg-overlay hover:text-ink"
          >
            Stop
          </button>
        ) : (
          <button
            type="button"
            onClick={submit}
            disabled={disabled}
            aria-label="Send"
            className="grid h-6 w-6 shrink-0 place-items-center rounded-md bg-accent text-accent-fg transition-opacity hover:opacity-90 disabled:opacity-40"
          >
            <svg width="13" height="13" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.8">
              <path d="M8 12.5v-9M4 7.5L8 3.5l4 4" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </button>
        )}
      </div>

      <p className="px-1 pt-1 text-[11px] text-muted">
        Enter to send · Shift+Enter for a new line · Esc to hide
      </p>
    </div>
  )
}
