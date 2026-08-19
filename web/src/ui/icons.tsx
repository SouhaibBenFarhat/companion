/**
 * Every icon in one place, at one size and stroke weight.
 *
 * Re-exported from Lucide rather than imported ad hoc, so a component asks the
 * kit for an icon instead of picking its own name and dimensions — which is how
 * the hand-drawn ones ended up with three different stroke widths.
 */
export {
  History as HistoryIcon,
  Plus as NewIcon,
  Settings2 as SettingsIcon,
  X as CloseIcon,
  ArrowUp as SendIcon,
  Trash2 as DeleteIcon,
  ChevronDown as ChevronIcon,
  FolderOpen as FolderIcon,
  Lock as ReadOnlyIcon,
  PencilLine as EditsIcon,
  Mic as ListenIcon,
  MicOff as MutedIcon,
  Sparkles as SpeakUpIcon,
  Terminal as AgentIcon,
  Check as CheckIcon,
} from 'lucide-react'

/** Panel-sized default. Lucide draws on a 24px grid; 14 suits 13px text. */
export const iconSize = 14
export const iconStroke = 1.75
