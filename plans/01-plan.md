# Companion — live awareness implementation plan

Press one button. Companion listens to both sides of the call, watches what is on screen, and can speak into the panel on its own.

Everything below is a decision, not an option. Where the research and the adversarial review disagree, the review wins and the line says so.

---

## Architecture

Two rules, both already in the repo. Pure logic lives in `Sources/CompanionCore` with no AppKit, so it is unit-testable. Everything that touches the system lives in `Sources/Companion`.

```
 ┌─ Sources/Companion (system) ─────────────┐   ┌─ Sources/CompanionCore (pure) ──────┐
 │                                          │   │                                     │
 │  microphone                              │   │                                     │
 │   └─► MicrophoneRecorder ────────────────┼──►│  AudioRingBuffer ──► PCMChunk       │
 │        AVAudioEngine + voice processing  │   │   (fixed size, no allocation)       │
 │                                          │   │        │                            │
 │  everything the Mac plays                │   │        ▼                            │
 │   └─► ProcessTapRecorder ────────────────┼──►│  SpeechSegmenter  ──► levels,       │
 │        Core Audio global process tap,    │   │  EchoGate             "user talking" │
 │        excludes Companion only           │   │        │                            │
 │              ▲                           │   │        ▼                            │
 │        CallCapture (owns both, rebuilds  │   │  AudioTimeline (one clock)          │
 │        on device change)                 │   │                                     │
 │              │                           │   │                                     │
 │              ▼                           │   │                                     │
 │  Transcriber ×2  (SpeechAnalyzer,        │   │                                     │
 │  macOS 26 only, one per stream) ─────────┼──►│  TranscriptBuffer (me / them,       │
 │                                          │   │   final text + volatile tail,       │
 │  AXAppObserver ─┐                        │   │   time window, sent watermark)      │
 │  AppFocusTracker├─► ScreenAwareness ─────┼──►│  ScreenContext, ContextDebouncer,   │
 │  BrowserReader  │   (own thread,         │   │  WindowTitleParser, AXTraversal,    │
 │  EditorReader  ─┘    run loop, budgets)  │   │  Redaction                          │
 │                                          │   │        │                            │
 │  ScreenFrame (one still, on request)     │   │        ▼                            │
 │                                          │   │  TurnTrigger ──► SuggestionGate     │
 │                                          │   │        │          (budget, novelty, │
 │  AwarenessCoordinator ◄──────────────────┼───┤        │           suppressors)     │
 │        │                                 │   │        ▼                            │
 │        ▼                                 │   │  AwarenessPrompt (build one turn)   │
 │  AgentSession  (one long-lived           │   │  AgentTurnEncoder (stdin lines)     │
 │  `claude -p --input-format stream-json`) │   │  AgentEvent (decode)                │
 │        │                                 │   │  Suggestion (structured output)     │
 │        ▼                                 │   │                                     │
 │  PanelController ──► WKWebView (React)   │   │                                     │
 └──────────────────────────────────────────┘   └─────────────────────────────────────┘
```

Two capture paths, not one. They are joined by mach host time, not by a shared device. A single `AVAudioEngine` has exactly one input device on macOS, so it cannot read the microphone and the tap aggregate device at the same time.

---

## Conflicts resolved

CI is continuous integration. AX is Accessibility. TCC is Transparency, Consent and Control. SDK is Software Development Kit. API is Application Programming Interface. CLI is command line interface.

