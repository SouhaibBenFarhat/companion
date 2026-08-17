import { useState } from 'react'
import { send } from '../lib/bridge'
import type { AgentInfo, SettingsPayload } from '../lib/types'

function Field({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <label className="block space-y-1">
      <span className="text-[12px] font-medium text-ink">{label}</span>
      {children}
      {hint && <span className="block text-[11px] text-muted">{hint}</span>}
    </label>
  )
}

const inputClass =
  'selectable w-full rounded-lg border border-line bg-raised px-2 py-1.5 text-[12px] text-ink outline-none focus:border-accent'

export function SettingsSheet({
  settings,
  agent,
  repository,
  onClose,
}: {
  settings: SettingsPayload
  agent: AgentInfo
  repository: string
  onClose: () => void
}) {
  const [draft, setDraft] = useState(settings)

  const apply = (patch: Partial<SettingsPayload>) => {
    const next = { ...draft, ...patch }
    setDraft(next)
    send({
      type: 'updateSettings',
      agent: next.agent,
      agentPath: next.agentPath,
      permission: next.permission,
      systemPrompt: next.systemPrompt,
    })
  }

  return (
    <div className="flex flex-1 flex-col overflow-y-auto">
      <div className="flex shrink-0 items-center justify-between border-b border-line px-3 py-2">
        <span className="text-[12px] font-medium">Settings</span>
        <button
          type="button"
          onClick={onClose}
          className="rounded-md px-2 py-0.5 text-[12px] text-muted transition-colors hover:bg-overlay hover:text-ink"
        >
          Done
        </button>
      </div>

      <div className="space-y-4 p-3">
        <Field label="Agent" hint={agent.found ? agent.path : 'Not found in the usual install folders.'}>
          <select
            value={draft.agent}
            onChange={(event) => apply({ agent: event.target.value })}
            className={inputClass}
          >
            <option value="claude">Claude Code</option>
            <option value="codex">Codex</option>
          </select>
        </Field>

        <Field
          label="Agent path"
          hint="Leave empty to search automatically. A launched app does not inherit your shell PATH, so this is stored as an absolute path."
        >
          <input
            type="text"
            spellCheck={false}
            value={draft.agentPath}
            placeholder={agent.path || '/opt/homebrew/bin/claude'}
            onChange={(event) => apply({ agentPath: event.target.value })}
            className={inputClass}
          />
        </Field>

        <Field label="Repo" hint={repository}>
          <button
            type="button"
            onClick={() => send({ type: 'pickRepository' })}
            className="w-full rounded-lg border border-line bg-raised px-2 py-1.5 text-left text-[12px] text-ink transition-colors hover:border-accent"
          >
            Choose folder…
          </button>
        </Field>

        <Field
          label="Permission"
          hint="Read only is the sensible default while pairing — an assistant should not edit the code you are showing someone."
        >
          <select
            value={draft.permission}
            onChange={(event) => apply({ permission: event.target.value })}
            className={inputClass}
          >
            <option value="readOnly">Read only</option>
            <option value="acceptEdits">Allow edits</option>
          </select>
        </Field>

        <Field
          label="Instructions"
          hint="Appended to the agent's own system prompt, never replacing it."
        >
          <textarea
            rows={6}
            value={draft.systemPrompt}
            onChange={(event) => apply({ systemPrompt: event.target.value })}
            className={`${inputClass} resize-none leading-relaxed`}
          />
        </Field>
      </div>
    </div>
  )
}
