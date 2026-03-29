#!/usr/bin/env python3
"""
Voice Command Setup Helper

Summary: Interactive setup script that installs all required Python packages
and downloads Vosk speech recognition models. Optionally installs a local
language model and updates Voice_Command.ini. Run via setup.bat.

Steps:
    1. Install Python packages (torch CPU, silero-vad, vosk, faster-whisper,
       sounddevice, psutil)
    2. Download English Vosk model to models/vosk/en/
    3. Optionally download a local language Vosk model to models/vosk/ll/
    4. Update Voice_Command.ini with the chosen localLanguage= setting

NOTE: Vosk model URLs were current as of 2025. If a download fails, visit
https://alphacephei.com/vosk/models for the latest model names and update
the LANGUAGES list below.
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile

SCRIPT_DIR  = os.path.dirname(os.path.abspath(__file__))
ROOT_DIR    = os.path.dirname(SCRIPT_DIR)
VOSK_EN_DIR = os.path.join(ROOT_DIR, "models", "vosk", "en")
VOSK_LL_DIR = os.path.join(ROOT_DIR, "models", "vosk", "ll")
INI_PATH    = os.path.join(ROOT_DIR, "Voice_Command.ini")

EN_MODEL = {
    "name":   "English",
    "url":    "https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.22.zip",
    "folder": "vosk-model-small-en-us-0.22",
}

LANGUAGES = [
    {"code": "nl", "name": "Dutch",      "url": "https://alphacephei.com/vosk/models/vosk-model-small-nl-0.22.zip",    "folder": "vosk-model-small-nl-0.22"},
    {"code": "de", "name": "German",     "url": "https://alphacephei.com/vosk/models/vosk-model-small-de-0.15.zip",    "folder": "vosk-model-small-de-0.15"},
    {"code": "fr", "name": "French",     "url": "https://alphacephei.com/vosk/models/vosk-model-small-fr-0.22.zip",    "folder": "vosk-model-small-fr-0.22"},
    {"code": "es", "name": "Spanish",    "url": "https://alphacephei.com/vosk/models/vosk-model-small-es-0.42.zip",    "folder": "vosk-model-small-es-0.42"},
    {"code": "it", "name": "Italian",    "url": "https://alphacephei.com/vosk/models/vosk-model-small-it-0.22.zip",    "folder": "vosk-model-small-it-0.22"},
    {"code": "pt", "name": "Portuguese", "url": "https://alphacephei.com/vosk/models/vosk-model-small-pt-0.3.zip",     "folder": "vosk-model-small-pt-0.3"},
    {"code": "ru", "name": "Russian",    "url": "https://alphacephei.com/vosk/models/vosk-model-small-ru-0.22.zip",    "folder": "vosk-model-small-ru-0.22"},
    {"code": "cn", "name": "Chinese",    "url": "https://alphacephei.com/vosk/models/vosk-model-small-cn-0.22.zip",    "folder": "vosk-model-small-cn-0.22"},
]


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

def sep():
    print("-" * 50)


def dir_has_content(path):
    return os.path.isdir(path) and bool(os.listdir(path))


def install_package(label, args):
    print(f"  Installing {label} ...", end="", flush=True)
    try:
        result = subprocess.run(args, capture_output=True, text=True)
        if result.returncode == 0:
            print(" OK")
            return True
        print(" FAILED")
        for line in result.stderr.strip().splitlines()[-3:]:
            print(f"    {line}")
        return False
    except Exception as exc:
        print(f" FAILED: {exc}")
        return False


def _progress_hook(label):
    def hook(count, block_size, total_size):
        if total_size > 0:
            pct  = min(100, count * block_size * 100 // total_size)
            done = count * block_size / 1024 / 1024
            tot  = total_size / 1024 / 1024
            print(f"\r  Downloading {label}: {pct:3d}%  ({done:.1f} / {tot:.1f} MB)  ",
                  end="", flush=True)
    return hook


def download_and_install_model(model, target_dir, label):
    """Download a Vosk model ZIP and extract its contents into target_dir."""
    try:
        with tempfile.TemporaryDirectory() as tmpdir:
            zip_path = os.path.join(tmpdir, "model.zip")
            urllib.request.urlretrieve(model["url"], zip_path, _progress_hook(label))
            print()  # end progress line

            print(f"  Extracting {label} ...", end="", flush=True)
            with zipfile.ZipFile(zip_path, "r") as zf:
                zf.extractall(tmpdir)

            # Locate the extracted model folder
            extracted = os.path.join(tmpdir, model["folder"])
            if not os.path.isdir(extracted):
                candidates = [
                    os.path.join(tmpdir, d) for d in os.listdir(tmpdir)
                    if os.path.isdir(os.path.join(tmpdir, d)) and d != "__MACOSX"
                ]
                if not candidates:
                    raise FileNotFoundError("No folder found inside downloaded ZIP")
                extracted = candidates[0]

            os.makedirs(target_dir, exist_ok=True)
            for item in os.listdir(extracted):
                src = os.path.join(extracted, item)
                dst = os.path.join(target_dir, item)
                if os.path.isdir(src):
                    if os.path.exists(dst):
                        shutil.rmtree(dst)
                    shutil.copytree(src, dst)
                else:
                    shutil.copy2(src, dst)

            print(" OK")
            return True

    except Exception as exc:
        print(f" FAILED: {exc}")
        print(f"  If this error persists, download the model manually from:")
        print(f"  https://alphacephei.com/vosk/models")
        print(f"  and extract its contents into: {target_dir}")
        return False


def update_ini_language(lang_code):
    """Write localLanguage=<code> into Voice_Command.ini under [Settings]."""
    if not os.path.isfile(INI_PATH):
        print(f"  Note: Voice_Command.ini not found.")
        print(f"  Please add 'localLanguage={lang_code}' under [Settings] manually.")
        return
    try:
        with open(INI_PATH, encoding="utf-16") as fh:
            content = fh.read()
        if re.search(r"(?im)^localLanguage\s*=", content):
            content = re.sub(r"(?im)^(localLanguage\s*=).*", r"\g<1>" + lang_code, content)
        else:
            content = re.sub(r"(?im)^(\[Settings\])", r"\1\nlocalLanguage=" + lang_code, content)
        with open(INI_PATH, "w", encoding="utf-16") as fh:
            fh.write(content)
        print(f"  Voice_Command.ini updated: localLanguage={lang_code}")
    except Exception as exc:
        print(f"  Note: Could not update INI automatically: {exc}")
        print(f"  Please add 'localLanguage={lang_code}' under [Settings] in Voice_Command.ini.")


# ------------------------------------------------------------------
# Setup steps
# ------------------------------------------------------------------

def step_packages():
    print("\nStep 1: Installing Python packages")
    sep()
    errors = []

    # torch CPU -- skip if already installed to avoid overwriting a user's existing install
    try:
        import torch  # noqa: F401
        print("  torch: already installed. Skipping.")
    except ImportError:
        ok = install_package(
            "torch (CPU only, ~200 MB -- this may take several minutes)",
            [sys.executable, "-m", "pip", "install", "torch",
             "--index-url", "https://download.pytorch.org/whl/cpu"],
        )
        if not ok:
            errors.append("torch")

    for pkg in ["silero-vad", "vosk", "faster-whisper", "sounddevice", "psutil", "openai", "sherpa-onnx", "huggingface_hub"]:
        ok = install_package(pkg, [sys.executable, "-m", "pip", "install", pkg])
        if not ok:
            errors.append(pkg)

    return errors


def step_english_model():
    print("\nStep 2: English Vosk model")
    sep()
    if dir_has_content(VOSK_EN_DIR):
        print("  Already installed. Skipping.")
        return []
    ok = download_and_install_model(EN_MODEL, VOSK_EN_DIR, "English model")
    return [] if ok else ["English Vosk model"]


def step_local_model():
    print("\nStep 3: Local language model (optional)")
    sep()
    answer = input("  Install a local language model for Vosk? (Y/N): ").strip().upper()
    if answer != "Y":
        print("  Skipped.")
        return [], None

    print()
    for i, lang in enumerate(LANGUAGES, 1):
        print(f"  {i:2}. {lang['name']} ({lang['code']})")
    print()

    while True:
        choice = input(f"  Enter number (1-{len(LANGUAGES)}): ").strip()
        if choice.isdigit() and 1 <= int(choice) <= len(LANGUAGES):
            lang = LANGUAGES[int(choice) - 1]
            break
        print(f"  Please enter a number between 1 and {len(LANGUAGES)}.")

    if dir_has_content(VOSK_LL_DIR):
        ow = input(
            f"  A local language model is already installed. "
            f"Overwrite with {lang['name']}? (Y/N): "
        ).strip().upper()
        if ow != "Y":
            print("  Skipped.")
            return [], None
        shutil.rmtree(VOSK_LL_DIR)

    ok = download_and_install_model(lang, VOSK_LL_DIR, f"{lang['name']} model")
    if ok:
        return [], lang["code"]
    return [f"{lang['name']} Vosk model"], None


# ------------------------------------------------------------------
# Entry point
# ------------------------------------------------------------------

def main():
    print("=" * 50)
    print("  Voice Command -- Setup")
    print("=" * 50)

    errors = []
    errors += step_packages()
    errors += step_english_model()
    ll_errors, lang_code = step_local_model()
    errors += ll_errors

    if lang_code:
        print()
        update_ini_language(lang_code)

    print()
    print("=" * 50)
    if errors:
        print("  Setup completed with errors:")
        for e in errors:
            print(f"    - {e}: FAILED")
        print()
        print("  Check your internet connection and try again.")
        print("  See README.txt for manual installation instructions.")
        sys.exit(1)
    else:
        print("  All steps completed successfully!")
        print()
        print("  Next steps:")
        print("  1. Open Voice_Command.ini and verify your settings")
        print("  2. Double-click Voice_Command.ahk to launch")
    print("=" * 50)


if __name__ == "__main__":
    main()