| Research said | We do | Why |
|---|---|---|
| `CATapDescription.init(stereoGlobalTapButExcluding:)` | `init(stereoGlobalTapButExcludeProcesses: [AudioObjectID])` | The review is right; I confirmed line 449 of the CoreAudio swiftinterface in the macOS 26.5 SDK. The research spelling does not compile. |
| Aggregate device needs taps, uid, name, private, drift | Also `kAudioAggregateDeviceMainSubDeviceKey` ("master") and `kAudioAggregateDeviceSubDeviceListKey` ("subdevices") | The review is right; both keys are in `AudioHardware.h` lines 1583 and 1592. Without a clock source the IO proc never fires and it looks exactly like a permission failure. |
| Build a `PCMChunk` inside the IO block | The IO block copies raw `Float32` into a pre-allocated ring and returns | The review is right; the research contradicted itself. `PCMChunk` holds `[Float]`, and allocating on the audio thread stutters the user's call, not just our recording. |
| `setVoiceProcessingEnabled(true)` removes the other person's voice from the microphone | Keep it, connect input to the main mixer at volume 0, but treat text-level de-duplication as the real defence | Both reviews are right in different ways. Voice processing needs a rendering graph to engage at all, and even then it cancels what *our* engine renders, not what Chrome renders. Do not build the speaker labels on it. |
| `installTap(onBus:bufferSize:format:)` with the 16 kHz target format | Install with `inputNode.outputFormat(forBus: 0)` read *after* enabling voice processing, then convert | The review is right; a format mismatch raises an Objective-C exception that Swift cannot catch and kills the app. |
| A `static var isSupported` on an `@available(macOS 26.0, *)` type | A separate ungated `SpeechSupport` enum | The review is right and reproduced the compiler error. |
| If asset status is not `.installed`, call `downloadAndInstall()` | Call `AssetInventory.reserve(locale:)` first, then check status, and release on teardown | The review is right; `reserve(locale:)` exists in the SDK. Without it, status never reaches `.installed` and the app re-downloads on every launch. |
| Call `finalize(through:)` every 5 seconds | Only finalize when the session stops | The review is right; forcing a boundary strips the context the model uses to correct itself, which is the same fault the research used to reject `SFSpeechRecognizer`. |
| Volatile results replace an earlier result over the same range | One finalized string per stream plus one replaceable volatile tail, driven by `volatileRange` | The review is right; range-equality matching duplicates text. |
| `AnalyzerInput(buffer:)` plus `.timeIndexedProgressiveTranscription` aligns the two streams | `AnalyzerInput(buffer:bufferStartTime:)` with a common host clock | The review is right; each analyzer's own timeline starts at zero, so the attribute alone aligns nothing. |
| `AXStartTextMarker` / `AXEndTextMarker` via `AXUIElementCopyParameterizedAttributeValue` | Plain `AXUIElementCopyAttributeValue` for the two markers; parameterized only for the range and the string | The review is right; as written the page-text path always fails. |
| Register `AXValueChanged` and `AXSelectedTextChanged` on the application element | Register those two on the focused element only, re-registering on focus change | The review is right; app-wide value changes are a flood from any live page, and debouncing removes the reads but not the cost of receiving them. |
| "All AX calls stay on the main thread — the API requires it" | A dedicated thread with `RunLoop.current.run()`, plus `AXUIElementSetMessagingTimeout(0.25)` | Both reviews are right. AX reads are synchronous cross-process messages; on the main thread one busy app freezes the panel. A plain `DispatchQueue` has no run loop, so an observer added there never fires. |
| `ContextDebouncer` emits after 400 ms of quiet, no timers | Also a maximum wait of about 1.5 s, and `readyToRead` returns the next check time so one `Timer` can be scheduled | The review is right; a pure quiet-window debounce never fires while someone types steadily, which is exactly when they ask a question. |
| Append the screen-context instruction to `DefaultSystemPrompt.text` | Assemble it at command-build time | The review is right; `Settings.systemPrompt` is persisted, so editing the default only reaches fresh installs. |
| `--json-schema` returns the answer as assistant text | Decode `structured_output` on the `result` line, and the `StructuredOutput` tool-use block | The review is right and ran it. As written the awareness lane would return nothing. `result` is the empty string. |
| Use a stable `--session-id` | Fresh UUID per session; reuse `--resume` for continuity | The review is right; a second use of the same id exits with a plain-text error that our JSON decoder drops silently. |
| Screenshots via a scratch folder and the `Read` tool | Same, plus `--add-dir <scratch>` | The review is right; the CLI runs with the repo as its working directory, so a file outside it is refused. I confirmed `--add-dir` exists in Claude Code 2.1.27. |
| Trim tools with `--tools ""` to save tokens | Never trim tools | Both agree; it disables prompt caching and `StructuredOutput` is itself in the tools list. |
| Prompt cache goes cold after 5 minutes | Cache is `ephemeral_1h` | The review is right; this risk was overstated. |
| Conversation files at 0755 let other local users read them | Set 0700 anyway, but the real controls are retention, redaction and a delete action | The review is right; `~/Library` is already `drwx------`, so the stated reason was false. |
| Edit `/opt/homebrew/Library/Taps/.../companion.rb` | Edit the `SouhaibBenFarhat/homebrew-tap` repo | The review is right; the local path is a clone that `brew update` overwrites. |
| `AudioHardwareCreateProcessTap` needs macOS 14.4 | The symbol is macOS 14.2; the TCC service arrived in 14.4 | The review is right; I confirmed `API_AVAILABLE(macos(14.2))` in `AudioHardwareTapping.h`. Treat 14.4 as the practical floor for capture. |
| Raise `LSMinimumSystemVersion` to gate the new symbols | Keep it at 14.0 and use `if #available` everywhere | The review is right; the plist is a launch check, and SwiftPM has no `.v14_2`. |
| `CallTarget` decides between a global tap and a per-process tap | One helper that names the app currently playing; always a global tap excluding ourselves | The review is right; every documented rule fell through to the global branch, so the other branch was unreachable. |
| `AudioTimeline` models per-stream latency offsets in detail | Keep the host-time conversion and the ordered merge, one constant offset per stream defaulting to zero | The review is right; tens of milliseconds are below the resolution of segments hundreds of milliseconds long. |
| Raise `SessionLog.pruneEvery` because awareness logs more | Log awareness far less | The review is right; a bigger prune interval makes the file larger between rewrites, not smaller. |
| `codex exec` has no streaming input, so Codex cannot host a long session | Codex has `app-server`, and `thread/inject_items` works | Both reviews are right. Claude Code is still first, because that is where the subscription is, but say it is a choice and not a limit of the tool. |

---

## Decisions to make before starting

Six real forks. TCC is Transparency, Consent and Control. CI is continuous integration.

**1. Get a Developer ID certificate now, or ship ad-hoc and accept re-granting?**
Recommendation: get it now, before any capture code. Today the app asks for no permissions, so the ad-hoc signature costs nothing. The moment it asks for four, every `brew upgrade` breaks them. Cost is 99 US dollars a year plus a day of CI work. This is the first milestone for a reason.

**2. Does the `macos-26` GitHub runner label exist and is it stable?**
Recommendation: confirm before Milestone 3, not during it. If it does not exist, transcription is blocked — the macOS 15 SDK has no `SpeechAnalyzer`, and an availability check does not make an unknown type compile. Fallback is a self-hosted runner for the release job only.

**3. Accept the macOS recording indicator in the shared screen, or drop capture?**
Recommendation: accept it and be loud about it. `NSWindow.sharingType = .none` hides the panel; it does nothing about the menu bar indicator, and the menu bar is inside the shared screen. There is no supported way to hide it. Change the README, put a red dot in the menu bar icon while listening, and show a banner in the panel. This is honest and it also happens to be the legal answer.

**4. Transcription floor: macOS 26 only, or build an `SFSpeechRecognizer` fallback for 14 and 15?**
Recommendation: macOS 26 only. The older path needs a fourth permission, restarts every minute on the server route, and cannot promise on-device. Users on macOS 14 and 15 keep the app they have today; the listening button is disabled with an honest reason.

**5. Awareness persona: append to the coding-agent prompt, or replace it?**
Recommendation: start with `--append-system-prompt` plus structured output, because the cached 19,700-token prefix makes each turn nearly free. Measure `speak:false` discipline on ten real calls. If the coding-agent persona keeps overriding the instruction, switch to `--system-prompt` and pay full price per turn. Write the number down either way.

**6. First release: transcript only, or suggestions on?**
Recommendation: ship Milestones 0 to 5 with `suggestionsEnabled = false`. A tool that interrupts a live call with something obvious gets switched off after one meeting. Turn it on in a later release once the thresholds are tuned against real calls.

---

## Milestone 0 — A signature that survives an upgrade

**Done when:** you install a build from the tap, grant Microphone in System Settings, install a second build from a different commit, and the grant is still there with no second prompt. `swift run Companion` also carries an Info.plist, so development prompts name Companion instead of your terminal.

TCC is Transparency, Consent and Control. It keys every grant to the code signature. `codesign --force --sign -` produces a new identity on every compile, so today's designated requirement is `cdhash H"98d16ec3…"` — a hash of the binary.

**Files to change**

