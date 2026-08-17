export type Role = 'user' | 'assistant'

export interface Msg {
  id: string
  role: Role
  text: string
}

export interface ConversationSummary {
  id: string
  title: string
}

export interface AgentInfo {
  kind: string
  title: string
  path: string
  found: boolean
}

export interface SettingsPayload {
  agent: string
  agentPath: string
  repositoryPath: string
  permission: string
  systemPrompt: string
}

export interface StatePayload {
  type: 'state'
  busy: boolean
  agent: AgentInfo
  settings: SettingsPayload
  repository: string
  currentId: string
  conversations: ConversationSummary[]
  messages: Msg[]
}

/** Everything Swift can push into the page. */
export type Incoming =
  | StatePayload
  | { type: 'delta'; text: string }
  | { type: 'tool'; name: string }
  | { type: 'busy'; busy: boolean }
  | { type: 'done'; isError: boolean; message: string }
  | { type: 'focus' }

/** Everything the page can ask Swift to do. */
export type Outgoing =
  | { type: 'ready' }
  | { type: 'ask'; text: string }
  | { type: 'cancel' }
  | { type: 'hide' }
  | { type: 'newConversation' }
  | { type: 'selectConversation'; id: string }
  | { type: 'deleteConversation'; id: string }
  | { type: 'pickRepository' }
  | { type: 'drag'; dx: number; dy: number }
  | { type: 'updateSettings'; agent?: string; agentPath?: string; permission?: string; systemPrompt?: string }
