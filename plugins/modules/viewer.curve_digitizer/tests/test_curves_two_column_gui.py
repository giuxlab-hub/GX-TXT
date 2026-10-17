# SPDX-License-Identifier: GPL-3.0-or-later
"""All Curves sections are vertically stacked; only assistant is two-column."""
import os
import sys
import tkinter as tk
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'python'))
from gxtxt_curve_digitizer import CurveDigitizerApp, CORE_PREFS, b64e


def records(*rows):
    return '\n'.join('\t'.join([name] + [b64e(str(v)) for v in fields]) for name, fields in rows)


class RPC:
    def attach(self, root): pass
    def call(self, command, *args):
        if command == 'CONFIG_READ':
            return records(*(('SETTING', [key, value, 'user']) for key, value in CORE_PREFS.items()))
        if command == 'IMAGE_TOOL': return ''
        raise AssertionError(command)


root = tk.Tk()
root.geometry('1380x830')
app = CurveDigitizerApp(root, RPC(), bootstrap_payload=records(('SESSION', ['session'])))
app.notebook.select(app.curves_tab)
root.update()
canvas = app.curves_scroll_canvas
assert app.curves_body.winfo_exists()
assert app.curve_tree.winfo_ismapped()
assert app._assist_layout_wide
settings, actions = app.assist_trace_settings, app.assist_trace_actions
assert settings.winfo_rootx() < actions.winfo_rootx()
assert abs(settings.winfo_rooty() - actions.winfo_rooty()) <= 4
# The family, curve list, interaction modes and assistant MUST be vertically stacked
# and not split into global work columns.
family = next(x for x in app.curves_body.winfo_children() if 'labelframe' in str(x))
assert family.winfo_rooty() < app.curve_tree.winfo_rooty()
assert app.curve_tree.winfo_rooty() < settings.winfo_rooty()
assert app.assist_segment.get() == 1
assert app.opacity_var.get() == 100
assert not hasattr(app, 'curves_left')
assert not hasattr(app, 'curves_right')
if os.environ.get('GX_CURVES_LAYOUT_SCREENSHOT'):
    from PIL import ImageGrab
    ImageGrab.grab().save(os.environ['GX_CURVES_LAYOUT_SCREENSHOT'])
# Smaller desktop: lower sections are reachable by scrollbar.
root.geometry('1000x580')
root.update()
assert canvas.winfo_height() > 150
bottom = canvas.bbox('all')[3]
assert bottom > canvas.winfo_height(), (bottom, canvas.winfo_height())
canvas.yview_moveto(1)
root.update()
assert canvas.yview()[1] >= 0.999
# Narrow pane: only the two assistant columns are stacked, NOT the entire tab.
app.controls_pane.sashpos(0, 390)
root.update()
assert not app._assist_layout_wide, canvas.winfo_width()
assert actions.winfo_rooty() > settings.winfo_rooty()
assert app.curve_tree.winfo_exists()
canvas.yview_moveto(1)
root.update()
assert canvas.yview()[1] >= 0.999
# Restore normal pane and two assistant subcolumns.
app.controls_pane.sashpos(0, 530)
root.update()
assert app._assist_layout_wide
assert settings.winfo_rootx() < actions.winfo_rootx()
assert app.curves_scrollbar.winfo_exists()
root.destroy()
print('PASS full-width stacked Curves sections, two-column assistant, small-window scrolling')
