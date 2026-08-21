import { useRef } from 'react'
import { send } from '../lib/bridge'
import { AutoTextarea, Bar, Button, DragRegion, Hint, IconButton, Well } from '../ui'
import { SendIcon, iconStroke } from '../ui/icons'

/** Roughly three lines at rest, eight before it scrolls. */
const MIN_HEIGHT = 58
const MAX_HEIGHT = 200

export function Composer({
  busy,
  disabled,
  focusToken,
  controls,
}: {
  busy: boolean
  disabled: boolean
  /** Changes whenever the panel is summoned, so the input takes focus again. */
  focusToken: number
  controls: React.ReactNode
}) {
  const field = useRef<HTMLTextAreaElement>(null)

  /** Returns whether the text left the field, so it knows to clear itself. */
  const submit = (text: string) => {
    if (!text || busy || disabled) return false
    send({ type: 'ask', text })
    return true
  }

  return (
    <Bar edge="top">
      <div className="p-2.5">
        <Well>
          <AutoTextarea
            ref={field}
            min={MIN_HEIGHT}
            max={MAX_HEIGHT}
            disabled={disabled}
            submit={submit}
            // Focus follows the panel being summoned, and returns when an
            // answer finishes.
            resetToken={`${focusToken}:${busy}`}
            placeholder={disabled ? 'No agent found' : 'Ask about this repo…'}
          />

          {/* Settings on the left, send on the right, one line. Inside the well
              rather than above it — everything shipped puts them here, and above
              the box is where things go when they are meant to disappear. */}
          <div className="flex items-center gap-1.5 pt-1">
            {controls}
            <span className="flex-1" />
            {busy && (
              <Button variant="ghost" size="sm" onClick={() => send({ type: 'cancel' })}>
                Stop
              </Button>
            )}
            <IconButton
              label="Send"
              variant="filled"
              tone="accent"
              disabled={disabled || busy}
              onClick={() => {
                if (!field.current) return
                if (!submit(field.current.value.trim())) return
                field.current.value = ''
                field.current.dispatchEvent(new Event('input', { bubbles: true }))
              }}
            >
              <SendIcon size={15} strokeWidth={iconStroke} />
            </IconButton>
          </div>
        </Well>

        {/* Dead space otherwise, so it earns its keep as a second grab area. */}
        <div className="px-1 pt-1.5">
          <DragRegion>
            <Hint>Enter to send · Shift+Enter for a new line · Esc to hide</Hint>
          </DragRegion>
        </div>
      </div>
    </Bar>
  )
}
