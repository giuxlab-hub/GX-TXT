# SPDX-License-Identifier: GPL-3.0-or-later
"""Save/reopen and repeated Apply in the same live configuration dialog."""
import sys,tkinter as tk,json
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'python'))
from gxtxt_curve_digitizer import CurveDigitizerApp,CORE_PREFS,b64e,b64d

def records(*rows):
    return '\n'.join('\t'.join([name]+[b64e(str(x)) for x in fields]) for name,fields in rows)

class Rpc:
    def __init__(self):
        self.values=dict(CORE_PREFS);self.docs={};self.commits=[]
    def attach(self,root):pass
    def call(self,cmd,*args):
        if cmd=='CONFIG_READ':return records(*(('SETTING',[k,v,'session']) for k,v in self.values.items()))
        if cmd=='CONFIG_COMMIT':
            changed={}
            for line in args[1].splitlines():
                k,prev,v=line.split('\t')
                assert self.values[k]==b64d(prev),f'Stale optimistic commit for {k}'
                changed[k]=b64d(v)
            self.values.update(changed);self.commits.append(changed)
            return self.call('CONFIG_READ')
        if cmd=='DOC_UPDATE':
            doc,payload,token,oldsha=args
            assert token=='s'
            self.docs[doc]=json.loads(payload)
            return doc+'\t'+'a'*64
        raise AssertionError((cmd,args))

def walk(parent):
    for child in parent.winfo_children():
        yield child
        yield from walk(child)

root=tk.Tk();root.geometry('1300x850')
rpc=Rpc();app=CurveDigitizerApp(root,rpc,bootstrap_payload=records(('SESSION',['s'])))
app.config=app.new_configuration('A');app.current_doc_id='doc-A';app.document_sha['doc-A']='a'*64
app.documents['doc-A']=app.config
app.open_viewer_settings();root.update();win=app.settings_dialog
labels={str(c.cget('text')):c for c in walk(win) if c.winfo_class()=='TButton'}
assert all(key in labels for key in ('Apply','OK','Cancel'))
assert labels['Apply'].winfo_ismapped(), 'Apply invisible'
mono=next(x for x in walk(win) if x.winfo_class()=='TCombobox' and 'Monotonic in X' in x.cget('values'))
source=next(x for x in walk(win) if x.winfo_class()=='TCombobox' and 'Sort by X' in x.cget('values'))
mono.set('Monotonic in X');root.update()
assert source.get()=='Sort by X'
labels['Apply'].invoke();root.update()
assert win.winfo_exists() and 'doc-A' in rpc.docs
assert rpc.docs['doc-A']['curve_ordering']=={'monotonicity':'x','source':'x'}
# A SECOND Apply in the same dialog should successfully save another CORE
# setting; the old optimistic commit snapshot must not be reused.
rad=next(x for x in walk(win) if x.winfo_class()=='TSpinbox' and float(x.cget('from'))==0 and float(x.cget('to'))==25)
rad.delete(0,'end');rad.insert(0,'9')
labels['Apply'].invoke();root.update()
assert rpc.values['snap_radius']=='9',rpc.values['snap_radius']
assert app.snap_radius.get()==9
# A third Apply with a different value must not conflict with the 1st/2nd.
rad.delete(0,'end');rad.insert(0,'12')
labels['Apply'].invoke();root.update()
assert rpc.values['snap_radius']=='12'
# Close and reopen the same Session config; ordering is durable.
win.destroy()
app.documents['doc-A']=rpc.docs['doc-A']
app.open_document('doc-A')
assert app.curve_monotonicity.get()=='x'
assert app.point_order_source.get()=='x'
root.destroy();print('PASS persistent Apply, repeat Apply, CORE defaults and reopen')
