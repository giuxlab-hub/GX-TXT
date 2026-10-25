"""Deposit new verified P019 and matching framework patch mirrors; no activation."""
from pathlib import Path
import hashlib,json,shutil,sys,zipfile
stage,release,mirrors=map(lambda p:Path(p).resolve(),sys.argv[1:])
archive=stage/'DEV111-P019.zip';digest=hashlib.sha256(archive.read_bytes()).hexdigest()
r=json.loads((stage/'VERIFICATION.json').read_text());assert r['status']=='PASS' and r['zip_sha256']==digest
ma=mirrors/'framework/archives/patches'/archive.name;expanded=mirrors/'framework/expanded/patches/DEV111-P019'
assert all(not p.exists() for p in [release,ma,Path(str(ma)+'.sha256'),expanded]),'New destinations required'
release.mkdir(parents=True)
for name in ['DEV111-P019.zip','DEV111-P019.zip.sha256','VERIFICATION.json']:shutil.copy2(stage/name,release/name)
ma.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(archive,ma);shutil.copy2(stage/'DEV111-P019.zip.sha256',Path(str(ma)+'.sha256'))
expanded.mkdir(parents=True)
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None;z.extractall(expanded)
    for row in z.infolist():
        if not row.is_dir():assert hashlib.sha256((expanded/row.filename).read_bytes()).hexdigest()==hashlib.sha256(z.read(row.filename)).hexdigest(),row.filename
assert hashlib.sha256(ma.read_bytes()).hexdigest()==digest
out={'status':'PASS','release':str(release),'archive':str(ma),'expanded':str(expanded),'sha256':digest,'activation':False}
(release/'DEPOSIT.json').write_text(json.dumps(out,indent=2)+'\n');print(json.dumps(out,indent=2))
