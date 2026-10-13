#!/usr/bin/env python3
"""Command-line entry point for the official Script Module Builder tool module."""
# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path
import runpy


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    runpy.run_path(str(root / "plugins/modules/tool.script_module_builder/runtime/builder.py"), run_name="__main__")
