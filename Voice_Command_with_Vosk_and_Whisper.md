# Voice Recognition Project Brief

This document describes the architecture, design decisions, and development plan for adding Vosk (sentence recognition) and Whisper (dictation) to the existing SAPI-based Voice Command system. All open questions have been resolved and are incorporated into the plan.

---

## Goal

Build a three-tier voice recognition system with AHK v2 as the main application and Python as a minimal bridge for Vosk and Whisper.

## Architecture

| Tier      | Engine                            | Purpose                                  | Latency                 | Example                                 |
| --------- | --------------------------------- | ---------------------------------------- | ----------------------- | --------------------------------------- |
| Commands  | **SAPI** (AHK native)       | Fixed short phrases that trigger actions | Instant                 | "Start Notepad++"                       |
| Sentences | **Vosk** (Python bridge)    | Open vocabulary, short spoken input      | Fast (~200ms)           | "I like to use Notepad++ for some text" |
| Dictation | **Whisper** (Python bridge) | Longer continuous speech to text         | Acceptable delay (1-3s) | Paragraphs, letters, notes              |

---

## Design Principles

- AHK v2 is the primary language — all GUI, logic, and actions stay in AHK. See `Voice_Command.ahk`
- Python is a **thin bridge only** — it handles speech recognition and sends text back to AHK
- The Python bridge is a **single script** handling both Vosk and Whisper
- The Python bridge **auto-starts** when the AHK app launches (Whisper model load takes 5–15s on CPU — on-demand start is impractical)
- Modes are **mutually exclusive**: only one engine owns the microphone at a time
- AHK controls which mode is active via TCP commands sent to the Python bridge

---

## Mode Management

Four modes, mutually exclusive:

| Mode    | Who owns mic | StatusCircle color | Label in circle        | Description                    |
| ------- | ------------ | ------------------ | ---------------------- | ------------------------------ |
| SAPI    | SAPI (AHK)   | Blue               | —                     | Default — command recognition |
| Vosk    | Python       | Green              | EN or LL (active lang) | Sentence recognition           |
| Whisper | Python       | Purple             | EN or LL (active lang) | Dictation / longer speech      |
| Pause   | None         | Orange             | —                     | All recognition suspended      |

**Switching rules:**

- When switching to Vosk or Whisper: AHK pauses SAPI grammar before handing control to Python
- When switching back to SAPI: AHK sends `MODE:sapi` to Python (Python releases mic), then AHK resumes SAPI grammar
- Switch can be triggered via: hotkey, voice command (via SAPI while in SAPI mode), or GUI button — user's free choice
- The existing StatusCircle (already in `Voice_Command.ahk`) is extended from 3 to 4 states

---

## Communication: AHK ↔ Python

**Method**: TCP socket (localhost)

- Python runs a TCP server on `localhost:7891` at startup
- AHK connects as TCP client
- All bidirectional communication goes through the socket
- AHK uses DllCall (Winsock API) for TCP client — a small reusable AHK helper

**Protocol:**

| Direction     | Message                    | Meaning                             |
| ------------- | -------------------------- | ----------------------------------- |
| AHK → Python | `MODE:sapi`              | Release mic, suspend bridge         |
| AHK → Python | `MODE:vosk`              | Switch to Vosk sentence recognition |
| AHK → Python | `MODE:whisper`           | Switch to Whisper dictation         |
| AHK → Python | `MODE:pause`             | Suspend recognition (keep mic free) |
| AHK → Python | `QUIT`                   | Shut down Python bridge             |
| Python → AHK | `TEXT:<recognized text>` | Recognized speech result            |
| Python → AHK | `STATUS:<message>`       | State update (e.g.`STATUS:ready`) |
| Python → AHK | `ERROR:<message>`        | Error report                        |

---

## Hardware Context

- Windows PC
- AMD Ryzen 7 5700U (8 cores, 16 threads) or alike
- Integrated AMD Radeon Vega 8 (no dedicated GPU)
- 16GB DDR4 — sufficient for Vosk small + Whisper small (~1.5GB total RAM usage)
- Windows 11

---

## StatusCircle Configuration

