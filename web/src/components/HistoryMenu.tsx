import { send } from '../lib/bridge'
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

      <div className="absolute right-2 top-10 z-20 max-h-[60%] w-[68%] overflow-y-auto rounded-xl border border-line bg-overlay p-1">
        {conversations.length === 0 && (
          <p className="px-2 py-3 text-[12px] text-muted">No conversations about this repo yet.</p>
        )}

        {conversations.map((conversation) => (
          <div
            key={conversation.id}
            className={`group flex items-center gap-1 rounded-lg px-2 py-1.5 ${
              conversation.id === currentId ? 'bg-base' : ''
            }`}
          >
            <button
              type="button"
              onClick={() => {
                send({ type: 'selectConversation', id: conversation.id })
                onClose()
              }}
              className="min-w-0 flex-1 truncate text-left text-[12px] text-ink"
            >
              {conversation.title}
            </button>

            <button
              type="button"
              aria-label="Delete conversation"
              onClick={() => send({ type: 'deleteConversation', id: conversation.id })}
              className="shrink-0 rounded p-0.5 text-muted opacity-0 transition-opacity group-hover:opacity-100 hover:text-danger"
            >
              <svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5">
                <path d="M3.5 4.5h9M6.5 4.5V3h3v1.5M5 4.5l.5 8h5l.5-8" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </button>
          </div>
        ))}
      </div>
    </>
  )
}
