# SPDX-License-Identifier: GPL-3.0-or-later
"""Isolated Tk contract tests for configuration save/review/duplicate/rename."""
import copy,hashlib,json,sys,tkinter as tk
from pathlib import Path
from tkinter import messagebox,simpledialog
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"python"))
from gxtxt_curve_digitizer import CurveDigitizerApp,CORE_PREFS,b64e,RpcError,PLUGIN_VERSION
def rec(*rows):
 return "\n".join("\t".join([kind]+[b64e(str(v)) for v in fields]) for kind,fields in rows)
class FakeRPC:
 def __init__(self):
  self.db={};self.seq=1;self.fail_update=False;self.fail_rename=False
  self.calls=[];self.foreign_count=0
 def attach(self,root):pass
 def _receipt(self,doc):
  entry=self.db[doc]
  return "\t".join([doc,entry["sha"],entry["gen"],str(entry["rev"])])
 def call(self,cmd,*args):
  self.calls.append((cmd,args))
  if cmd=="CONFIG_READ":return rec(*( ("SETTING",[k,v,"user"]) for k,v in CORE_PREFS.items()))
  if cmd=="IMAGE_TOOL":return ""
  if cmd=="DOC_CREATE":
   self.seq+=1;doc="doc"+str(self.seq)
   payload=json.loads(args[0])
   digest=hashlib.sha256(args[0].encode()).hexdigest()
   self.db[doc]={"config":payload,"sha":digest,"gen":"g"+doc,"rev":1,"native":payload["name"]}
   return self._receipt(doc)
  if cmd=="DOC_READ":
   doc=args[0];entry=self.db[doc]
   return rec(("DOCUMENT",[doc,json.dumps(entry["config"],ensure_ascii=False),
                       "now",entry["sha"],entry["gen"],str(entry["rev"])]))
  if cmd=="DOC_UPDATE":
   if self.fail_update:raise RpcError("Test: failed JSON update")
   doc,payload,token,sha,gen,rev=args
   entry=self.db[doc]
   if (entry["sha"],entry["gen"],str(entry["rev"]))!=(sha,gen,rev):
    raise RpcError("Test: stale JSON update")
   entry["config"]=json.loads(payload)
   entry["sha"]=hashlib.sha256(payload.encode()).hexdigest()
   entry["rev"]+=1
   return self._receipt(doc)
  if cmd=="DOC_RENAME":
   if self.fail_rename:raise RpcError("Test: native rename refused")
   doc,name,token,sha,gen,rev=args
   entry=self.db[doc]
   if (entry["sha"],entry["gen"],str(entry["rev"]))!=(sha,gen,rev):
    raise RpcError("Test: stale native rename")
   if name in [e["native"] for did,e in self.db.items() if did!=doc]:
    raise RpcError("Test: duplicate native name")
   entry["native"]=name
   entry["rev"]+=1
   return self._receipt(doc)
  raise AssertionError((cmd,args))
def new_app():
 root=tk.Tk();root.geometry("1170x760+4300+4300")
 rpc=FakeRPC()
 app=CurveDigitizerApp(root,rpc,bootstrap_payload=rec(("SESSION",["test_session"])))
 cfg=app.new_configuration("Original")
 app.config=copy.deepcopy(cfg);app.project=app.config_to_project(cfg)
 app.current_doc_id="doc1";app.session_token="test_session"
 raw=json.dumps(cfg,ensure_ascii=False,separators=(",",":"),allow_nan=False)
 sha=hashlib.sha256(raw.encode()).hexdigest()
 rpc.db["doc1"]={"config":copy.deepcopy(cfg),"sha":sha,"gen":"gdoc1","rev":1,"native":"Original"}
 app.document_receipts["doc1"]=("gdoc1","1")
 app.document_sha["doc1"]=sha
 app.documents["doc1"]=copy.deepcopy(cfg)
 app._workspace_baseline=app.workspace_payload()
 return root,app,rpc
def destroy_safely(root):
 for job in root.tk.call("after","info"):
  try:root.after_cancel(job)
  except tk.TclError:pass
 root.destroy()
