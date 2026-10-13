#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Compatibility entry point; source-preserving decoder is owned by CORE.
from pathlib import Path
import runpy
_core = Path(__file__).resolve().parents[4] / 'core' / 'python' / 'crystal_data.py'
globals().update(runpy.run_path(str(_core), run_name='__main__' if __name__ == '__main__' else __name__))
