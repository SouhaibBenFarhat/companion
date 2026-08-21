import { send } from '../lib/bridge'
import { Bar, Button, LiveDot, Meter, Toggle, cx } from '../ui'
import type { Levels, ListeningState, TranscriptLine } from '../lib/types'

/// The last few lines, so it is obvious what Companion is hearing.
function Transcript({ lines }: { lines: TranscriptLine[] }) {
  if (lines.length === 0) return null

  return (
    <div className="mt-2 max-h-20 space-y-0.5 overflow-y-auto">
      {lines.slice(-6).map((line) => (
        <p key={line.id} className={cx('text-xs leading-snug', line.live ? 'text-muted' : 'text-ink')}>
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
    // Capped and scrollable. Header plus this plus the composer used to add up
    // to more than the whole window at its 320x240 minimum, and the composer
    // fell off the bottom with no way to reach it.
    <Bar edge="bottom">
      <div className="max-h-[var(--awareness-max)] overflow-y-auto px-3 py-2">
        {error ? (
          <p className="text-xs leading-relaxed text-danger-text">{error}</p>
        ) : (
          <>
            <div className="flex items-center gap-2">
              {/* macOS shows its own recording indicator anyway, so there is
                  nothing to gain from being subtle about it. */}
              <LiveDot />
              <span className="text-xs font-medium text-ink">Listening</span>
              {listening.callApp && (
                <span className="min-w-0 truncate text-xs text-muted">· {listening.callApp}</span>
              )}

              {/* A switch belongs here and not in the composer row: it means
                  nothing unless Companion is listening, and this bar only
                  exists while it is. */}
              <div className="ml-auto flex items-center gap-2">
                <Toggle label="Speak up" checked={suggestionsEnabled} onChange={onSuggestionsChange} />
                <Button variant="ghost" size="sm" onClick={() => send({ type: 'toggleListening' })}>
                  Stop
                </Button>
              </div>
            </div>

            <div className="mt-2 flex items-end gap-3">
              <Meter label="You" level={listening.active ? levels.me : 0} />
              <Meter label="The call" level={listening.active ? levels.them : 0} />
            </div>

            {screen && (
              <p className="mt-1.5 truncate text-xs text-muted" title={screen}>
                Watching · {screen}
              </p>
            )}

            <Transcript lines={transcript} />
          </>
        )}
      </div>
    </Bar>
  )
}
