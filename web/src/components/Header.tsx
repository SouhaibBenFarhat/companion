import { send, startDrag } from '../lib/bridge'
import { Bar, IconButton } from '../ui'
import { ChatIcon, CloseIcon, HistoryIcon, NewIcon, SettingsIcon, iconSize, iconStroke } from '../ui/icons'

export function Header({
  repository,
  historyOpen,
  settingsOpen,
  onChat,
  onHistory,
  onSettings,
}: {
  repository: string
  historyOpen: boolean
  settingsOpen: boolean
  onChat: () => void
  onHistory: () => void
  onSettings: () => void
}) {
  const name = repository.split('/').filter(Boolean).pop() ?? repository

  return (
    <Bar
      edge="bottom"
      onMouseDown={(e) => startDrag(e)}
      className="group relative cursor-grab active:cursor-grabbing"
    >
      {/* Grab handle. The only visible hint that the panel moves, so it sits
          top-centre where the eye goes, and brightens on hover. */}
      {/* A grab strip above the controls. Everything in the header drags, but
          the buttons sit close together — this leaves a band you can land on
          without aiming, which is what makes the window feel movable. */}
      <div
        aria-hidden="true"
        className="absolute inset-x-0 top-0 h-7"
      />
      <div
        aria-hidden="true"
        className="absolute inset-x-0 top-[10px] mx-auto h-1 w-9 rounded-full bg-muted/30 transition-colors group-hover:bg-muted/60"
      />

      <div className="flex items-center gap-1 px-2 pb-2 pt-7">
        <button
          type="button"
          title={`${repository} — click to change, drag to move`}
          onMouseDown={(e) => startDrag(e, () => send({ type: 'pickRepository' }))}
          className="mr-auto min-w-0 cursor-grab truncate rounded-md px-1.5 py-1 text-left text-[12px] font-medium text-muted transition-colors hover:bg-control-hover hover:text-ink active:cursor-grabbing"
        >
          {name}
        </button>

        {/* Pairs with Settings: one marks the conversation, the other the
            settings, and the lit one says where you are. Without it the only
            way back is the gear you used to leave, which reads as a toggle
            rather than a place. */}
        <IconButton
          label="Chat"
          active={!settingsOpen}
          onMouseDown={(e) => startDrag(e, onChat)}
        >
          <ChatIcon size={iconSize} strokeWidth={iconStroke} />
        </IconButton>

        {/* Every control drags too, and still fires on a plain click. Opting
            out of dragging is what made the grab area so thin before. */}
        <IconButton
          label="History"
          active={historyOpen}
          onMouseDown={(e) => startDrag(e, onHistory)}
        >
          <HistoryIcon size={iconSize} strokeWidth={iconStroke} />
        </IconButton>

        <IconButton
          label="New conversation"
          onMouseDown={(e) => startDrag(e, () => send({ type: 'newConversation' }))}
        >
          <NewIcon size={iconSize} strokeWidth={iconStroke} />
        </IconButton>

        <IconButton
          label="Settings"
          active={settingsOpen}
          onMouseDown={(e) => startDrag(e, onSettings)}
        >
          <SettingsIcon size={iconSize} strokeWidth={iconStroke} />
        </IconButton>

        <IconButton label="Hide" onMouseDown={(e) => startDrag(e, () => send({ type: 'hide' }))}>
          <CloseIcon size={iconSize} strokeWidth={iconStroke} />
        </IconButton>
      </div>
    </Bar>
  )
}