- **Size**: read from INI key `intCircleSize` under `[Gui]`; any value below 50 is silently raised to 50 internally (minimum needed for legible text). Default value in INI: 50.
- **Label text color**: white (`FFFFFF`). Already implemented in `ShowCircle()`. White provides sufficient contrast against both the Vosk background (green `00CC44`) and the Whisper background (purple `9900CC`). No color change needed.
- Labels (`EN` / `LL`) are shown only in Vosk and Whisper modes; SAPI and Pause show no label.

---

## Vosk Implementation

- Python package: `vosk`
- English model always loaded at startup (default language)
- Local language model loaded from `models/vosk/ll/` — a generic folder slot for any non-English language; no INI key needed for Vosk (the model folder IS the language)
- AHK variable `speakLanguage`: `default` = English, `special` = local language (LL)
- User can switch between default and local language via GUI/hotkey
- `DefaultLanguage=EN|LL` in `Voice_Command.ini` sets which language is active on startup (persists across sessions)
- Each language requires its own Vosk model downloaded and placed in the appropriate folder (`en/` or `ll/`)
- Supports custom grammars for improved accuracy on expected phrases
- Built-in VAD — Vosk detects end of speech automatically; no external VAD needed

---

## Whisper Implementation

- Python package: `faster-whisper` (CPU mode) — **not** whisper.cpp
- Model size: **auto-selected at bridge startup** based on available system RAM:
  - RAM ≥ 24GB → `medium` (more accurate, 3–8s per utterance on CPU)
  - RAM < 24GB → `small` (faster, 1–3s per utterance on CPU)
  - Can be overridden manually via `Voice_Command.ini` key `whisperModel=small|medium`
  - Uses `psutil.virtual_memory().total` to detect RAM at runtime
- Language support: multilingual by default — supports English, Dutch, German, and 99 others without separate models
- Active language passed per transcription call from `LocalLanguage=` INI key (e.g. `LocalLanguage=nl`, `LocalLanguage=de`); omitted or empty defaults to English
- Unlike Vosk, Whisper requires an explicit language code — the `LocalLanguage=` key is mandatory for non-English dictation
- `DefaultLanguage=EN|LL` in `Voice_Command.ini` sets which language is active on startup (same key as Vosk)

**VAD for Whisper — how it works:**

Whisper does not detect speech boundaries on its own. `silero-vad` is used as the audio gating layer:

1. Python captures a continuous audio stream from the microphone (via `sounddevice` or `pyaudio`)
2. `silero-vad` processes audio in 30ms chunks in real time, outputting a speech probability per chunk
3. When probability exceeds threshold (e.g. 0.5) → speech detected → buffering begins
4. When probability drops below threshold for ~500ms consecutively → end of utterance detected
5. The buffered audio segment is passed to `faster-whisper` for transcription
6. Transcription result is sent to AHK via TCP socket as `TEXT:<result>`

This is fully automatic — no push-to-talk needed. The user speaks, pauses, and the result appears.

---

## SAPI Implementation

- Already in use via AHK v2 COM integration. See `Voice_Command.ahk`
- No changes to SAPI logic — the grammar management already supports pause/resume (`blnCommandsEnabled`)
- SAPI is paused (`objGrammar.SetRuleState`) when Vosk or Whisper becomes active

---

## Distribution

- Python part: recipients install Python, then run `setup.bat`

```
VoiceApp/
├── Voice_Command.ahk
├── lib/
│   ├── General/
│   │   └── Peep_v2.ahk
│   └── Project/
│       ├── Voice_Command_Core.ahk
│       ├── Voice_Command_UI.ahk
│       └── Voice_Command_Utils.ahk
├── python/
│   ├── bridge.py
│   ├── requirements.txt
│   └── setup.bat          (pip install + model downloads)
├── models/
│   ├── vosk/
│   │   ├── en/            (English model — always present)
│   │   └── ll/            (local language model — generic slot, any language)
│   └── whisper/           (faster-whisper small model)
└── README.txt
```

`requirements.txt` includes: `vosk`, `faster-whisper`, `silero-vad`, `sounddevice`, `torch` (CPU)

---

## Development Phases

### Phase 1 — Python Bridge with Vosk + TCP Socket

