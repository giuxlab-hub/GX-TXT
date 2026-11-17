#!/usr/bin/env python3
"""Read-only P011-bis GitHub source-manifest and installer integrity verifier."""
from pathlib import Path
import hashlib,json,argparse

def hashfile(p):
    with p.open("rb") as fp:
        return hashlib.file_digest(fp,"sha256").hexdigest()

def verify(root):
    folder=root/"patches/dev112/DEV112-P011-bis"
    data=json.loads((folder/"MANIFEST.json").read_text())
    atomic=json.loads((folder/"ATOMIC_MANIFEST.json").read_text())
    package=json.loads((folder/"ATOMIC_PACKAGE_FILES.json").read_text())
    before=json.loads((folder/"P011_BASELINE_FILES.json").read_text())
    after=json.loads((folder/"P011_BIS_SOURCE_FILES.json").read_text())
    assert data["patch"]==atomic["release"]=="DEV112-P011-bis"
    assert data["requires"]=="exact accepted DEV112-P011"
    assert data["source_commit"]==atomic["source_commit"]
    assert data["final_decision"]=="ACCEPT_FOR_DELIVERY"
    assert data["accepted_roles"]==["GUI","TECH","SCI"]
    assert data["activation"] is False
    assert len(before)==data["baseline_files"]==6532
    assert len(after)==data["post_files"]==6612
    assert len({k for k,v in after.items() if before.get(k)!=v})==data["changed_file_count"]==222
    assert set(before)<=set(after)
    assert data["baseline_source_sha256"]==atomic["baseline_source_archive_sha256"]
    assert data["post_source_sha256"]==atomic["source_archive_sha256"]
    assert hashfile(folder/"ATOMIC_PACKAGE_FILES.json")==data["atomic_package_index_sha256"]
    assert hashfile(folder/"apply.py")==atomic["installer_sha256"]
    for name,orig in (
      ("ATOMIC_MANIFEST.json","MANIFEST.json"),
      ("P011_BASELINE_FILES.json","BASELINE_FILES.json"),
      ("P011_BIS_SOURCE_FILES.json","SOURCE_FILES.json"),
      ("INSTALLATION_ORIGINAL.md","INSTALL.md"),
      ("apply.py","apply.py")
    ):
        assert hashfile(folder/name)==package[orig],(name,"package pin mismatch")
    assets=data["original_release_assets"]
    assert len(assets)==4
    sha_text=(folder/"SHA256SUMS").read_text()
    for item in assets:
        assert item["sha256"]+"  "+item["filename"] in sha_text
    print("PASS P011-bis: 222 source changes, 6612 final entries, exact P011 predecessor, accepted original package pins")
    print("PASS: four release asset SHA-256 references and guarded atomic installer source")
    return 0

if __name__=="__main__":
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--repository",type=Path,required=True)
    raise SystemExit(verify(ap.parse_args().repository))
