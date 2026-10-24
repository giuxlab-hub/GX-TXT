#!/usr/bin/env python3
"""Unit tests for the read-only DEV111 patch chain validator."""
from __future__ import annotations
import importlib.util
from pathlib import Path
import sys
import unittest

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("gxtxt_dev111_patch_validator", HERE / "validate_dev111_patches.py")
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)

class Dev111PatchVerifierTests(unittest.TestCase):
    def test_declared_chain_and_original_fixtures(self):
        info = MODULE.read_manifest()
        self.assertEqual([p["patch"] for p in info["patches"]],
                         ["p001-r2", "p002", "p003", "p004", "p005", "p006"])
        self.assertEqual(len(info["originalFixtures"]), 7)
        self.assertEqual(len(info["p005PreservedSources"]), 7)

    def test_p006_public_exception_scope(self):
        info = MODULE.read_manifest()
        self.assertEqual(len(info["p006PublicPriorExceptions"]), 6)
        self.assertEqual(len(info["p006PublicAfterExceptions"]), 5)
        self.assertEqual(len(info["patches"][-1]["files"]), 16)

    def test_rejects_incomplete_p006_gui_api(self):
        info = MODULE.read_manifest()
        def fake_blob(commit, name):
            return b"proc ::GX::datasetPreviewGuiApiInfo {} {}" if name.endswith("dataset_preview_gui_v1.tcl") else b""
        with self.assertRaises(ValueError):
            MODULE.validate_p006_gui_integration(fake_blob, info)

    def test_rejects_unsafe_source_paths(self):
        for value in ("../escape", "/absolute/file", "dir/../../other", "C:\\secret", "dir\\file"):
            with self.subTest(path=value):
                with self.assertRaises(ValueError):
                    MODULE.safe_rel(value)

    def test_rejects_wrong_native_elf(self):
        for value in (b"", b"\x7fELF", b"not-ELF" * 1024):
            with self.subTest(length=len(value)):
                with self.assertRaises(ValueError):
                    MODULE.validate_elf(value)

    def test_rejects_wrong_native_architecture(self):
        p = bytearray(8192)
        p[:6] = b"\x7fELF\x02\x01"
        p[16:18] = (3).to_bytes(2, "little")
        p[18:20] = (183).to_bytes(2, "little")  # ARM64 must not pass x86_64 validation.
        with self.assertRaisesRegex(ValueError, "x86_64"):
            MODULE.validate_elf(bytes(p))

    def test_rejects_incomplete_worker_bootstrap(self):
        info = MODULE.read_manifest()
        def fake_blob(_commit, path):
            if path == "core/native2d/CMakeLists.txt":
                return b"add_library(gxpreviewprovider MODULE ...)"
            if path == "core/tcl/dataset_preview_worker_v1.tcl":
                return b"# No proper bootstrap"
            return b"\x7fELF"
        with self.assertRaises(ValueError):
            MODULE.validate_p005_integration(fake_blob, info)

if __name__ == "__main__":
    unittest.main()
