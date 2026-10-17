# SPDX-License-Identifier: GPL-3.0-or-later
"""Tk/Xvfb test of namespace filtering and automatic catalog invalidation."""
from __future__ import annotations

import sys
import tkinter as tk
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))
from gxtxt_curve_digitizer import CurveDigitizerApp, b64e


def records(*items):
    return "\n".join("\t".join([kind] + [b64e(str(x)) for x in values])
                     for kind, values in items)


class FakeRpc:
    def __init__(self):
        self.counter = 0
        self.responses = {}
        self.sha = "abc"
        self.revision = 3
        self.session = "session"
        self.images = [
            ("image_one", "group/sem", "image.raster", "png", "image/png", "abc"),
            ("image_two", "base", "image.raster", "png", "image/png", "xyz"),
        ]

    def attach(self, root):
        return None

    def begin(self, command, *args):
        self.counter += 1
        request_id = str(self.counter)
        state = ("STATE", [self.session, "catalog-token", str(self.revision), "base"])
        if command == "CATALOG_REV":
            payload = records(state)
        elif command == "BOOTSTRAP":
            payload = records(("SESSION", [self.session]))
        elif command == "CATALOG":
            payload = records(state, ("NAMESPACE", ["base"]),
                              ("NAMESPACE", ["group"]), ("NAMESPACE", ["group/sem"]),
                              *(("IMAGE", list(img)) for img in self.images))
        else:
            raise AssertionError(f"Unexpected async command {command}")
        self.responses[request_id] = payload
        return request_id

    def poll_response(self, request_id):
        return self.responses.pop(request_id)

    def call(self, command, *args):
        assert command == "SOURCE", command
        return records(("ID", [args[0]]), ("SHA256", [self.sha]),
                       ("METADATA", ["image.width_px", "720"]),
                       ("METADATA", ["image.height_px", "560"]))


def main():
    root = tk.Tk()
    root.withdraw()
    rpc = FakeRpc()
    bootstrap = records(("SESSION", ["session"]),
                        ("DATASET", ["image_one", "image.raster", "png", "image/png", "abc"]),
                        ("DATASET", ["image_two", "image.raster", "png", "image/png", "xyz"]))
    app = CurveDigitizerApp(root, rpc, bootstrap_payload=bootstrap)
    root.deiconify()
    root.update_idletasks()
    assert app.status_label.winfo_exists()
    assert not hasattr(app, "namespace_combo")
    assert app.source_combo.winfo_exists()
    assert app.config_combo.winfo_exists()
    app.check_dataset_catalog(force=True)
    app._poll_catalog_reply()
    assert app.catalog_revision == 3
    assert sorted(app.datasets) == ["image_one", "image_two"]
    app.open_namespace_picker()
    root.update_idletasks()
    assert app.namespace_dialog.winfo_exists()
    app.namespace_dialog.destroy()
    app.namespace_var.set("group")
    app.on_namespace_selected()
    assert app.dataset_choices() == ["image_one"]
    app.namespace_var.set("base")
    app.on_namespace_selected()
    assert app.dataset_choices() == ["image_two"]
    app.namespace_var.set("All namespaces")
    app.on_namespace_selected()
    app.current_doc_id = "doc_one"
    app.config = {"source": {"dataset_id": "image_one", "sha256": "abc"}}
    app.source_var.set("image_one")
    app.check_dataset_catalog(force=True)
    app._poll_catalog_reply()
    assert app.stale_source is False
    assert app.source_var.get() == "image_one"
    # Same Dataset ID with changed contents cannot silently reuse calibration.
    rpc.revision = 4
    rpc.sha = "changed"
    rpc.images[0] = ("image_one", "group/sem", "image.raster", "png", "image/png", "changed")
    app.check_dataset_catalog()
    app._poll_catalog_reply()  # changed revision -> request authoritative catalog
    app._poll_catalog_reply()  # apply catalog -> verify source SHA
    assert app.stale_source is True
    assert app.config["source"]["sha256"] == "abc"
    assert app.source_var.get() == "image_one"
    # When an image disappears, retain the historical selector and identity.
    rpc.revision = 5
    rpc.images.pop(0)
    app.check_dataset_catalog()
    app._poll_catalog_reply()
    app._poll_catalog_reply()
    assert app.stale_source is True
    assert app.source_var.get() == "image_one"
    assert "MISSING" in app.source_diag.get()
    # Session switch immediately invalidates old edits and reloads the new
    # Session instead of retaining a stale, permanently disabled viewer.
    rpc.session = "other-session"
    rpc.revision = 6
    app.check_dataset_catalog()
    app._poll_catalog_reply()
    assert app.catalog_session_invalid is True
    assert app.session_refreshing is True
    app._poll_session_bootstrap()
    assert app.catalog_session_invalid is False
    assert app.session_token == "other-session"
    assert app.current_doc_id is None
    assert app.source_var.get() == ""
    assert app.documents == {}
    root.destroy()
    print("PASS Tk workspace filtering, revision monitoring, unchanged linked Dataset identity, stale source guard")


if __name__ == "__main__":
    main()
