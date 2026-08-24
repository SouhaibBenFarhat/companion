import { send } from '../lib/bridge'
import { Bar, Button, GrabHandle, IconButton, startDrag } from '../ui'
import {
  ChatIcon,
  CloseIcon,
  FolderIcon,
  HistoryIcon,
  NewIcon,
  SettingsIcon,
  iconSize,
  iconStroke,
} from '../ui/icons'
import { HistoryMenu } from './HistoryMenu'
import type { ConversationSummary } from '../lib/types'

/**
 * The top strip: which repo, and the four panel actions.
 *
 * Every control here drags the window as well as doing its own job, so the
 * whole strip is grabbable rather than a thin gap between buttons: mousedown
 * starts the drag, click does the job, and a press that really dragged has its
 * click swallowed.
 *
 * Both handlers, not one. Doing the job from inside `startDrag` meant the
 * keyboard could never reach any of these — Tab and Enter send a click, and
 * nothing was listening for one.
 *
 * History is the exception: it anchors a menu, so it opens on press like every
 * other menu on the system and cannot also start a drag.
 */
export function Header({
  repository,
  hasRepository,
  conversations,
  currentId,
  historyOpen,
  settingsOpen,
  onChat,
  onHistoryOpenChange,
  onSettings,
}: {
  repository: string
  hasRepository: boolean
  conversations: ConversationSummary[]
  currentId: string
  historyOpen: boolean
  settingsOpen: boolean
  onChat: () => void
  onHistoryOpenChange: (open: boolean) => void
  onSettings: () => void
}) {
  // Without a folder the agent runs in your home directory, and the name of
  // that folder looks exactly like a project name. Saying so is the difference
  // between "this repo" meaning your code and it meaning your whole Mac.
  const name = hasRepository ? (repository.split('/').filter(Boolean).pop() ?? repository) : 'No folder'

  return (
    <Bar edge="bottom" onMouseDown={startDrag}>
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
              tone={hasRepository ? 'neutral' : 'danger'}
              title={
                hasRepository
                  ? `${repository} — click to change, drag to move`
                  : `No project folder chosen. The agent is running in ${repository}. Click to pick one.`
              }
              onMouseDown={startDrag}
              onClick={() => send({ type: 'pickRepository' })}
            >
              {!hasRepository && <FolderIcon size={12} strokeWidth={2} className="shrink-0" />}
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
            onMouseDown={startDrag}
            onClick={onChat}
          >
            <ChatIcon size={iconSize} strokeWidth={iconStroke} />
          </IconButton>

          <HistoryMenu
            open={historyOpen}
            onOpenChange={onHistoryOpenChange}
            conversations={conversations}
            currentId={currentId}
            trigger={
              // Opens the menu on press, so it is the one control in the
              // strip that must not also grab the window.
              <IconButton
                label="History"
                pressed={historyOpen}
                onMouseDown={(event) => event.stopPropagation()}
              >
                <HistoryIcon size={iconSize} strokeWidth={iconStroke} />
              </IconButton>
            }
          />

          <IconButton
            label="New conversation"
            onMouseDown={startDrag}
            onClick={() => send({ type: 'newConversation' })}
          >
            <NewIcon size={iconSize} strokeWidth={iconStroke} />
          </IconButton>

          <IconButton
            label="Settings"
            pressed={settingsOpen}
            onMouseDown={startDrag}
            onClick={onSettings}
          >
            <SettingsIcon size={iconSize} strokeWidth={iconStroke} />
          </IconButton>

          <IconButton
            label="Hide"
            onMouseDown={startDrag}
            onClick={() => send({ type: 'hide' })}
          >
            <CloseIcon size={iconSize} strokeWidth={iconStroke} />
          </IconButton>
        </div>
      </div>
    </Bar>
  )
}
