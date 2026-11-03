#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Read-only SHA-256 validation for GX-TXT DEV112-r2 P001–P004 archives."""
import argparse
import hashlib
import json
from pathlib import Path
from zipfile import ZipFile

def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream,"sha256").hexdigest()

def audit(root,number):
    patch=f"P{number:03d}"
    base=root/"patches/dev112"/f"DEV112-{patch}"
    info=json.loads((base/"MANIFEST.json").read_text(encoding="utf-8"))
    file_manifest=json.loads((base/"FILES.json").read_text(encoding="utf-8"))
    assert info["patch"]==file_manifest["patch"]==f"DEV112-{patch}"
    archive=base/info["archive"]
    assert digest(archive)==info["archive_sha256"]
    assert archive.stat().st_size==info["archive_bytes"]
    with ZipFile(archive) as z:
        names=z.namelist()
        assert len(names)==len(set(names))
        if number==4:
            post=file_manifest["postimage"]
            entries=[(p,post[p]) for p in file_manifest["payload"]]
        else:
            entries=[(p["path"],p["after"])
                     for p in (file_manifest["changed_files"] if number==1
                               else file_manifest["files"])]
        assert len(entries)==info["product_file_count"]
        for name,expected in entries:
            data=z.read(name)
            assert len(data)==expected["size"],(patch,name,"size")
            assert hashlib.sha256(data).hexdigest()==expected["sha256"],(patch,name,"SHA")
        assert z.testzip() is None,patch
    for item in info["packages"]:
        package=base/item["name"]
        assert package.stat().st_size==item["bytes"]
        assert digest(package)==item["sha256"]
        assert (base/(item["name"]+".sha256")).read_text().split()[0]==item["sha256"]
    for item in info["additional_files"]:
        extra=base/item["name"]
        assert extra.stat().st_size==item["bytes"]
        assert digest(extra)==item["sha256"]
    return info["product_file_count"],len(info["packages"])

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository",type=Path,required=True,
                        help="Checkout of maintenance/dev112")
    args=parser.parse_args()
    changed=archives=0
    for n in range(1,5):
        c,a=audit(args.repository,n)
        changed+=c
        archives+=a
        print(f"PASS DEV112-P{n:03d}: {c} payload identities, {a} original ZIP packages")
    print(f"PASS: {changed} declared payload identities, {archives} delivered ZIPs")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
