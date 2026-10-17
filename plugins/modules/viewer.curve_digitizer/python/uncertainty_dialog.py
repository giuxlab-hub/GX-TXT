# SPDX-License-Identifier: GPL-3.0-or-later
"""Explicit uncertainty declaration for current Curve Digitalizer v2.0.

The GUI declares scientific assumptions; numerical interpretation and validity
belong to uncertainty_engine, and nothing here modifies the source image.
"""
import copy
import tkinter as tk
from tkinter import ttk, messagebox
from uncertainty_engine import checked_spec, review_fingerprint

class UncertaintyDialog(tk.Toplevel):
    def __init__(self, app):
        super().__init__(app.root)
        self.app=app
        self.title('Pixel and calibration uncertainty')
        self.transient(app.root)
        self.geometry('790x510')
        self.minsize(660,420)
        cfg=app.serialize_configuration()
        spec=cfg.get('uncertainty') or {'mode':'none'}
        fields=[
            ('mode','Error model',spec.get('mode','none'),('none','pixel_calibration','physical_override')),
            ('pixel_distribution','Pixel scale meaning',spec.get('pixel_distribution','rectangular_full_width'),('rectangular_full_width','normal_standard_uncertainty')),
            ('pixel_scale','Pixel X/Y widths or standard uncertainties',spec.get('pixel_scale',[]),None),
            ('calibration_standard_uncertainty','8 corner + 4 axis-endpoint standard uncertainties',spec.get('calibration_standard_uncertainty',[]),None),
            ('override_standard_uncertainty','Physical X/Y standard uncertainties',spec.get('override_standard_uncertainty',[]),None),
            ('rationale','Evidence / reason for declared uncertainty',spec.get('rationale',''),None),
        ]
        self.values={}
        for row,(key,label,value,options) in enumerate(fields):
            v=tk.StringVar(value=' '.join(map(str,value)) if isinstance(value,list) else value)
            self.values[key]=v
            ttk.Label(self,text=label).grid(row=row,column=0,sticky='w',padx=7,pady=5)
            w=ttk.Combobox(self,textvariable=v,values=options,state='readonly') if options else ttk.Entry(self,textvariable=v,width=46)
            w.grid(row=row,column=1,sticky='ew',padx=7,pady=5)
        ttk.Label(self,wraplength=760,justify='left',text=(
            'Corner input order: BL X/Y, BR X/Y, TL X/Y, TR X/Y (pixels); '
            'then X minimum/maximum and Y minimum/maximum (physical units). '
            'Zero pixel-localization uncertainty is valid when explicitly justified. '
            'Pixel width is NOT a standard uncertainty unless a distribution is justified. '
            'For SEM scale bars, nonzero corner sigmas do not describe physical bar-length uncertainty.'))\
            .grid(row=6,column=0,columnspan=2,padx=8,pady=7,sticky='ew')
        ttk.Button(self,text='Apply and save declaration',command=self.apply).grid(row=7,column=0,columnspan=2,pady=8)
        self.status=tk.StringVar(value='No implicit uncertainty is introduced by digitization quality metrics.')
        ttk.Label(self,textvariable=self.status,wraplength=720,justify='left').grid(row=8,column=0,columnspan=2,padx=8,sticky='w')
        ttk.Button(self,text='Close',command=self.destroy).grid(row=9,column=0,columnspan=2,pady=10)
        self.columnconfigure(1,weight=1)

    def declaration(self):
        def parse(name,count):
            try: a=[float(v) for v in self.values[name].get().replace(',',' ').split()]
            except ValueError: raise ValueError(f'{name}: enter {count} numbers.')
            if len(a)!=count: raise ValueError(f'{name}: enter exactly {count} numbers.')
            return a
        mode=self.values['mode'].get()
        if mode=='none':return {'mode':'none'}
        spec={'mode':mode,'rationale':self.values['rationale'].get().strip()}
        if mode=='physical_override':
            spec['override_standard_uncertainty']=parse('override_standard_uncertainty',2)
        elif mode=='pixel_calibration':
            spec['pixel_distribution']=self.values['pixel_distribution'].get()
            spec['pixel_scale']=parse('pixel_scale',2)
            spec['calibration_standard_uncertainty']=parse('calibration_standard_uncertainty',12)
        return checked_spec(spec,scale_bar=bool(self.app.config.get('scale_reference')))

    def apply(self):
        try:
            spec=self.declaration()
            if not self.app.commit_axes(False):return
            # Lock assumptions to the current scientific calibration and
            # original point identities. A later edit forces re-review.
            if spec['mode']!='none':
                spec['review_fingerprint']=review_fingerprint(self.app.serialize_configuration())
            self.app.snapshot()
            self.app.config['uncertainty']=copy.deepcopy(spec)
            if not self.app.persist():
                self.status.set('Unable to persist declaration.');return
            self.status.set('Saved explicitly in this digitizer configuration. '
                            'Publication applies the declaration separately to each selected calibration.' if spec['mode']!='none'
                            else 'Uncertainty publication disabled; no sigmas will be invented.')
        except (ValueError,TypeError) as exc:
            messagebox.showerror('Uncertainty declaration',str(exc),parent=self)
