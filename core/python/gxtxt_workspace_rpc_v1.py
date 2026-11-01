# SPDX-License-Identifier: GPL-3.0-or-later
"""Lifecycle transport for existing desktop Workspace clients.

The reader thread only queues bytes. All UI/model callbacks run on the original
Tk thread. Native CORE owns every saved object, receipt and persistence barrier.
"""
from __future__ import annotations

import base64
import queue
import sys
import threading
from tkinter import TclError, messagebox


def _encode(value: str) -> str:
    return base64.b64encode(str(value).encode("utf-8")).decode("ascii")


def _decode(value: str) -> str:
    return base64.b64decode(value, validate=True).decode("utf-8")


class WorkspaceRpcClient:
    def __init__(self):
        self.counter = 0
        self.focus_callback = None
        self.control_callback = None
        self._incoming = queue.Queue()
        self._responses = {}
        self._depth = 0
        self._root = None
        self._closed = False
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for line in sys.stdin:
            self._incoming.put(line.rstrip("\n"))
        self._incoming.put(None)

    def attach(self, root, control_callback):
        self._root = root
        self.control_callback = control_callback
        root.after(30, self._poll)

    def _consume(self, line):
        if line is None:
            self._closed = True
            raise RuntimeError("The GX-TXT host connection closed; this desktop cannot write to another Session")
        fields = line.split("\t")
        if fields == ["CONTROL", "FOCUS"]:
            if self.focus_callback:
                self.focus_callback()
        elif len(fields) >= 4 and fields[:2] == ["CONTROL", "WORKSPACE"]:
            request, action = fields[2:4]
            try:
                if self.control_callback is None:
                    raise RuntimeError("Workspace desktop has not finished opening")
                result = self.control_callback(action, *(_decode(arg) for arg in fields[4:]))
                status = "OK"
            except Exception as exc:
                status, result = "ERR", str(exc)
            if request != "notice":
                sys.stdout.write("\t".join(["WORKSPACE_RESULT", request, status, _encode(result)]) + "\n")
                sys.stdout.flush()
            if action == "CLOSE" and status == "OK":
                self._closed = True
        elif len(fields) == 4 and fields[0] == "RES":
            self._responses[fields[1]] = (fields[2], _decode(fields[3]))
        else:
            raise RuntimeError("Invalid Workspace desktop response")

    def _poll(self):
        if self._closed:
            return
        try:
            if not self._depth:
                while True:
                    try:
                        line = self._incoming.get_nowait()
                    except queue.Empty:
                        break
                    self._consume(line)
        except RuntimeError as exc:
            if self._root.winfo_exists():
                messagebox.showerror("Workspace connection", str(exc), parent=self._root)
        try:
            if not self._closed and self._root.winfo_exists():
                self._root.after(30, self._poll)
        except TclError:
            self._closed = True

    def call(self, command: str, *args: str) -> str:
        if self._closed:
            raise RuntimeError("The Workspace host connection is closed")
        self.counter += 1
        request = str(self.counter)
        sys.stdout.write("\t".join(["REQ", request, command] + [_encode(arg) for arg in args]) + "\n")
        sys.stdout.flush()
        self._depth += 1
        try:
            while request not in self._responses:
                self._consume(self._incoming.get())
            status, result = self._responses.pop(request)
            if status != "OK":
                raise RuntimeError(result)
            return result
        finally:
            self._depth -= 1


class JsonWorkspaceLifecycle:
    """Optional plumbing mixin; independent clients keep their original UI."""

    def workspace_lifecycle_start(self):
        self.workspace_mark_saved()
        self.rpc.attach(self.root, self.workspace_control)

    def workspace_mark_saved(self):
        self._workspace_baseline = self.workspace_payload()

    def workspace_review(self, action="continuing"):
        # This compares only this owner's explicitly captured model at an
        # explicit transition; there is no polling/serialization on pointer moves.
        baseline = getattr(self, "_workspace_baseline", None)
        try:
            clean = baseline is None or self.workspace_payload() == baseline
        except Exception:
            clean = False
        if clean:
            return True
        answer = messagebox.askyesnocancel(
            "Workspace changes", f"Save the current Workspace before {action}?\n\nYes: Save. No: Discard unsaved changes. Cancel: keep editing.",
            parent=self.root, default="cancel")
        if answer is None:
            return False
        if answer:
            return bool(self.save_workspace())
        return True

    def workspace_control(self, action, *args):
        if action == "REVIEW":
            return "accepted" if self.workspace_review(args[0]) else "cancelled"
        if action == "CLOSE":
            self.dispose()
            return "closed"
        if action == "OPEN":
            return "opened" if self.open_workspace(args[0]) else "cancelled"
        if action == "META":
            identity, generation, before, after, name = args
            if self.document_receipts.get(identity) == (generation, before):
                self.document_receipts[identity] = (generation, after)
            return "notified"
        raise RuntimeError(f"Unsupported Workspace desktop lifecycle action: {action}")
