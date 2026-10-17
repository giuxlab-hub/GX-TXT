# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root out
set root [file normalize $root];set out [file normalize $out]
if {![string match */_private_dev106/* $out] || [file exists $out]} {error {Fresh private output required}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT} {set ::env($key) [file join $out $key]}
set argv0 __xml_bridge_contract__;source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
set ::GX::cfg(output_root) [file join $out Sessions];::GX::createNewSession xml_bridge
::GX::configurationSet scripts.user_root [file join $out user_scripts]
set python {from gxtxt import gxtxt_api_call as call
model = call('SOURCE_SURFACE_API_v1', 'scan', ['python', "print('Ω')\n"])
assert model['engine'] == 'gxtxt.native_source.v1' and model['tokens']
api = 'XML_DOCUMENT_API_v1'
d = call(api, 'create', ['laboratory'])
r = call(api, 'root', [d])
call(api, 'attribute', [d, r, 'xmlns:q', 'urn:measurement'])
v = call(api, 'append', [d, r, 'q:measurement', '3.2 Ω'])
call(api, 'attribute', [d, v, 'unit', 'V'])
assert call(api, 'text', [d, v]) == '3.2 Ω'
assert len(call(api, 'query', [d, r, 'measurement'])) == 1
try:
    call(api, 'write', [d, '../escaped.xml'])
except Exception:
    pass
else:
    raise AssertionError('XML write escaped authorized Job')
call(api, 'write', [d, 'bridge_result.xml'])
call(api, 'release', [d])
print('XML_BRIDGE_OK Python')
}
set octave {api='XML_DOCUMENT_API_v1';
d=gxtxt_api_call(api,'create',{'laboratory'});
r=gxtxt_api_call(api,'root',{d});
gxtxt_api_call(api,'attribute',{d,r,'xmlns:q','urn:measurement'});
v=gxtxt_api_call(api,'append',{d,r,'q:measurement','3.2 Ω'});
gxtxt_api_call(api,'attribute',{d,v,'unit','V'});
assert(strcmp(gxtxt_api_call(api,'text',{d,v}),'3.2 Ω'));
found=gxtxt_api_call(api,'query',{d,r,'measurement'});assert(numel(found)==1);
refused=false;try gxtxt_api_call(api,'write',{d,'../escaped.xml'});catch refused=true;end_try_catch
assert(refused);
gxtxt_api_call(api,'write',{d,'bridge_result.xml'});
gxtxt_api_call(api,'release',{d});
disp('XML_BRIDGE_OK Octave');
}
set receipts {}
foreach language {Python Octave} code [list $python $octave] {
    set id xml_[string tolower $language]
    ::GX::scriptRegistrySave session $id "Native XML $language" $code [dict create language $language]
    set job [::GX::scriptJobSubmit session:$id {}];set job [::GX::scriptJobWait [dict get $job id] 90]
    if {[dict get $job state] ne {COMPLETED}} {error "Native $language XML Job failed: $job"}
    set path [file join [dict get $job output_dir] bridge_result.xml]
    if {![file isfile $path]} {error {Actual XML output missing}}
    set check {import sys,xml.etree.ElementTree as E; r=E.parse(sys.argv[1]).getroot();m=r.find('{urn:measurement}measurement');assert r.tag=='laboratory' and m.text=='3.2 Ω' and m.attrib['unit']=='V';print('PASS independent XML namespace/text/attribute')}
    puts [exec /usr/bin/python3 -c $check $path]
    dict set receipts $language [dict create job [dict get $job id] xml_sha256 [::GX::sha256File $path]]
}
set f [open [file join $out result.tcldict] w];puts $f [dict create status PASS receipts $receipts];close $f
