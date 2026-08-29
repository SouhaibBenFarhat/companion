import { send } from '../lib/bridge'
import { Menu, MenuDivider, MenuItem } from '../ui'
import type { ConversationSummary } from '../lib/types'

export function HistoryMenu({
  open,
  onOpenChange,
  trigger,
  conversations,
  currentId,
  canExport,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  trigger: React.ReactNode
  conversations: ConversationSummary[]
  currentId: string
  /** The current thread has messages. Keyed on exactly what the export
      writes — the conversations list can disagree with it in both
      directions: a fresh empty thread with old threads listed, and a
      first-call thread whose debounced save has not landed yet. */
  canExport: boolean
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
          onDelete={() => send({ type: 'deleteConversation', id: conversation.id })}
        />
      ))}

      {/* The current thread is the one exported — a per-row control cannot be
          reached with the arrow keys inside a Radix menu, and the current
          thread is the one people mean. Swift shows the save dialog. */}
      {canExport && (
        <>
          <MenuDivider />
          <MenuItem
            label="Export chat as Markdown…"
            onSelect={() => send({ type: 'exportConversation', format: 'markdown' })}
          />
          <MenuItem
            label="Export chat as JSON…"
            onSelect={() => send({ type: 'exportConversation', format: 'json' })}
          />
        </>
      )}
    </Menu>
  )
}
