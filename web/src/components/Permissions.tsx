import { send } from '../lib/bridge'
import { Button, Divider, Hint, Notice, cx } from '../ui'
import type { PermissionItem, Permissions as PermissionsPayload } from '../lib/types'

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

        {granted && item.needsRestart && (
          <Hint>Just granted this? Quit and reopen Companion — macOS only reads it once per launch.</Hint>
        )}
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
