from pathlib import Path
import hashlib,json,subprocess,sys,time,os
framework,out=map(Path,sys.argv[1:3]);case="perf_dimension" if len(sys.argv)>3 and sys.argv[3]=="dimension" else "perf"
assert case in {"perf","perf_dimension"}
assert not out.exists()
log=Path(str(out)+'.log');receipt=Path(str(out)+'.run.json');assert not log.exists() and not receipt.exists()
script=Path(__file__).parent/('gui_'+case+'.tcl')
cmd=['timeout','480s','xvfb-run','-a','-s','-screen 0 1600x1100x24','tclsh',str(script),str(framework),str(out)]
files=['plugins/modules/viewer.curve_workbench/api/curve_workbench_parts.tcl','core/tcl/native2d_cad_tools_constraints_v1.tcl','plugins/modules/viewer.curve_workbench/api/curve_workbench_advanced_constraints.tcl','core/tcl/native2d_cad_canvas_v1.tcl','core/tcl/native2d_cad_tools_v1.tcl','plugins/modules/viewer.curve_workbench/api/curve_workbench_advanced_tools.tcl','plugins/modules/viewer.curve_workbench/api/curve_workbench_interaction_v1.tcl','plugins/modules/viewer.curve_workbench/api/curve_workbench_selection.tcl','plugins/modules/viewer.curve_workbench/api/curve_workbench_representation_v4.tcl','core/tcl/native2d_cad_v1.tcl','core/native2d/bin/gx2dtcl.so','core/history/libgxtxt_history.so','plugins/modules/viewer.curve_workbench/api/curve_workbench_cad_canvas.tcl','plugins/modules/viewer.curve_workbench/api/curve_workbench_history.tcl','plugins/modules/viewer.curve_workbench/module.ini','plugins/modules/viewer.curve_workbench/plugin-package.ini','plugins/modules/viewer.curve_workbench/SHA256SUMS','plugins/modules/viewer.curve_workbench/SHA256SUMS.txt','plugins/modules/viewer.curve_workbench/api/curve_workbench_api_v1.tcl','core/tcl/dataset_transform_responsive_v1.tcl','core/tcl/native2d_viewport_host_v1.tcl','plugins/modules/viewer.curve_workbench/api/curve_workbench_interaction_v2.tcl','plugins/modules/viewer.curve_workbench/api/curve_workbench_source_v2.tcl','plugins/modules/viewer.curve_workbench/api/curve_workbench_geometry_v2.tcl','plugins/modules/viewer.curve_workbench/api/curve_workbench_coordinate_controls_v1.tcl']
pins={name:hashlib.sha256((framework/name).read_bytes()).hexdigest() for name in files if (framework/name).exists()}
t=time.monotonic()
with log.open('w') as stream:status=subprocess.run(cmd,stdout=stream,stderr=subprocess.STDOUT).returncode
record={'framework':str(framework),'case':case,'command':cmd,'code':status,'elapsed_seconds':time.monotonic()-t,'source_pins':pins,'tested_copy_pins':{name:hashlib.sha256((out/'framework'/name).read_bytes()).hexdigest() for name in files if (out/'framework'/name).exists()},'environment_hints':{k:v for k,v in os.environ.items() if k.startswith('P019_')},'script_sha256':hashlib.sha256(script.read_bytes()).hexdigest()}
receipt.write_text(json.dumps(record,indent=2)+'\n')
if out.exists():(out/'EXIT_CODE.txt').write_text(str(status)+'\n')
print(json.dumps(record,indent=2));sys.exit(status)