- Python bridge script with TCP server on localhost:7891
- Vosk integration: always load English model from `models/vosk/en/`; load local language model from `models/vosk/ll/` if that folder exists
- AHK variable `speakLanguage` controls active Vosk model (`default` = English, `special` = LL)
- Read `DefaultLanguage=` from INI at startup to set initial active language (EN or LL)
- User can switch between languages via GUI/hotkey (F4)
- AHK: launch bridge at startup, connect via TCP socket (DllCall Winsock helper)
- AHK reads `TEXT:` results from socket and logs/displays them
- AHK sends `MODE:vosk` and `MODE:sapi` commands
- StatusCircle: extend to 4 states (SAPI, Vosk, Whisper, Pause); Vosk circle shows EN or NL label in center; size read from INI `[Gui] intCircleSize` with minimum 50
- Test: full round-trip AHK ↔ Python, English and configured additional language

### Phase 2 — Add Whisper Mode

- Add `silero-vad` audio gating to Python bridge
- Add `faster-whisper` (model auto-selected by RAM, multilingual) to bridge
- Implement `MODE:whisper` handling: switch from Vosk to Whisper pipeline
- Language passed to faster-whisper from `LocalLanguage=` INI key at transcription time — no extra model needed
- AHK: send mode switch commands, receive and handle `TEXT:` results
- AHK GUI: toggle Vosk ↔ Whisper, select language
- StatusCircle: Whisper circle shows EN or NL label in center (same logic as Vosk)
- Test: dictation in English and Dutch
  Extra questions and their answers:
  - F3 currently toggles SAPI ↔ Vosk. With Whisper it cycles: SAPI → Vosk → Whisper → SAPI
  - INI key name for Whisper model: whisperModel=small|medium under [Settings]. Correct.

### Phase 3 — Integration with Existing SAPI System

- Connect all three tiers: SAPI (commands), Vosk (sentences), Whisper (dictation)
- Mode switching: hotkey, SAPI voice command ("switch to dictation"), and GUI button
- SAPI pauses mic when switching to Vosk/Whisper; resumes on switch back
- AHK GUI: unified mode panel showing current engine + language
- StatusCircle reflects all 4 modes with correct colors
- Test: full workflow across all three tiers without mic conflicts

### Phase 4 — Distribution Packaging

- `setup.bat`: pip install all dependencies; always download English Vosk model to `models/vosk/en/`; optionally download local language Vosk model to `models/vosk/ll/`; download Whisper model (size auto-selected by RAM)
- Model download automation with progress feedback
- `README.txt` with installation instructions
- Test on a clean machine

---

## Resolved Decisions

| Question                      | Decision                                                                                                                                                                                                                                                                          |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Mic conflict strategy         | Modes exclusive — SAPI paused when Python bridge is active                                                                                                                                                                                                                       |
| AHK→Python communication     | TCP socket (localhost:7891) — simple, reliable, bidirectional                                                                                                                                                                                                                    |
| Whisper speech trigger        | silero-vad — automatic end-of-utterance detection, no push-to-talk                                                                                                                                                                                                               |
| Dutch language support        | Yes, from Phase 1 — both EN and NL Vosk models loaded at startup                                                                                                                                                                                                                 |
| Whisper engine                | faster-whisper (not whisper.cpp) — stays in Python, pip-installable                                                                                                                                                                                                              |
| Single or dual Python process | Single process — loads both Vosk and Whisper models at startup                                                                                                                                                                                                                   |
| Auto-start Python bridge      | Yes — auto-start at AHK launch; Whisper model load time makes on-demand impractical                                                                                                                                                                                              |
| Whisper model size            | Auto-selected at startup:`medium` if RAM ≥ 24GB, else `small`; overridable via `Voice_Command.ini`                                                                                                                                                                         |
| Mode switching UI             | All three: hotkey, voice command (via SAPI), GUI button                                                                                                                                                                                                                           |
| Language selection            | Vosk: generic `models/vosk/ll/` folder — no language code needed. Whisper: `LocalLanguage=nl` in INI — explicit code required. `DefaultLanguage=EN\|LL` in INI sets startup language for both engines. `speakLanguage` AHK variable: `default` = EN, `special` = LL. |
| StatusCircle states           | Extended to 4: SAPI (blue), Vosk (green), Whisper (purple), Pause (orange). Vosk and Whisper circles show a language label in the center: EN or LL (uppercase of active language). SAPI and Pause show no label.                                                                  |
| StatusCircle size             | Configurable via INI `[Gui] intCircleSize`; minimum 50 enforced internally — values below 50 are treated as 50.                                                                                                                                                                |
| EN/NL label text color        | White (`FFFFFF`) — already in code; contrast-rich on green (Vosk) and purple (Whisper). No color change needed.                                                                                                                                                                |

