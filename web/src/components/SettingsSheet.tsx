import { useState } from 'react'
import { send } from '../lib/bridge'
import { Bar, Button, Field, Input, Notice, Select, Textarea, Toggle } from '../ui'
import { FolderIcon, iconSize, iconStroke } from '../ui/icons'
import { Permissions } from './Permissions'
import type {
  AgentInfo,
  InputDevice,
  Permissions as PermissionsPayload,
  SettingsPayload,
} from '../lib/types'

function Group({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="space-y-3.5">
      <h3 className="text-[11px] font-semibold uppercase tracking-[0.09em] text-muted">{title}</h3>
      {children}
    </section>
  )
}

export function SettingsSheet({
  settings,
  agent,
  repository,
  permissions,
  inputDevices,
  onClose,
}: {
  settings: SettingsPayload
  agent: AgentInfo
  repository: string
  permissions: PermissionsPayload
  inputDevices: InputDevice[]
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
      suggestionsEnabled: next.suggestionsEnabled,
      microphoneDeviceUID: next.microphoneDeviceUID,
      hideFromScreenShare: next.hideFromScreenShare,
    })
  }

  return (
    <div className="flex min-h-0 flex-1 flex-col">
      <Bar edge="bottom" className="flex items-center justify-between px-3 py-2">
        <span className="text-[12px] font-medium text-ink">Settings</span>
        <Button variant="ghost" size="sm" onClick={onClose}>
          Done
        </Button>
      </Bar>

      <div className="min-h-0 flex-1 space-y-6 overflow-y-auto p-3">
        <Group title="Agent">
          {!agent.found && (
            <Notice tone="danger">
              {agent.title} was not found. Install it, or set the path below.
            </Notice>
          )}

          <Field
            label="Which agent"
            htmlFor="agent"
            hint={agent.version ? `Verified — ${agent.version}` : undefined}
          >
            <Select id="agent" value={draft.agent} onChange={(e) => apply({ agent: e.target.value })}>
              <option value="claude">Claude Code</option>
              <option value="codex">Codex</option>
            </Select>
          </Field>

          <Field
            label="Path to the binary"
            htmlFor="agent-path"
            hint="Leave empty to search the usual install folders. A launched app does not inherit your shell PATH, so this is stored as an absolute path."
          >
            <Input
              id="agent-path"
              value={draft.agentPath}
              placeholder={agent.path || '/opt/homebrew/bin/claude'}
              onChange={(e) => apply({ agentPath: e.target.value })}
            />
          </Field>
        </Group>

        <Group title="Repo">
          <Field label="Folder the agent runs in" hint={repository}>
            <Button variant="secondary" full onClick={() => send({ type: 'pickRepository' })}>
              <FolderIcon size={iconSize} strokeWidth={iconStroke} />
              Choose folder…
            </Button>
          </Field>

          <Field
            label="Permission"
            htmlFor="permission"
            hint="Read only is the sensible default while pairing — an assistant should not edit the code you are showing someone."
          >
            <Select
              id="permission"
              value={draft.permission}
              onChange={(e) => apply({ permission: e.target.value })}
            >
              <option value="readOnly">Read only</option>
              <option value="acceptEdits">Allow edits</option>
            </Select>
          </Field>
        </Group>

        <Group title="During a call">
          <Field
            label="Microphone"
            htmlFor="microphone"
            hint={
              settings.microphoneMissing
                ? 'The microphone you chose is not connected. The system default is being used until it comes back.'
                : 'Which input records your side. The system default follows macOS, which can hand your Mac the iPhone microphone without warning.'
            }
          >
            <Select
              id="microphone"
              value={draft.microphoneDeviceUID}
              onChange={(e) => apply({ microphoneDeviceUID: e.target.value })}
            >
              <option value="">System default</option>
              {inputDevices.map((device) => (
                <option key={device.uid} value={device.uid}>
                  {device.name}
                  {device.isSystemDefault ? ' (system default)' : ''}
                </option>
              ))}
            </Select>
          </Field>

          <Toggle
            label="Speak up without being asked"
            hint="Off, Companion listens and answers when you ask. On, it can interrupt with something it thinks you would miss — at most three times a minute, never while you are talking."
            checked={draft.suggestionsEnabled}
            onChange={(value) => apply({ suggestionsEnabled: value })}
          />
        </Group>

        <Group title="Screen share">
          <Toggle
            label="Hide the panel from screen sharing"
            hint="On, screen capture skips this window — the reason Companion exists. Off, it appears like any other window, which is what you want to record a demo or take a screenshot of it."
            checked={draft.hideFromScreenShare}
            onChange={(value) => apply({ hideFromScreenShare: value })}
          />
          {!draft.hideFromScreenShare && (
            <Notice tone="danger">
              The panel is visible to anyone you share your screen with.
            </Notice>
          )}
        </Group>

        <Group title="Permissions">
          <Permissions permissions={permissions} />
        </Group>

        <Group title="Answers">
          <Field
            label="Extra instructions"
            htmlFor="system-prompt"
            hint="Appended to the agent's own system prompt, never replacing it."
          >
            <Textarea
              id="system-prompt"
              rows={7}
              value={draft.systemPrompt}
              onChange={(e) => apply({ systemPrompt: e.target.value })}
            />
          </Field>
        </Group>
      </div>
    </div>
  )
}
