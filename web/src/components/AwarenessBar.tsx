import { send } from '../lib/bridge'
import { Bar, Button, Toggle, cx } from '../ui'
import type { Levels, ListeningState, TranscriptLine } from '../lib/types'

/// A meter that reads like a voice, not like a number.
function Meter({ label, level, active }: { label: string; level: number; active: boolean }) {
  // Root mean square of speech sits low in a 0-1 range, so a linear bar barely
  // moves. The cube root opens up the quiet end where conversation lives.
  const filled = active ? Math.min(1, Math.cbrt(Math.max(0, level)) * 1.35) : 0

  return (
    <div className="min-w-0 flex-1">
      <div className="flex items-baseline justify-between">
        <span className="text-[10px] font-medium uppercase tracking-[0.08em] text-muted">{label}</span>
      </div>
      <div className="mt-1 h-1 overflow-hidden rounded-full bg-input">
        <div
          className="h-full rounded-full bg-accent transition-[width] duration-75"
          style={{ width: `${filled * 100}%` }}
        />
      </div>
    </div>
  )
}

/// The last few lines, so it is obvious what Companion is hearing.
function Transcript({ lines }: { lines: TranscriptLine[] }) {
  if (lines.length === 0) return null

  return (
    <div className="mt-2 max-h-20 space-y-0.5 overflow-y-auto">
      {lines.slice(-6).map((line) => (
        <p key={line.id} className={cx('text-[11px] leading-snug', line.live ? 'text-muted' : 'text-ink')}>
          <span className="text-muted">{line.who}: </span>
          {line.text}
        </p>
      ))}
    </div>
  )
}

export function AwarenessBar({
  listening,
  levels,
  error,
  transcript,
  screen,
  suggestionsEnabled,
  onSuggestionsChange,
}: {
  listening: ListeningState
  levels: Levels
  error: string
  transcript: TranscriptLine[]
  screen: string
  suggestionsEnabled: boolean
  onSuggestionsChange: (value: boolean) => void
}) {
  if (!listening.active && !error) return null

  return (
    <Bar edge="bottom" className="px-3 py-2">
      {error ? (
        <p className="text-[11px] leading-relaxed text-danger">{error}</p>
      ) : (
        <>
          <div className="flex items-center gap-2">
            {/* macOS shows its own recording indicator anyway, so there is
                nothing to gain from being subtle about it. */}
            <span className="h-1.5 w-1.5 shrink-0 animate-pulse rounded-full bg-danger" />
            <span className="text-[11px] font-medium text-ink">Listening</span>
            {listening.callApp && (
              <span className="min-w-0 truncate text-[11px] text-muted">· {listening.callApp}</span>
            )}
            {/* A switch belongs here and not in the composer row: it means
                nothing unless Companion is listening, and this bar only exists
                while it is. */}
            <div className="ml-auto flex items-center gap-2">
              <Toggle
                label="Speak up"
                checked={suggestionsEnabled}
                onChange={onSuggestionsChange}
              />
              <Button variant="ghost" size="sm" onClick={() => send({ type: 'toggleListening' })}>
                Stop
              </Button>
            </div>
          </div>

          <div className="mt-2 flex items-end gap-3">
            <Meter label="You" level={levels.me} active={listening.active} />
            <Meter label="The call" level={levels.them} active={listening.active} />
          </div>

          {screen && (
            <p className="mt-1.5 truncate text-[11px] text-muted" title={screen}>
              Watching · {screen}
            </p>
          )}

          <Transcript lines={transcript} />
        </>
      )}
    </Bar>
  )
}

/// Shown in the composer area when nothing is being captured yet.
export function StartListening({ canListen }: { canListen: boolean }) {
  return (
    <Button
      variant="secondary"
      size="sm"
      full
      disabled={!canListen}
      onClick={() => send({ type: 'toggleListening' })}
      className={cx(!canListen && 'opacity-60')}
    >
      {canListen ? 'Start listening to the call' : 'Permissions needed to listen'}
    </Button>
  )
}
