import { send } from '../lib/bridge'
import { IconButton, Menu, MenuItem } from '../ui'
import { DeleteIcon } from '../ui/icons'
import type { ConversationSummary } from '../lib/types'

export function HistoryMenu({
  open,
  onOpenChange,
  trigger,
  conversations,
  currentId,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  trigger: React.ReactNode
  conversations: ConversationSummary[]
  currentId: string
}) {
  return (
    <Menu open={open} onOpenChange={onOpenChange} trigger={trigger} align="end">
      {conversations.length === 0 && (
        <p className="px-2 py-3 text-sm text-muted">No conversations about this repo yet.</p>
      )}

      {conversations.map((conversation) => (
        <MenuItem
          key={conversation.id}
          selected={conversation.id === currentId}
          label={conversation.title}
          onSelect={() => send({ type: 'selectConversation', id: conversation.id })}
          trailing={
            <IconButton
              label="Delete conversation"
              size="xs"
              tone="danger"
              onClick={(event) => {
                event.stopPropagation()
                send({ type: 'deleteConversation', id: conversation.id })
              }}
            >
              <DeleteIcon size={12} strokeWidth={2} />
            </IconButton>
          }
        />
      ))}
    </Menu>
  )
}
