#!/usr/bin/env python3
"""
Voice Command Bridge -- Vosk + Whisper + TCP server (Phase 2)

Communicates with Voice_Command.ahk via TCP on localhost:7891.

Receives: MODE:vosk | MODE:whisper | MODE:sapi | MODE:pause | LANG:default | LANG:special | QUIT
Sends:    TEXT:<recognized text> | STATUS:<msg> | ERROR:<msg>

Usage:
    python bridge.py "path\\to\\Voice_Command.ini"
"""

import configparser
import json
import logging
import os
import queue
import socket
import sys
import threading

from vosk import Model, KaldiRecognizer

HOST = "127.0.0.1"
PORT = 7891
SAMPLE_RATE = 16000
BLOCKSIZE   = 8000

# silero-vad constants
VAD_CHUNK   = 512    # 32ms at 16kHz -- minimum required by silero-vad
VAD_THRESH  = 0.5    # speech probability threshold
SILENCE_END = 17     # ~510ms of consecutive silent chunks -> end of utterance


# ------------------------------------------------------------------
# INI reader -- handles UTF-16 LE (AHK default) and UTF-8
# ------------------------------------------------------------------

def load_ini(ini_path):
    cfg = configparser.ConfigParser()
    for enc in ("utf-16", "utf-8-sig", "cp1252"):
        try:
            with open(ini_path, encoding=enc) as fh:
                cfg.read_file(fh)
            if cfg.sections():
                return cfg
        except (UnicodeError, UnicodeDecodeError):
            cfg = configparser.ConfigParser()
    return cfg


# ------------------------------------------------------------------
# Bridge
# ------------------------------------------------------------------

