import { useState } from 'react'
import { send } from '../lib/bridge'
import { AgentMenu } from './AgentMenu'
import { Surface, cx, focusRing } from '../ui'
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
          never be carried by a glyph alone. */}
      <div className="relative">
        <button
          type="button"
          aria-pressed={!readOnly}
          title={
            readOnly
              ? 'The agent can read this repo but not change it'
              : 'The agent can change files in this repo'
          }
          onClick={() => (readOnly ? setConfirmEdits(true) : setPermission('readOnly'))}
          className={cx(
            'inline-flex h-7 items-center gap-1.5 rounded-md px-1.5 text-[12px] transition-colors',
            // Tinted, not red. Red says something is broken; this is a state
            // the user deliberately turned on. The caution belongs in the
            // confirmation, which is where the decision actually happens.
            readOnly
              ? 'text-muted hover:bg-control-hover hover:text-ink'
              : 'bg-accent/12 text-accent-text hover:bg-accent/20',
            focusRing,
          )}
        >
          {readOnly ? (
            <ReadOnlyIcon size={13} strokeWidth={1.9} />
          ) : (
            <EditsIcon size={13} strokeWidth={1.9} />
          )}
          <span>{readOnly ? 'Read only' : 'Can edit'}</span>
        </button>

        {/* Arming costs two clicks; disarming costs one. */}
        {confirmEdits && (
          <Surface
            level="overlay"
            className="absolute bottom-full left-0 z-30 mb-1.5 w-[240px] p-2.5"
          >
            <p className="text-[12px] leading-relaxed text-ink">
              Let the agent change files in{' '}
              <span className="font-medium">{repository.split('/').filter(Boolean).pop()}</span>?
            </p>
            <p className="mt-1 text-[11px] leading-relaxed text-muted">
              It can edit the code you are showing on the call.
            </p>
            <div className="mt-2.5 flex justify-end gap-1.5">
              <button
                type="button"
                onClick={() => setConfirmEdits(false)}
                className={cx(
                  'h-7 rounded-md px-2.5 text-[12px] text-muted transition-colors hover:bg-control-hover hover:text-ink',
                  focusRing,
                )}
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={() => setPermission('acceptEdits')}
                className={cx(
                  'h-7 rounded-md bg-danger px-2.5 text-[12px] font-medium text-white transition-opacity hover:opacity-90',
                  focusRing,
                )}
              >
                Allow edits
              </button>
            </div>
          </Surface>
        )}
      </div>

      <AgentMenu
        open={menuOpen}
        onOpenChange={setMenuOpen}
        settings={settings}
        agent={agent}
        repository={repository}
      />

      {/* Unavailable is not the same as off, and never `disabled` — the user
          can unlock it, so the button stays live and routes to the fix. */}
      <button
        type="button"
        aria-pressed={listening.active}
        title={permissions.canListen ? 'Follow both sides of the call' : permissions.summary}
        onClick={() => (permissions.canListen ? send({ type: 'toggleListening' }) : onOpenPermissions())}
        className={cx(
          'relative grid h-7 w-7 place-items-center rounded-md transition-colors',
          listening.active
            ? 'bg-accent/12 text-accent-text'
            : permissions.canListen
              ? 'text-muted hover:bg-control-hover hover:text-ink'
              : 'text-muted/60 hover:bg-control-hover hover:text-muted',
          focusRing,
        )}
      >
        {permissions.canListen ? (
          <ListenIcon size={14} strokeWidth={1.9} />
        ) : (
          <MutedIcon size={14} strokeWidth={1.9} />
        )}

        {/* Anything that changes the answer and cannot be seen at rest is a
            trap. This is the only combination that changes behaviour. */}
        {listening.active && settings.suggestionsEnabled && (
          <span
            aria-hidden="true"
            className="absolute right-0.5 top-0.5 h-1.5 w-1.5 rounded-full bg-accent"
          />
        )}
      </button>

      {/* Pixels on request only. The screen is read as text continuously,
          which is exact and free; a picture is for the cases with no text —
          a diagram, a rendered page, a canvas. */}
      <button
        type="button"
        title={
          screenshot === 'ready'
            ? 'A picture of your window will go with the next message'
            : 'Attach a picture of the window in front'
        }
        onClick={() => send({ type: 'lookAtScreen' })}
        className={cx(
          'grid h-7 w-7 place-items-center rounded-md transition-colors',
          screenshot === 'ready'
            ? 'bg-accent/12 text-accent-text'
            : screenshot === 'failed'
              ? 'text-danger hover:bg-control-hover'
              : 'text-muted hover:bg-control-hover hover:text-ink',
          screenshot === 'capturing' && 'animate-pulse',
          focusRing,
        )}
      >
        <ScreenshotIcon size={14} strokeWidth={1.9} />
      </button>
    </div>
  )
}
