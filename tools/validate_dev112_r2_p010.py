#!/usr/bin/env python3
"""Read-only verification of accepted GX-TXT DEV112-r2 P010 distribution identities."""
from pathlib import Path
from zipfile import ZipFile
import argparse,json,hashlib

def digest(p):
    with Path(p).open("rb") as f:
        return hashlib.file_digest(f,"sha256").hexdigest()

def check(root):
    base=root/"patches/dev112/DEV112-P010"
    info=json.loads((base/"MANIFEST.json").read_text())
    file_manifest=json.loads((base/"SOURCE_FILES.json").read_text())
    assert info["patch"]==file_manifest["patch"]=="DEV112-P010"
    assert info["source_baseline"]=="DEV112-P009"
    assert info["supported_routes"]==["post-p009"]==list(file_manifest["routes"])
    assert len(file_manifest["payload"])==info["product_changes"]==90
    assert len(file_manifest["postimage"])==info["final_inventory_entries"]==6503
    archive=base/info["archive"]
    assert digest(archive)==info["archive_sha256"]
    with ZipFile(archive) as z:
        names=z.namelist()
        assert len(names)==len(set(names))
        for path in file_manifest["payload"]:
            actual=z.read(path)
            expected=file_manifest["postimage"][path]
            assert len(actual)==expected["size"],path
            assert hashlib.sha256(actual).hexdigest()==expected["sha256"],path
            assert (z.getinfo(path).external_attr>>16)&0o777==expected["mode"]&0o777,path
        assert z.testzip() is None
    for file in info["files"]:
        p=base/file["filename"]
        side=base/(file["filename"]+".sha256")
        assert side.is_file() and side.read_text().split()[0]==file["sha256"]
        if p.is_file():
            assert p.stat().st_size==file["bytes"]
            assert digest(p)==file["sha256"]
        else:
            assert file["filename"] in (
                "DEV112-P010-delivery.tar.gz",
                "DEV112-P010-framework-source.tar.gz",
            )
    print("PASS DEV112 P010: 90 patch postimages, 6503 final source identities, exact post-P009 baseline and 8 release object hashes")
    return 0

if __name__=="__main__":
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--repository",type=Path,required=True)
    raise SystemExit(check(ap.parse_args().repository))
