#!/usr/bin/env python3
"""
This file: one-time download script for Parakeet TDT ONNX model files.
Downloads pre-quantized INT8 ONNX model files from Hugging Face into the
models/parakeet/v2/ and/or models/parakeet/v3/ folders, matching the folder
structure expected by bridge.py.

Usage:
    python python/download_parakeet.py v2        # English only (0.6B v2)
    python python/download_parakeet.py v3        # 25 languages (0.6B v3)
    python python/download_parakeet.py both      # Download both

Requirements:
    pip install huggingface_hub

Model sources (sherpa-onnx pre-packaged INT8 exports):
    v2: https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8
    v3: https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8

Note: If the repo names above have changed, search on https://huggingface.co/csukuangfj
for "parakeet-tdt" to find the current repo names.
"""

import os
import sys

# ---------------------------------------------------------------------------
# HuggingFace repo IDs for the sherpa-onnx pre-packaged Parakeet ONNX models.
# Update these if the repos are renamed on Hugging Face.
# ---------------------------------------------------------------------------
REPOS = {
    "v2": "csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8",
    "v3": "csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8",
}

# Files to download from each repo
MODEL_FILES = [
    "encoder.int8.onnx",
    "decoder.int8.onnx",
    "joiner.int8.onnx",
    "tokens.txt",
]



def download_version(version: str, models_root: str) -> None:
    try:
        from huggingface_hub import hf_hub_download
    except ImportError:
        print("ERROR: huggingface_hub not installed.")
        print("Run: pip install huggingface_hub")
        sys.exit(1)

    repo_id   = REPOS[version]
    local_dir = os.path.join(models_root, "parakeet", version)
    os.makedirs(local_dir, exist_ok=True)

    print(f"\nDownloading Parakeet {version} from {repo_id}")
    print(f"Destination: {local_dir}\n")

    for filename in MODEL_FILES:
        dest = os.path.join(local_dir, filename)
        if os.path.isfile(dest):
            print(f"  [SKIP]  {filename} (already exists)")
            continue
        print(f"  [GET ]  {filename} ...")
        try:
            hf_hub_download(
                repo_id=repo_id,
                filename=filename,
                local_dir=local_dir,
            )
            print(f"  [OK  ]  {filename}")
        except Exception as exc:
            print(f"  [FAIL]  {filename}: {exc}")
            err_str = str(exc)
            # if the message: "Parakeet {version} download failed: repo not found or not authorized." is displayed:
            # Check https://huggingface.co/csukuangfj for the current repo name
            # and update REPOS['{version}'] in download_parakeet.py
            if "401" in err_str or "403" in err_str or "404" in err_str or "gated" in err_str.lower() or "unauthorized" in err_str.lower() or "not found" in err_str.lower():
                raise RuntimeError(
                    f"Parakeet {version} download failed: repo not found or not authorized.\n"
                    f"The HuggingFace repo may have been renamed.\n"
                    f"Inform Niek Mollers, niek.mollers@hartenwiel.nl"
                ) from exc
            raise RuntimeError(f"Parakeet {version} download failed: {exc}") from exc

    # Remove the .cache folder created by huggingface_hub during download
    cache_dir = os.path.join(local_dir, ".cache")
    if os.path.isdir(cache_dir):
        import shutil
        shutil.rmtree(cache_dir)

    print(f"\nParakeet {version} ready in: {local_dir}")


def main() -> None:
    if len(sys.argv) < 2 or sys.argv[1] not in ("v2", "v3", "both"):
        print("Usage: python download_parakeet.py [v2|v3|both]")
        print("  v2   — English only (Parakeet TDT 0.6B v2, ~640 MB)")
        print("  v3   — 25 languages (Parakeet TDT 0.6B v3, ~650 MB)")
        print("  both — Download both versions")
        sys.exit(1)

    arg         = sys.argv[1]
    script_dir  = os.path.dirname(os.path.abspath(__file__))
    models_root = os.path.normpath(os.path.join(script_dir, "..", "models"))

    versions = ["v2", "v3"] if arg == "both" else [arg]
    for v in versions:
        download_version(v, models_root)

    print("\nAll done. You can now select Parakeet in the Voice Command settings GUI.")


if __name__ == "__main__":
    main()
