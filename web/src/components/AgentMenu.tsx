import { send } from '../lib/bridge'
import { Button, Menu, MenuDivider, MenuItem } from '../ui'
import { ChevronIcon, FolderIcon } from '../ui/icons'
import type { AgentInfo, SettingsPayload } from '../lib/types'

const AGENTS = [
  { id: 'claude', name: 'Claude Code' },
  { id: 'codex', name: 'Codex' },
] as const

/**
 * Which agent answers.
 *
 * All the behaviour — arrow keys, focus, dismissal, ARIA — comes from the kit's
 * Menu. This file used to carry its own copy of half of that, and the half it
 * had was the easy half.
 */
export function AgentMenu({
  open,
  onOpenChange,
  settings,
  agent,
  repository,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  settings: SettingsPayload
  agent: AgentInfo
  repository: string
}) {
  const update = (patch: Partial<SettingsPayload>) =>
    send({
      type: 'updateSettings',
      agent: patch.agent ?? settings.agent,
      agentPath: settings.agentPath,
      permission: settings.permission,
      systemPrompt: settings.systemPrompt,
      suggestionsEnabled: settings.suggestionsEnabled,
      microphoneDeviceUID: settings.microphoneDeviceUID,
      hideFromScreenShare: settings.hideFromScreenShare,
    })

  const repoName = repository.split('/').filter(Boolean).pop() ?? 'Choose a folder'

  return (
    <Menu
      open={open}
      onOpenChange={onOpenChange}
      trigger={
        <Button variant="ghost" size="sm" tight pressed={open}>
          {/* Not found is an error, so it gets a dot — never the soft fill,
              which means "you armed something dangerous". */}
          {!agent.found && <span className="h-1.5 w-1.5 rounded-full bg-danger" aria-hidden="true" />}
          <span className="max-w-[var(--label-max)] truncate">{agent.title}</span>
          <ChevronIcon size={12} strokeWidth={2} />
        </Button>
      }
    >
      {AGENTS.map((option) => {
        const selected = settings.agent === option.id
        return (
          <MenuItem
            key={option.id}
            selected={selected}
            label={option.name}
            tone={selected && !agent.found ? 'danger' : 'neutral'}
            detail={
              selected
                ? agent.found
                  ? agent.version || 'Signed in and ready'
                  : 'Not installed on this Mac'
                : `Use ${option.name} instead`
            }
            onSelect={() => update({ agent: option.id })}
          />
        )
      })}

      <MenuDivider />

      <MenuItem
        icon={<FolderIcon size={12} strokeWidth={2} className="text-muted" />}
        label="Change repo…"
        trailing={repoName}
        onSelect={() => send({ type: 'pickRepository' })}
      />
    </Menu>
  )
}
