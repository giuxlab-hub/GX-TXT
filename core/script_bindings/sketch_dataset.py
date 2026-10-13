"""Canonical Sketch data through the existing researcher Script Bridge."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError
REGISTRATION = {
    "api_id":"SKETCH_DATASET_API_v1", "api_version":1,
    "provider_kind":"core", "provider_id":"sketch_dataset",
    "documentation_ref":"docs/api/SKETCH_DATASET_API_v1.md",
    "operations":{name:{"name":name,"summary":"Canonical Sketch "+name,
        "arguments":[{"name":"request","kind":"struct","required":True}],
        "argument_convention":"request struct","result_contract":"portable geometry or publication receipt",
        "result_convention":"struct"} for name in ("read","validate","publish")}
}
def invoke(host,operation,args):
    if len(args)!=1 or not isinstance(args[0],dict):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments","Sketch requires one request struct")
    r=args[0]
    if operation=="read":
        payload=host.call("::GX::sketchDatasetRead",host.session,r["dataset_id"])
        return decode_sketch(host,payload)
    if operation=="validate":
        host.call("::GX::sketchDatasetValidate",r["sketch"])
        return {"valid":True}
    if operation=="publish":
        result=host.as_dict(host.call("::GX::sketchDatasetPublish",host.session,host.module_id,r["dataset_id"],r["sketch"],r.get("options",{})))
        result.pop("path",None);return result
    raise BridgeError("GXTXT:ScriptBridge:InvalidArguments","Unknown Sketch operation")

def decode_definition(host, raw):
    result=host.as_dict(raw)
    for key,value in list(result.items()):
        if key=="parts":
            result[key]=[{"definition":decode_definition(host,host.as_dict(p)["definition"]),"reversed":bool(int(host.as_dict(p).get("reversed",0)))} for p in host.as_list(value)]
        elif key=="controls":result[key]=[[float(x) for x in host.as_list(row)] for row in host.as_list(value)]
        elif key=="tangents":result[key]=[[int(host.as_list(row)[0])]+[[float(x) for x in host.as_list(a)] for a in host.as_list(row)[1:]] for row in host.as_list(value)]
        elif key=="matrix":result[key]=[float(x) for x in host.as_list(value)]
        elif key=="nodes":result[key]=[int(x) for x in host.as_list(value)]
        elif key in ("radius_x","radius_y","rotation","angle_start","angle_sweep","tolerance"):result[key]=float(value)
        elif key=="closed":result[key]=bool(int(value))
    return result

def decode_sketch(host,raw):
    result=host.as_dict(raw);objects={};constraints={}
    for key,raw_object in host.as_dict(result["objects"]).items():
        obj=host.as_dict(raw_object);obj["definition"]=decode_definition(host,obj["definition"])
        obj["units"]=host.as_list(obj["units"]);objects[key]=obj
    for key,raw_record in host.as_dict(result["constraints"]).items():
        record=host.as_dict(raw_record);record["definition"]=host.as_dict(record["definition"]);constraints[key]=record
    result["objects"]=objects;result["constraints"]=constraints
    result["parameters"]={key:host.as_dict(value) for key,value in host.as_dict(result["parameters"]).items()}
    return result
