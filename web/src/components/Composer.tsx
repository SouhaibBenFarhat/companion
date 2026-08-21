import { useRef } from 'react'
import { send } from '../lib/bridge'
import { AutoTextarea, Bar, Divider, DragRegion, Hint, IconButton, Well } from '../ui'
import { SendIcon, StopIcon, iconStroke } from '../ui/icons'

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

  const sendNow = () => {
    if (!field.current) return
    if (!submit(field.current.value.trim())) return
    field.current.value = ''
    field.current.dispatchEvent(new Event('input', { bubbles: true }))
  }

  return (
    <Bar edge="top">
      <div className="p-2.5">
        <Well>
          {/* Send sits with the writing, not with the settings — it is the one
              control that acts on what you typed. Centred against the field
              rather than pinned to its floor, so it holds still as the box
              grows instead of walking down the panel line by line. */}
          <div className="flex items-center gap-1.5 px-2.5 pb-1.5 pt-2.5">
            <div className="min-w-0 flex-1">
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
            </div>

            {/* One slot, one meaning: the button that starts the answer is the
                button that stops it. */}
            {busy ? (
              <IconButton
                label="Stop"
                variant="filled"
                tone="neutral"
                onClick={() => send({ type: 'cancel' })}
              >
                <StopIcon size={13} strokeWidth={iconStroke} />
              </IconButton>
            ) : (
              <IconButton
                label="Send"
                variant="filled"
                tone="accent"
                disabled={disabled}
                onClick={sendNow}
              >
                <SendIcon size={15} strokeWidth={iconStroke} />
              </IconButton>
            )}
          </div>

          {/* Splits what you are writing from what it will be written with. */}
          <Divider />

          <div className="flex min-w-0 items-center gap-1.5 px-2 py-1.5">{controls}</div>
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
