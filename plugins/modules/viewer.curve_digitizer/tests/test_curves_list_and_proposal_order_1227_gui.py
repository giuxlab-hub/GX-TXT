# SPDX-License-Identifier: GPL-3.0-or-later
"""Tk/Xvfb regression: independent curve-list scroll and ordered proposal edits."""
import sys, pathlib, tkinter as tk
from PIL import Image, ImageDraw
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'python'))
from gxtxt_curve_digitizer import CurveDigitizerApp, CORE_PREFS, b64e
from digitizer_model import Series

def records(*rows):
    return '\n'.join('\t'.join([key] + [b64e(str(v)) for v in values]) for key, values in rows)

class RPC:
    def attach(self, root): pass
    def call(self, cmd, *args):
        if cmd == 'CONFIG_READ':
            return records(*(('SETTING', [key, val, 'user']) for key, val in CORE_PREFS.items()))
        if cmd == 'DOC_UPDATE':
            return args[0] + '\t' + 'a'*64
        if cmd == 'IMAGE_TOOL':
            return ''
        raise AssertionError((cmd, args))

root = tk.Tk(); root.geometry('1160x780+5+5')
app = CurveDigitizerApp(root, RPC(), bootstrap_payload=records(('SESSION',['session'])))
app.config = app.new_configuration('scroll-and-order')
app.config['source'] = {'dataset_id':'test','sha256':'a'*64, 'width':300,'height':160}
app.current_doc_id = 'doc'
app.document_sha['doc'] = 'a'*64
im = Image.new('RGB',(300,160),'white')
ImageDraw.Draw(im).line([(5,130),(75,65),(155,40),(280,25)],fill='black',width=3)
app.set_image(im)
app.notebook.select(app.curves_tab)
for label, x, y in [('bottom_left',0,159),('bottom_right',299,159),
                    ('top_left',0,0),('top_right',299,0)]:
    app.project.calibration.set_corner(label,x,y)

# A long series list scrolls independently of the enclosing Curves page.
app.project.series = [Series(name=f'curve-{i:02d}') for i in range(30)]
app.active_series_id = app.project.series[0].id
app.refresh_curve_tree()
root.update_idletasks(); root.update()
assert app.curve_tree_scrollbar.winfo_ismapped(), 'No dedicated curve-list scrollbar'
app.curve_tree.yview_moveto(.55)
root.update_idletasks(); root.update()
before_tree = app.curve_tree.yview()[0]
before_page = app.curves_scroll_canvas.yview()[0]
assert before_tree > .4, ('Tree did not scroll independently', app.curve_tree.yview())
app.curve_tree.event_generate('<MouseWheel>', delta=-120)
root.update()
assert app.curve_tree.yview()[0] > before_tree, ('Mouse wheel did not scroll tree', before_tree, app.curve_tree.yview())
assert abs(app.curves_scroll_canvas.yview()[0] - before_page) < 1e-8, (
    'Mouse wheel improperly moved enclosing Curves page',before_page,app.curves_scroll_canvas.yview())
# Updating point counts or visibility never resets the curve list to its top.
prev = app.curve_tree.yview()[0]
app.project.series[17].points.clear()
app.project.series[17].visible = False
app.refresh_curve_tree()
root.update_idletasks(); root.update()
assert abs(app.curve_tree.yview()[0] - prev) < 1e-7, (
    'Refreshing curve rows resets scroll position', prev, app.curve_tree.yview())

# The selected destination interval is determined by final scientific X, not
# by the generated point the operator originally grabbed on the preview.
app.project.series = [Series(name='trace')]
app.active_series_id = app.project.series[0].id
app.refresh_curve_tree()
app.guide_points = [(5.,130.), (75.,65.), (155.,40.), (280.,25.)]
app.curve_monotonicity.set('x'); app.point_order_source.set('x')
app._finish_guided_proposal(None,'offline')
assert len(app.assisted_proposal.segments) == 3, app.assist_status.get()
# Press a generated vertex on the FIRST segment and drop into the SECOND.
app._assist_drag = ('insert',0,1)
app._assist_preview_cursor = (110.,55.)
app._finish_proposal_edit(110.,55.)
assert len(app.guide_points) == 5, app.assist_status.get()
assert app.guide_points[2] == (110.,55.), (app.guide_points,app.assist_status.get())
assert len(app.assisted_proposal.segments) == 4
assert [p[0] for p in app.guide_points] == sorted(p[0] for p in app.guide_points)
assert app.assist_segment.get() == 2
# Now grab a vertex of a LATER segment and place the correction BEFORE G2.
app._assist_drag = ('insert',3,1)
app._assist_preview_cursor = (50.,100.)
app._finish_proposal_edit(50.,100.)
assert len(app.guide_points) == 6, app.assist_status.get()
assert app.guide_points[1] == (50.,100.), app.guide_points
assert [p[0] for p in app.guide_points] == sorted(p[0] for p in app.guide_points)
assert len(app.assisted_proposal.segments) == len(app.guide_points)-1
# Undo precisely restores previous topology; nothing scientific accepted.
app.undo_proposal_edit()
assert len(app.guide_points) == 5
assert app.guide_points[2] == (110.,55.)
assert not app.project.series[0].points
root.destroy()
print('PASS dedicated list scrollbar/wheel, tree refresh retention, moved correction order and undo')
