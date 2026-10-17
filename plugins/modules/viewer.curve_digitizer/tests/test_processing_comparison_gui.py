"""GUI regression: split view, independent/synchronized view and safe point editing."""
# SPDX-License-Identifier: GPL-3.0-or-later
import sys, os, uuid, time, tkinter as tk
from pathlib import Path
from PIL import Image
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/"python"))
from gxtxt_curve_digitizer import CurveDigitizerApp, CORE_PREFS, b64e
from digitizer_model import Series
from processing_controls import merge_filter_operations, FilterControls, STANDARD_ORDER


def records(*rows):
    return "\n".join("\t".join([name] + [b64e(str(v)) for v in fields]) for name, fields in rows)


class Rpc:
    def attach(self, root): pass
    def call(self, command, *args):
        if command == "CONFIG_READ":
            return records(*(("SETTING", [key, value, "user"]) for key, value in CORE_PREFS.items()))
        if command == "CONFIG_COMMIT": return records(*(("SETTING", [key, value, "session"]) for key,value in CORE_PREFS.items()))
        if command == "IMAGE_TOOL": return "/opt/imagemagick/bin/magick\tImageMagick 7 test"
        if command == "DOC_UPDATE": return args[0] + "\t" + uuid.uuid4().hex
        raise AssertionError(command)


# Standard normalizes order; advanced preserves positions and duplicate steps.
ops = [{"kind":"gamma","value":"0.8"},{"kind":"median","value":"2"}]
assert [v["kind"] for v in merge_filter_operations(ops,"sharpen",True,"0x2")] == ["median","gamma","sharpen"]
assert [v["kind"] for v in merge_filter_operations(ops,"sharpen",True,"0x2",advanced=True)] == ["gamma","median","sharpen"]
assert merge_filter_operations(ops,"gamma",False,"",advanced=True) == [{"kind":"median","value":"2"}]
assert [v["kind"] for v in merge_filter_operations([{"kind":"grayscale","value":""}],"channel",True,"Red")] == ["channel"]

root=tk.Tk();root.geometry("1260x820")
app=CurveDigitizerApp(root,Rpc(),bootstrap_payload=records(("SESSION",["session"])))
app.current_doc_id="idoc_011";app.document_sha["idoc_011"]="a"*64
app.config=app.new_configuration("comparison")
app.config["source"]={"dataset_id":"sem.original","sha256":"a"*64,"width":240,"height":180}
app.set_image(Image.new("RGB",(240,180),(120,160,200)))
app.project.series=[Series(name="Reference edge")]
app.active_series_id=app.project.series[0].id
root.update()
assert app.notebook.select() == str(app.source_tab)
app.canvas_press(51,70)
assert len(app.project.series[0].points)==0, "Source tab cannot digitize"
app.add_point(51,70)
assert len(app.project.series[0].points)==0, "direct callback must be guarded too"
app.notebook.select(app.curves_tab);root.update()
app.canvas_press(51,70)
assert len(app.project.series[0].points)==1, "Curves tab must still digitize"
app.notebook.select(app.processing_tab);root.update()
app.canvas_press(52,72)
app.delete_selected_point()
assert len(app.project.series[0].points)==1, "processing tab cannot modify curves"

# Checkbox + slider model updates the exact list of operations.
controls=app.processing_filter_controls
assert isinstance(controls, FilterControls)
assert len(controls.enabled)==11
controls.enabled["gamma"].set(True);controls._emit("gamma",force=True)
assert any(op["kind"]=="gamma" for op in app.processing_operations)
assert controls.widgets["median"][0].instate(["disabled"])
app.processing_compare.set(True);app._update_processing_view_layout();root.update()
assert app.compare_original_canvas.original_image is app.image
assert app.compare_processed_canvas.original_image is app.image
assert app.compare_original_canvas.on_left_press is None
assert app.compare_processed_canvas.on_left_drag is None

# Two canvases have independent scales when synchronization is off.
a,b=app.compare_original_canvas,app.compare_processed_canvas
initial_b=b.scale
a.zoom_at(20,20,1.7);root.update()
assert a.scale!=initial_b and b.scale==initial_b
# With synchronization enabled, both scale and displayed raster center align.
app.processing_sync_views.set(True)
a.zoom_at(35,35,1.2);root.update()
assert abs(a.scale-b.scale)<1e-8
ca=a.canvas_to_image(a.winfo_width()/2,a.winfo_height()/2)
cb=b.canvas_to_image(b.winfo_width()/2,b.winfo_height()/2)
assert max(abs(ca[0]-cb[0]),abs(ca[1]-cb[1]))<1e-7

# Image processing updates only the processed view and never image geometry.
app.processing_executable="/opt/imagemagick/bin/magick"
app.processing_engine_version="ImageMagick 7 test"
app.process_image_preview()
for _ in range(200):
    root.update();time.sleep(.01)
    if not app.processing_active and app.processed_image is not None:break
assert app.processed_image is not None, app.processing_status.get()
assert app.compare_original_canvas.original_image is app.image
assert app.compare_processed_canvas.original_image is app.processed_image
assert app.processed_image.size == app.image.size == (240,180)
# Switching tab restores single editable canvas and never discards scientific work.
app.notebook.select(app.source_tab);root.update()
assert len(app.project.series[0].points)==1
assert not app._is_processing_tab()
root.destroy()
print("PASS split image view, independent/synced pan-zoom, 11 filters, safe Curves-only edits")
