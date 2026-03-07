#!/usr/bin/env python3
"""
Voice Command Bridge -- Vosk + TCP server (Phase 1)

Communicates with Voice_Command.ahk via TCP on localhost:7891.

Receives: MODE:vosk | MODE:sapi | MODE:pause | LANG:default | LANG:special | QUIT
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
BLOCKSIZE = 8000


# ------------------------------------------------------------------
# INI reader — handles UTF-16 LE (AHK default) and UTF-8
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
        self.ini_path   = ini_path
        self.mode       = "sapi"      # sapi | vosk | pause
        self.lang       = "default"   # default | special
        self.special_lang = ""        # e.g. "nl"
        self.models     = {}          # {"default": Model, "special": Model}
        self.recognizers = {}         # {"default": KaldiRecognizer, ...}
        self.audio_queue = queue.Queue()
        self.conn       = None
        self.conn_lock  = threading.Lock()
        self.stop_audio = threading.Event()
        self.audio_thread = None
        self.running    = True

    # --------------------------------------------------------------
    # Config & model loading
    # --------------------------------------------------------------

    def load_config(self):
        cfg = load_ini(self.ini_path)
        self.special_lang = cfg.get("Settings", "LocalLanguage", fallback="").strip().lower()
        logging.info("LocalLanguage setting: '%s'", self.special_lang or "(none)")

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
            self.mode = "vosk"
            self._start_audio()
            self.send("STATUS:mode_vosk")

        elif line == "MODE:sapi":
            self.mode = "sapi"
            self._stop_audio()
            self.send("STATUS:mode_sapi")

        elif line == "MODE:pause":
            self.mode = "pause"
            self._stop_audio()
            self.send("STATUS:mode_pause")

        elif line == "LANG:default":
            self.lang = "default"
            if "default" in self.models:
                # Reset recognizer to clear any partial audio state
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
    # Audio capture & Vosk recognition
    # --------------------------------------------------------------

    def _start_audio(self):
        """Start audio capture thread if not already running."""
        if self.audio_thread and self.audio_thread.is_alive():
            return
        self.stop_audio.clear()
        # Flush stale audio
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
        """Capture audio from mic and run Vosk recognition until stop_audio is set."""
        import sounddevice as sd

        def audio_callback(indata, frames, time_info, status):
            if not self.stop_audio.is_set():
                self.audio_queue.put(bytes(indata))

        try:
            with sd.RawInputStream(
                samplerate=SAMPLE_RATE,
                blocksize=BLOCKSIZE,
                dtype="int16",
                channels=1,
                callback=audio_callback,
            ):
                logging.info("Microphone stream open.")
                while not self.stop_audio.is_set():
                    try:
                        data = self.audio_queue.get(timeout=0.1)
                    except queue.Empty:
                        continue

                    rec = self.recognizers.get(self.lang) or self.recognizers.get("default")
                    if rec is None:
                        continue

                    if rec.AcceptWaveform(data):
                        result = json.loads(rec.Result())
                        text = result.get("text", "").strip()
                        if text:
                            logging.info("TEXT: %s", text)
                            self.send(f"TEXT:{text}")
                    # Partial results are discarded in Phase 1

        except Exception as exc:
            logging.error("Audio loop error: %s", exc)
            self.send(f"ERROR:{exc}")

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
