import { useEffect, useRef } from 'react'
import { send, startDrag } from '../lib/bridge'
import { Bar, Button, Hint, IconButton } from '../ui'
import { SendIcon, iconStroke } from '../ui/icons'

/** Roughly three lines at rest, eight before it scrolls. */
const MIN_HEIGHT = 58
const MAX_HEIGHT = 200

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

  const resize = () => {
    const element = input.current
    if (!element) return
    element.style.height = 'auto'
    element.style.height = `${Math.min(Math.max(element.scrollHeight, MIN_HEIGHT), MAX_HEIGHT)}px`
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
    <Bar edge="top" className="p-2.5">
      {/* A recessed well, not another raised surface: the field reads as a hole
          in the chrome rather than a card sitting on it. */}
      <div className="rounded-xl border border-line-strong bg-input px-3 pb-2 pt-2.5 transition-colors focus-within:border-accent focus-within:bg-input-focus">
        <textarea
          ref={input}
          rows={3}
          disabled={disabled}
          onInput={resize}
          onKeyDown={(event) => {
            if (event.key === 'Enter' && !event.shiftKey) {
              event.preventDefault()
              submit()
            }
          }}
          placeholder={disabled ? 'No agent found' : 'Ask about this repo…'}
          style={{ minHeight: MIN_HEIGHT, maxHeight: MAX_HEIGHT }}
          className="selectable block w-full resize-none bg-transparent text-[13px] leading-relaxed text-ink outline-none placeholder:text-muted disabled:cursor-not-allowed"
        />

        {/* Actions on their own row, so growing text never squeezes them. */}
        <div className="flex items-center justify-end gap-1.5 pt-1">
          {busy && (
            <Button variant="ghost" size="sm" onClick={() => send({ type: 'cancel' })}>
              Stop
            </Button>
          )}
          <IconButton
            label="Send"
            disabled={disabled || busy}
            onClick={submit}
            className="bg-accent text-accent-fg hover:bg-accent-hover hover:text-accent-fg active:brightness-90"
          >
            <SendIcon size={15} strokeWidth={iconStroke} />
          </IconButton>
        </div>
      </div>

      {/* Dead space otherwise, so it earns its keep as a second grab area. */}
      <Hint onMouseDown={(e) => startDrag(e)} className="cursor-grab px-1 pt-1.5 active:cursor-grabbing">
        Enter to send · Shift+Enter for a new line · Esc to hide
      </Hint>
    </Bar>
  )
}