class VoiceBridge:
    def __init__(self, ini_path):
        self.ini_path     = ini_path
        self.mode         = "sapi"      # sapi | vosk | whisper | pause
        self.lang         = "default"   # default | special
        self.special_lang = ""          # e.g. "nl" -- from INI localLanguage=
        self.models       = {}          # {"default": Model, "special": Model}
        self.recognizers  = {}          # {"default": KaldiRecognizer, ...}
        self.whisper_model = None       # faster_whisper.whisperModel instance
        self.whisper_size  = ""         # "small" | "medium"
        self.vad_model     = None       # silero-vad torch model
        self.audio_queue         = queue.Queue()
        self.conn                = None
        self.conn_lock           = threading.Lock()
        self.stop_audio          = threading.Event()
        self.audio_thread        = None
        self.running             = True
        self._whisper_requested  = False  # True while async load is pending

    # --------------------------------------------------------------
    # Config & model loading
    # --------------------------------------------------------------

    def load_config(self):
        cfg = load_ini(self.ini_path)
        self.special_lang = cfg.get("Settings", "localLanguage", fallback="").strip().lower()
        logging.info("localLanguage setting: '%s'", self.special_lang or "(none)")

    def load_models(self):
        base = os.path.normpath(
            os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "models", "vosk")
        )

        # English model -- always required
        en_path = os.path.join(base, "en")
        if not os.path.isdir(en_path):
            raise FileNotFoundError(f"English Vosk model not found: {en_path}")
        logging.info("Loading English model: %s", en_path)
        self.models["default"] = Model(en_path)
        self.recognizers["default"] = KaldiRecognizer(self.models["default"], SAMPLE_RATE)
        logging.info("English model loaded.")

        # Local language model -- optional, always in the fixed "ll" folder
        lang_path = os.path.join(base, "ll")
        if os.path.isdir(lang_path):
            logging.info("Loading local language (LL) model: %s", lang_path)
            self.models["special"] = Model(lang_path)
            self.recognizers["special"] = KaldiRecognizer(
                self.models["special"], SAMPLE_RATE
            )
            logging.info("LL model loaded.")
        else:
            logging.info("No local language (LL) model found at: %s", lang_path)

    def load_whisper(self):
        """Load faster-whisper model and silero-vad. Non-fatal if packages missing."""
        import torch
        from faster_whisper import WhisperModel
        cfg = load_ini(self.ini_path)

        # Determine model size: INI override or auto-detect by RAM
        ini_size = cfg.get("Settings", "whisperModel", fallback="").strip().lower()
        if ini_size in ("small", "medium"):
            self.whisper_size = ini_size
            logging.info("Whisper model size: %s (INI override)", self.whisper_size)
        else:
            import psutil
            ram_bytes = psutil.virtual_memory().total
            ram_gb    = ram_bytes / (1024 ** 3)
            self.whisper_size = "medium" if ram_gb >= 24 else "small"
            logging.info(
                "Whisper model size: %s (RAM: %.1fGB detected)",
                self.whisper_size, ram_gb
            )

        # Load faster-whisper
        logging.info("Loading faster-whisper model '%s' (CPU, int8)...", self.whisper_size)
        self.whisper_model = WhisperModel(
            self.whisper_size, device="cpu", compute_type="int8"
        )
        logging.info("faster-whisper model loaded.")

        # Load silero-vad
        logging.info("Loading silero-vad...")
        self.vad_model, _ = torch.hub.load(
            repo_or_dir="snakers4/silero-vad",
            model="silero_vad",
            force_reload=False,
            onnx=False,
            verbose=False,
        )
        self.vad_model.eval()
        logging.info("silero-vad loaded.")

        self.send("STATUS:whisper_ready")

    # --------------------------------------------------------------
    # Network helpers
    # --------------------------------------------------------------

    def send(self, msg):
        """Send one message line to AHK."""
        with self.conn_lock:
            if self.conn:
                try:
                    self.conn.sendall((msg + "\n").encode("utf-8"))
                except OSError:
                    pass

    # --------------------------------------------------------------
    # Command handling (runs in TCP recv thread)
    # --------------------------------------------------------------

    def handle_command(self, line):
        logging.info("CMD: %s", line)

        if line == "MODE:vosk":
            self._whisper_requested = False
            self.mode = "vosk"
            self._start_audio()
            self.send("STATUS:mode_vosk")

        elif line == "MODE:whisper":
            if self.whisper_model is None:
                self._whisper_requested = True
                self.send("STATUS:whisper_loading")
                threading.Thread(target=self._load_whisper_async, daemon=True).start()
            else:
                self._whisper_requested = False
                self.mode = "whisper"
                self._start_audio()
                self.send("STATUS:mode_whisper")

        elif line == "MODE:sapi":
            self._whisper_requested = False
            self.mode = "sapi"
            self._stop_audio()
            self.send("STATUS:mode_sapi")

        elif line == "MODE:pause":
            self._whisper_requested = False
            self.mode = "pause"
            self._stop_audio()
            self.send("STATUS:mode_pause")

        elif line == "LANG:default":
            self.lang = "default"
            if "default" in self.models:
                self.recognizers["default"] = KaldiRecognizer(
                    self.models["default"], SAMPLE_RATE
                )
            self.send("STATUS:lang_default")
            logging.info("Language: default (English)")

        elif line == "LANG:special":
            if "special" in self.models:
                self.lang = "special"
                self.recognizers["special"] = KaldiRecognizer(
                    self.models["special"], SAMPLE_RATE
                )
                self.send("STATUS:lang_special")
                logging.info("Language: special (%s)", self.special_lang)
            else:
                self.send("ERROR:No special language model loaded")

        elif line == "QUIT":
            logging.info("QUIT received -- shutting down.")
            self.running = False
            self._stop_audio()

    # --------------------------------------------------------------
    # Audio capture, Vosk recognition, Whisper VAD pipeline
    # --------------------------------------------------------------

    def _load_whisper_async(self):
        """Load Whisper and VAD in a background thread; activate whisper mode when ready."""
        try:
            self.load_whisper()
            if not self._whisper_requested:
                # User switched away while loading -- stay in current mode
                logging.info("Whisper loaded but mode was cancelled; staying in '%s'.", self.mode)
                self.send("STATUS:whisper_ready")
                return
            self._whisper_requested = False
            self.mode = "whisper"
            self._start_audio()
            self.send("STATUS:mode_whisper")
        except Exception as exc:
            logging.error("Whisper/VAD load failed: %s", exc)
            self._whisper_requested = False
            self.send(f"ERROR:Whisper load failed: {exc}")

    def _start_audio(self):
        """Start audio capture thread if not already running."""
        if self.audio_thread and self.audio_thread.is_alive():
            return
        self.stop_audio.clear()
        while not self.audio_queue.empty():
            try:
                self.audio_queue.get_nowait()
            except queue.Empty:
                break
        self.audio_thread = threading.Thread(target=self._audio_loop, daemon=True)
        self.audio_thread.start()
        logging.info("Audio thread started.")

    def _stop_audio(self):
        """Signal audio thread to stop."""
        self.stop_audio.set()
        logging.info("Audio stop signaled.")

    def _audio_loop(self):
        """Capture audio and route to Vosk or Whisper+VAD depending on self.mode."""
        import sys
        import numpy as np

        # Stage 1: sounddevice import triggers PortAudio device enumeration, which can
        # hang indefinitely when a Bluetooth headset is asleep. Import in a thread with
        # a 10-second timeout. On timeout the user can wake the headset and press F3 again.
        if "sounddevice" not in sys.modules:
            _sd_ready = threading.Event()
            def _import_sd():
                import sounddevice  # noqa: F401 -- populates sys.modules
                _sd_ready.set()
            threading.Thread(target=_import_sd, daemon=True).start()
            if not _sd_ready.wait(timeout=10):
                logging.error("sounddevice import timed out -- Bluetooth headset may be asleep.")
                self.send("ERROR:Mic init timed out. Wake headset and press F3 again.")
                return
        import sounddevice as sd

        # Stage 2: opening RawInputStream negotiates with the audio device, which also
        # hangs when a Bluetooth headset is asleep. Open in a thread with a 10-second timeout.

        # Whisper VAD state
        speech_buffer  = []   # accumulated bytes for one utterance
        vad_remainder  = b""  # leftover bytes between sounddevice blocks
        in_speech      = False
        silence_chunks = 0

        def audio_callback(indata, frames, time_info, status):
            if not self.stop_audio.is_set():
                self.audio_queue.put(bytes(indata))

        _stream_holder = [None]
        _stream_error  = [None]
        _stream_ready  = threading.Event()

        def _open_stream():
            try:
                s = sd.RawInputStream(
                    samplerate=SAMPLE_RATE,
                    blocksize=BLOCKSIZE,
                    dtype="int16",
                    channels=1,
                    callback=audio_callback,
                )
                s.start()
                _stream_holder[0] = s
            except Exception as exc:
                _stream_error[0] = exc
            _stream_ready.set()

        threading.Thread(target=_open_stream, daemon=True).start()
        if not _stream_ready.wait(timeout=10):
            logging.error("Microphone stream open timed out -- Bluetooth headset may be asleep.")
            self.send("ERROR:Mic stream timed out. Wake Bluetooth headset and press F3 again.")
            return
        if _stream_error[0]:
            logging.error("Audio stream error: %s", _stream_error[0])
            self.send(f"ERROR:Audio stream error: {_stream_error[0]}")
            return

        logging.info("Microphone stream open.")
        try:
            while not self.stop_audio.is_set():
                try:
                    data = self.audio_queue.get(timeout=0.1)
                except queue.Empty:
                    continue

                # ---- VOSK branch ----
                if self.mode == "vosk":
                    # Reset Whisper VAD state when switching modes
                    speech_buffer  = []
                    vad_remainder  = b""
                    in_speech      = False
                    silence_chunks = 0

                    rec = self.recognizers.get(self.lang) or self.recognizers.get("default")
                    if rec is None:
                        continue
                    if rec.AcceptWaveform(data):
                        result = json.loads(rec.Result())
                        text   = result.get("text", "").strip()
                        if text:
                            logging.info("TEXT (vosk): %s", text)
                            self.send(f"TEXT:{text}")

                # ---- WHISPER branch ----
                elif self.mode == "whisper":
                    import torch  # lazy: only needed for VAD; cached after first import
                    if self.vad_model is None or self.whisper_model is None:
                        continue

                    # Combine leftover from previous block with new data
                    raw    = vad_remainder + data
                    offset = 0

                    # Process in 480-sample (30ms) VAD chunks
                    while offset + VAD_CHUNK * 2 <= len(raw):
                        chunk_bytes = raw[offset : offset + VAD_CHUNK * 2]
                        offset     += VAD_CHUNK * 2

                        # Convert int16 bytes -> float32 tensor for silero-vad
                        chunk_np     = np.frombuffer(chunk_bytes, dtype=np.int16) \
                                         .astype(np.float32) / 32768.0
                        chunk_tensor = torch.from_numpy(chunk_np)

                        with torch.no_grad():
                            speech_prob = self.vad_model(chunk_tensor, SAMPLE_RATE).item()

                        if speech_prob >= VAD_THRESH:
                            in_speech      = True
                            silence_chunks = 0
                            speech_buffer.append(chunk_bytes)

                        elif in_speech:
                            silence_chunks += 1
                            speech_buffer.append(chunk_bytes)  # include trailing audio

                            if silence_chunks >= SILENCE_END:
                                # End of utterance -- send to Whisper
                                audio_bytes = b"".join(speech_buffer)
                                audio_np    = np.frombuffer(audio_bytes, dtype=np.int16) \
                                                .astype(np.float32) / 32768.0

                                if self.lang == "special":
                                    lang_code = self.special_lang
                                else:
                                    lang_code = "en"

                                try:
                                    segments, _ = self.whisper_model.transcribe(
                                        audio_np,
                                        language=lang_code,
                                        beam_size=5,
                                    )
                                    text = " ".join(
                                        seg.text.strip() for seg in segments
                                    ).strip()
                                except Exception as exc:
                                    logging.error("Whisper transcribe error: %s", exc)
                                    text = ""

                                if text:
                                    logging.info("TEXT (whisper): %s", text)
                                    self.send(f"TEXT:{text}")

                                speech_buffer  = []
                                in_speech      = False
                                silence_chunks = 0

                    vad_remainder = raw[offset:]  # save unprocessed bytes

        except Exception as exc:
            logging.error("Audio loop error: %s", exc)
            self.send(f"ERROR:{exc}")
        finally:
            if _stream_holder[0]:
                try:
                    _stream_holder[0].stop()
                    _stream_holder[0].close()
                except Exception:
                    pass

    # --------------------------------------------------------------
    # TCP server
    # --------------------------------------------------------------

    def run(self):
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind((HOST, PORT))
        srv.listen(1)
        srv.settimeout(1.0)
        logging.info("TCP server on %s:%d -- waiting for AHK.", HOST, PORT)

        while self.running:
            try:
                conn, addr = srv.accept()
            except socket.timeout:
                continue
            except OSError:
                break

            logging.info("AHK connected from %s", addr)
            with self.conn_lock:
                self.conn = conn
            self.send("STATUS:ready")

            try:
                buf = ""
                while self.running:
                    chunk = conn.recv(1024)
                    if not chunk:
                        break
                    buf += chunk.decode("utf-8", errors="replace")
                    while "\n" in buf:
                        line, buf = buf.split("\n", 1)
                        line = line.strip()
                        if line:
                            self.handle_command(line)
            except OSError as exc:
                logging.warning("Connection error: %s", exc)
            finally:
                self._stop_audio()
                with self.conn_lock:
                    self.conn = None
                try:
                    conn.close()
                except OSError:
                    pass
                logging.info("AHK disconnected.")

        srv.close()
        logging.info("Bridge shut down.")


# ------------------------------------------------------------------
# Entry point
# ------------------------------------------------------------------

def main():
    ini_path = sys.argv[1] if len(sys.argv) > 1 else ""
    if not ini_path or not os.path.isfile(ini_path):
        print(f"ERROR: INI file not found: {ini_path}", file=sys.stderr)
        sys.exit(1)

    log_file = os.path.join(os.path.dirname(os.path.abspath(ini_path)), "bridge.log")
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        handlers=[
            logging.StreamHandler(sys.stdout),
            logging.FileHandler(log_file, encoding="utf-8"),
        ],
    )

    bridge = VoiceBridge(ini_path)
    try:
        bridge.load_config()
        bridge.load_models()
    except Exception as exc:
        logging.error("Startup failed: %s", exc)
        sys.exit(1)

    bridge.run()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        import traceback, pathlib
        err_file = pathlib.Path(__file__).parent.parent / "bridge_err.txt"
        err_file.write_text(traceback.format_exc(), encoding="utf-8")
        raise
