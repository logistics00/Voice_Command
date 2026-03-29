#!/usr/bin/env python3
"""
Voice Command Bridge -- Vosk + Whisper + Parakeet + TCP server

Communicates with Voice_Command.ahk via TCP on localhost:7891.

Receives: MODE:vosk | MODE:dictate | MODE:sapi | MODE:pause | LANG:default | LANG:special | QUIT
          MODE:whisper is accepted as a backward-compatible alias for MODE:dictate
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

OPENAI_TRANSCRIBE_MODEL = "gpt-4o-transcribe"


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
        self.ini_path            = ini_path
        self.mode                = "sapi"       # sapi | vosk | dictate | pause
        self.lang                = "default"    # default | special
        self.special_lang        = ""           # e.g. "nl" -- from INI localLanguage=
        self.models              = {}           # {"default": Model, "special": Model}
        self.recognizers         = {}           # {"default": KaldiRecognizer, ...}
        self.whisper_model       = None         # faster_whisper.WhisperModel instance
        self.whisper_size        = ""           # "small" | "medium"
        self.parakeet_recognizer = None         # sherpa_onnx.OfflineRecognizer instance
        self.vad_model           = None         # silero-vad torch model
        self.dictate_mode        = "faster-whisper"  # faster-whisper|whisper-gpt-4o|parakeet-v2|parakeet-v3
        self.openai_api_key      = ""           # OpenAI API key for cloud transcription
        self.audio_queue         = queue.Queue()
        self.conn                = None
        self.conn_lock           = threading.Lock()
        self.stop_audio          = threading.Event()
        self.audio_thread        = None
        self.running             = True
        self._dictate_requested  = False        # True while async load is pending

    # --------------------------------------------------------------
    # Config & model loading
    # --------------------------------------------------------------

    def load_config(self):
        cfg = load_ini(self.ini_path)
        self.special_lang   = cfg.get("Settings", "localLanguage", fallback="").strip().lower()

        dictate_mode = cfg.get("Settings", "dictateMode", fallback="faster-whisper").strip().lower()
        if not dictate_mode:
            dictate_mode = "faster-whisper"

        self.dictate_mode   = dictate_mode
        self.openai_api_key = cfg.get("Settings", "openaiApiKey", fallback="").strip()
        logging.info("localLanguage: '%s'", self.special_lang or "(none)")
        logging.info("dictateMode: %s", self.dictate_mode)

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

    def load_dictate_backend(self):
        """Load the selected dictate backend and silero-vad."""
        import torch

        cfg = load_ini(self.ini_path)

        # Re-read settings so a GUI change takes effect without bridge restart
        dictate_mode = cfg.get("Settings", "dictateMode", fallback="faster-whisper").strip().lower()
        if not dictate_mode:
            dictate_mode = "faster-whisper"
        self.dictate_mode   = dictate_mode
        self.openai_api_key = cfg.get("Settings", "openaiApiKey", fallback="").strip()

        logging.info("Loading dictate backend: %s", self.dictate_mode)

        if self.dictate_mode == "whisper-gpt-4o":
            if not self.openai_api_key:
                self.send("ERROR:OpenAI API key missing. Set openaiApiKey in INI.")
                return
            logging.info("Dictate backend: OpenAI (%s)", OPENAI_TRANSCRIBE_MODEL)

        elif self.dictate_mode == "faster-whisper":
            from faster_whisper import WhisperModel

            ini_size = cfg.get("Settings", "whisperModel", fallback="").strip().lower()
            if ini_size in ("small", "medium"):
                self.whisper_size = ini_size
                logging.info("Whisper model size: %s (INI override)", self.whisper_size)
            else:
                import psutil
                ram_gb = psutil.virtual_memory().total / (1024 ** 3)
                self.whisper_size = "medium" if ram_gb >= 24 else "small"
                logging.info("Whisper model size: %s (RAM: %.1fGB detected)",
                             self.whisper_size, ram_gb)

            logging.info("Loading faster-whisper model '%s' (CPU, int8)...", self.whisper_size)
            self.whisper_model = WhisperModel(
                self.whisper_size, device="cpu", compute_type="int8"
            )
            logging.info("faster-whisper model loaded.")

        elif self.dictate_mode in ("parakeet-v2", "parakeet-v3"):
            import sherpa_onnx

            version   = "v2" if self.dictate_mode == "parakeet-v2" else "v3"
            model_dir = os.path.normpath(os.path.join(
                os.path.dirname(os.path.abspath(__file__)),
                "..", "models", "parakeet", version
            ))

            # Support both plain and INT8-quantised file names
            def _find(base_name):
                for name in (base_name + ".int8.onnx", base_name + ".onnx"):
                    p = os.path.join(model_dir, name)
                    if os.path.isfile(p):
                        return p
                return None

            encoder = _find("encoder")
            decoder = _find("decoder")
            joiner  = _find("joiner")
            tokens  = os.path.join(model_dir, "tokens.txt")

            missing = [n for n, p in
                       [("encoder", encoder), ("decoder", decoder),
                        ("joiner", joiner), ("tokens.txt", tokens if os.path.isfile(tokens) else None)]
                       if p is None]
            if missing:
                import ctypes
                size_mb = "~640 MB" if version == "v2" else "~650 MB"
                self.send("STATUS:parakeet_download_prompt")
                logging.info("Showing Parakeet download dialog for %s (missing: %s)", version, missing)
                answer = ctypes.windll.user32.MessageBoxW(
                    0,
                    f"Parakeet {version} model files are not installed.\n"
                    f"Download size: {size_mb}\n\n"
                    f"Download now?",
                    f"Voice Command \u2014 Parakeet {version} model missing",
                    0x40001,  # MB_OKCANCEL | MB_TOPMOST
                )
                logging.info("User download dialog answer: %s", "OK" if answer == 1 else "Cancel")
                if answer != 1:  # 1 = OK, 2 = Cancel
                    raise FileNotFoundError(
                        f"Parakeet {version} model files missing in {model_dir}: {missing}"
                    )
                self.send("STATUS:parakeet_downloading")
                from download_parakeet import download_version
                models_root = os.path.normpath(os.path.join(
                    os.path.dirname(os.path.abspath(__file__)), "..", "models"
                ))
                download_version(version, models_root)
                # Re-scan after download
                encoder = _find("encoder")
                decoder = _find("decoder")
                joiner  = _find("joiner")
                tokens  = os.path.join(model_dir, "tokens.txt")
                still_missing = [n for n, p in
                    [("encoder", encoder), ("decoder", decoder),
                     ("joiner", joiner), ("tokens.txt", tokens if os.path.isfile(tokens) else None)]
                    if p is None]
                if still_missing:
                    raise FileNotFoundError(
                        f"Parakeet {version} download incomplete, still missing: {still_missing}"
                    )

            logging.info("Loading Parakeet %s from %s ...", version, model_dir)
            self.parakeet_recognizer = sherpa_onnx.OfflineRecognizer.from_transducer(
                encoder=encoder,
                decoder=decoder,
                joiner=joiner,
                tokens=tokens,
                num_threads=4,
                sample_rate=SAMPLE_RATE,
                feature_dim=80,
                decoding_method="greedy_search",
                model_type="nemo_transducer",
            )
            logging.info("Parakeet %s loaded.", version)

        else:
            self.send(f"ERROR:Unknown dictateMode: {self.dictate_mode}")
            return

        # Load silero-vad (needed for all backends to detect end-of-utterance)
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

        self.send("STATUS:dictate_ready")

    def _transcribe_openai(self, audio_np, lang_code):
        """Send audio to OpenAI Transcriptions API and return the transcribed text."""
        import io
        import wave
        try:
            import openai
        except ImportError:
            self.send("ERROR:openai package not installed. Run: pip install openai")
            return ""

        wav_io = io.BytesIO()
        with wave.open(wav_io, "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(SAMPLE_RATE)
            pcm = (audio_np * 32767).astype("int16")
            wf.writeframes(pcm.tobytes())
        wav_bytes = wav_io.getvalue()

        try:
            client = openai.OpenAI(api_key=self.openai_api_key)
            response = client.audio.transcriptions.create(
                model=OPENAI_TRANSCRIBE_MODEL,
                file=("audio.wav", wav_bytes, "audio/wav"),
                language=lang_code,
            )
            return response.text.strip()
        except openai.APIError as exc:
            logging.error("OpenAI transcription error: %s", exc)
            return ""

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
            self._dictate_requested = False
            self.mode = "vosk"
            self._start_audio()
            self.send("STATUS:mode_vosk")

        elif line in ("MODE:dictate", "MODE:whisper"):   # MODE:whisper = backward-compat alias
            cfg = load_ini(self.ini_path)
            dictate_mode = cfg.get("Settings", "dictateMode", fallback="faster-whisper").strip().lower()
            if not dictate_mode:
                dictate_mode = "faster-whisper"

            # If backend changed, reset loaded models
            if dictate_mode != self.dictate_mode:
                self.whisper_model       = None
                self.parakeet_recognizer = None
                self.vad_model           = None
                self.dictate_mode        = dictate_mode

            if self.vad_model is None:
                self._dictate_requested = True
                self.send("STATUS:dictate_loading")
                threading.Thread(target=self._load_dictate_async, daemon=True).start()
            else:
                self._dictate_requested = False
                self.mode = "dictate"
                self._start_audio()
                self.send("STATUS:mode_dictate")

        elif line == "MODE:sapi":
            self._dictate_requested = False
            self.mode = "sapi"
            self._stop_audio()
            self.send("STATUS:mode_sapi")

        elif line == "MODE:pause":
            self._dictate_requested = False
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
    # Audio capture, Vosk recognition, Dictate VAD pipeline
    # --------------------------------------------------------------

    def _load_dictate_async(self):
        """Load dictate backend and VAD in a background thread; activate dictate mode when ready."""
        try:
            self.load_dictate_backend()
            if not self._dictate_requested:
                logging.info("Dictate backend loaded but mode was cancelled; staying in '%s'.", self.mode)
                self.send("STATUS:dictate_ready")
                return
            self._dictate_requested = False
            self.mode = "dictate"
            self._start_audio()
            self.send("STATUS:mode_dictate")
        except Exception as exc:
            logging.error("Dictate backend load failed: %s", exc)
            self._dictate_requested = False
            self.send(f"ERROR:Dictate backend load failed: {exc}")

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
        """Capture audio and route to Vosk or Dictate+VAD depending on self.mode."""
        import sys
        import numpy as np

        if "sounddevice" not in sys.modules:
            _sd_ready = threading.Event()
            def _import_sd():
                import sounddevice  # noqa: F401
                _sd_ready.set()
            threading.Thread(target=_import_sd, daemon=True).start()
            if not _sd_ready.wait(timeout=10):
                logging.error("sounddevice import timed out -- Bluetooth headset may be asleep.")
                self.send("ERROR:Mic init timed out. Wake headset and press F3 again.")
                return
        import sounddevice as sd

        # Dictate VAD state
        speech_buffer  = []
        vad_remainder  = b""
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

                # ---- DICTATE branch (faster-whisper | whisper-gpt-4o | parakeet-v2/v3) ----
                elif self.mode == "dictate":
                    import torch
                    if self.vad_model is None:
                        continue
                    if self.dictate_mode == "faster-whisper" and self.whisper_model is None:
                        continue
                    if self.dictate_mode == "whisper-gpt-4o" and not self.openai_api_key:
                        continue
                    if self.dictate_mode.startswith("parakeet") and self.parakeet_recognizer is None:
                        continue

                    raw    = vad_remainder + data
                    offset = 0

                    while offset + VAD_CHUNK * 2 <= len(raw):
                        chunk_bytes = raw[offset : offset + VAD_CHUNK * 2]
                        offset     += VAD_CHUNK * 2

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
                            speech_buffer.append(chunk_bytes)

                            if silence_chunks >= SILENCE_END:
                                audio_bytes = b"".join(speech_buffer)
                                audio_np    = np.frombuffer(audio_bytes, dtype=np.int16) \
                                                .astype(np.float32) / 32768.0

                                lang_code = self.special_lang if self.lang == "special" else "en"

                                text = ""
                                try:
                                    if self.dictate_mode.startswith("parakeet"):
                                        stream = self.parakeet_recognizer.create_stream()
                                        stream.accept_waveform(SAMPLE_RATE, audio_np)
                                        self.parakeet_recognizer.decode_stream(stream)
                                        text = stream.result.text.strip()

                                    elif self.dictate_mode == "whisper-gpt-4o":
                                        text = self._transcribe_openai(audio_np, lang_code)

                                    else:  # faster-whisper
                                        segments, _ = self.whisper_model.transcribe(
                                            audio_np,
                                            language=lang_code,
                                            beam_size=5,
                                        )
                                        text = " ".join(
                                            seg.text.strip() for seg in segments
                                        ).strip()

                                except Exception as exc:
                                    logging.error("Dictate transcribe error: %s", exc)

                                if text:
                                    logging.info("TEXT (dictate/%s): %s", self.dictate_mode, text)
                                    self.send(f"TEXT:{text}")

                                speech_buffer  = []
                                in_speech      = False
                                silence_chunks = 0

                    vad_remainder = raw[offset:]

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
    try:
        if os.path.isfile(log_file):
            os.remove(log_file)
    except OSError:
        pass  # File locked by a previous process; will be overwritten
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
