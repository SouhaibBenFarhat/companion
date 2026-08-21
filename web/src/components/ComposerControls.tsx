import { useState } from 'react'
import { send } from '../lib/bridge'
import { AgentMenu } from './AgentMenu'
import { Button, IconButton, Popover } from '../ui'
import { EditsIcon, ListenIcon, MutedIcon, ReadOnlyIcon, ScreenshotIcon } from '../ui/icons'
import type { AgentInfo, ListeningState, Permissions, SettingsPayload } from '../lib/types'

/**
 * The controls that sit on the bottom edge of the input, beside Send.
 *
 * Three, not five. The repo is already in the header 40 points above, and
 * printing a folder name twice in a 460 point panel is the cheapest thing a
 * toolbar can do. Speak up lives in the listening bar, because it means
 * nothing unless Companion is listening and that bar only exists then.
 *
 * Each control is a different shape because each value is a different kind:
 * one of a set, a dangerous two-state, and a session switch. Five identical
 * pills said the app had no opinion about which mattered.
 */
export function ComposerControls({
  settings,
  agent,
  repository,
  listening,
  permissions,
  screenshot,
  onOpenPermissions,
}: {
  settings: SettingsPayload
  agent: AgentInfo
  repository: string
  listening: ListeningState
  permissions: Permissions
  screenshot: 'capturing' | 'ready' | 'failed' | 'none'
  onOpenPermissions: () => void
}) {
  const [menuOpen, setMenuOpen] = useState(false)
  const [confirmEdits, setConfirmEdits] = useState(false)
  const readOnly = settings.permission === 'readOnly'
  const repoName = repository.split('/').filter(Boolean).pop()

  const setPermission = (value: 'readOnly' | 'acceptEdits') => {
    send({
      type: 'updateSettings',
      agent: settings.agent,
      agentPath: settings.agentPath,
      permission: value,
      systemPrompt: settings.systemPrompt,
      suggestionsEnabled: settings.suggestionsEnabled,
    })
    setConfirmEdits(false)
  }

  return (
    <div className="flex items-center gap-0.5">
      {/* Permission keeps its word at every width. A dangerous state must
          never be carried by a glyph alone. Arming costs two clicks;
          disarming costs one. */}
      <Popover
        open={confirmEdits}
        onOpenChange={setConfirmEdits}
        trigger={
          <Button
            variant={readOnly ? 'ghost' : 'outlined'}
            tone={readOnly ? 'neutral' : 'danger'}
            size="sm"
            tight
            aria-pressed={!readOnly}
            title={
              readOnly
                ? 'The agent can read this repo but not change it'
                : 'The agent can change files in this repo'
            }
            onClick={() => (readOnly ? setConfirmEdits(true) : setPermission('readOnly'))}
          >
            {readOnly ? (
              <ReadOnlyIcon size={13} strokeWidth={1.9} />
            ) : (
              <EditsIcon size={13} strokeWidth={1.9} />
            )}
            <span>{readOnly ? 'Read only' : 'Can edit'}</span>
          </Button>
        }
      >
        <p className="text-sm leading-relaxed text-ink">
          Let the agent change files in <span className="font-medium">{repoName}</span>?
        </p>
        <p className="mt-1 text-xs leading-relaxed text-muted">
          It can edit the code you are showing on the call.
        </p>
        <div className="mt-2.5 flex justify-end gap-1.5">
          <Button variant="ghost" size="sm" onClick={() => setConfirmEdits(false)}>
            Cancel
          </Button>
          <Button variant="filled" tone="danger" size="sm" onClick={() => setPermission('acceptEdits')}>
            Allow edits
          </Button>
        </div>
      </Popover>

      <AgentMenu
        open={menuOpen}
        onOpenChange={setMenuOpen}
        settings={settings}
        agent={agent}
        repository={repository}
      />

      {/* Unavailable is not the same as off, and never `disabled` — the user
          can unlock it, so the button stays live and routes to the fix.
          The badge marks the one combination that changes behaviour without
          being visible at rest. */}
      <IconButton
        label={permissions.canListen ? 'Follow both sides of the call' : permissions.summary}
        pressed={listening.active}
        tone="accent"
        badge={listening.active && settings.suggestionsEnabled}
        onClick={() =>
          permissions.canListen ? send({ type: 'toggleListening' }) : onOpenPermissions()
        }
      >
        {permissions.canListen ? (
          <ListenIcon size={14} strokeWidth={1.9} />
        ) : (
          <MutedIcon size={14} strokeWidth={1.9} />
        )}
      </IconButton>

      {/* Pixels on request only. The screen is read as text continuously,
          which is exact and free; a picture is for the cases with no text —
          a diagram, a rendered page, a canvas. */}
      <IconButton
        label={
          screenshot === 'ready'
            ? 'A picture of your window will go with the next message'
            : 'Attach a picture of the window in front'
        }
        pressed={screenshot === 'ready'}
        tone={screenshot === 'failed' ? 'danger' : 'accent'}
        busy={screenshot === 'capturing'}
        onClick={() => send({ type: 'lookAtScreen' })}
      >
        <ScreenshotIcon size={14} strokeWidth={1.9} />
      </IconButton>
    </div>
  )
}
