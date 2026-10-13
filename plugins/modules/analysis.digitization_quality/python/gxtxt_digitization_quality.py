# SPDX-License-Identifier: GPL-3.0-or-later
import base64, json, os, sys
from pathlib import Path
import tkinter as tk
from tkinter import ttk, messagebox
APP="GX-TXT Digitization Quality"
def e(v): return base64.b64encode(v.encode()).decode()
def d(v): return base64.b64decode(v).decode()
def records(p):
    for line in p.splitlines():
        if line:
            f=line.split('\t'); yield f[0],[d(x) for x in f[1:]]
class RPC:
    def __init__(self): self.n=0; self.focus=None
    def call(self,cmd,*args):
        self.n+=1; rid=str(self.n); sys.stdout.write('\t'.join(['REQ',rid,cmd]+[e(str(a)) for a in args])+'\n'); sys.stdout.flush()
        while True:
            line=sys.stdin.readline()
            if line=='': raise RuntimeError('GX-TXT host connection closed.')
            line=line.rstrip('\n')
            if line=='CONTROL\tFOCUS':
                if self.focus:self.focus()
                continue
            f=line.split('\t')
            if len(f)==4 and f[0]=='RES' and f[1]==rid:
                p=d(f[3]);
                if f[2]=='ERR': raise RuntimeError(p)
                return p
class App:
    def __init__(self,root,rpc):
        self.root=root; self.rpc=rpc; rpc.focus=self.focus; self.configs={}; self.var=tk.StringVar(); self.status=tk.StringVar(value='Select a Curve Digitalizer configuration.')
        root.title(APP); root.geometry('980x720'); root.minsize(700,500)
        top=ttk.Frame(root,padding=10); top.pack(fill='x'); ttk.Label(top,text='Configuration:').pack(side='left'); self.combo=ttk.Combobox(top,textvariable=self.var,state='readonly',width=60); self.combo.pack(side='left',fill='x',expand=True,padx=(8,0)); self.combo.bind('<<ComboboxSelected>>',self.run)
        self.text=tk.Text(root,wrap='word',font=('TkDefaultFont',10)); self.text.pack(fill='both',expand=True,padx=10); self.text.configure(state='disabled'); ttk.Label(root,textvariable=self.status,relief='sunken',anchor='w',padding=(5,2)).pack(fill='x',padx=10,pady=10)
        for kind,fields in records(rpc.call('BOOTSTRAP')):
            if kind=='CONFIG':
                doc,name,source,ready=fields; label=f'{name} [{doc}]'; self.configs[label]=doc
        self.combo['values']=list(self.configs)
        scen=os.environ.get('GX_DIGITIZATION_QUALITY_TEST_SCENARIO','')
        if scen: root.after(200,self.test)
    def focus(self): self.root.lift(); self.root.focus_force()
    def run(self,*_):
        label=self.var.get();
        if not label:return
        try:p=self.rpc.call('DIAGNOSTICS',self.configs[label])
        except Exception as ex: messagebox.showerror(APP,str(ex)); return
        source=''; msg=''; result=None
        for kind,fields in records(p):
            if kind=='SOURCE_STATUS': source,msg=fields
            elif kind=='RESULT_JSON': result=json.loads(fields[0])
        lines=[f'Source integrity: {source}',msg,'']
        if result:
            if result.get('condition_number') is not None: lines.append(f"Homography condition number: {result['condition_number']:.6g}")
            if result.get('reprojection_rms') is not None: lines.append(f"Four-point reprojection RMS: {result['reprojection_rms']:.6g}")
            lines.append('')
            for item in result['diagnostics']: lines.append(f"[{item['severity'].upper()}] {item['message']}")
        self.text.configure(state='normal'); self.text.delete('1.0','end'); self.text.insert('1.0','\n'.join(lines)); self.text.configure(state='disabled'); self.status.set('Diagnostics calculated. Scientific state was not modified.')
    def test(self):
        marker=os.environ.get('GX_DIGITIZATION_QUALITY_TEST_MARKER','');
        try:
            if not self.configs: raise RuntimeError('No configurations')
            label=next(iter(self.configs)); self.var.set(label); self.run(); txt=self.text.get('1.0','end')
            if 'reprojection RMS' not in txt or 'Source integrity: VERIFIED' not in txt: raise RuntimeError('expected diagnostics missing')
            if marker: Path(marker).write_text('PASS\n')
        except Exception as ex:
            if marker: Path(marker).write_text('FAIL: '+str(ex)+'\n')
        finally:self.root.after(100,self.root.destroy)
def main():
    root=tk.Tk(); rpc=RPC()
    try: App(root,rpc)
    except Exception as ex: messagebox.showerror(APP,str(ex)); root.destroy(); return 1
    root.mainloop(); return 0
if __name__=='__main__': raise SystemExit(main())
