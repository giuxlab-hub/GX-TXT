# SPDX-License-Identifier: GPL-3.0-or-later
"""F5 GUI: 14 shared sigmas / 3 physical uncertainty values on Y2."""
import os
from pathlib import Path
from PIL import ImageGrab

MODULE=Path(__file__).resolve().parents[1]
fixture_path = MODULE/"tests/test_y2_f3_gui_publication.py"
fixture_namespace = {"__name__":"f5_fixture_helpers", "__file__":str(fixture_path)}
fixture_source = fixture_path.read_text(encoding="utf-8")
assert "\nyes=gui.messagebox.askyesno" in fixture_source
exec(compile(fixture_source.split("\nyes=gui.messagebox.askyesno")[0],
             str(fixture_path), "exec"), fixture_namespace)
prepare = fixture_namespace["prepare"]
root,app,rpc,errors=prepare("test_01_logx_y1lin_y2lin")
from uncertainty_dialog import UncertaintyDialog
from uncertainty_engine import review_fingerprint
from digitizer_model import Project
from gxtxt_curve_digitizer import PLUGIN_VERSION

try:
    assert PLUGIN_VERSION=="2.0.25"
    app.snapshot=lambda:None
    app.persist=lambda:True
    dialog=UncertaintyDialog(app)
    root.update()
    assert dialog.dual_y
    dialog.values["mode"].set("pixel_calibration")
    dialog.values["pixel_distribution"].set("normal_standard_uncertainty")
    dialog.values["pixel_scale"].set("0.4 0.6")
    dialog.values["calibration_standard_uncertainty"].set(" ".join(["0.1"]*14))
    dialog.values["rationale"].set("Reviewed synthetic correlated Y1 and Y2 source")
    spec=dialog.declaration()
    assert len(spec["calibration_standard_uncertainty"])==14
    root.update()  # Ensure the displayed declaration is current in screenshots.
    if os.environ.get("GX_F5_DIALOG_SCREENSHOT"):
        target=Path(os.environ["GX_F5_DIALOG_SCREENSHOT"])
        target.parent.mkdir(parents=True,exist_ok=True)
        ImageGrab.grab().save(target)
        print("SCREENSHOT",target)
    dialog.apply()
    assert app.config["uncertainty"]["mode"]=="pixel_calibration"
    assert len(app.config["uncertainty"]["calibration_standard_uncertainty"])==14
    assert app.config["uncertainty"]["review_fingerprint"]==review_fingerprint(
        app.serialize_configuration())
    dialog.values["mode"].set("physical_override")
    dialog.values["override_standard_uncertainty"].set("0.1 0.2 0.7")
    spec=dialog.declaration()
    assert spec["override_standard_uncertainty"]==[0.1,0.2,0.7]
    dialog.apply()
    assert len(app.config["uncertainty"]["override_standard_uncertainty"])==3
    dialog.destroy()
    # Monoaxis legacy editor remains 12 and 2 values, not widened spuriously.
    app.project=Project()
    app.config=app.new_configuration("Monoaxis legacy")
    legacy=UncertaintyDialog(app)
    assert not legacy.dual_y
    legacy.values["mode"].set("pixel_calibration")
    legacy.values["pixel_distribution"].set("normal_standard_uncertainty")
    legacy.values["pixel_scale"].set("0.4 0.6")
    legacy.values["calibration_standard_uncertainty"].set(" ".join(["0.1"]*12))
    legacy.values["rationale"].set("Legacy approved pixel calibration")
    assert len(legacy.declaration()["calibration_standard_uncertainty"])==12
    legacy.values["mode"].set("physical_override")
    legacy.values["override_standard_uncertainty"].set("0.1 0.2")
    assert legacy.declaration()["override_standard_uncertainty"]==[0.1,0.2]
    legacy.destroy()
    print("PASS F5 GUI: 14/3 Y1+Y2 declared, review fingerprint, 12/2 legacy preserved")
finally:
    root.destroy()
