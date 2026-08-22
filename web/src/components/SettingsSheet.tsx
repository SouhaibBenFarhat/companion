import { useState } from 'react'
import { send } from '../lib/bridge'
import {
  Button,
  Field,
  GroupTitle,
  Input,
  Notice,
  Segmented,
  Select,
  Sheet,
  Textarea,
  Toggle,
} from '../ui'
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
      <GroupTitle>{title}</GroupTitle>
      {children}
    </section>
  )
}

/**
 * Settings.
 *
 * No title bar and no Done in the corner. The panel is 460 points tall — a
 * header saying "Settings" above a screen that is obviously settings costs a
 * row of that for nothing. Done floats over the end of the list instead, where
 * it stays reachable at any scroll position.
 *
 * Every change saves as you make it. Done only closes.
 */
export function SettingsSheet({
  settings,
  agent,
  repository,
  hasRepository,
  permissions,
  inputDevices,
  onClose,
}: {
  settings: SettingsPayload
  agent: AgentInfo
  repository: string
  hasRepository: boolean
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
      theme: next.theme,
      transcriptionEngine: next.transcriptionEngine,
    })
  }

  return (
    <Sheet
      action={
        <Button variant="filled" size="md" full onClick={onClose}>
          Done
        </Button>
      }
    >
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
        {!hasRepository && (
          <Notice>
            No folder chosen, so the agent is running in {repository} — your home folder, not a
            project. Pick one and "this repo" starts meaning your code.
          </Notice>
        )}

        <Field label="Folder the agent runs in" hint={repository}>
          <Button size="md" full onClick={() => send({ type: 'pickRepository' })}>
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

        <Field
          label="Speech to text"
          hint="Whisper runs a 1.6 GB model on the Neural Engine and downloads it the first time you listen. It is markedly better on identifiers and library names, which is most of what a pairing call is made of. Apple's is instant and needs no download."
        >
          <Segmented
            label="Speech to text"
            value={draft.transcriptionEngine}
            onChange={(transcriptionEngine) => apply({ transcriptionEngine })}
            options={[
              { value: 'whisper', label: 'Whisper' },
              { value: 'apple', label: 'Apple' },
            ]}
          />
        </Field>

        <Toggle
          label="Speak up without being asked"
          hint="Off, Companion listens and answers when you ask. On, it can interrupt with something it thinks you would miss — at most three times a minute, never while you are talking."
          checked={draft.suggestionsEnabled}
          onChange={(value) => apply({ suggestionsEnabled: value })}
        />
      </Group>

      <Group title="Appearance">
        <Field
          label="Light or dark"
          hint="Set on the window, so the blurred material behind the panel changes with it. Following the system is the usual choice; pick one outright when you are presenting on a projector."
        >
          <Segmented
            label="Light or dark"
            value={draft.theme}
            onChange={(theme) => apply({ theme })}
            options={[
              { value: 'system', label: 'System' },
              { value: 'light', label: 'Light' },
              { value: 'dark', label: 'Dark' },
            ]}
          />
        </Field>
      </Group>

      <Group title="Screen share">
        <Toggle
          label="Hide the panel from screen sharing"
          hint="On, screen capture skips this window — the reason Companion exists. Off, it appears like any other window, which is what you want to record a demo or take a screenshot of it."
          checked={draft.hideFromScreenShare}
          onChange={(value) => apply({ hideFromScreenShare: value })}
        />
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
    </Sheet>
  )
}