assert PLUGIN_VERSION=="2.0.25"
oldprompt=messagebox.askyesnocancel
oldask=simpledialog.askstring
olderror=messagebox.showerror
errors=[]
messagebox.showerror=lambda *args,**kw:errors.append(args)
try:
 # (2) pure display zoom/pan is not a scientific edit or prompt.
 root,app,rpc=new_app()
 try:
  original=app._workspace_baseline
  app.canvas.scale=5;app.canvas.offset_x=371;app.canvas.offset_y=-13
  assert app.workspace_payload()==original
  messagebox.askyesnocancel=lambda *args,**kw: (_ for _ in ()).throw(AssertionError("Zoom prompted Save"))
  assert app.workspace_review("Close")
  assert app.persist() # explicit save still retains the view
  assert rpc.db["doc1"]["config"]["view"]["scale"]==5
  assert app._workspace_baseline==app.workspace_payload()
  app.notes.insert("1.0","edited")
  assert app.workspace_payload()!=app._workspace_baseline
 finally:destroy_safely(root)
 print("PASS zoom and pan not dirty; explicit save persists viewport; Notes still dirty")
 # (3) Duplicate - No discards unsaved draft from the new copy.
 root,app,rpc=new_app()
 try:
  app.notes.insert("1.0","unsaved draft")
  messagebox.askyesnocancel=lambda *args,**kw:False
  app.duplicate_config()
  created=rpc.db["doc2"]["config"]
  assert created["notes"]=="",created["notes"]
  assert rpc.db["doc1"]["config"]["notes"]==""
  assert created["configuration_id"]!=rpc.db["doc1"]["config"]["configuration_id"]
  assert created["name"]=="Original copy"
 finally:destroy_safely(root)
 print("PASS Duplicate No uses persisted source, not pending Notes")
 root,app,rpc=new_app()
 try:
  app.notes.insert("1.0","saved by review")
  messagebox.askyesnocancel=lambda *args,**kw:True
  app.duplicate_config()
  assert rpc.db["doc1"]["config"]["notes"]=="saved by review"
  assert rpc.db["doc2"]["config"]["notes"]=="saved by review"
 finally:destroy_safely(root)
 print("PASS Duplicate Yes saves first, then duplicates; records have distinct IDs")
 root,app,rpc=new_app()
 try:
  app.notes.insert("1.0","cancel")
  messagebox.askyesnocancel=lambda *args,**kw:None
  app.duplicate_config()
  assert "doc2" not in rpc.db
 finally:destroy_safely(root)
 print("PASS Duplicate Cancel has no side effects")
 # (4) Rename - the native catalog and config JSON name MUST match.
 root,app,rpc=new_app()
 try:
  simpledialog.askstring=lambda *args,**kw:"Renamed"
  app.rename_config()
  assert rpc.db["doc1"]["native"]=="Renamed",rpc.db["doc1"]
  assert rpc.db["doc1"]["config"]["name"]=="Renamed"
  assert app.config["name"]=="Renamed"
  assert app.document_receipts["doc1"]==("gdoc1",str(rpc.db["doc1"]["rev"]))
  assert app.document_sha["doc1"]==rpc.db["doc1"]["sha"]
  assert len([c for c,args in rpc.calls if c=="DOC_RENAME"])==1
 finally:destroy_safely(root)
 print("PASS native catalog rename + JSON rename and new revision baseline")
 root,app,rpc=new_app()
 try:
  simpledialog.askstring=lambda *args,**kw:"Renamed"
  rpc.fail_rename=True
  app.rename_config()
  assert rpc.db["doc1"]["native"]=="Original"
  assert rpc.db["doc1"]["config"]["name"]=="Original"
  assert app.config["name"]=="Original"
 finally:destroy_safely(root)
 print("PASS native rename failure leaves original state intact")
 root,app,rpc=new_app()
 try:
  simpledialog.askstring=lambda *args,**kw:"Renamed"
  rpc.fail_update=True
  app.rename_config()
  assert rpc.db["doc1"]["native"]=="Original",rpc.db["doc1"]
  assert rpc.db["doc1"]["config"]["name"]=="Original"
  assert app.config["name"]=="Original"
  assert len([c for c,args in rpc.calls if c=="DOC_RENAME"])==2
 finally:destroy_safely(root)
 print("PASS failed JSON save compensates native catalog name")
 # (5) Outside application focus now saves; dialog/review guard protects draft.
 root,app,rpc=new_app()
 try:
  focused=app.root.focus_get
  app.root.focus_get=lambda:None
  actions=[]
  try:
   app.workspace_focus_commit(lambda:actions.append("external"))
   root.update()
   assert actions==["external"],actions
   app._workspace_reviewing=True
   app.workspace_focus_commit(lambda:actions.append("review"))
   root.update()
   assert actions==["external"],actions
   app._workspace_reviewing=False
   app.workspace_focus_commit(lambda:actions.append("stale review event"))
   app._workspace_review_serial+=1
   root.update()
   assert actions==["external"],actions
   app.workspace_focus_commit(lambda:actions.append("stale document event"))
   app.current_doc_id="different_document"
   root.update()
   assert actions==["external"],actions
   app.current_doc_id="doc1"
   foreign=tk.Toplevel(root)
   app.root.focus_get=lambda:foreign
   app.workspace_focus_commit(lambda:actions.append("dialog"))
   root.update()
   assert actions==["external"],actions
   foreign.destroy()
   modal=tk.Toplevel(root)
   modal.grab_set()
   app.root.focus_get=lambda:None
   app.workspace_focus_commit(lambda:actions.append("grabbed modal"))
   root.update()
   assert actions==["external"],actions
   modal.grab_release()
   modal.destroy()
  finally:app.root.focus_get=focused
 finally:destroy_safely(root)
 print("PASS external FocusOut autosave, no premature save in modal or review")
finally:
 messagebox.askyesnocancel=oldprompt
 simpledialog.askstring=oldask
 messagebox.showerror=olderror
print("PASS all configuration GUI regression scenarios")
