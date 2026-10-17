# SPDX-License-Identifier: GPL-3.0-or-later
"""Regression: a long curve list must NEVER scroll the parent Curves page.

Test both normal Tk wheel delivery to the Treeview and a Windows-style wheel
routed to the top-level while the pointer is still inside the curve list.
Also check redundant parent scrollbar suppression on an already fitted page.
"""
from __future__ import annotations
import pathlib, sys, tkinter as tk
from types import SimpleNamespace
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]/'python'))
from gxtxt_curve_digitizer import CurveDigitizerApp, CORE_PREFS, b64e
from digitizer_model import Series


def records(*rows):
    return '\n'.join('\t'.join([key]+[b64e(str(v)) for v in values]) for key, values in rows)


class RPC:
    def attach(self, root): pass
    def call(self, cmd, *args):
        if cmd == 'CONFIG_READ':
            return records(*(('SETTING', [key, value, 'user']) for key, value in CORE_PREFS.items()))
        if cmd == 'DOC_UPDATE': return args[0] + '\t' + 'a'*64
        if cmd == 'IMAGE_TOOL': return ''
        raise AssertionError((cmd, args))


root = tk.Tk()
root.geometry('1160x780+10+10')
app = CurveDigitizerApp(root, RPC(), bootstrap_payload=records(('SESSION',['test_session'])))
app.notebook.select(app.curves_tab)
app.project.series = [Series(name=f'curve_{n:03d}') for n in range(45)]
app.active_series_id = app.project.series[0].id
app.refresh_curve_tree()
root.update()

outer = app.curves_scroll_canvas
inner = app.curve_tree
assert app.curve_tree_scrollbar.winfo_ismapped(), 'Dedicated curve-list scrollbar must be visible'
assert app._curves_page_scrollable, 'Expected outer page to overflow at this screen height'
assert app.curves_scrollbar.winfo_ismapped(), 'Outer page overflow should remain reachable'

# Ordinary dispatch must scroll ONLY the curve list.
outer.yview_moveto(.2)
inner.yview_moveto(.3)
root.update()
parent_before = outer.yview()[0]
child_before = inner.yview()[0]
inner.event_generate('<MouseWheel>', delta=-120)
root.update()
assert inner.yview()[0] > child_before, (inner.yview(), child_before)
assert abs(outer.yview()[0] - parent_before) < 1e-7, (outer.yview(), parent_before)

# Simulate a Windows/Tk wheel delivered via the top-level instead of Treeview:
# even in that case, pointer over the list must NEVER move the outer canvas.
inside_list = (app.curve_list_frame.winfo_rootx() + 25,
               app.curve_list_frame.winfo_rooty() + 30)
actual_pointer = outer.winfo_pointerxy
outer.winfo_pointerxy = lambda: inside_list
try:
    for _ in range(5):
        ret = app._curves_mousewheel(SimpleNamespace(num=None,delta=-120, widget=root))
        assert ret == 'break', ret
        root.update()
        assert abs(outer.yview()[0] - parent_before) < 1e-7, (outer.yview(), parent_before)
finally:
    outer.winfo_pointerxy = actual_pointer

# Over any ordinary control that is not the curve table, outer scrolls normally
# when the tab actually exceeds the viewport height.
inside_controls = (app.assist_frame.winfo_rootx()+20,
                   app.assist_frame.winfo_rooty()+20)
outer.winfo_pointerxy = lambda: inside_controls
try:
    before = outer.yview()[0]
    ret=app._curves_mousewheel(SimpleNamespace(num=None,delta=-120,widget=app.assist_frame))
    root.update()
    assert ret == 'break'
    assert outer.yview()[0] > before, (before, outer.yview())
finally:
    outer.winfo_pointerxy=actual_pointer

# A page that fits vertically must not expose an idle, second scrollbar.
orig_height = outer.winfo_height
outer.winfo_height = lambda: app.curves_body.winfo_height()+80
try:
    app._curves_scroll_region()
    assert not app._curves_page_scrollable
    assert not app.curves_scrollbar.winfo_manager(), 'Parent scroll bar not hidden on fitted page'
    assert outer.yview()[0] == 0.0
finally:
    outer.winfo_height = orig_height
app._curves_scroll_region()
root.update()
assert app._curves_page_scrollable
assert app.curves_scrollbar.winfo_ismapped()

root.destroy()
print('PASS tree-only wheel, fallback root dispatch, conditional parent scrollbar, and outer controls scroll')
