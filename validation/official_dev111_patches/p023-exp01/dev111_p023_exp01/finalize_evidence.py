#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
from pathlib import Path
import hashlib,json,shutil,subprocess,sys
root=Path(sys.argv[1]).resolve();scratch=Path(sys.argv[2]).resolve();assert root==scratch/'framework'
docs=root/'docs/development/DEV111-P023-EXP01';dest=docs/'evidence';dest.mkdir(exist_ok=True)
# Only synthetic or technical records, never descend Session/profile/resource trees.
groups={
 'profile-cold01':['objects1/TIMES.json','objects1/OPEN_COUNTER.tcldict','objects1/DRAG_COUNTER.tcldict','objects1/RESULT.json','objects1-moved.png'],
 'profile-cold02':['objects10/TIMES.json','objects10/OPEN_COUNTER.tcldict','objects10/DRAG_COUNTER.tcldict','objects50/TIMES.json','objects50/OPEN_COUNTER.tcldict','objects50/DRAG_COUNTER.tcldict','objects50/RESULT.json','objects50-moved.png'],
 'profile-final03':['INPUT.jsonl']+[f'objects{n}/{p}' for n in [1,10,50] for p in ['TIMES.json','RESULT.json','OPEN_COUNTER.tcldict','DRAG_COUNTER.tcldict','BEFORE.tcldict','AFTER.tcldict','UNDO.tcldict','HISTORY_BEFORE.tcldict','HISTORY_AFTER.tcldict']]+['objects50-moved.png'],
 'normal-lifecycle04':['RESULT.json','SCIENCE.tcldict','CANCEL_PREVIEW.tcldict','CANCEL_RESULT.tcldict','CLOSED_BINDINGS.tcldict','INPUT.jsonl','01-saved-native.png','02-editor-closed-body-visible.png','03-gui-line-finished.png'],
 'consumer-scenarios08':['RESULT.json','INPUT.jsonl','CAMERA_COUNTER.tcldict','01-closed-native-depth.png','02-picked-native.png','03-edited-native-and-handles.png','04-closed-after-save.png','05a-active-dashed-style-fallback.png','06-edge-on-science-preserved.png','07-camera-recovery.png'],
 'cache-contract03':['RESULT.tcldict'],'quick-contract08':['RESULT.tcldict'],'native-contract03':['RESULT.tcldict','admitted.png'],'icon-batch01':['RESULT.json'],'counter-overhead01':['RESULT.tcldict'],'mass-baseline02':['RESULT.tcldict'],'mass-index-fixture02':['RESULT.tcldict'],
 'mass-final10':['RESULT.tcldict'],'mass-final50':['RESULT.tcldict'],'mass-final100':['RESULT.tcldict'],'mass-gui-profile01':['ADMITTED.tcldict','DISPOSAL.tcldict'],'mass-gui-input01':['100-native-sketches.png','INPUT.jsonl'],
 'authored1-final03':['RESULT.json','SCIENCE.tcldict','RENDERER.tcldict','DISPOSAL.tcldict','INPUT.jsonl','constructed-native-sketch.png'],
 'authored2-final01':['RESULT.json','SCIENCE.tcldict','RENDERER.tcldict','DISPOSAL.tcldict','INPUT.jsonl','constructed-native-sketch.png'],
}
# Completed final reruns are incorporated only after their actual results exist.
for name in ['consumer-final01','software-profile01','software-lifecycle01','final-window-close01','consumer-edge-final02']:
 folder=scratch/name
 if folder.exists():
  group=[p.relative_to(folder).as_posix() for p in folder.rglob('*') if p.is_file() and p.suffix in {'.json','.jsonl','.tcldict','.png','.txt','.tsv'}]
  assert all(not any(x in Path(n).parts for x in ['Sessions','home','cache','resources','config','data','state','tmp','buffers','installation','jobs']) for n in group)
  groups[name]=group
for group,names in groups.items():
 for name in names:
  source=scratch/group/name;assert source.is_file() and not source.is_symlink(),source
  target=dest/group/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
for name in ['resident-normal04','resident-normal05','resident-normal06','resident-normal07','resident-normal08','consumer-launch04','consumer-launch05','consumer-launch07','mass-gui02']:
 source=scratch/name/'LAUNCH.json'
 if source.is_file():
  target=dest/name/'LAUNCH.json';target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
rows=[dict(path=p.relative_to(root).as_posix(),sha256=sha(p),bytes=p.stat().st_size) for p in sorted(dest.rglob('*')) if p.is_file()]
(docs/'EVIDENCE_INVENTORY.json').write_text(json.dumps(dict(scope='synthetic technical evidence only; no original Session or third-party code',files=rows),indent=2)+'\n')
print(len(rows),'reviewed evidence files copied')
