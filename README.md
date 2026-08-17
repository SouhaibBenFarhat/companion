# Companion

A floating chat panel for macOS that **never appears in screen share**.

Ask it questions while you present or pair — the people watching your screen
see only your work, not your notes.

<p align="center">
  <img src="site/icon.png" width="128" alt="Companion">
</p>

## Why

When you share your screen in Meet or Teams, everything on it goes out — helper
windows included. Companion sets `NSWindowSharingNone`, so screen capture skips
it entirely. It stays on your display and disappears from the shared stream.

That keeps the shared view clean and easy for people to follow, which is the
whole point.

## How it works

Companion doesn't talk to a model API itself. It drives a coding agent CLI
(command line interface) you already have installed — Claude Code or Codex —
running headless in your repo:

- **No API (Application Programming Interface) key.** The CLI holds your
  subscription login. Nothing to store, nothing to leak.
- **No context management to build.** The agent reads the files, decides what
  matters, and compacts long threads on its own.
- **Real tools.** It can read, grep and run commands in the repo you point it at.

## Install

```
brew install --cask souhaibbenfarhat/tap/companion   # first install
brew upgrade --cask companion                        # upgrade
```

Requires macOS 14 (Sonoma) or later on Apple Silicon, plus one of:

```
npm install -g @anthropic-ai/claude-code   # or
npm install -g @openai/codex
```

## Use

| Shortcut | Action |
| --- | --- |
| <kbd>⌥</kbd><kbd>Space</kbd> | Show / hide the panel |
| <kbd>Esc</kbd> | Hide the panel |
| <kbd>⌘</kbd><kbd>↩</kbd> | Send |

The panel takes keyboard focus without bringing Companion to the front, so the
app you were presenting stays active and the call app sees no window switch.

## Develop

```
npm --prefix web install
npm --prefix web run dev          # Vite dev server on :5173
COMPANION_WEB_URL=http://localhost:5173 swift run Companion
```

Without `COMPANION_WEB_URL` the app loads the built assets from its bundle, or
from `web/dist` when running out of the source tree.

```
swift test              # CompanionCore unit tests
scripts/build-app.sh    # dist/Companion.app + dist/Companion-arm64.zip
```

## Licence

MIT
