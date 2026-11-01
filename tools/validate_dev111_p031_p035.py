#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Read-only integrity check of public GX-TXT DEV111 P031..P035 distributions."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
from zipfile import ZipFile

def digest(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream,"sha256").hexdigest()

def audit(manifest, repo):
    errors=[]
    patch=manifest["patch"]
    path=repo/manifest["archivePath"]
    if not path.is_file():return [patch+": framework ZIP missing "+str(path)]
    if digest(path)!=manifest["archiveSha256"]:
        return [patch+": framework ZIP SHA-256 mismatch"]
    for item in manifest.get("distributionPackages",[]):
        file=repo/item["archivePath"]
        if not file.is_file() or digest(file)!=item["archiveSha256"]:
            errors.append(patch+": delivered "+item["category"]+" missing/mismatched "+file.name)
    if errors:return errors
    with ZipFile(path) as z:
        names=z.namelist()
        if len(names)!=len(set(names)):errors.append(patch+": duplicate archive members")
        mapping=set(names)
        for item in manifest["files"]:
            if item.get("action")=="delete":continue
            member=item["path"]
            if member not in mapping:
                errors.append(patch+": missing source blob "+member);continue
            expected=item.get("after_sha256") or (item.get("after") or {}).get("sha256")
            if not expected or hashlib.sha256(z.read(member)).hexdigest()!=expected:
                errors.append(patch+": source blob SHA-256 mismatch "+member)
    return errors

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--repository",type=Path,required=True)
    p.add_argument("--manifests",type=Path,default=Path(__file__).resolve().parents[1])
    args=p.parse_args()
    failures=0
    for n in range(31,36):
        name=f"p{n:03d}"
        manifest=json.loads((args.manifests/f"patch-manifest-dev111-{name}.json").read_text(encoding="utf8"))
        errors=audit(manifest,args.repository)
        if errors:
            for error in errors:print("FAIL",error)
            failures+=len(errors)
        else:
            categories={}
            for f in manifest["distributionPackages"]:
                categories[f["category"]]=categories.get(f["category"],0)+1
            print("PASS",manifest["patch"],"archive",len(manifest["files"]),
                  "source paths",len(manifest["distributionPackages"]),"other ZIPs",categories)
    if failures:
        print("FAIL",failures,"archive/identity discrepancies")
        return 1
    print("PASS: all five archived releases and every distributed ZIP, read-only.")
    print("Scientific/GUI/installation acceptance is not implied by this public integrity check.")
    return 0

if __name__=="__main__":
    sys.exit(main())
