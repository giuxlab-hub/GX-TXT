# SPDX-License-Identifier: GPL-3.0-or-later
"""Legacy Y1 separate calibrations can also opt into Group creation."""
from __future__ import annotations

import runpy
import tkinter as tk
from pathlib import Path
from tkinter import messagebox

baseline=Path(__file__).with_name("test_publication_three_curves_2020_gui.py")
namespace=runpy.run_path(str(baseline))
root,app,rpc=namespace["create"]()
messages=[]
records=[]
original_call=rpc.call
old_error=messagebox.showerror
old_yes=messagebox.askyesno

def fake_call(command,*args):
    if command=="GROUP_CAPABLE":return "1"
    if command=="GROUP_CREATE":
        token,group_id,caption,ids=args
        assert group_id.startswith("cdg_")
        records.append((group_id,ids.splitlines()))
        return group_id
    if command=="PUBLISH":
        original_call(command,*args)  # Retain full original scientific payload.
        return (args[2] + "\t/mock/no-write.csv\t" + "a"*64 + "\tcurve_family.table")
    return original_call(command,*args)

rpc.call=fake_call
messagebox.showerror=lambda *a,**k:messages.append(a)
messagebox.askyesno=lambda *a,**k:True
try:
    assert not app.publish_group_datasets.get()
    app.publish_group_datasets.set(True)
    app.publish_layout.set("separate")
    app.refresh_publish_measurements()
    app.select_all_publish_measurements()
    app.publish_dataset()
    assert not messages,messages
    assert len(rpc.requests)==3,len(rpc.requests)
    assert len(records)==1,records
    print("GROUP MEMBERS",repr(records[0][1]))
    print("PUBLISHED IDS",repr([args[2] for args in rpc.requests]))
    assert records[0][1]==[args[2] for args in rpc.requests]
    assert "Dataset Group: cdg_" in app.publish_result.get()
    assert app.serialize_configuration()["publication"]["group_datasets"]
    print("PASS F4 legacy Y1: three split calibration outputs, one explicitly opted-in Group")
finally:
    messagebox.showerror=old_error
    messagebox.askyesno=old_yes
    for event in root.tk.call("after","info"):
        try:root.after_cancel(event)
        except tk.TclError:pass
    try:root.destroy()
    except tk.TclError:pass