## What to Download and Install

1. Check Python Version
   Vosk and faster-whisper require Python 3.8 or higher. Verify: python --version

---

2. Python Packages — Install via pip

  Run these commands in order (torch must come before silero-vad):

  pip install torch --index-url https://download.pytorch.org/whl/cpu
  pip install silero-vad
  pip install vosk
  pip install faster-whisper
  pip install sounddevice
  pip install psutil

  Why CPU-only torch? The standard pip install torch downloads the CUDA version (~2.5GB). The CPU-only version is ~200MB and sufficient for silero-vad on your hardware.

---

3. Vosk Models — Manual Download

  Go to: https://alphacephei.com/vosk/models

  Download these two ZIP files:

  ┌─────────────────────────────────┬───────┬──────────────────────────────┐
  │              Model              │ Size  │           Purpose            │
  ├─────────────────────────────────┼───────┼──────────────────────────────┤
  │ vosk-model-small-en-us (latest) │ ~40MB │ English sentence recognition │
  ├─────────────────────────────────┼───────┼──────────────────────────────┤
  │ vosk-model-small-nl (latest)    │ ~39MB │ Local language (LL) model    │
  └─────────────────────────────────┴───────┴──────────────────────────────┘

  Extract each ZIP. You'll get a folder. Place them in your project:
  models/vosk/en/   ← contents of the English model folder
  models/vosk/ll/   ← contents of the local language model folder (e.g. Dutch)

---

4. Whisper Model — Downloads Automatically

  faster-whisper fetches the model from Hugging Face on first use. Nothing to download manually. On first run of the bridge script it will download ~1.5GB (medium model) to:
  C:\Users\Niek\.cache\huggingface\hub
  Requires internet on that first run. Subsequent runs use the cache.

---

5. silero-vad Model — Downloads Automatically

  Downloads ~5MB on first use, cached locally by PyTorch. No action needed.

---

  Summary

  ┌──────────────────────┬───────────────────────────┬────────┐
  │         Item         │          Action           │  Size  │
  ├──────────────────────┼───────────────────────────┼────────┤
  │ torch (CPU)          │ pip install               │ ~200MB │
  ├──────────────────────┼───────────────────────────┼────────┤
  │ silero-vad           │ pip install               │ small  │
  ├──────────────────────┼───────────────────────────┼────────┤
  │ vosk                 │ pip install               │ small  │
  ├──────────────────────┼───────────────────────────┼────────┤
  │ faster-whisper       │ pip install               │ small  │
  ├──────────────────────┼───────────────────────────┼────────┤
  │ sounddevice          │ pip install               │ small  │
  ├──────────────────────┼───────────────────────────┼────────┤
  │ psutil               │ pip install               │ small  │
  ├──────────────────────┼───────────────────────────┼────────┤
  │ Vosk EN model        │ Manual download + extract │ ~40MB  │
  ├──────────────────────┼───────────────────────────┼────────┤
  │ Vosk LL model        │ Manual download + extract │ ~39MB  │
  ├──────────────────────┼───────────────────────────┼────────┤
  │ Whisper medium model │ Auto on first run         │ ~1.5GB │
  ├──────────────────────┼───────────────────────────┼────────┤
  │ silero-vad model     │ Auto on first run         │ ~5MB   │
  └──────────────────────┴───────────────────────────┴────────┘

## Questions before I code Phase 1:

1. The plan says "User can switch between languages via GUI/hotkey".
   For Phase 1, is F3 to toggle SAPI↔Vosk enough, and a separate hotkey (e.g. F4) for language toggle (default↔special)? Or should the language switch be GUI-only for now?
   Answer: Via F4
2. Should TEXT: results from Vosk be typed into the active window (like dictation), or just displayed in a tooltip + logged for now in Phase 1?
   Answer: Typed into active window.
3. Do the Vosk model folders already exist, or should I add a check/warning when they're missing?
   Answer: They have been setup.
