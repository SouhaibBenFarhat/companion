import { send } from '../lib/bridge'
import { useState } from 'react'
import { Button, Divider, Hint, Notice, cx } from '../ui'
import type { PermissionItem, Permissions as PermissionsPayload } from '../lib/types'

/**
 * The way out when the switch is already on and the app is still refused.
 *
 * A grant is filed against what the app's signature says. Replace an unsigned
 * build with a signed one and the old entry stays behind: macOS has a decision
 * on record for this bundle identifier, so it stops prompting, and the row in
 * System Settings reads on while the app gets nothing. Nothing inside the app
 * can clear that — the command is the only route, and it is the user's to run.
 */
function Stuck({ command }: { command: string }) {
  const [copied, setCopied] = useState(false)

  return (
    <div className="mt-1.5">
      <Hint>
        Switch already on and still asking? macOS is holding an old entry for a
        previous build of this app. Clear it in Terminal, then reopen Companion:
      </Hint>
      <div data-surface="code" className="mt-1 flex items-center gap-2 rounded-md px-2 py-1.5">
        <code className="selectable min-w-0 flex-1 truncate font-mono text-xs text-ink">{command}</code>
        <Button
          size="xs"
          tight
          onClick={() => {
            navigator.clipboard.writeText(command)
            setCopied(true)
            window.setTimeout(() => setCopied(false), 1600)
          }}
        >
          {copied ? 'Copied' : 'Copy'}
        </Button>
      </div>
    </div>
  )
}

function Row({ item }: { item: PermissionItem }) {
  const granted = item.state === 'granted'

  return (
    <div className="flex items-start gap-2.5 py-2">
      <span
        aria-hidden="true"
        className={cx(
          'mt-1.5 inline-block h-1.5 w-1.5 shrink-0 rounded-full',
          granted ? 'bg-accent-text' : 'bg-faint',
        )}
      />

      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <span className="text-sm font-medium text-ink">{item.title}</span>
          {granted && <span className="text-xs text-muted">on</span>}
        </div>
        <Hint>{item.reason}</Hint>

        {/* Before it is granted, not after. macOS reads these once, at launch,
            so switching one on while Companion is running changes nothing and
            "Check again" can never notice. Saying so only after it worked is
            the wrong way round. */}
        {item.needsRestart && (
          <div className="mt-1">
            <Hint>
              {granted
                ? 'Just switched this on? Reopen Companion — macOS only reads it at launch.'
                : 'Switched it on and this still says off? Reopen Companion — macOS only reads it at launch.'}
            </Hint>
            <div className="mt-1.5">
              <Button size="xs" onClick={() => send({ type: 'relaunch' })}>
                Quit and reopen
              </Button>
            </div>
          </div>
        )}

        {!granted && item.resetCommand && <Stuck command={item.resetCommand} />}
      </div>

      {!granted && (
        <Button
          size="sm"
          onClick={() =>
            send(
              item.state === 'notAsked'
                ? { type: 'requestPermission', id: item.id }
                : { type: 'openPermissionSettings', id: item.id },
            )
          }
        >
          {item.state === 'notAsked' ? 'Allow' : 'Open Settings'}
        </Button>
      )}
    </div>
  )
}

export function Permissions({ permissions }: { permissions: PermissionsPayload }) {
  return (
    <div className="space-y-1">
      {!permissions.isReady && <Notice>{permissions.summary}</Notice>}

      <div>
        {permissions.items.map((item, index) => (
          <div key={item.id}>
            {index > 0 && <Divider />}
            <Row item={item} />
          </div>
        ))}
      </div>

      {/* macOS re-reads these only when asked, so a grant made in System
          Settings does not reach a panel that is already open. */}
      <Button variant="ghost" size="sm" full onClick={() => send({ type: 'refreshPermissions' })}>
        Check again
      </Button>
    </div>
  )
}
