# SPDX-License-Identifier: GPL-3.0-or-later
"""Per-curve optional raster stroke-width editor; descriptive only."""
from __future__ import annotations
import copy
import hashlib
import json
import math
import tkinter as tk
from tkinter import ttk
from assisted_constraints import spline_points
from stroke_width_measure import automatic_width, manual_width

def trace_hash(series):
    if series is None:return ''
    data=[[p.id,round(p.pixel_x,6),round(p.pixel_y,6)] for p in series.points]
    return hashlib.sha256(json.dumps(data,separators=(',',':')).encode()).hexdigest()

class StrokeWidthUI:
    def stroke_setup(self):
        self.stroke_data={}
        self.stroke_origin_sha=''
        self.stroke_visible=False
        self.stroke_drag=None
        self.stroke_loading=False
        self.stroke_enabled=tk.BooleanVar(value=False)
        self.stroke_method=tk.StringVar(value='automatic')
        self.stroke_probe=tk.IntVar(value=12)
        self.stroke_edge=tk.StringVar(value='A')
        self.stroke_status=tk.StringVar(value='Stroke-width panel closed.')
        self.stroke_cal_status=tk.StringVar(value='Selected curve: stroke width inactive.')

    def stroke_serialize(self):
        return {'source_sha256':self.stroke_origin_sha,'by_curve':copy.deepcopy(self.stroke_data)}

    def stroke_load(self):
        saved=self.config.get('stroke_width') or {}
        self.stroke_data=copy.deepcopy(saved.get('by_curve') or {})
        if not isinstance(self.stroke_data,dict):self.stroke_data={}
        self.stroke_origin_sha=str(saved.get('source_sha256',''))
        self.stroke_drag=None
        self.stroke_refresh()

    def stroke_active_record(self):
        return self.stroke_data.get(self.active_series_id) if self.active_series_id else None

    def stroke_record(self):
        return self.stroke_data.setdefault(self.active_series_id,{
            'enabled':False,'method':'automatic','probe_px':12,'edges':{'A':[],'B':[]},'result':None,
            'source_sha256':str((self.config.get('source') or {}).get('sha256',''))})

    def stroke_valid_source(self):
        return (self.image is not None and bool(self.stroke_origin_sha) and
                self.stroke_origin_sha==str((self.config.get('source') or {}).get('sha256','')))

    def stroke_valid_result(self,series,rec):
        result=rec.get('result') or {}
        if not result or not self.stroke_valid_source():return False
        if rec.get('source_sha256','') != str((self.config.get('source') or {}).get('sha256','')):return False
        if rec.get('method')=='automatic' and result.get('trace_sha256')!=trace_hash(series):return False
        return True

    def stroke_refresh(self):
        self.stroke_loading=True
        try:
            rec=self.stroke_active_record() or {}
            self.stroke_enabled.set(bool(rec.get('enabled',False)))
            self.stroke_method.set(rec.get('method','automatic') if rec.get('method') in ('manual','automatic') else 'automatic')
            self.stroke_probe.set(max(2,min(40,int(rec.get('probe_px',12)))))
        except (ValueError,TypeError):self.stroke_probe.set(12)
        finally:self.stroke_loading=False
        self.stroke_update_status()

    def stroke_summary(self):
        series=self.active_series()
        if series is None:return 'No curve selected.'
        rec=self.stroke_active_record() or {}
        if not rec.get('enabled',False):return series.name+': INACTIVE.'
        if (not self.stroke_valid_source() or
            rec.get('source_sha256','')!=str((self.config.get('source') or {}).get('sha256',''))):
            return series.name+': STALE source image; no active measurement.'
        if not self.stroke_valid_result(series,rec):
            return series.name+': enabled; no valid current measurement.'
        measure=rec['result']
        return (f"{series.name}: ACTIVE {rec['method']}, {measure['width_px']:.2f} px (median), "
                f"{measure['accepted_samples']} accepted / {measure['rejected_samples']} rejected probes.")

    def stroke_update_status(self):
        status=self.stroke_summary()
        self.stroke_status.set(status)
        self.stroke_cal_status.set('Stroke width — '+status+
            '\nDiagnostic only: NOT a standard uncertainty; no implicit CORE Numeric propagation.')

    def stroke_toggle_panel(self):
        self.stroke_visible=not self.stroke_visible
        if self.stroke_visible:
            self.stroke_panel.pack(fill='x',after=self.stroke_buttons,pady=(4,6))
            self.stroke_refresh()
        else:
            self.stroke_panel.pack_forget()
            if self.mode.get()=='stroke_edge':self.mode.set('add')

    def stroke_open_from_calibration(self):
        self.notebook.select(self.curves_tab)
        if not self.stroke_visible:self.stroke_toggle_panel()

    def stroke_preferences_changed(self,*_):
        if self.stroke_loading or self.loading_ui or not self.active_series_id:return
        try:probe=int(self.stroke_probe.get())
        except (ValueError,TypeError,tk.TclError):return
        if not 2<=probe<=40:return
        method=self.stroke_method.get()
        if method not in ('manual','automatic'):return
        enabled=bool(self.stroke_enabled.get())
        existing=self.stroke_active_record() or {}
        new_sha=str((self.config.get('source') or {}).get('sha256',''))
        if enabled and ((self.stroke_origin_sha and self.stroke_origin_sha!=new_sha) or
                        (existing.get('source_sha256') and existing.get('source_sha256')!=new_sha)):
            self.stroke_loading=True
            try:self.stroke_enabled.set(bool(existing.get('enabled',False)))
            finally:self.stroke_loading=False
            self.stroke_status.set('Different raster: reset this curve measurement before re-enabling.')
            return
        old=(bool(existing.get('enabled')),existing.get('method','automatic'),int(existing.get('probe_px',12)))
        if old==(enabled,method,probe):return
        self.snapshot()
        rec=self.stroke_record()
        rec.update(enabled=enabled,method=method,probe_px=probe,result=None,source_sha256=new_sha)
        self.stroke_origin_sha=str((self.config.get('source') or {}).get('sha256',''))
        self.stroke_update_status()
        self.persist();self.redraw()

    def stroke_reset_curve(self):
        if not self.active_series_id:return
        self.snapshot()
        self.stroke_data.pop(self.active_series_id,None)
        self.stroke_origin_sha=str((self.config.get('source') or {}).get('sha256',''))
        self.stroke_refresh()
        self.persist();self.redraw()

    def stroke_auto_measure(self):
        if not self.require_working_source() or not self.active_series_id:return
        if self.stroke_origin_sha and not self.stroke_valid_source():
            self.stroke_status.set('Source changed; reset this curve measurement before using the new raster.')
            return
        series=self.active_series()
        rec=self.stroke_active_record() or {}
        if series is None or not rec.get('enabled',False):
            self.stroke_status.set('Enable measurement for the selected curve first.');return
        try:
            points=[(p.pixel_x,p.pixel_y) for p in series.points]
            result=automatic_width(self.image,points,radius=int(self.stroke_probe.get()))
        except (ValueError,TypeError) as exc:
            self.stroke_status.set('Auto measurement failed: '+str(exc));return
        self.snapshot()
        self.stroke_origin_sha=str((self.config.get('source') or {}).get('sha256',''))
        rec=self.stroke_record()
        result['trace_sha256']=trace_hash(series)
        rec['method']='automatic'
        rec['source_sha256']=str((self.config.get('source') or {}).get('sha256',''))
        rec['result']=result
        self.stroke_refresh()
        self.persist();self.redraw()

    def stroke_edit_mode(self):
        if not self.require_working_source() or not self.active_series_id:return
        if self.stroke_origin_sha and not self.stroke_valid_source():
            self.stroke_status.set('Source changed; reset this curve measurement before editing boundaries.')
            return
        if self.stroke_method.get()!='manual':
            self.stroke_method.set('manual')
            self.stroke_preferences_changed()
        if not self.stroke_enabled.get():
            self.stroke_enabled.set(True)
            self.stroke_preferences_changed()
        self.stroke_origin_sha=str((self.config.get('source') or {}).get('sha256',''))
        self.mode.set('stroke_edge')
        self.stroke_status.set('Place nodes for edge '+self.stroke_edge.get()+
            ' on the original ink boundary; drag existing handles to refine.')

    def stroke_path(self,edge=None):
        return self.stroke_record().setdefault('edges',{}).setdefault(edge or self.stroke_edge.get(),[])

    def stroke_edge_press(self,x,y):
        if not self.stroke_visible or not self.active_series_id:return
        rec=self.stroke_active_record()
        if rec is None or not rec.get('enabled'):return
        path=self.stroke_path()
        cx,cy=self.canvas.image_to_canvas(x,y)
        for j,(px,py) in enumerate(path):
            a,b=self.canvas.image_to_canvas(px,py)
            if math.hypot(a-cx,b-cy)<=10:
                self.stroke_drag=(self.stroke_edge.get(),j,[px,py],self._history_capture())
                return
        if len(path)>=200 or (path and math.dist(path[-1],(x,y))<.2):return
        self.snapshot()
        path.append([float(x),float(y)])
        rec['result']=None
        self.stroke_update_status();self.persist();self.redraw()

    def stroke_edge_drag(self,x,y):
        if self.stroke_drag is None:return
        edge,j,_start,_snapshot=self.stroke_drag
        path=self.stroke_path(edge)
        if not 0<=j<len(path):return
        target=[float(x),float(y)]
        if ((j>0 and math.dist(target,path[j-1])<.2) or
            (j+1<len(path) and math.dist(target,path[j+1])<.2)):return
        path[j]=target;self.redraw()

    def stroke_edge_release(self,x,y):
        if self.stroke_drag is None:return
        self.stroke_edge_drag(x,y)
        edge,j,start,original=self.stroke_drag
        self.stroke_drag=None
        path=self.stroke_path(edge)
        if not 0<=j<len(path) or math.dist(path[j],start)<.05:return
        # Exactly one chronological Edit/Undo event for a complete mouse drag.
        self.undo_stack.append(original)
        self.undo_stack=self.undo_stack[-100:]
        self.redo_stack.clear()
        self.stroke_record()['result']=None
        self.stroke_update_status();self.persist();self.redraw()

    def stroke_delete_node(self):
        if not self.active_series_id:return
        path=self.stroke_path()
        if not path:return
        self.snapshot();path.pop()
        self.stroke_record()['result']=None
        self.stroke_update_status();self.persist();self.redraw()

    def stroke_clear_edges(self):
        rec=self.stroke_active_record()
        if rec is None or not any(rec.get('edges',{}).values()):return
        self.snapshot()
        rec['edges']={'A':[],'B':[]};rec['result']=None
        self.stroke_update_status();self.persist();self.redraw()

    def stroke_manual_measure(self):
        if not self.stroke_valid_source() or (
            self.stroke_active_record() or {}).get('source_sha256','') != str((self.config.get('source') or {}).get('sha256','')):
            self.stroke_status.set('Source changed or unavailable; reset this measurement first.')
            return
        rec=self.stroke_active_record()
        if not rec or not rec.get('enabled',False):return
        try:
            a=rec['edges']['A'];b=rec['edges']['B']
            result=manual_width(a,b)
        except (ValueError,TypeError,KeyError) as exc:
            self.stroke_status.set('Manual measurement failed: '+str(exc));return
        self.snapshot()
        rec['method']='manual'
        rec['source_sha256']=str((self.config.get('source') or {}).get('sha256',''))
        rec['result']=result
        self.stroke_update_status();self.persist();self.redraw()

    def stroke_draw(self,canvas):
        if not self.stroke_visible or not self._is_curves_tab() or canvas is not self.canvas:return
        rec=self.stroke_active_record()
        if not rec or not rec.get('enabled'):return
        for edge,color in (('A','#48baff'),('B','#aaf05a')):
            nodes=rec.get('edges',{}).get(edge,[])
            if len(nodes)>=2:
                try:points=spline_points(nodes,spacing=1.5)
                except ValueError:points=nodes
                coords=[]
                for x,y in points:
                    px,py=canvas.image_to_canvas(x,y);coords.extend((px,py))
                if len(coords)>=4:canvas.create_line(*coords,fill=color,width=2,dash=(3,2),tags=('overlay',))
            for x,y in nodes:
                px,py=canvas.image_to_canvas(x,y)
                canvas.create_rectangle(px-5,py-5,px+5,py+5,outline=color,width=2,tags=('overlay',))
