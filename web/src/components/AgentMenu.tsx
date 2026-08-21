import { useEffect, useRef } from 'react'
import { send } from '../lib/bridge'
import { Surface, cx, focusRing } from '../ui'
import { CheckIcon, ChevronIcon, FolderIcon } from '../ui/icons'
import type { AgentInfo, SettingsPayload } from '../lib/types'

const AGENTS = [
  { id: 'claude', name: 'Claude Code' },
  { id: 'codex', name: 'Codex' },
] as const

/**
 * Which agent answers.
 *
 * A pop-up button rather than a control that cycles on click: this is one
 * value out of a set, one of them can be missing entirely, and you cannot
 * choose between two things you are not being shown.
 *
 * Plain text and a chevron, no border and no fill at rest. It is the only
 * control in the row carrying a word, because it is the one whose value cannot
 * be guessed from a glyph.
 */
export function AgentMenu({
  open,
  onOpenChange,
  settings,
  agent,
  repository,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  settings: SettingsPayload
  agent: AgentInfo
  repository: string
}) {
  const container = useRef<HTMLDivElement>(null)

  // Click away and Escape both close. Escape is caught here rather than at the
  // window, so it closes the menu without also hiding the whole panel.
  useEffect(() => {
    if (!open) return

    const onPointerDown = (event: MouseEvent) => {
      if (!container.current?.contains(event.target as Node)) onOpenChange(false)
    }
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.stopPropagation()
        onOpenChange(false)
      }
    }
    document.addEventListener('mousedown', onPointerDown)
    document.addEventListener('keydown', onKey, true)
    return () => {
      document.removeEventListener('mousedown', onPointerDown)
      document.removeEventListener('keydown', onKey, true)
    }
  }, [open, onOpenChange])

  const choose = (id: string) => {
    send({
      type: 'updateSettings',
      agent: id,
      agentPath: settings.agentPath,
      permission: settings.permission,
      systemPrompt: settings.systemPrompt,
      suggestionsEnabled: settings.suggestionsEnabled,
    })
    onOpenChange(false)
  }

  const repoName = repository.split('/').filter(Boolean).pop() ?? 'Choose a folder'

  return (
    <div ref={container} className="relative">
      <button
        type="button"
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => onOpenChange(!open)}
        className={cx(
          'inline-flex h-7 items-center gap-1 rounded-md px-1.5 text-[12px] transition-colors',
          'text-muted hover:bg-overlay-hover hover:text-ink',
          open && 'bg-control-hover text-ink',
          focusRing,
        )}
      >
        {/* Not found is an error, so it gets a dot — never the same red fill
            used for "you armed something dangerous". */}
        {!agent.found && <span className="h-1.5 w-1.5 rounded-full bg-danger" aria-hidden="true" />}
        <span className="max-w-[8rem] truncate">{agent.title}</span>
        <ChevronIcon size={12} strokeWidth={2} className={cx('transition-transform', open && 'rotate-180')} />
      </button>

      {open && (
        <Surface
          level="overlay"
          role="menu"
          className="absolute bottom-full left-0 z-30 mb-1.5 min-w-[210px] p-1"
        >
          {AGENTS.map((option) => {
            const selected = settings.agent === option.id
            const missing = selected && !agent.found

            return (
              <button
                key={option.id}
                type="button"
                role="menuitemradio"
                aria-checked={selected}
                onClick={() => choose(option.id)}
                className={cx(
                  'flex w-full items-start gap-2 rounded-lg px-2 py-1.5 text-left transition-colors',
                  'hover:bg-overlay-hover',
                  focusRing,
                )}
              >
                <span className="mt-0.5 w-3 shrink-0">
                  {selected && <CheckIcon size={12} strokeWidth={2.5} className="text-accent-text" />}
                </span>
                <span className="min-w-0 flex-1">
                  <span className="block text-[12px] font-medium text-ink">{option.name}</span>
                  {/* A name with no meaning is not a choice. */}
                  <span className={cx('block text-[11px] leading-snug', missing ? 'text-danger' : 'text-muted')}>
                    {selected
                      ? agent.found
                        ? agent.version || 'Signed in and ready'
                        : 'Not installed on this Mac'
                      : `Use ${option.name} instead`}
                  </span>
                </span>
              </button>
            )
          })}

          <div className="my-1 h-px bg-line" />

          <button
            type="button"
            role="menuitem"
            onClick={() => {
              send({ type: 'pickRepository' })
              onOpenChange(false)
            }}
            className={cx(
              'flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-left transition-colors',
              'hover:bg-overlay-hover',
              focusRing,
            )}
          >
            <FolderIcon size={12} strokeWidth={2} className="shrink-0 text-muted" />
            <span className="min-w-0 flex-1 truncate text-[12px] text-ink">Change repo…</span>
            <span className="max-w-[7rem] shrink-0 truncate text-[11px] text-muted">{repoName}</span>
          </button>
        </Surface>
      )}
    </div>
  )
}
