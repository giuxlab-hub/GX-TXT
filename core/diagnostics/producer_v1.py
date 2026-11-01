# SPDX-License-Identifier: GPL-3.0-or-later
"""CORE-owned native producer binding for existing managed stderr drains.

The host alone provides the installed library and per-generation descriptor.
No worker-side environment discovery, filesystem reader, queue or retry thread.
One owner serializes calls. Keep the actual normal stderr drain independent.
"""
import ctypes
from pathlib import Path


class Origin(ctypes.Structure):
    _fields_ = [(name, ctypes.c_char_p) for name in (
        "source", "component", "module_id", "viewer_id", "job_id", "api_id",
        "operation", "process_id", "stream", "severity", "chunk_id", "chunk_index")]


class Producer:
    def __init__(self, installed_library, descriptor):
        expected = Path(__file__).resolve().parent / "bin" / "gxdiagnostics.so"
        requested = Path(installed_library).resolve(strict=True)
        if expected.is_symlink() or expected.parent.is_symlink() or requested != expected:
            raise ValueError("Diagnostics producer requires its matching installed CORE library")
        self.lib = ctypes.CDLL(str(expected))
        self.lib.gxdiag_producer_attach_v1.argtypes = (
            ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p), ctypes.c_char_p, ctypes.c_size_t)
        self.lib.gxdiag_producer_attach_v1.restype = ctypes.c_int
        self.lib.gxdiag_producer_emit_v1.argtypes = (
            ctypes.c_void_p, ctypes.POINTER(Origin), ctypes.c_void_p, ctypes.c_size_t)
        self.lib.gxdiag_producer_emit_v1.restype = ctypes.c_int
        self.lib.gxdiag_producer_close_v1.argtypes = (ctypes.c_void_p,)
        self.lib.gxdiag_producer_close_v1.restype = None
        self.handle = ctypes.c_void_p()
        self.python_failures = 0
        self.last_error = ""
        error = ctypes.create_string_buffer(512)
        self.attach_result = self.lib.gxdiag_producer_attach_v1(
            descriptor.encode("ascii"), ctypes.byref(self.handle), error, len(error))
        self.attach_error = error.value.decode("utf-8", "replace")

    def emit(self, payload, **origin):
        """One <=32768-byte raw chunk. Result0 queued/1 OFF/2 overload/3
        oversize/4 broken IPC/5 invalid argument. No retries or stream changes.
        process_id must be the captured child's real PID (or explicit unknown).
        """
        if not self.handle:
            return 1
        try:
            encoded = {}
            for key, value in origin.items():
                if key not in {field[0] for field in Origin._fields_}:
                    raise ValueError("Unknown diagnostic origin field")
                if value is None:
                    encoded[key] = None
                    continue
                text = str(value)
                if len(text) > 512 or "\0" in text:
                    raise ValueError("Invalid diagnostic origin text")
                encoded[key] = text.encode("utf-8")
            context = Origin(**encoded)
            if len(payload) > 32768:
                placeholder = ctypes.c_char()
                return self.lib.gxdiag_producer_emit_v1(
                    self.handle, ctypes.byref(context), ctypes.byref(placeholder), len(payload))
            data = ctypes.create_string_buffer(payload, max(1, len(payload)))
            return self.lib.gxdiag_producer_emit_v1(
                self.handle, ctypes.byref(context), data, len(payload))
        except Exception as error:
            self.python_failures += 1
            self.last_error = str(error)
            return 5

    def close(self):
        if self.handle:
            self.lib.gxdiag_producer_close_v1(self.handle)
            self.handle = ctypes.c_void_p()
