#!/usr/bin/env python3
"""Read-only checksum and file-identity validation for GX-TXT DEV112-r2 P009."""
import argparse, hashlib, json
from pathlib import Path
from zipfile import ZipFile
from hashlib import sha256

def digest(p):
    with p.open("rb") as f:
        return hashlib.file_digest(f,"sha256").hexdigest()

def audit(repo):
    d=repo/"patches/dev112/DEV112-P009"
    info=json.loads((d/"MANIFEST.json").read_text(encoding="utf-8"))
    source=json.loads((d/"SOURCE_FILES.json").read_text(encoding="utf-8"))
    assert info["patch"]==source["patch"]=="DEV112-P009"
    assert info["product_changes"]==len(source["payload"])==1711
    assert info["final_inventory_entries"]==len(source["postimage"])==6462
    assert set(source["routes"])=={
        "r2","post-p005","post-p006-r5","post-p007","post-p008"
    }
    archive=d/"DEV112-P009.zip"
    assert digest(archive)==info["archive_sha256"]
    with ZipFile(archive) as z:
        names=z.namelist()
        assert len(names)==len(set(names))
        for relative in source["payload"]:
            entry=z.getinfo(relative)
            actual=z.read(relative)
            expected=source["postimage"][relative]
            assert len(actual)==expected["size"],relative
            assert sha256(actual).hexdigest()==expected["sha256"],relative
            assert (entry.external_attr>>16)&0o777==expected["mode"]&0o777,relative
        assert z.testzip() is None
    for object in info["files"]:
        name=object["filename"]
        f=d/name
        side=d/(name+".sha256")
        if f.is_file():
            assert f.stat().st_size==object["bytes"]
            assert digest(f)==object["sha256"]
            assert side.read_text(encoding="utf-8").split()[0]==object["sha256"]
        else:
            # Large delivery/source archives are release assets, not Git blobs.
            assert name in ("DEV112-P009-delivery.zip","DEV112-P009-framework-source.tar.gz")
            assert side.read_text(encoding="utf-8").split()[0]==object["sha256"]
    print("PASS DEV112-P009: 1711 ZIP payload identities, 6462 declared final files,")
    print("     five cumulative installation baselines and original artifact SHA-256 references")
    return 0

if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--repository",type=Path,required=True)
    raise SystemExit(audit(p.parse_args().repository))
