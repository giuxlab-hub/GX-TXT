from pathlib import Path
import hashlib,json,subprocess,sys,time
framework,out=map(Path,sys.argv[1:3]);mode=sys.argv[3]
assert mode in ['baseline','patched'];assert not out.exists()
log=Path(str(out)+'.log');receipt=Path(str(out)+'.run.json');assert not log.exists() and not receipt.exists()
script=Path(__file__).parent/'gui_performance.tcl';script_hash=hashlib.sha256(script.read_bytes()).hexdigest()
files=['core/tcl/native2d_cad_canvas_v1.tcl','core/tcl/native2d_cad_v1.tcl','core/native2d/bin/gx2dtcl.so','core/history/libgxtxt_history.so','plugins/modules/viewer.curve_workbench/api/curve_workbench_cad_canvas.tcl','plugins/modules/viewer.curve_workbench/api/curve_workbench_history.tcl','plugins/modules/viewer.curve_workbench/api/curve_workbench_scene.tcl','plugins/modules/viewer.curve_workbench/module.ini']
pins={name:hashlib.sha256((framework/name).read_bytes()).hexdigest() for name in files if (framework/name).exists()}
cmd=['timeout','480s','xvfb-run','-a','-s','-screen 0 1600x1100x24','tclsh',str(script),str(framework),str(out),mode];t=time.monotonic()
with log.open('w') as stream:status=subprocess.run(cmd,stdout=stream,stderr=subprocess.STDOUT).returncode
record={'framework':str(framework),'mode':mode,'command':cmd,'code':status,'elapsed_seconds':time.monotonic()-t,'source_pins':pins,'loaded_copy_pins':{name:hashlib.sha256((out/'framework'/name).read_bytes()).hexdigest() for name in files if (out/'framework'/name).exists()},'script_sha256':script_hash}
receipt.write_text(json.dumps(record,indent=2)+'\n')
if out.exists():(out/'EXIT_CODE.txt').write_text(str(status)+'\n')
print(json.dumps(record,indent=2));sys.exit(status)
