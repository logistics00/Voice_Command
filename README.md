# Voice Command

A three-tier voice recognition system for Windows built on AutoHotkey v2 and Python.

---

## What It Does

| Mode | Engine | Purpose | Response |
|---|---|---|---|
| Commands | SAPI (Windows built-in) | Fixed short phrases that trigger actions | Instant |
| Sentences | Vosk | Open vocabulary sentence recognition | ~200 ms |
| Dictation | Whisper (faster-whisper) | Longer continuous speech to text | 1–3 seconds |

Text recognised in Vosk and Whisper modes is typed directly into whatever window is active.
All three tiers support English and one additional local language (e.g. Dutch, German, French).

---

## Prerequisites

### Python 3.8 or higher
Download: https://www.python.org/downloads/

> **Important:** During installation, tick **Add Python to PATH**

Verify after installation — open a Command Prompt and type:
```
python --version
```

### AutoHotkey v2.0 or higher
Download: https://www.autohotkey.com/

The 64-bit version is recommended.

---

## Installation

1. Open the Voice Command folder.
2. Double-click **setup.bat** and follow the on-screen instructions:
   - Checks your Python version.
   - Installs all required Python packages.
     > The `torch` package (~200 MB) may take several minutes.
   - Downloads the English Vosk speech model (~40 MB).
   - Asks whether you want a local language model (e.g. Dutch). If yes, select from the numbered list.
   - Updates `Voice_Command.ini` with your language choice.

The Whisper model (~500 MB for `small`, ~1.5 GB for `medium`) downloads automatically
the first time you switch to Whisper mode. An internet connection is required for that first use.

If any step fails, see [Troubleshooting](#troubleshooting).

---

## First Launch

Double-click **Voice_Command.ahk**

A coloured circle appears in the top-right corner of your screen — this is the status indicator.
A tooltip *"Connecting to Python bridge, please wait..."* appears briefly. When it disappears the system is ready.

---

## Configuration

Open `Voice_Command.ini` with Notepad, or via the tray icon → **Edit INI File**.

### [Settings]

| Key | Example | Description |
|---|---|---|
| `localLanguage` | `nl` | Language code for your local language model (nl, de, fr, es, …) |
| `defaultLanguage` | `EN` | Language active on startup: `EN` = English, `LL` = local language |
| `whisperModel` | `small` | Whisper model size: `small` or `medium`. Omit for auto-selection by RAM. |
| `loggingType` | `0` | Logging detail: 0 = off, 1 = flow, 2 = test, 4 = errors, 7 = all |

### [Gui]

| Key | Example | Description |
|---|---|---|
| `intCircleSize` | `50` | Diameter of the status circle in pixels (minimum: 50) |

---

## Hotkeys

| Key | Action |
|---|---|
| **F1** | Toggle listening on/off. Circle turns red when off. |
| **F2** | Open Command Manager — add, edit or delete SAPI commands. |
| **F3** | Cycle voice mode: SAPI → Vosk → Whisper → SAPI |
| **F4** | Toggle language between English and your local language (Vosk/Whisper only). |

---

## Voice Modes

The circle colour shows the current mode:

| Colour | Mode |
|---|---|
| Blue | SAPI — command recognition active |
| Red | Listening OFF (F1 pressed) |
| Orange | Paused — commands disabled (say "Start" to resume) |
| Green | Vosk — sentence recognition |
| Purple | Whisper — dictation |

In Vosk and Whisper modes the circle shows a language label: **EN** or your local language code (e.g. **NL**). Only one engine uses the microphone at a time.

### SAPI (commands)
Speak a command phrase exactly as defined in Command Manager.
Example: *"Start Notepad"*

### Vosk (sentences)
Speak naturally. When you pause, the recognised text is typed into the active window.
Speak in the language shown in the circle.

### Whisper (dictation)
Speak naturally. A pause of ~0.5 seconds triggers transcription and types the result into the active window.
The first activation downloads the Whisper model (~500 MB) — subsequent activations are immediate.
Speak in the language shown in the circle.

---

## Troubleshooting

**"Python was not found" when running setup.bat**
Reinstall Python and tick **Add Python to PATH** during setup.

**"Could not connect to Python bridge" on startup**
- Wait a moment — the bridge loads Vosk models at start.
- Check `bridge.log` in the Voice Command folder for error details.
- If you use a Bluetooth headset: wake it up, then close and restart `Voice_Command.ahk`.

**No text appears when speaking in Vosk or Whisper mode**
- Confirm the circle is green (Vosk) or purple (Whisper).
- Check the language label — speak in the language shown.
- Check your microphone via the tray icon → **Microphone Settings**.

**Whisper mode takes a long time on first use**
Normal — the Whisper model downloads on first activation (~500 MB). Subsequent activations are immediate.

**Whisper transcribes in the wrong language**
Make sure the circle label matches the language you are speaking. Use **F4** to toggle.

**A download failed during setup**
Check your internet connection and run `setup.bat` again.
Alternatively, download your language model manually from https://alphacephei.com/vosk/models
and extract its contents into:
```
models\vosk\en\   (English model)
models\vosk\ll\   (local language model)
```

**Tray icon or circle does not appear**
Make sure AutoHotkey v2.0 64-bit is installed.
Right-click `Voice_Command.ahk` and choose *"Run with AutoHotkey v2"*.
