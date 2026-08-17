import { send, startDrag } from '../lib/bridge'

function IconButton({
  label,
  onClick,
  children,
}: {
  label: string
  onClick: () => void
  children: React.ReactNode
}) {
  return (
    <button
      type="button"
      title={label}
      aria-label={label}
      onClick={onClick}
      // The header is a drag surface; without this a click that moves one
      // pixel would drag instead of press.
      onMouseDown={(e) => e.stopPropagation()}
      className="grid h-6 w-6 place-items-center rounded-md text-muted transition-colors hover:bg-overlay hover:text-ink"
    >
      {children}
    </button>
  )
}

export function Header({
  repository,
  onHistory,
  onSettings,
}: {
  repository: string
  onHistory: () => void
  onSettings: () => void
}) {
  const name = repository.split('/').filter(Boolean).pop() ?? repository

  return (
    <header
      onMouseDown={startDrag}
      className="flex shrink-0 items-center gap-2 border-b border-line px-3 py-2"
    >
      <button
        type="button"
        title={repository}
        onClick={() => send({ type: 'pickRepository' })}
        onMouseDown={(e) => e.stopPropagation()}
        className="min-w-0 flex-1 truncate text-left text-[12px] font-medium text-muted transition-colors hover:text-ink"
      >
        {name}
      </button>

      <IconButton label="History" onClick={onHistory}>
        <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5">
          <path d="M8 4v4l2.5 1.5" strokeLinecap="round" />
          <circle cx="8" cy="8" r="5.5" />
        </svg>
      </IconButton>

      <IconButton label="New conversation" onClick={() => send({ type: 'newConversation' })}>
        <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5">
          <path d="M8 3.5v9M3.5 8h9" strokeLinecap="round" />
        </svg>
      </IconButton>

      <IconButton label="Settings" onClick={onSettings}>
        <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5">
          <circle cx="8" cy="8" r="2" />
          <path d="M8 1.5v1.8M8 12.7v1.8M14.5 8h-1.8M3.3 8H1.5M12.6 3.4l-1.3 1.3M4.7 11.3l-1.3 1.3M12.6 12.6l-1.3-1.3M4.7 4.7L3.4 3.4" strokeLinecap="round" />
        </svg>
      </IconButton>

      <IconButton label="Hide" onClick={() => send({ type: 'hide' })}>
        <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5">
          <path d="M4.5 4.5l7 7M11.5 4.5l-7 7" strokeLinecap="round" />
        </svg>
      </IconButton>
    </header>
  )
}
