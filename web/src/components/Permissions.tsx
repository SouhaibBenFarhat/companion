import { send } from '../lib/bridge'
import { Button, Notice, cx } from '../ui'
import type { PermissionItem, Permissions as PermissionsPayload } from '../lib/types'

function Dot({ state }: { state: PermissionItem['state'] }) {
  return (
    <span
      aria-hidden="true"
      className={cx(
        'mt-1.5 inline-block h-1.5 w-1.5 shrink-0 rounded-full',
        state === 'granted' ? 'bg-accent-text' : 'bg-muted/50',
      )}
    />
  )
}

function Row({ item }: { item: PermissionItem }) {
  const granted = item.state === 'granted'

  return (
    <div className="flex items-start gap-2.5 py-2">
      <Dot state={item.state} />

      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <span className="text-[12px] font-medium text-ink">{item.title}</span>
          {granted && <span className="text-[11px] text-muted">on</span>}
        </div>
        <p className="mt-0.5 text-[11px] leading-relaxed text-muted">{item.reason}</p>

        {granted && item.needsRestart && (
          <p className="mt-1 text-[11px] leading-relaxed text-muted">
            Just granted this? Quit and reopen Companion — macOS only reads it once per launch.
          </p>
        )}
      </div>

      {!granted && (
        <Button
          variant="secondary"
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

      <div className="divide-y divide-line">
        {permissions.items.map((item) => (
          <Row key={item.id} item={item} />
        ))}
      </div>

      {/* macOS re-reads these only when asked, so a grant made in System
          Settings does not reach a panel that is already open. */}
      <Button
        variant="ghost"
        size="sm"
        full
        onClick={() => send({ type: 'refreshPermissions' })}
      >
        Check again
      </Button>
    </div>
  )
}
