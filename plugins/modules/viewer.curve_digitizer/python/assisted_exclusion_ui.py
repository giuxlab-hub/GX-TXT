# SPDX-License-Identifier: GPL-3.0-or-later
"""Source-bound, per-curve exclusion paths with unified GX-TXT Edit history."""
from __future__ import annotations
import copy
import math
import uuid
from assisted_constraints import spline_points
from tkinter import messagebox

class ExclusionControls:
    def exclusion_setup(self):
        self.exclusion_paths = {}
        self.exclusion_origin_sha = ""
        self.exclusion_drag = None
        self.exclusion_loading = False

    @staticmethod
    def _normalized_paths(raw):
        result = {}
        if not isinstance(raw,dict): return result
        for curve, paths in raw.items():
            if not isinstance(curve,str) or not isinstance(paths,list): continue
            clean=[]
            for ordinal, old in enumerate(paths[:16]):
                nodes=old.get('nodes',[]) if isinstance(old,dict) else old
                if not isinstance(nodes,list) or len(nodes)>200: continue
                try:
                    nodes=[[float(pt[0]),float(pt[1])] for pt in nodes
                           if isinstance(pt,(list,tuple)) and len(pt)==2
                           and all(math.isfinite(float(v)) for v in pt)]
                except (ValueError,TypeError,OverflowError): continue
                # Migrate 2.0.5 list-only paths without losing any node.
                clean.append({'id':old.get('id') if isinstance(old,dict) and isinstance(old.get('id'),str)
                              and old.get('id') else 'exclude_legacy_'+uuid.uuid5(uuid.NAMESPACE_URL,
                                                curve+':'+str(ordinal)).hex,
                              'enabled':bool(old.get('enabled',True)) if isinstance(old,dict) else True,
                              'nodes':nodes})
            if clean:result[curve]=clean
        return result

    def exclusion_load(self):
        stored=self.config.get('tracing_constraints') or {}
        self.exclusion_loading=True
        try:
            self.exclusion_paths=self._normalized_paths(stored.get('paths_by_curve',{}))
            self.exclusion_origin_sha=str(stored.get('source_sha256',''))
            self.exclusion_drag=None
            self.exclusion_selected_id=None
            prior=stored.get('smoothness','Off')
            self.assist_smoothness.set(prior if prior in ('Off','Gentle','Strong') else 'Off')
            self.exclusion_enabled.set(bool(stored.get('enabled',True)))
            try:self.exclusion_width.set(max(1,min(40,int(stored.get('width',6)))))
            except (ValueError,TypeError):self.exclusion_width.set(6)
            self.exclusion_path_index.set(1)
        finally:self.exclusion_loading=False
        self.exclusion_refresh_list()

    def exclusion_record(self):
        return {'smoothness':self.assist_smoothness.get(),
                'enabled':bool(self.exclusion_enabled.get()),
                'width':max(1,min(40,int(self.exclusion_width.get()))),
                'source_sha256':self.exclusion_origin_sha,
                'paths_by_curve':copy.deepcopy(self.exclusion_paths)}

    def exclusion_entries(self):
        return self.exclusion_paths.get(self.active_series_id,[])

    def exclusion_active_paths(self):
        if not self.exclusion_enabled.get() or not self.active_series_id:return ()
        sha=str((self.config.get('source') or {}).get('sha256',''))
        if self.exclusion_origin_sha and sha!=self.exclusion_origin_sha:return ()
        return tuple(item['nodes'] for item in self.exclusion_entries()
                     if item['enabled'] and len(item['nodes'])>=2)

    def exclusion_kwargs(self):
        return {'smoothness':self.assist_smoothness.get(),
                'exclusions':self.exclusion_active_paths(),
                'exclusion_width':int(self.exclusion_width.get())}

    def exclusion_refresh_list(self):
        tree=getattr(self,'exclusion_list',None)
        if tree is None or not tree.winfo_exists():return
        paths=self.exclusion_entries()
        selected=getattr(self,'exclusion_selected_id',None)
        tree.delete(*tree.get_children())
        for i,item in enumerate(paths):
            tree.insert('', 'end', iid=item['id'],values=('☑' if item['enabled'] else '☐',
                        'Path '+str(i+1),len(item['nodes'])))
        if selected and tree.exists(selected):
            tree.selection_set(selected)
        elif paths:
            try:index=max(0,min(int(self.exclusion_path_index.get())-1,len(paths)-1))
            except (ValueError,TypeError):index=0
            tree.selection_set(paths[index]['id'])
            self.exclusion_selected_id=paths[index]['id']
        else:self.exclusion_selected_id=None
        self.exclusion_refresh_status()

    def exclusion_refresh_status(self):
        paths=self.exclusion_entries()
        count=sum(1 for x in paths if x['enabled'])
        choice=next((x for x in paths if x['id']==getattr(self,'exclusion_selected_id',None)),None)
        name='none'
        if choice:
            name='Path '+str(paths.index(choice)+1)+' · '+str(len(choice['nodes']))+' X nodes'
        self.exclusion_status.set('Selected: '+name+'  |  Enabled: '+str(count)+'/'+str(len(paths)))

    def exclusion_selected(self):
        paths=self.exclusion_entries()
        selected=getattr(self,'exclusion_selected_id',None)
        for i,item in enumerate(paths):
            if item['id']==selected:return paths,i
        return (paths,0) if paths else (None,None)

    def exclusion_select(self,_event=None):
        tree=getattr(self,'exclusion_list',None)
        if tree is None:return
        selection=tree.selection()
        if selection:
            self.exclusion_selected_id=selection[0]
            paths,index=self.exclusion_selected()
            if index is not None:self.exclusion_path_index.set(index+1)
        self.exclusion_refresh_status()
        self.redraw()

    def exclusion_table_click(self,event):
        tree=self.exclusion_list
        if tree.identify('region',event.x,event.y)!='cell':return
        if tree.identify_column(event.x)!='#1':return
        iid=tree.identify_row(event.y)
        if not iid:return
        self.exclusion_selected_id=iid
        self.exclusion_toggle_path(iid)
        return 'break'

    def exclusion_toggle_path(self,iid):
        target=next((p for p in self.exclusion_entries() if p['id']==iid),None)
        if target is None:return
        self.snapshot()
        target['enabled']=not target['enabled']
        self._exclusion_changed('Path activation changed; regenerate the proposal.')
        
    def exclusion_config_changed(self,*_):
        if self.exclusion_loading or self.loading_ui:return
        if self.assist_smoothness.get() not in ('Off','Gentle','Strong'):
            self.assist_smoothness.set('Off')
        try:self.exclusion_width.set(max(1,min(40,int(self.exclusion_width.get()))))
        except (ValueError,TypeError):self.exclusion_width.set(6)
        old=(self.config.get('tracing_constraints') or {})
        new=self.exclusion_record()
        if old!=new:
            self.snapshot(saved_config=True)
            self._exclusion_changed('Trace constraints updated; regenerate the proposal.')

    def _exclusion_changed(self,message):
        self._assist_proposal_stale = self.assisted_proposal is not None
        self.exclusion_refresh_list()
        self.exclusion_status.set(message)
        self.persist();self.redraw()

    def exclusion_new_path(self):
        if not self.require_working_source() or not self.active_series_id:return
        sha=str((self.config.get('source') or {}).get('sha256',''))
        if self.exclusion_origin_sha and self.exclusion_origin_sha!=sha and self.exclusion_paths:
            self.exclusion_status.set('Source changed: clear all old exclusion paths first.')
            return
        raw=self.exclusion_paths.get(self.active_series_id,[])
        if len(raw)>=16:self.exclusion_status.set('Maximum 16 paths per curve.');return
        self.snapshot()
        raw=self.exclusion_paths.setdefault(self.active_series_id,[])
        self.exclusion_origin_sha=sha
        new={'id':'exclude_'+uuid.uuid4().hex,'enabled':True,'nodes':[]}
        raw.append(new);self.exclusion_selected_id=new['id']
        self.exclusion_path_index.set(len(raw))
        self.mode.set('exclude')
        self._exclusion_changed('New path: click to add red X nodes, or drag an existing X.')

    def exclusion_current(self):
        paths,index=self.exclusion_selected()
        if paths is None:return None,None
        self.exclusion_path_index.set(index+1)
        return paths,index

    def exclusion_press(self,x,y):
        if not self.active_series_id:return
        paths,index=self.exclusion_current()
        if paths is None:
            self.exclusion_new_path()
            paths,index=self.exclusion_current()
            if paths is None:return
        current=paths[index]['nodes']
        cx,cy=self.canvas.image_to_canvas(x,y)
        for j,node in enumerate(current):
            px,py=self.canvas.image_to_canvas(*node)
            if math.hypot(cx-px,cy-py)<=11:
                self.exclusion_drag=(index,j,[float(node[0]),float(node[1])])
                return
        if len(current)>=200:self.exclusion_status.set('Maximum 200 nodes per path.');return
        if current and math.dist(current[-1],(x,y))<.1:
            self.exclusion_status.set('Choose a different raster point.');return
        self.snapshot()
        current.append([float(x),float(y)])
        self._exclusion_changed('Added red X node; regenerate the proposal.')

    def exclusion_move(self,x,y):
        if self.exclusion_drag is None:return
        paths=self.exclusion_entries()
        i,j,_start=self.exclusion_drag
        if i>=len(paths) or j>=len(paths[i]['nodes']):return
        current=paths[i]['nodes']
        point=[float(x),float(y)]
        if ((j>0 and math.dist(current[j-1],point)<.1) or
            (j+1<len(current) and math.dist(current[j+1],point)<.1)):return
        current[j]=point
        self.redraw()

    def exclusion_release(self,x,y):
        if self.exclusion_drag is None:return
        i,j,start=self.exclusion_drag
        self.exclusion_move(x,y)
        self.exclusion_drag=None
        paths=self.exclusion_entries()
        if i>=len(paths) or j>=len(paths[i]['nodes']):return
        end=paths[i]['nodes'][j]
        if math.dist(end,start)>.01:
            # The canvas drag already mutated the current node; register one
            # pre-drag event, never one event per mouse-move pixel.
            self.snapshot(exclusion_previous=(i,j,start))
            self._exclusion_changed('Red X moved; regenerate the proposal.')
        else:self.redraw()

    def exclusion_remove(self,whole=False):
        paths,index=self.exclusion_current()
        if paths is None:return
        if not paths[index]['nodes'] and not whole:return
        self.snapshot()
        if whole:paths.pop(index)
        else:paths[index]['nodes'].pop()
        self.exclusion_selected_id=paths[min(index,len(paths)-1)]['id'] if paths else None
        self._exclusion_changed('Exclusion edit recorded; regenerate the proposal.')

    def exclusion_clear_all(self):
        if not self.exclusion_paths and not self.exclusion_origin_sha:return
        if not messagebox.askyesno('Curve Digitalizer',
            'Clear all exclusion paths? Accepted points and published Datasets remain unchanged.',
            parent=self.root):return
        self.snapshot()
        self.exclusion_paths={}
        self.exclusion_origin_sha=str((self.config.get('source') or {}).get('sha256',''))
        self.exclusion_selected_id=None
        self._exclusion_changed('All exclusion paths cleared.')

    def exclusion_draw(self,canvas):
        if not self._is_curves_tab() or canvas is not self.canvas:return
        for item in self.exclusion_entries():
            nodes=item['nodes']
            if len(nodes)>1:
                try:points=spline_points(nodes,spacing=2)
                except ValueError:points=nodes
                coords=[]
                for x,y in points:
                    px,py=canvas.image_to_canvas(x,y);coords.extend((px,py))
                if len(coords)>=4:
                    active=item['enabled'] and self.exclusion_enabled.get()
                    color='#ff3b3b' if active else '#8e8181'
                    band=max(3,2*float(self.exclusion_width.get())*canvas.scale)
                    if active:canvas.create_line(*coords,fill='#7c2630',width=band,tags=('overlay',))
                    canvas.create_line(*coords,fill=color,width=2,dash=(5,3),tags=('overlay',))
            for x,y in nodes:
                px,py=canvas.image_to_canvas(x,y)
                color='#ff2323' if item['enabled'] else '#8e8181'
                canvas.create_line(px-6,py-6,px+6,py+6,fill=color,width=3,tags=('overlay',))
                canvas.create_line(px-6,py+6,px+6,py-6,fill=color,width=3,tags=('overlay',))
