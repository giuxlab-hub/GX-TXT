#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Read-only public archive and file-identity checks for GX-TXT DEV111 P029."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import zipfile

IDS = ("p029",)

def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()

def sha256_file(path):
    with path.open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()

def check(manifest, root):
    errors=[]
    patch=manifest["patch"]
    archive=root/manifest["archivePath"]
    if not archive.is_file():
        return [f"{patch}: missing {archive}"]
    if sha256_file(archive)!=manifest["archiveSha256"]:
        return [f"{patch}: archive checksum mismatch"]
    for extra in manifest.get("alternativeModulePackages",[]):
        companion=root/extra["archivePath"]
        if not companion.is_file():
            errors.append(f"{patch}: missing companion {companion}")
            continue
        if sha256_file(companion)!=extra["archiveSha256"]:
            errors.append(f"{patch}: companion hash mismatch {companion}")
    with zipfile.ZipFile(archive) as z:
        names=set(z.namelist())
        if len(names)!=len(z.namelist()):errors.append(f"{patch}: duplicate ZIP member")
        for item in manifest["files"]:
            path=item["path"]
            if item.get("action")=="delete": continue
            if path not in names:
                errors.append(f"{patch}: missing member {path}");continue
            digest=item.get("after_sha256") or (item.get("after") or {}).get("sha256")
            if not digest:
                errors.append(f"{patch}: no final digest for {path}");continue
            if sha256_bytes(z.read(path))!=digest:
                errors.append(f"{patch}: incorrect member SHA256 {path}")
    return errors

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--repository",type=Path,required=True,help="GX-TXT maintenance/dev111 checkout")
    p.add_argument("--manifests",type=Path,default=Path(__file__).resolve().parents[1])
    args=p.parse_args()
    total=0
    for patch in IDS:
        source=args.manifests/f"patch-manifest-dev111-{patch}.json"
        if not source.is_file():
            print(f"FAIL {patch}: missing manifest");total+=1;continue
        manifest=json.loads(source.read_text(encoding="utf8"))
        errors=check(manifest,args.repository)
        if errors:
            for err in errors: print("FAIL",err)
            total+=len(errors)
        else:
            print(f"PASS {manifest['patch']}: archive and {len(manifest['files'])} file identities")
    if total:
        print(f"FAIL: {total} mismatches")
        return 1
    print("PASS: public archive/manifests; scientific and GUI execution outside this check")
    return 0

if __name__=="__main__":
    sys.exit(main())
