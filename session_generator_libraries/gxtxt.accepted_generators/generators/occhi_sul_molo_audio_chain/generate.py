#!/usr/bin/env python3
"""Generate a GX-TXT teaching Session with the authorized original recording."""
from __future__ import annotations

import argparse
import hashlib
import shutil
from pathlib import Path
from session_recipe import configure

EXPECTED_SHA256 = "09d2235cb618fd65d834124f7c0af1fa023d6ef3b579de60b45e0d538b26cdcc"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target-session", required=True)
    parser.add_argument("--library-id")
    parser.add_argument("--generator-id")
    args = parser.parse_args()
    root = Path(args.target_session)
    asset = Path(__file__).resolve().parent / "assets" / "Occhi_Sul_Molo_lavoro.wav"
    if sha256(asset) != EXPECTED_SHA256:
        raise ValueError("bundled author-owned audio does not match the validated SHA-256")
    raw = root / "raw"
    metadata = root / "metadata"
    raw.mkdir(parents=True, exist_ok=True)
    metadata.mkdir(parents=True, exist_ok=True)
    target = raw / asset.name
    if target.exists():
        raise FileExistsError(target)
    shutil.copyfile(asset, target)
    if sha256(target) != EXPECTED_SHA256:
        target.unlink(missing_ok=True)
        raise ValueError("generated audio copy failed integrity check")
    (metadata / "audio_source.sha256").write_text(
        f"{EXPECTED_SHA256}  raw/{target.name}\n", encoding="ascii"
    )
    guide = (Path(__file__).resolve().parent / "STUDENT_GUIDE.md").read_text(encoding="utf-8")
    (root / "STUDENT_GUIDE.md").write_text(guide, encoding="utf-8")
    configure(root, 'occhi_sul_molo_audio_chain', [dict(
        source='raw/Occhi_Sul_Molo_lavoro.wav', id='occhi_sul_molo_lavoro',
        binary=True, kind='audio.waveform', format='wav', media_type='audio/wav',
    )], [dict(id='analysis.audio_decode',
             sources={'primary': 'occhi_sul_molo_lavoro'},
             config={'amplitude_scale': '1', 'amplitude_unit': 'FS'})],
              'Author-owned audio decode and spectral analysis')
    print(f"PASS author-owned audio generator: {target} SHA-256={EXPECTED_SHA256}")


if __name__ == "__main__":
    main()