- `packaging/Companion.entitlements` (new). One key: `com.apple.security.device.audio-input`. Deliberately absent: `com.apple.security.app-sandbox` (the app spawns arbitrary CLIs and reads the user's repos) and `com.apple.security.get-task-allow` (notarization rejects it). Put a comment in the file saying why.
- `packaging/Info.plist`. Add `NSMicrophoneUsageDescription`, `NSAudioCaptureUsageDescription`, `NSSpeechRecognitionUsageDescription`, `NSDesktopFolderUsageDescription`, `NSDocumentsFolderUsageDescription`, `NSDownloadsFolderUsageDescription`. There is no plist key for Screen Recording or Accessibility — do not invent one. Leave `LSMinimumSystemVersion` at 14.0.
- `scripts/build-app.sh`. Replace line 39 with a signing step that reads `$SIGNING_IDENTITY` and runs `codesign --force --options runtime --timestamp --entitlements packaging/Companion.entitlements --sign "$SIGNING_IDENTITY"`. Keep an ad-hoc fallback for local work with a loud warning. Then verify: `codesign --verify --strict`, print `codesign -d -r-`, and assert `get-task-allow` and `app-sandbox` are absent. Do not put `--deep` in the signing command; verification only.
- `.github/workflows/release.yml`. Import the Developer ID certificate into a temporary keychain, build with `SIGNING_IDENTITY`, `xcrun notarytool submit --wait` with an App Store Connect API key, `xcrun stapler staple` the `.app`, **re-zip with `ditto`, then recompute the sha256** (line 49 currently hashes the pre-staple zip), upload with `--clobber`, then bump the tap. Delete the keychain in an `if: always()` step.
- `.github/workflows/tests.yml`. Keep ad-hoc for pull requests. Add a shell check that the plist keys exist in `dist/Companion.app/Contents/Info.plist` and each value is longer than 20 characters.
- `Package.swift`. Embed the plist into the development binary: `linkerSettings: [.unsafeFlags(["-Xlinker","-sectcreate","-Xlinker","__TEXT","-Xlinker","__info_plist","-Xlinker","packaging/Info.plist"])]` on the `Companion` target. Without this, `swift run Companion` produces a bare binary with no usage strings and audio work cannot be tested in development at all.
- `Sources/Companion/AgentRunner.swift`. Three fixes. Line 59 logs the whole argument list, which puts the user's question on disk verbatim. Line 65 logs 60 characters of `ANTHROPIC_API_KEY`. Line 86 logs the first 160 characters of every output line, which is answer text — the comment above it claiming the file is safe to paste into an issue is already false. Log flag names, argument counts and decoded event types. While in this file, fix the data races: `failure` is written on the timer queue and read on main, `outputBuffer` is appended on the pipe queue and flushed on main, `process` is touched from both. Capture callbacks will make all three worse.
- `Sources/CompanionCore/Redaction.swift` (new, pure). Masks API keys, bearer tokens, private key blocks, long base64 runs, and `KEY=value` lines. Used by the log now and by the transcript later.
- `Sources/CompanionCore/SessionLog.swift` and `Sources/CompanionCore/ConversationStore.swift`. Run every line through `Redaction.scrub`. Create the directory with POSIX permissions `0o700`. Note in the comment that `~/Library` is already private, so this is defence in depth and not the main control.
- `README.md`. State the real floors: the app runs on macOS 14, capture needs 14.4, transcription needs 26.

**CompanionCore vs Companion:** only `Redaction.swift` is pure. Everything else is packaging and one existing impure file.

**Unit tests**

- `Tests/CompanionCoreTests/RedactionTests.swift` — each secret shape masked; ordinary code and ordinary sentences untouched. The false-positive cases matter more than the misses.
- `Tests/CompanionCoreTests/SessionLogTests.swift` — add a case asserting a known prompt string never appears in a formatted line.
- Shell assertions in `tests.yml` for the plist keys and the entitlements.

**Device only:** the grant-survives-upgrade test (sign build A, grant, sign build B from another commit with the same certificate, `brew upgrade`, confirm no prompt); notarization; stapling; installing from the tap on a clean machine.

---

## Milestone 1 — Permission doctor

**Done when:** the menu bar has a "Permissions…" item. It opens the panel on one row per permission with the live state, a button that opens the exact System Settings pane, and a "Quit and reopen" action for Screen Recording. Nothing is captured yet.

**Files**

CompanionCore (pure):
- `Sources/CompanionCore/Permissions.swift` (new). `PermissionKind` (`microphone`, `systemAudio`, `screenRecording`, `accessibility`, `speechRecognition`), `PermissionState` (`notDetermined`, `denied`, `granted`, `needsRelaunch`), a sentence per state, a System Settings URL per kind, and `missing(for: AwarenessSettings)` so a user is never asked for a permission the current settings do not need.

Companion (system):
- `Sources/Companion/PermissionCoordinator.swift` (new). Reads without prompting: `AVCaptureDevice.authorizationStatus(for: .audio)`, `CGPreflightScreenCaptureAccess()`, `AXIsProcessTrusted()`, `SFSpeechRecognizer.authorizationStatus()`. For system audio there is no preflight, so probe once by attempting a tap and reading the `OSStatus`. Poll on a slow timer (3 to 5 seconds) plus `NSWorkspace.didActivateApplicationNotification`, off the main thread, hop back to main to publish. Never branch on the return value of `CGRequestScreenCaptureAccess()` — it reports the state before the user answers.
- `Sources/Companion/PanelController.swift`. New outbound `permissions` message. New inbound `requestPermission`, `openPermissionSettings`, `relaunchApp`. Cap `queued` (line 158 grows without limit while `isReady` is false) at a few hundred entries and drop the oldest.
- `Sources/Companion/AppDelegate.swift`. Menu item next to "Choose repo…".

Web:
- `web/src/lib/types.ts`, `web/src/App.tsx`, `web/src/components/PermissionsNotice.tsx` (new). Reuse `Surface`, `Notice`, `Button`.

**Unit tests**

- `Tests/CompanionCoreTests/PermissionsTests.swift` — every state maps to a non-empty sentence and a valid URL; `screenRecording` maps to `needsRelaunch` after a request; `missing(for:)` names only what the settings require.

**Device only:** whether a TCC alert raised by a non-activating accessory app appears in front of a full-screen call app; the exact wording of the system-audio prompt; whether `x-apple.systempreferences` has a working anchor for the audio-capture pane (the Microphone, Accessibility, Screen Recording and Speech Recognition anchors are known; this one is a guess).

---

## Milestone 2 — Two live audio streams

**Done when:** the menu bar has "Start listening". The panel shows two live level meters, "You" and "The call", and names the app currently playing. The menu bar icon shows a red dot while listening. Stopping returns both meters to zero and destroys the tap and the aggregate device. No audio is written to disk, ever.

PCM is pulse code modulation. IO is input and output.

**Files — CompanionCore (pure)**

- `PCMChunk.swift` (new). `CaptureSpeaker { case me, them }` and `PCMChunk { speaker, hostTimeNanoseconds, frameCount, sampleRate, samples: [Float] }`.
- `AudioRingBuffer.swift` (new). Fixed capacity, pre-allocated `Float` storage, atomic read and write indices, sized for a few hundred milliseconds. The IO block only copies bytes and bumps an index. `PCMChunk` is built on the consumer side.
- `SpeechSegmenter.swift` (new). Energy plus a hangover window, one instance per stream. Powers the meters and the "user is talking" suppressor. It does not decide transcript boundaries — the Speech framework does that in Milestone 3.
- `EchoGate.swift` (new). Compares microphone energy against tap energy at a searched delay and reports which "me" segments look like a delayed copy. Take the delay as a parameter and search a window: built-in speakers are roughly 30 to 60 ms, Bluetooth is commonly 150 to 300 ms.
- `AudioTimeline.swift` (new). Host time in nanoseconds to session-relative seconds, one constant offset per stream defaulting to zero, and an ordered merge of two labelled segment lists.
- `CaptureRestartPolicy.swift` (new). Collapses a burst of device-change notifications into one rebuild.
- `AwarenessSettings.swift` (new). `enabled`, `captureMicrophone`, `captureSystemAudio`, `echoCancellationEnabled` (default true), `transcriptWindowSeconds` (default 300), `persistTranscript` (default false). Every field through `decodeIfPresent` with a default.
- `Settings.swift`. One new field, `awareness: AwarenessSettings`, defaulted in the memberwise init and read with `decodeIfPresent`. One nested field, not ten flat ones — `Settings` already has eleven. Also add a pure `hotKeyChanged(from:)` so `AppDelegate.registerHotKey()` stops tearing down the global shortcut on every keystroke in the settings sheet.

**Files — Sources/Companion (system)**

- `AudioProcessRegistry.swift` (new). Reads `kAudioHardwarePropertyProcessObjectList`, maps each object to pid, bundle identifier and `kAudioProcessPropertyIsRunningOutput`, and finds our own object via `kAudioHardwarePropertyTranslatePIDToProcessObject` with `getpid()`. Handle `kAudioObjectUnknown` — if Companion has never played a sound its object may not exist yet, and passing a garbage id is worse than an empty exclusion list. Note in the code that `isRunningOutput == 1` means "holds an active output stream", not "making sound now", so the panel label is approximate.
- `ProcessTapRecorder.swift` (new). `CATapDescription(stereoGlobalTapButExcludeProcesses: [ourObject])`, `isPrivate = true`, `muteBehavior` left at `.unmuted` — any other value silences the user's call. Create the tap, read `kAudioTapPropertyUID` and `kAudioTapPropertyFormat` (never assume the format), then build a private aggregate device with `taps`, `uid`, `drift`, `private = 1`, **`master` set to the current default output device's UID**, and `subdevices` as an empty array. Drive it with `AudioDeviceCreateIOProcIDWithBlock`. Inside the block: copy raw floats into the ring, take `inInputTime.pointee.mHostTime`, return. No allocation, no locks, no logging. Passing a dispatch queue does not make the block safe — the header says all IO blocks are dispatched synchronously. Make the block weak. Store every `AudioObjectAddPropertyListenerBlock` return value so it can actually be removed. At launch, sweep `kAudioHardwarePropertyTapList` and destroy anything with our name prefix left by a crash; also sweep aggregate devices.
- `MicrophoneRecorder.swift` (new). Order matters: check the permission first (before the grant, `inputNode.outputFormat` reports 0 Hz and installing a tap throws), stop the engine, `setVoiceProcessingEnabled(true)`, set `voiceProcessingOtherAudioDuckingConfiguration` to the mildest level so the call does not get quieter, connect `inputNode` to `mainMixerNode` and set `mainMixerNode.outputVolume = 0` so voice processing can engage without the user hearing themselves, `engine.prepare()`, **then** read `inputNode.outputFormat(forBus: 0)` and pass that exact format to `installTap`. Subtract `presentationLatency` from the timestamp. Fall back to plain capture and log the reason if voice processing throws.
- `CallCapture.swift` (new). Owns both recorders, converts each stream to 16 kHz mono off the audio thread with its own `AVAudioConverter`, rebuilds both paths on a debounced device change. Listen to `kAudioHardwarePropertyDefaultOutputDevice`, `kAudioHardwarePropertyDefaultInputDevice` **and** `Notification.Name.AVAudioEngineConfigurationChange` — the engine has its own contract and will silently stop delivering microphone buffers if it is ignored. Cap memory: 16 kHz mono `Float32` is roughly 230 MB (megabytes) per stream per hour, so define a drop policy.
- `AppDelegate.swift`. Start/stop menu item, launch sweep, teardown in `applicationWillTerminate`.
- `StatusIcon.swift`. A listening variant.

**Web:** `web/src/components/AwarenessBar.tsx` (new), `types.ts`, `App.tsx`. Send levels as their own message type. Never through `state` — `App.tsx` calls `resetStreaming()` on every `state` payload and would wipe a half-drawn answer each time somebody spoke.

**Unit tests**

- `AudioRingBufferTests.swift` — wrap-around, overflow drops the oldest, partial read.
- `PCMChunkTests.swift` — duration arithmetic, round trip.
- `SpeechSegmenterTests.swift` — silence only; one utterance; a 200 ms gap stays one segment; a 2 s gap splits; a stream ending mid-utterance flushes.
- `EchoGateTests.swift` — a delay sweep at 40 ms, 150 ms and 300 ms; microphone energy while the tap is silent is kept; both talking at once is kept.
- `AudioTimelineTests.swift` — overlap, exact abutment, out-of-order arrival.
- `CaptureRestartPolicyTests.swift` — a burst of five notifications in 20 ms yields one rebuild.
- `AwarenessSettingsTests.swift` and an addition to `SettingsTests.swift` — an old settings file with no `awareness` key decodes to defaults.

**Device only:** every Core Audio call; whether a running tap lights an indicator in Control Center (this decides whether the tap really beats ScreenCaptureKit); the click test for host-time alignment; unplugging headphones mid-call; switching to a Bluetooth headset; whether `setVoiceProcessingEnabled` succeeds while Meet or Zoom already holds voice processing on the same device.

---

## Milestone 3 — A live transcript, two speakers

**Done when:** with listening on, the panel shows a two-column live transcript. Unsettled text is visibly marked. Nothing is written to disk unless the user turns persistence on. The first item in this milestone is the CI move, before any Speech code is written.

VAD is voice activity detection.

**Files**

CI first:
- `.github/workflows/tests.yml` (jobs `test` at line 13 and `build` at line 23) and `.github/workflows/release.yml` (line 18): move from `macos-15` to `macos-26` and pin Xcode explicitly with `sudo xcode-select -s /Applications/Xcode_26.app`. The macOS 15 SDK has no `SpeechAnalyzer`, and `if #available` does not make an unknown type compile. Job names `test` and `build` are wired into branch protection — do not rename them.

CompanionCore (pure):
- `TranscriptBuffer.swift` (new). Per speaker: one finalized string plus one replaceable volatile tail. Times as `Double` seconds, not `CMTimeRange` — every sibling type here is `Codable` and `CMTimeRange` is not. A time window that prunes old text, a `lastSentIndex` watermark with `delta()`, a `recentWindow(seconds:)` for the trigger layer, and a `text(window:)` renderer producing "You: … / Them: …" lines under a character budget.
- `TranscriptDedupe.swift` (new). Drops a "me" utterance that closely matches a "them" utterance within the same short time window. This, not echo cancellation, is what stops the other person's words appearing twice when the user is on speakers.
- `Redaction.swift`. Extend: every utterance passes through it before it reaches an agent or a log.

Companion (system):
- `SpeechSupport.swift` (new, **not** `@available`). `static var isSupported: Bool { if #available(macOS 26.0, *) { return SpeechTranscriber.isAvailable }; return false }`. This is the type the menu bar and the panel ask.
- `Transcriber.swift` (new, `@available(macOS 26.0, *)`). One instance per stream. Order: `SpeechTranscriber.supportedLocale(equivalentTo:)` to map the user's locale, `AssetInventory.reserve(locale:)`, then `AssetInventory.status(forModules:)`, then `assetInstallationRequest(supporting:)` plus `downloadAndInstall()` with its `Progress` shown in the panel, then `SpeechAnalyzer.prepareToAnalyze(in:)` so the first seconds of the call are not swallowed. Convert audio to `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)` — measured as 16 kHz mono Int16 interleaved — and pass a common `bufferStartTime`. Add `SpeechDetector` to the same analyzer for VAD (voice activity detection); its asset is already installed. Feed input through a **bounded** `AsyncStream` (`.bufferingNewest`), never the unbounded default. Release the reserved locale on teardown; the machine allows five.
- `PanelController.swift`. Mark it `@MainActor`. Speech results arrive from an actor, and `evaluateJavaScript` plus `queued`, `isReady` and `pendingAnswer` are all main-thread state today with no synchronisation. Coalesce transcript pushes to about four a second and drop them entirely while the panel is hidden.

Web: `web/src/components/TranscriptView.tsx` (new) plus the `Incoming` union and the switch in `App.tsx`. The bridge is typed, so an unhandled message type is a compile error — which is the point.

**Unit tests**

- `TranscriptBufferTests.swift` — the volatile tail is replaced, not appended; the tail shrinks when the finalized region grows; the window drops the oldest; the watermark advances exactly once per delta; two speakers interleave by time.
- `TranscriptDedupeTests.swift` — an exact repeat within 2 s is dropped; the same words 30 s apart are kept; a genuine agreement ("yes, exactly") is kept.
- Extend `RedactionTests.swift` for transcript-shaped input.

**Device only:** the asset download on a machine that has never used dictation; real accuracy on a compressed call with two accents; whether `localspeechrecognition` memory stays flat over a full hour; whether `SpeechAnalyzer` asks for the Speech Recognition permission inside a signed bundle (the earlier test fed a file, so it proved nothing). Do not put a live `SpeechAnalyzer` test into `swift test` — a fresh runner has no model and the job would download hundreds of megabytes or hang. Gate any fixture test behind an environment variable.

---

## Milestone 4 — Ask about the call

**Done when:** mid-call you press the hotkey, type "what did they just ask me?", and get an answer that uses the last few minutes of the transcript. There is also a one-tap "Ask about the last minute" button. This is the first point where the feature earns its place, and it uses the existing per-question `AgentRunner`.

**Files**

CompanionCore (pure):
- `AwarenessPrompt.swift` (new). `DefaultAwarenessPrompt.text` — the standing instruction — plus `buildTurn(reason:transcript:context:budget:)` that assembles one turn under a character budget, drops the oldest transcript first, and always keeps the reason.
- `AgentCommand.swift`. Assemble the awareness instruction into `--append-system-prompt` at build time. Do not edit `DefaultSystemPrompt.text`: `Settings.systemPrompt` defaults to it and is then persisted, so an edit reaches new installs only.
- `Conversation.swift`. Add `origin: MessageOrigin` (`.asked`, `.unprompted`) to `Message` with a defaulting decode, so old conversation files keep loading.

Companion:
- `PanelController.swift`. In `ask()` (line 222), prepend the transcript block when listening is on. Add `origin` to the messages array inside `sendState()` (line 209) — adding it to the TypeScript type alone leaves it permanently undefined at runtime while `tsc` still passes.

Web: `types.ts` (`origin` on `Msg`), `MessageList.tsx` styling.

**Unit tests**

- `AwarenessPromptTests.swift` — the built turn stays under budget; the oldest transcript is dropped first; the reason always survives; redacted content never appears.
- Additions to `AgentCommandTests.swift` — the awareness instruction is appended and the stored `systemPrompt` is preserved.
- Additions to `ConversationTests.swift` — an old conversation JSON decodes with `origin == .asked`; a kept suggestion never becomes the conversation title.

**Device only:** answer quality.

---

## Milestone 5 — Screen awareness through Accessibility

**Done when:** the panel shows a "Looking at" strip naming the app, window and file or URL, updating as you move around, with a switch to turn it off for the session and a view showing exactly the text that would be sent. Answers can name the file you are on without you pasting it.

AX is Accessibility.

**Files — CompanionCore (pure)**

- `ScreenContext.swift` (new). `appName`, `bundleIdentifier`, `processIdentifier`, `windowTitle`, `url`, `filePath`, `selectionText`, `textExcerpt`, `source` (`axDocument`, `axWebArea`, `titleParse`, `diskRead`, `pixels`), `capturedAt`, plus `promptBlock()` and a freshness check.
- `ContextDebouncer.swift` (new). `record(kind:at:)` and `readyToRead(now:) -> Decision`, where the decision also carries the next check time so one `Timer` can be scheduled. Short settle for app switches (about 120 ms), long for value changes (about 600 ms), a hard floor of one read per 250 ms per app, **and a maximum wait of about 1.5 s** so continuous typing still produces reads.
- `WindowTitleParser.swift` (new). Per app family. VS Code and Cursor use `${dirty}${activeEditorShort}${separator}${rootName}${separator}${profileName}${separator}${appName}` with ` — ` as the separator, which gives a bare file name and a folder name, never a path. Xcode gives `File.swift — Project`. JetBrains gives `project – path/to/file`. Output is `fileName`, `workspaceName`, `isDirty`, plus a resolver that searches the configured repo and returns a path only on an exact single match.
- `AXTraversal.swift` (new). The budget and ordering policy over an abstract node protocol: breadth-first, node budget 400, depth cap 20. Depth-first from a Chrome window burns the whole budget inside the tab strip and never reaches the web area. Putting this here is what makes it testable — `Package.swift` has one test target and it depends on `CompanionCore` only.
- `Redaction.swift`. Extend with the context rules: drop a context whose focused subrole is `AXSecureTextField`; **check the deny-lists against the full URL first**, then strip query, fragment and user info; blank the whole context for password managers, banking and health apps, and for any path containing login, signin, password, reset, oauth or token; cap the excerpt and strip `U+FFFC` padding.
- `AwarenessSettings.swift`. Add `observeScreen` (off), `captureText` (off), `allowElectronAccessibility` (off), `deniedBundleIdentifiers`, `deniedHosts`.

**Files — Sources/Companion (system)**

- `AccessibilityAccess.swift` (new). Copy Island's version (`isTrusted`, `prompt`, `openSettings`) and add `classify(_ error: AXError)` mapping `-25211` to permission missing, `-25205`/`-25208` to unsupported by app, `-25202` to element gone, `-25212` to no value. When `AXIsProcessTrusted()` is false, treat `-25204` as permission missing too.
- `AXElement.swift` (new). Typed reads returning a `Result` that carries the `AXError`. Call `AXUIElementSetMessagingTimeout(element, 0.25)` on every application element and once on the system-wide element. Without it, one busy Chrome blocks each read for the system default and the panel freezes.
- `AXAppObserver.swift` (new). One `AXObserverCreateWithInfoCallback` per process. On the **application** element register only `AXFocusedUIElementChanged`, `AXFocusedWindowChanged`, `AXMainWindowChanged`, `AXTitleChanged`, `AXApplicationActivated`, `AXUIElementDestroyed`. Register `AXValueChanged` and `AXSelectedTextChanged` on the **focused element only**, re-registering on every focus change. Add the run loop source in `CFRunLoopMode.commonModes` — the app runs `NSOpenPanel.runModal()` and a status menu, and both push a different mode. Retry registration with backoff: a freshly launched app answers `-25204` for a few hundred milliseconds. Guard against observing our own pid, which returns `-25208`. On teardown do all three of: remove each notification, remove the run loop source in the same mode, release the observer. Keep at most three observers alive.
- `AppFocusTracker.swift` (new). `NSWorkspace.didActivateApplicationNotification` and `didTerminateApplicationNotification` on `NSWorkspace.shared.notificationCenter`.
- `ScreenAwareness.swift` (new). The coordinator, running on its own `Thread` with `RunLoop.current.run()`. Cheap path first: frontmost app, focused window `AXTitle`, `AXDocument`. Only then the readers. "Is the user looking at Companion?" comes from `panel.isKeyWindow` and `NSWindow.didBecomeKeyNotification`, **not** from `NSWorkspace` — `ChatPanel` is a `.nonactivatingPanel` with `canBecomeMain` false, so Companion never becomes the frontmost application.
- `BrowserReader.swift` (new). Window `AXDocument` first (it is the live tab URL and costs about 0.026 ms). Otherwise walk **up** through `AXParent` from the focused element to find the `AXWebArea` — cheaper and deterministic than searching down. Page text: `AXUIElementCopyAttributeValue` for `AXStartTextMarker` and `AXEndTextMarker` (plain attributes), then `AXTextMarkerRangeForUnorderedTextMarkers` with a `CFArray` of the two, then `AXStringForTextMarkerRange`. Branch on the `AXError` at all three steps. Note that walking into the web area turns Chrome's renderer accessibility tree on, which costs the user's browser CPU — the window-level read does not.
- `EditorReader.swift` (new). Tier 1: native apps through window `AXDocument`. Tier 2: Electron through `AXManualAccessibility`, **off by default** — setting it flips VS Code's `code --status` to "Screen Reader: yes" and changes how the editor renders mid-call. Tier 3, the default for VS Code, Cursor and Slack: parse the title, resolve the file in the configured repo, read it from disk. Cap every text read: ask for a bounded range with `kAXStringForRangeParameterizedAttribute`, or read `kAXNumberOfCharactersAttribute` first and refuse above a limit. Terminal scrollback is megabytes.
- `PanelController.swift`. Wrap the context block in explicit delimiters and add one line to the assembled system prompt saying the block is observed data and never an instruction. `Settings.permission` can be `.acceptEdits`, so a code comment or a web page on screen can otherwise reach an agent that is allowed to write files.

**Web:** the "Looking at" strip in `AwarenessBar.tsx`, plus a view of the exact text that will be sent, with a per-question clear button.

**Unit tests**

- `ContextDebouncerTests.swift` — 20 value events 10 ms apart yield one read; an app switch cuts through a pending wait; the rate floor holds; **continuous events for 60 s still produce reads**; the returned next-check time is correct.
- `RedactionTests.swift` additions — every context rule with a positive and a negative case, and the ordering case where the deny-list must see the full URL.
- `WindowTitleParserTests.swift` — real titles for VS Code, Cursor, Xcode, IntelliJ, Terminal and Chrome, including single-match and multi-match resolution.
- `ScreenContextTests.swift` — prompt block for a full, a title-only and an empty context; freshness.
- `AXTraversalTests.swift` — budget, depth cap, breadth-first order over a fake tree.

**Device only:** every AX read; Safari and Xcode (both entirely unverified); VS Code with a window actually open; whether Chrome fires `AXTitleChanged` on a tab switch; the settle windows, which are guesses.

---

## Milestone 6 — One long-lived reasoning session

**Done when:** follow-up answers in the typed panel start streaming in about a second instead of five, because the agent process is already warm. The panel shows a "Session" row with a Stop button.

JSON is a text format for data. UUID is a universally unique identifier.

**Files — CompanionCore (pure)**

- `AgentTransport.swift` (new). A protocol with `send(turn:)`, `interrupt()`, `stop()` and an event stream, so a Codex `app-server` implementation can be added later without touching the coordinator.
- `AgentTurnEncoder.swift` (new). Two exact line shapes, both verified: `{"type":"user","message":{"role":"user","content":[{"type":"text","text":"…"}]}}` and `{"type":"control_request","request_id":"…","request":{"subtype":"interrupt"}}`.
- `Suggestion.swift` (new). Decodes `{speak, confidence, text}`, tolerating a fenced code block.
- `AgentCommand.swift`. Add `buildStreamingSession(...)`: `-p`, `--input-format stream-json`, `--output-format stream-json`, `--verbose` (required — the CLI refuses to start without it), `--model`, `--append-system-prompt`, `--json-schema`, `--add-dir <scratch>`, and the existing permission flags. A fresh UUID per session, never a reused `--session-id`. No `--tools ""`. No `--include-partial-messages` on this lane: with a schema there is no streamed text.
- `AgentEvent.swift`. New cases `.structuredResult(Data)`, `.turnFinished(usage:)`, `.turnInterrupted`. Handle `structured_output` on the `result` line and treat a `tool_use` block named `StructuredOutput` as the answer, not as a tool. `error_during_execution` after an interrupt is normal, not a crash. A `system`/`init` line now arrives at the start of **every** turn. A line that is not JSON must surface as a failure instead of being dropped — that is how `Error: Session ID … is already in use.` currently disappears.

**Files — Sources/Companion (system)**

- `AgentSession.swift` (new). Copy `AgentRunner` but keep a writable stdin `Pipe` instead of `FileHandle.nullDevice` (line 74), and explicitly **remove** the 300-second deadline and the `watchForFailure` call to `process?.terminate()` — both would kill a live call brain. Write on a private serial queue with the throwing `write(contentsOf:)`. A supervisor restarts a dead child and re-seeds it from `TranscriptBuffer`.
- `main.swift`. `signal(SIGPIPE, SIG_IGN)` at startup. Writing to a dead child's stdin otherwise kills Companion mid-call.
- `PanelController.swift`. The typed panel and the awareness lane are separate sessions. `ask()` guards on `!runner.isRunning` (line 224), so one shared runner would make the panel report "busy" whenever awareness was thinking.

**Unit tests**

- `AgentTurnEncoderTests.swift` — encode and compare against the two literal strings.
- `AgentEventTests.swift` additions — a real `result` line with `"result":""` and a populated `structured_output`; an interrupt result; a plain-text error line becoming a failure; a repeated `system`/`init`.
- `AgentCommandTests.swift` additions — `--verbose` present, `--tools` absent, `--add-dir` present and pointing outside the repo, a valid lowercase UUID.
- `SuggestionTests.swift` — clean, fenced and malformed.

**Device only:** whether one process stays healthy for a two-hour call; memory and file handles; what the CLI's own compaction does to the transcript watermark; how a suggestion-per-minute cadence consumes the subscription window.

---

## Milestone 7 — Companion speaks on its own

**Done when:** during a call, Companion posts a suggestion card at most once a minute, clearly marked as something it noticed rather than an answer you asked for, with Keep and Dismiss. It stays quiet while you are speaking or typing. It ships off by default.

**Files — CompanionCore (pure)**

- `TurnTrigger.swift` (new). `endOfUtterance`, `questionDetected`, `nameSpoken`, `screenSettled`, `hotkey`, `silenceAfterQuestion`, each with a priority, plus a cheap local classifier over the last finalized utterance. This layer is what keeps most events from ever reaching the model.
- `SuggestionGate.swift` (new). Hard suppressors (user speaking in the last 1.5 s, key down within 2 s, a turn already running, an unread suggestion on screen), a token bucket of one per 60 s with burst 2, a per-call cap, a confidence floor, and a novelty check that hashes suggestion text and suppresses near-duplicates for 10 minutes. Inject the clock and inject the "is the user typing" read as a closure — `CGEventSource.secondsSinceLastEventType` needs no Accessibility permission, which is why it is chosen, but it must not fire when the user is typing **into Companion's own panel**.
- `AwarenessState.swift` (new). `asleep`, `starting`, `listening`, `thinking`, `paused`, `needsPermission`, `failed`, with an explicit transition table, and `canWake` derived from `Permissions.missing(for:)`.
- `SessionLog.swift`. New categories: `awareness`, `capture`, `asr`, `screen`, `trigger`, `suggest`. Types and decisions only. Never transcript text, never screen text, never suggestion text. Log at a low rate; do not raise `pruneEvery`.

**Files — Sources/Companion (system)**

- `AwarenessCoordinator.swift` (new). Trigger in, gate, build the turn from `TranscriptBuffer.delta()` plus the reason, send, decode, gate again on confidence and novelty, hand to the panel. A higher-priority trigger interrupts the running turn — messages sent mid-turn are queued, not steered, so interrupt is required, not optional. Keep this type thin; every decision is a call into a tested pure type.
- `PanelController.swift`. `suggestion` is its own outbound message, delivered whole. Inbound `dismissSuggestion` and `keepSuggestion`. **`keepSuggestion` must not call `sendState()`** — that sends a `state` message, and `App.tsx` line 36 answers every one with `resetStreaming()`, wiping a half-drawn answer. Send a narrow `messageAppended` message instead.
- `StatusIcon.swift` and `AppDelegate.swift`. When the panel is hidden, an unread suggestion shows as a badge in the menu bar. The app has no Dock icon, so a suggestion delivered to a hidden panel is otherwise invisible.

**Web:** `SuggestionCard.tsx` (new) with a left rule, a "noticed" label and Keep / Dismiss; an Awareness group in `SettingsSheet.tsx` sent through its own `updateAwarenessSettings` message, because `apply` posts on every keystroke and every post writes the settings file.

**Unit tests**

- `TurnTriggerTests.swift` — a table of sentences to expected triggers.
- `SuggestionGateTests.swift` — bucket refill, cooldown boundary, hourly cap, duplicate suppression, a manual wake clearing the cooldown, the panel-has-focus exception to the typing suppressor.
- `AwarenessStateTests.swift` — illegal transitions refused; `canWake` false when any needed permission is missing; the missing list names only what the settings need.
- `SessionLogTests.swift` addition — feed lines containing a marker string and assert it never reaches the log.

**Device only:** whether it feels helpful or annoying. Every threshold named here — 700 ms silence, 1.5 s screen settle, one per 60 s, 0.7 confidence — is a starting guess.

---

## Milestone 8 — Look at my screen

**Done when:** a "Look at my screen" button takes one still frame of the focused window, and the answer refers to what is actually on it. The frame is deleted a few minutes later. Off by default, never automatic.

**Files**

CompanionCore (pure):
- `ScreenFrameGeometry.swift` (new). Window size to target size, aspect kept, long edge capped at 1024 points.
- `ScratchCleanup.swift` (new). Age-based deletion with an injected clock.

Companion:
- `ScreenFrame.swift` (new). `CGPreflightScreenCaptureAccess()` first so nothing prompts by surprise. Then `SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)`, match by process id and window id, `SCContentFilter(desktopIndependentWindow:)`, a small `SCStreamConfiguration`, `SCScreenshotManager.captureImage(contentFilter:configuration:)` (macOS 14.0; `captureImage(in:)` is 15.2 and `SCScreenshotConfiguration` is 26.0, so neither is usable). One image, no stream, no frame loop. Write the PNG (an image format) into a scratch directory that is passed to the CLI with `--add-dir`, never into the user's repo. After granting Screen Recording the app must relaunch before capture works, so show a "Quit and reopen" action rather than pretending it succeeded.

Do not push the image as a content block on the session's stdin. It is silently dropped: the model replies that it sees no image and the input token count does not move.

**Unit tests:** `ScreenFrameGeometryTests.swift`, `ScratchCleanupTests.swift`.

**Device only:** capture latency and memory; the recording indicator; relaunch behaviour.

---

## Risks and open questions

**1. The ad-hoc signature is the biggest defect, and it only appears after release.**
`scripts/build-app.sh` line 39 runs `codesign --force --sign -`. The designated requirement of the current build is `cdhash H"98d16ec3…"` — a hash that changes on every compile. TCC (Transparency, Consent and Control) stores a snapshot of that requirement with the grant and revalidates on every access. So every `brew upgrade` drops the grants. For Screen Recording and Accessibility it is worse than a re-prompt: System Settings keeps showing Companion with the switch on while the API returns false, so the user sees a permission they already gave and an app that says it does not have it. There is no in-app fix; they must remove and re-add the row. Fix this in Milestone 0 or do not start. Also confirm, before committing, that a tap even succeeds under an ad-hoc signature — if it does not, the certificate is a prerequisite and not a cleanup.

**2. The recording indicator is inside the shared screen.**
`ChatPanel.swift` line 34 sets `sharingType = .none`, which hides the panel. The menu bar indicator and the Control Center entry are drawn by the system and are captured. So is every TCC alert, System Settings window and the repo picker. The app's headline promise is that it stays out of the shared view; the moment listening starts, that stops being fully true. There is no supported way to suppress it. Say so in the README and in the panel, and never trigger a first-run permission flow mid-call.

**3. Consent is a legal question, not an ethical one.**
Companion transcribes the other person, who agreed to nothing. In Germany, recording the non-public spoken word without consent is a criminal offence under §201 StGB, and transcription is recording. Colleagues' voices are personal data under the GDPR (General Data Protection Regulation). Capture defaults to off, `persistTranscript` defaults to false, the panel shows a live indicator, and the README states it plainly. Whether that is enough is a question for a lawyer, not for this document.

**4. Speaker labels break without headphones.**
The tap stream is clean either way, because it copies what the app plays before it reaches the hardware. The microphone is not: on speakers it picks up the far end, so the other person's words appear twice, once labelled correctly and once as "you". Voice processing may or may not help — on macOS it cancels what our own engine renders, and Companion renders silence. `TranscriptDedupe` is the defence that must work. Test it with speakers at high volume.

**5. Doing real work on the audio thread stutters the user's call, not just our recording.**
The aggregate device shares the HAL's IO thread. Copy bytes into the ring buffer and return. A dispatch queue does not help; the header says all IO blocks are dispatched synchronously.

**6. Retain cycles keep the tap alive after the interface says it stopped.**
`AudioDeviceCreateIOProcIDWithBlock` copies and holds its block until `AudioDeviceDestroyIOProcID`. `installTap` holds its block until `removeTap`. `AudioObjectAddPropertyListenerBlock` holds its block until removed with the identical block object. A strong `self` in any of them means Companion keeps recording system audio after the user pressed Stop. That is the worst possible bug for this app.

**7. Two agent processes share one subscription window.**
The typed panel and the awareness lane both draw on the same Claude Max plan. A suggestion a minute for a two-hour call is roughly 120 turns on top of the user's own questions. Running out mid-call breaks the panel — the feature the app actually exists for. Add a shared budget and give the typed panel priority.

**8. Battery and CPU, next to a call that is already heavy.**
Two capture paths, two transcribers, an AX observer set and a long-lived subprocess. If the call stutters, Companion gets the blame whether or not it is at fault. Every path needs a cheap idle mode, and awareness defaults to off.

**9. Screen text goes into a prompt that can reach an agent allowed to write files.**
`Settings.permission` can be `.acceptEdits`. A README, a code comment or a web page visible on screen becomes model input. Wrap it in delimiters, say in the system prompt that it is observed data and never an instruction, and never let it be the whole prompt. Arguments are passed as argv, so there is no shell injection — this is a different problem.

**Open questions, in the order they should be settled**

1. Does a running Core Audio process tap light an indicator? If it does, the main argument for choosing it over ScreenCaptureKit collapses. Test on a throwaway account before committing to the design.
2. Does the `macos-26` runner exist and what Xcode does it default to? Everything in Milestone 3 depends on it.
3. Do TCC grants really survive a rebuild under Developer ID? The reasoning is sound and matches every shipping app inspected, but if it is wrong it is wrong in the field, for every user, at once. Prove it: sign build A, grant, sign build B from another commit with the same certificate and team, upgrade, confirm no prompt.
4. Does a TCC alert from a non-activating accessory app appear in front of a full-screen call app? If not, the only route is sending the user to System Settings, and the request APIs are never called.
5. Does `AssetInventory.status` reach `.installed` after `reserve(locale:)`? Run it once deliberately and watch the network — it may pull several hundred megabytes.
6. Does `--json-schema` survive an interrupt? An interrupted turn produces `error_during_execution` with no `structured_output`, so the decoder must tolerate its absence. Untested.
7. Does the microphone and tap in one aggregate device arrive in one IO proc call under one timestamp? If yes, the whole `AudioTimeline` problem disappears — at the cost of `AVAudioEngine` voice processing. Worth an hour before building two paths.
8. Safari and Xcode are entirely unverified for AX (Accessibility) reads. So is VS Code with a window actually open, and how much of a file it exposes.
9. Does `setVoiceProcessingEnabled(true)` succeed while the call app already holds voice processing on the same input device — and does it make the user sound worse to the other side? This fails only on a real call with a real second person, and the user finds out from them.
