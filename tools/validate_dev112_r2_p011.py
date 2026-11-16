#!/usr/bin/env python3
"""Read-only verification of official GX-TXT DEV112-r2 P011 source/patch objects."""
from pathlib import Path
from zipfile import ZipFile
import json,hashlib,argparse

def sha(p):
    with Path(p).open("rb") as f:
        return hashlib.file_digest(f,"sha256").hexdigest()

def check(repo):
    root=repo/"patches/dev112/DEV112-P011"
    m=json.loads((root/"MANIFEST.json").read_text(encoding="utf8"))
    files=json.loads((root/"SOURCE_FILES.json").read_text(encoding="utf8"))
    assert m["patch"]==files["patch"]=="DEV112-P011"
    assert m["source_baseline"]=="DEV112-P010"
    assert m["supported_routes"]==list(files["routes"])==["post-p010"]
    assert len(files["payload"])==m["product_changes"]==121
    assert len(files["postimage"])==m["final_inventory_entries"]==6532
    archive=root/"DEV112-P011-overlay.zip"
    assert sha(archive)==m["archive_sha256"]
    with ZipFile(archive) as z:
        names=z.namelist()
        assert len(names)==len(set(names))
        for rel in files["payload"]:
            record=files["postimage"][rel]
            data=z.read(rel)
            assert len(data)==record["size"],rel
            assert hashlib.sha256(data).hexdigest()==record["sha256"],rel
            assert (z.getinfo(rel).external_attr>>16)&0o777 == record["mode"]&0o777,rel
        assert z.testzip() is None
    assert len(m["files"])==5
    for entry in m["files"]:
        path=root/entry["filename"]
        side=root/(entry["filename"]+".sha256")
        assert side.is_file() and side.read_text(encoding="utf8").split()[0]==entry["sha256"]
        if path.is_file():
            assert path.stat().st_size==entry["bytes"]
            assert sha(path)==entry["sha256"]
        else:
            assert entry["filename"] in ("DEV112-P011-delivery.tar.gz","DEV112-P011-framework-source.tar.gz")
    print("PASS GX-TXT DEV112 P011: 121 patch postimages, 6532 final source records, exact post-P010 admission, 5 distribution object hashes")
    return 0
if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository",type=Path,required=True)
    raise SystemExit(check(parser.parse_args().repository))
