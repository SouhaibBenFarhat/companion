import { send } from '../lib/bridge'
import { IconButton, Surface, cx } from '../ui'
import { DeleteIcon, iconStroke } from '../ui/icons'
import type { ConversationSummary } from '../lib/types'

export function HistoryMenu({
  conversations,
  currentId,
  onClose,
}: {
  conversations: ConversationSummary[]
  currentId: string
  onClose: () => void
}) {
  return (
    <>
      {/* Click anywhere else to dismiss. */}
      <div className="absolute inset-0 z-10" onClick={onClose} />

      <Surface
        level="overlay"
        className="absolute right-2 top-12 z-20 max-h-[62%] w-[70%] overflow-y-auto p-1"
      >
        {conversations.length === 0 && (
          <p className="px-2 py-3 text-[12px] text-muted">No conversations about this repo yet.</p>
        )}

        {conversations.map((conversation) => {
          const current = conversation.id === currentId
          return (
            <div
              key={conversation.id}
              className={cx(
                'group flex items-center gap-1 rounded-lg pr-1 transition-colors',
                current ? 'bg-overlay-active' : 'hover:bg-overlay-hover',
              )}
            >
              <button
                type="button"
                onClick={() => {
                  send({ type: 'selectConversation', id: conversation.id })
                  onClose()
                }}
                className={cx(
                  'min-w-0 flex-1 truncate px-2 py-1.5 text-left text-[12px]',
                  current ? 'font-medium text-ink' : 'text-muted group-hover:text-ink',
                )}
              >
                {conversation.title}
              </button>

              <IconButton
                label="Delete conversation"
                size="sm"
                onClick={() => send({ type: 'deleteConversation', id: conversation.id })}
                className="opacity-0 transition-opacity group-hover:opacity-100 hover:text-danger"
              >
                <DeleteIcon size={12} strokeWidth={iconStroke} />
              </IconButton>
            </div>
          )
        })}
      </Surface>
    </>
  )
}
