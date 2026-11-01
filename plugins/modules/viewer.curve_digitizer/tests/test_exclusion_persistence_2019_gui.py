# SPDX-License-Identifier: GPL-3.0-or-later
"""Fake native-document RPC, without touching real Sessions or installed code."""
import sys,json,copy,tkinter as tk
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"python"))
from gxtxt_curve_digitizer import CurveDigitizerApp,CORE_PREFS,b64e
from digitizer_model import Series
def records(*rows):
    return "\n".join("\t".join([key]+[b64e(str(a)) for a in args]) for key,args in rows)
class RPC:
    def __init__(self):self.document=None;self.rev=1
    def attach(self,r):pass
    def call(self,cmd,*args):
        if cmd=="CONFIG_READ":
            return records(*( ("SETTING",[k,v,"user"]) for k,v in CORE_PREFS.items()))
        if cmd=="IMAGE_TOOL":return ""
        if cmd=="DOC_UPDATE":
            id,payload,token,sha,gen,rev=args
            assert id=="test_doc" and token=="session" and gen=="test_gen",args
            self.rev+=1;self.document=json.loads(payload)
            return f"test_doc\tfake_sha\t{gen}\t{self.rev}"
        if cmd=="DOC_READ":
            assert args==("test_doc",)
            return records(("DOCUMENT",["test_doc",json.dumps(self.document,ensure_ascii=False),"today","fake_sha","test_gen",str(self.rev)]))
        if cmd=="SOURCE":raise RuntimeError("No real source resources in isolated test")
        raise RuntimeError("unknown cmd "+cmd)
rpc=RPC()
root=tk.Tk();root.geometry("1100x750+4000+4000")
app=CurveDigitizerApp(root,rpc,bootstrap_payload=records(("SESSION",["session"])))
try:
    app.current_doc_id="test_doc"
    app.document_sha["test_doc"]="fake_sha"
    app.document_receipts["test_doc"]=("test_gen","1")
    cfg=app.new_configuration("roundtrip")
    cfg["source"]={"dataset_id":"image01","sha256":"b"*64,"width":320,"height":200}
    app.config=cfg
    app.project=app.config_to_project(cfg)
    c1=Series(name="c5")
    c2=Series(name="c15")
    app.project.series=[c1,c2]
    app.active_series_id=c1.id
    app.refresh_curve_tree()
    app.exclusion_paths={c1.id:[{"id":"path_c1","enabled":False,
                              "nodes":[[10.,50.],[30.,51.]]}],
                         c2.id:[{"id":"path_c2","enabled":True,
                              "nodes":[[15.,90.],[28.,92.]]}]}
    app.exclusion_origin_sha="b"*64
    assert app.persist()
    print("SAVE_HAS_PATHS",sorted(rpc.document["tracing_constraints"]["paths_by_curve"]))
    assert set(rpc.document["tracing_constraints"]["paths_by_curve"])=={c1.id,c2.id}
    app.exclusion_paths={}
    app.exclusion_origin_sha=""
    app.load_current_source=lambda:None
    assert app.open_document("test_doc",reviewed=True)
    print("RELOADED_PATHS",[(k,len(v)) for k,v in app.exclusion_paths.items()])
    assert app.exclusion_origin_sha=="b"*64
    assert app.exclusion_paths[c1.id][0]["nodes"]==[[10.,50.],[30.,51.]]
    assert app.exclusion_paths[c2.id][0]["nodes"]==[[15.,90.],[28.,92.]]
    print("LIST_ON_FIRST",app.exclusion_list.get_children())
    assert app.exclusion_list.get_children()==("path_c1",)
    # Simulate real user selecting second series in Treeview.
    app.curve_tree.selection_set(c2.id)
    app.on_curve_selected()
    print("ACTIVE_SERIES",app.active_series_id,"LIST_ON_SECOND",app.exclusion_list.get_children())
    print("EXPECTED_LIST_SECOND",("path_c2",))
    assert app.exclusion_list.get_children()==("path_c2",)
    assert app.exclusion_entries()[0]["id"]=="path_c2"
    assert app.exclusion_entries()[0]["enabled"] is True
    app.curve_tree.selection_set(c1.id)
    app.on_curve_selected()
    assert app.exclusion_list.get_children()==("path_c1",)
    assert app.exclusion_entries()[0]["enabled"] is False
    # The selection itself must NEVER rewrite or remove persisted data.
    assert set(rpc.document["tracing_constraints"]["paths_by_curve"])=={c1.id,c2.id}
    assert app.exclusion_paths[c2.id][0]["nodes"]==[[15.,90.],[28.,92.]]
    print("PASS saved paths, reopened configuration, curve A/B/A UI, enabled state")
finally:
    for job in root.tk.call("after","info"):
        try:root.after_cancel(job)
        except tk.TclError:pass
    root.destroy()
