#!/usr/bin/env python3
"""Read-only integrity validation of the published GX-TXT DEV112-r2 P008 artifacts."""
from pathlib import Path
from zipfile import ZipFile
from hashlib import sha256
import hashlib, json, argparse

def digest(path):
    with Path(path).open("rb") as source:
        return hashlib.file_digest(source,"sha256").hexdigest()

def audit(repo):
    folder=repo/"patches/dev112/DEV112-P008"
    d=json.loads((folder/"MANIFEST.json").read_text(encoding="utf8"))
    m=json.loads((folder/"SOURCE_FILES.json").read_text(encoding="utf8"))
    assert d["patch"]==m["patch"]=="DEV112-P008"
    assert d["product_changes"]==len(m["payload"])==1575
    assert d["final_inventory_entries"]==len(m["postimage"])==6403
    assert set(m["routes"])=={"r2","post-p005","post-p006-r5","post-p007"}
    archive=folder/"DEV112-P008.zip"
    assert digest(archive)==d["archive_sha256"]
    with ZipFile(archive) as zipped:
        names=zipped.namelist()
        assert len(names)==len(set(names))
        for relative in m["payload"]:
            info=zipped.getinfo(relative)
            contents=zipped.read(relative)
            expected=m["postimage"][relative]
            assert len(contents)==expected["size"]
            assert sha256(contents).hexdigest()==expected["sha256"],relative
            assert (info.external_attr>>16)&0o777 == expected["mode"]&0o777,relative
        assert zipped.testzip() is None
    for file in d["files"]:
        p=folder/file["filename"]
        assert p.is_file() and p.stat().st_size==file["bytes"]
        assert digest(p)==file["sha256"]
        assert (folder/(p.name+".sha256")).read_text().split()[0]==file["sha256"]
    with ZipFile(folder/"DEV112-P008-delivery.zip") as delivery:
        assert len(delivery.namelist())==len(set(delivery.namelist()))
        assert sha256(delivery.read("patch/DEV112-P008.zip")).hexdigest()==d["archive_sha256"]
        assert delivery.testzip() is None
    print("PASS GX-TXT DEV112-r2 P008: 1575 payload postimages, 6403 final inventory entries, 4 original release objects and exact complete delivery")
    return 0

if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--repository",type=Path,required=True)
    raise SystemExit(audit(p.parse_args().repository))
