"""Public Curve Digitizer processed image facade for both Python and Octave."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError

API_ID = "CURVE_DIGITIZER_IMAGE_PROCESSING_API_v1"
_OPERATIONS = {
    "read": ("Read processed-image lineage, processing steps and geometry", "manifest struct"),
    "operations": ("Read ordered processing operations", "operation list"),
    "lineage": ("Read SHA-verified chain of original and processed Image Datasets", "lineage list"),
    "has_manifest": ("Test whether an Image Dataset carries this manifest", "boolean"),
}
REGISTRATION = {
    "api_id": API_ID,
    "api_version": 1,
    "provider_kind": "module",
    "provider_id": "viewer.curve_digitizer",
    "documentation_ref": "plugins/modules/viewer.curve_digitizer/IMAGE_PROCESSING_API_v1.md",
    "operations": {name: {
        "name": name, "summary": purpose,
        "arguments": [{"name": "dataset_id", "kind": "canonical Dataset ID", "required": True}],
        "argument_convention": "dataset_id",
        "result_contract": result, "result_convention": result,
    } for name, (purpose, result) in _OPERATIONS.items()},
}


def invoke(host, operation, args):
    if operation not in _OPERATIONS or len(args) != 1 or not isinstance(args[0], str) or not args[0]:
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"{API_ID}/{operation} requires one Dataset ID")
    mapping = {"read": "read", "operations": "operations", "lineage": "lineage", "has_manifest": "hasManifest"}
    # Public Tcl API is sourced only after the installed module's descriptor
    # declares the exact API ID and version, as enforced by Script Bridge.
    path = "::GX::CurveDigitizerImage::" + mapping[operation]
    if not host.tcl.call("info", "commands", path):
        # A headless Script Bridge may not eagerly load viewer API entrypoints.
        # Loading this standalone read-only API is safe and never opens the GUI.
        from pathlib import Path
        script = Path(__file__).resolve().parent / "curve_digitizer_image_processing_api_v1.tcl"
        host.tcl.call("source", str(script))
    value = host.call(path, args[0])
    if operation == "has_manifest":
        return bool(int(value))
    if operation in {"operations", "lineage"}:
        return [host.as_dict(item) for item in host.as_list(value)]
    obj = host.as_dict(value)
    obj["processing_operations"] = [host.as_dict(item) for item in host.as_list(obj["processing_operations"])]
    obj["geometry_preserved"] = bool(int(obj["geometry_preserved"]))
    for key in ("image_width", "image_height", "operation_count", "api_version"):
        obj[key] = int(obj[key])
    return obj

# Public diagnostic data bound to a published Dataset ID, not to a GUI window.
# Both Python and GNU Octave use this provider descriptor without CORE edits.
_QUALITY_API="CURVE_DIGITIZER_QUALITY_API_v2"
QUALITY_REGISTRATION={
    "api_id":_QUALITY_API,"api_version":2,"provider_kind":"module",
    "provider_id":"viewer.curve_digitizer",
    "documentation_ref":"plugins/modules/viewer.curve_digitizer/QUALITY_API_v2.md",
    "operations":{name:{
        "name":name,"summary":summary,
        "arguments":[{"name":"dataset_id","kind":"canonical Dataset ID","required":True}],
        "argument_convention":"dataset_id","result_convention":result,"result_contract":result
    } for name,summary,result in (
        ("diagnostics","Read complete published digitization diagnostics","quality struct"),
        ("issue_report","Read versioned JSON diagnostic report","JSON UTF-8 string"),
        ("has_quality","Test diagnostic report availability","boolean"),
    )},
}
_UNCERTAINTY_API='CURVE_DIGITIZER_UNCERTAINTY_API_v1'
UNCERTAINTY_REGISTRATION={
    'api_id':_UNCERTAINTY_API,'api_version':1,'provider_kind':'module',
    'provider_id':'viewer.curve_digitizer',
    'documentation_ref':'plugins/modules/viewer.curve_digitizer/UNCERTAINTY_API_v1.md',
    'operations':{name:{
        'name':name,'summary':purpose,
        'arguments':[{'name':'dataset_id','kind':'canonical Dataset ID','required':True}],
        'argument_convention':'dataset_id','result_convention':result,'result_contract':result
    } for name,purpose,result in (
        ('uncertainty_read','Read the reviewed physical uncertainty binding','uncertainty struct'),
        ('uncertainty_report','Read scientific interpretation and declarations','JSON UTF-8 string'),
        ('uncertainty_factors','Read retained compact covariance factors','JSON UTF-8 string'),
        ('uncertainty_available','Test whether a current Dataset has uncertainty','boolean'),
        ('uncertainty_covariance','Materialize a bounded X or Y covariance matrix','matrix float64'),
    )},
}
# dev097 CORE statistical consumer operations. These are deliberately distinct
# from the older local matrix inspection function; the Fitter consumes the
# retained binding and canonical managed HDF5 covariance, not a Python list.
UNCERTAINTY_REGISTRATION['operations'].update({
    'uncertainty_core_meaning': {
        'name':'uncertainty_core_meaning','summary':'Retrieve validated CORE statistical interpretation',
        'arguments':[{'name':'dataset_id','kind':'canonical Dataset ID','required':True}],
        'result_contract':'CORE validated meaning and source binding (typed UTF-8)'},
    'uncertainty_publish_covariance': {
        'name':'uncertainty_publish_covariance','summary':'Publish CORE-managed response covariance for GLS Fitter',
        'arguments':[{'name':name,'kind':'text','required':True}
                     for name in ('dataset_id','output_dataset_id','axis')],
        'result_contract':'canonical HDF5 covariance Dataset publication receipt'},
})
UNCERTAINTY_REGISTRATION['operations']['uncertainty_covariance']['arguments']=[
    {'name':'dataset_id','kind':'canonical Dataset ID','required':True},
    {'name':'axis','kind':'x or y','required':True},
]
REGISTRATIONS=[REGISTRATION,QUALITY_REGISTRATION,UNCERTAINTY_REGISTRATION]

_previous_invoke=invoke
def invoke(host,operation,args):
    api_context=getattr(host,'_current_binding_api_id',None)
    # The Script Bridge invokes a shared module handler without passing the API
    # identity; operation name disambiguates these two disjoint operation sets.
    if operation in QUALITY_REGISTRATION['operations']:
        if len(args)!=1 or not isinstance(args[0],str) or not args[0]:
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments",f"{_QUALITY_API}/{operation} requires one Dataset ID")
        name={'diagnostics':'read','issue_report':'reportJson','has_quality':'hasReport'}[operation]
        cmd='::GX::CurveDigitizerQuality::'+name
        if not host.tcl.call('info','commands',cmd):
            from pathlib import Path
            host.tcl.call('source',str(Path(__file__).resolve().parent/'curve_digitizer_quality_api_v2.tcl'))
        result=host.call(cmd,args[0])
        if operation=='has_quality':return bool(int(result))
        if operation=='issue_report':return str(result)
        value=host.as_dict(result)
        value['report_available']=bool(int(value['report_available']))
        return value
    if operation=='uncertainty_core_meaning':
        if len(args)!=1 or not isinstance(args[0],str) or not args[0]:
            raise BridgeError('GXTXT:ScriptBridge:InvalidArguments','Dataset ID required')
        host.call('::GX::modulePublicApiActivate','viewer.curve_digitizer',
                  'CURVE_DIGITIZER_COMPANION_API_v1')
        raw=host.call('::GX::CurveDigitizerCompanion::publicationUncertainty',args[0])
        if not str(raw):return {'available':False}
        context=host.as_dict(raw)
        return {'available':True,'meaning_utf8':str(context['meaning']),
                'binding_utf8':str(context['binding'])}
    if operation=='uncertainty_publish_covariance':
        if len(args)!=3 or not all(isinstance(v,str) and v for v in args) or args[2] not in ('x','y'):
            raise BridgeError('GXTXT:ScriptBridge:InvalidArguments',
                              'dataset_id, output_dataset_id and x|y required')
        host.call('::GX::modulePublicApiActivate','viewer.curve_digitizer',
                  'CURVE_DIGITIZER_COMPANION_API_v1')
        raw=host.call('::GX::CurveDigitizerCompanion::publishCovariance',*args)
        return {'dataset_id':args[1],'receipt_utf8':str(raw)}
    if operation in UNCERTAINTY_REGISTRATION['operations']:
        if operation=='uncertainty_covariance':
            if len(args)!=2 or not isinstance(args[0],str) or not args[0] or args[1] not in ('x','y'):
                raise BridgeError('GXTXT:ScriptBridge:InvalidArguments',
                                  'uncertainty_covariance(dataset_id, x|y) required')
            import json
            from pathlib import Path
            import sys
            sys.path.insert(0,str(Path(__file__).resolve().parent.parent/'python'))
            from uncertainty_engine import covariance_from_factors
            cmd='::GX::CurveDigitizerUncertainty::factorsJson'
            if not host.tcl.call('info','commands',cmd):
                host.tcl.call('source',str(Path(__file__).resolve().parent/'curve_digitizer_uncertainty_api_v1.tcl'))
            blob=host.call(cmd,args[0])
            return covariance_from_factors(json.loads(str(blob)),args[1]).tolist()
        if len(args)!=1 or not isinstance(args[0],str) or not args[0]:
            raise BridgeError('GXTXT:ScriptBridge:InvalidArguments',
                              f'{_UNCERTAINTY_API}/{operation} requires one Dataset ID')
        cmd={'uncertainty_read':'read','uncertainty_report':'reportJson',
             'uncertainty_factors':'factorsJson','uncertainty_available':'hasReport'}[operation]
        path='::GX::CurveDigitizerUncertainty::'+cmd
        if not host.tcl.call('info','commands',path):
            from pathlib import Path
            host.tcl.call('source',str(Path(__file__).resolve().parent/'curve_digitizer_uncertainty_api_v1.tcl'))
        value=host.call(path,args[0])
        if operation=='uncertainty_available':return bool(int(value))
        if operation=='uncertainty_read':
            obj=host.as_dict(value)
            obj['point_count']=int(obj['point_count'])
            obj['api_version']=int(obj['api_version'])
            return obj
        return str(value)
    return _previous_invoke(host,operation,args)
