import { send } from '../lib/bridge'
import { Bar, Button, GrabHandle, IconButton, startDrag } from '../ui'
import { ChatIcon, CloseIcon, HistoryIcon, NewIcon, SettingsIcon, iconSize, iconStroke } from '../ui/icons'
import { HistoryMenu } from './HistoryMenu'
import type { ConversationSummary } from '../lib/types'

/**
 * The top strip: which repo, and the four panel actions.
 *
 * Every control here drags the window as well as doing its own job, so the
 * whole strip is grabbable rather than a thin gap between buttons. `startDrag`
 * fires the click itself when the pointer barely moved.
 *
 * History is the exception: it anchors a menu, so it opens on press like every
 * other menu on the system and cannot also start a drag.
 */
export function Header({
  repository,
  conversations,
  currentId,
  historyOpen,
  settingsOpen,
  onChat,
  onHistoryOpenChange,
  onSettings,
}: {
  repository: string
  conversations: ConversationSummary[]
  currentId: string
  historyOpen: boolean
  settingsOpen: boolean
  onChat: () => void
  onHistoryOpenChange: (open: boolean) => void
  onSettings: () => void
}) {
  const name = repository.split('/').filter(Boolean).pop() ?? repository

  return (
    <Bar edge="bottom" onMouseDown={(event) => startDrag(event)}>
      <div className="group relative cursor-grab active:cursor-grabbing">
        <GrabHandle />

        {/* A band above the controls with nothing in it. The buttons sit close
            together, so this is the part you can land on without aiming — which
            is what makes the window feel movable. */}
        <div className="flex items-center gap-1 px-2 pb-2 pt-7">
          <span className="mr-auto min-w-0">
            <Button
              variant="ghost"
              size="sm"
              tight
              title={`${repository} — click to change, drag to move`}
              onMouseDown={(event) => startDrag(event, () => send({ type: 'pickRepository' }))}
            >
              <span className="max-w-[var(--label-max)] truncate font-medium">{name}</span>
            </Button>
          </span>

          {/* Pairs with Settings: one marks the conversation, the other the
              settings, and the lit one says where you are. Without it the only
              way back is the gear you used to leave, which reads as a toggle
              rather than a place. */}
          <IconButton
            label="Chat"
            pressed={!settingsOpen}
            onMouseDown={(event) => startDrag(event, onChat)}
          >
            <ChatIcon size={iconSize} strokeWidth={iconStroke} />
          </IconButton>

          <HistoryMenu
            open={historyOpen}
            onOpenChange={onHistoryOpenChange}
            conversations={conversations}
            currentId={currentId}
            trigger={
              <IconButton label="History" pressed={historyOpen}>
                <HistoryIcon size={iconSize} strokeWidth={iconStroke} />
              </IconButton>
            }
          />

          <IconButton
            label="New conversation"
            onMouseDown={(event) => startDrag(event, () => send({ type: 'newConversation' }))}
          >
            <NewIcon size={iconSize} strokeWidth={iconStroke} />
          </IconButton>

          <IconButton
            label="Settings"
            pressed={settingsOpen}
            onMouseDown={(event) => startDrag(event, onSettings)}
          >
            <SettingsIcon size={iconSize} strokeWidth={iconStroke} />
          </IconButton>

          <IconButton
            label="Hide"
            onMouseDown={(event) => startDrag(event, () => send({ type: 'hide' }))}
          >
            <CloseIcon size={iconSize} strokeWidth={iconStroke} />
          </IconButton>
        </div>
      </div>
    </Bar>
  )
}
