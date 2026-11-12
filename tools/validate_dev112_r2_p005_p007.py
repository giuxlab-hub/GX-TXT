#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Read-only archive/member integrity verification for GX-TXT DEV112-r2 P005–P007."""
from pathlib import Path
from zipfile import ZipFile
from hashlib import sha256
import hashlib, json, argparse

def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream,"sha256").hexdigest()

def audit(root,n):
    patch=f"P{n:03d}"
    folder=root/"patches/dev112"/f"DEV112-{patch}"
    info=json.loads((folder/"MANIFEST.json").read_text(encoding="utf8"))
    manifest=json.loads((folder/"SOURCE_FILES.json").read_text(encoding="utf8"))
    assert info["patch"]==manifest["patch"]==f"DEV112-{patch}"
    archive=folder/info["archive"]
    assert archive.is_file()
    assert digest(archive)==info["archive_sha256"]
    with ZipFile(archive) as z:
        members=z.namelist()
        assert len(set(members))==len(members)
        assert len(manifest["payload"])==info["product_changes"]
        for entry in manifest["payload"]:
            expected=manifest["postimage"][entry]
            member=z.getinfo(entry)
            data=z.read(entry)
            assert len(data)==expected["size"],(patch,entry,"size")
            assert sha256(data).hexdigest()==expected["sha256"],(patch,entry,"hash")
            assert ((member.external_attr>>16)&0o777)==(expected["mode"]&0o777),(patch,entry,"mode")
        assert z.testzip() is None
    for meta in info["files"]:
        file=folder/meta["filename"]
        assert file.is_file() and file.stat().st_size==meta["bytes"]
        assert digest(file)==meta["sha256"]
        side=folder/(meta["filename"]+".sha256")
        if side.exists():
            assert side.read_text(encoding="utf8").split()[0]==meta["sha256"]
        if meta["filename"].endswith("-delivery.zip"):
            with ZipFile(file) as z:
                assert "patch/"+info["archive"] in z.namelist()
                assert sha256(z.read("patch/"+info["archive"])).hexdigest()==info["archive_sha256"]
    return info["product_changes"],len(info["files"])

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--repository",type=Path,required=True)
    args=p.parse_args()
    total=packages=0
    for n in (5,6,7):
        count,assets=audit(args.repository,n)
        total+=count;packages+=assets
        print(f"PASS DEV112-P{n:03d}: {count} postimages and {assets} distributed files")
    print(f"PASS: {total} payload postimages and {packages} distribution objects")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
