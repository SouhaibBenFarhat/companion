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
  /** Reported by `--version`, empty until the check finishes. */
  version: string
  /** Whether the binary has actually been run yet. */
  checked: boolean
}

export interface SettingsPayload {
  agent: string
  agentPath: string
  repositoryPath: string
  permission: string
  systemPrompt: string
  /** Whether Companion may speak without being asked. */
  suggestionsEnabled: boolean
  persistTranscript: boolean
  /** Empty means the system default. */
  microphoneDeviceUID: string
  /** Whether screen capture skips the panel. */
  hideFromScreenShare: boolean
  /** The chosen microphone is not plugged in right now. */
  microphoneMissing: boolean
}

export type PermissionId = 'microphone' | 'systemAudio' | 'accessibility'
export type PermissionState = 'granted' | 'denied' | 'notAsked'

export interface PermissionItem {
  id: PermissionId
  title: string
  reason: string
  state: PermissionState
  /** Granting these while the app runs does not take effect until it restarts. */
  needsRestart: boolean
}

export interface Permissions {
  canListen: boolean
  canSeeScreen: boolean
  isReady: boolean
  summary: string
  /** The one to ask for next, or empty when nothing is missing. */
  next: string
  items: PermissionItem[]
}

export interface Levels {
  me: number
  them: number
}

export interface ListeningState {
  active: boolean
  /** Best guess at which app the call is in, may be empty. */
  callApp: string
}

export interface TranscriptLine {
  id: string
  speaker: 'me' | 'them'
  who: string
  text: string
  /** Still being revised by the recogniser. */
  live: boolean
}

export interface Suggestion {
  text: string
  reason: string
}

export interface InputDevice {
  uid: string
  name: string
  isSystemDefault: boolean
}

export interface StatePayload {
  type: 'state'
  busy: boolean
  agent: AgentInfo
  settings: SettingsPayload
  repository: string
  permissions: Permissions
  inputDevices: InputDevice[]
  listening: ListeningState
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
  | { type: 'done'; isError: boolean; message: string; code?: string }
  | { type: 'focus' }
  | { type: 'levels'; me: number; them: number }
  | { type: 'captureError'; message: string }
  | { type: 'openSettings' }
  | { type: 'transcript'; entries: TranscriptLine[] }
  | { type: 'screen'; app: string; detail: string }
  | { type: 'suggestion'; text: string; reason: string }
  | { type: 'screenshot'; state: 'capturing' | 'ready' | 'failed' | 'none'; name?: string; message?: string }

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
  | { type: 'signIn' }
  | { type: 'requestPermission'; id: PermissionId }
  | { type: 'openPermissionSettings'; id: PermissionId }
  | { type: 'refreshPermissions' }
  | { type: 'toggleListening' }
  | { type: 'lookAtScreen' }
  | { type: 'drag'; dx: number; dy: number }
  | {
      type: 'updateSettings'
      agent?: string
      agentPath?: string
      permission?: string
      systemPrompt?: string
      suggestionsEnabled?: boolean
      microphoneDeviceUID?: string
      hideFromScreenShare?: boolean
    }
