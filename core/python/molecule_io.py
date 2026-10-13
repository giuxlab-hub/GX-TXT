#!/usr/bin/env python3
"""Source-preserving molecular inspection and VTK display conversion.

The SDF/XYZ/PDB payload remains authoritative.  The VTP file is a derived
display artifact; measurements always use coordinates read from the payload.
"""
from __future__ import annotations

import argparse
import base64
import json
import math
import pathlib
import sys
import urllib.error
import urllib.parse
import urllib.request

RADII = {"H": .31, "B": .85, "C": .76, "N": .71, "O": .66, "F": .57,
         "P": 1.07, "S": 1.05, "Cl": 1.02, "Br": 1.20, "I": 1.39,
         "Na": 1.66, "Mg": 1.41, "Fe": 1.32, "Cu": 1.32, "Zn": 1.22}
VDW = {"H": 1.20, "B": 1.92, "C": 1.70, "N": 1.55, "O": 1.52,
       "F": 1.47, "P": 1.80, "S": 1.80, "Cl": 1.75, "Br": 1.85,
       "I": 1.98, "Na": 2.27, "Mg": 1.73, "Fe": 1.56, "Cu": 1.40,
       "Zn": 1.39}
NUMBER = {"H": 1, "B": 5, "C": 6, "N": 7, "O": 8, "F": 9,
          "Na": 11, "Mg": 12, "P": 15, "S": 16, "Cl": 17, "Fe": 26,
          "Cu": 29, "Zn": 30, "Br": 35, "I": 53}


def element(text: str) -> str:
    s = text.strip().title()
    if not s or not s[0].isalpha() or len(s) > 2:
        raise ValueError(f"Invalid element symbol: {text!r}")
    return s


def infer_bonds(atoms):
    result = []
    for i, a in enumerate(atoms):
        for j in range(i + 1, len(atoms)):
            b = atoms[j]
            d = math.dist(a[1:4], b[1:4])
            if .35 < d < 1.20 * (RADII.get(a[0], .77) + RADII.get(b[0], .77)):
                result.append((i + 1, j + 1, 1))
    return result


def read_sdf(path):
    text = path.read_text(encoding="utf-8", errors="replace")
    frames = []
    for block in text.split("$$$$"):
        lines = block.splitlines()
        if len(lines) < 5 or not lines[3].strip():
            continue
        if "V3000" in lines[3]:
            raise ValueError("SDF V3000 is not yet supported; use V2000")
        try:
            na, nb = int(lines[3][0:3]), int(lines[3][3:6])
        except ValueError as exc:
            raise ValueError("Invalid SDF V2000 counts line") from exc
        if not 0 < na <= 10000 or not 0 <= nb <= 50000 or len(lines) < 4 + na + nb:
            raise ValueError("SDF atom/bond count exceeds bounds or is truncated")
        atoms = []
        for line in lines[4:4 + na]:
            charge_code = int(line[36:39].strip() or "0")
            charge = {1: 3, 2: 2, 3: 1, 5: -1, 6: -2, 7: -3}.get(charge_code, 0)
            atoms.append((element(line[31:34]), float(line[0:10]), float(line[10:20]), float(line[20:30]), charge))
        bonds = []
        for line in lines[4 + na:4 + na + nb]:
            a, b, order = int(line[0:3]), int(line[3:6]), int(line[6:9])
            if not (1 <= a <= na and 1 <= b <= na and a != b):
                raise ValueError("SDF bond refers to an invalid atom")
            bonds.append((a, b, order))
        for line in lines[4 + na + nb:]:
            if line.startswith("M  CHG"):
                parts = line.split()
                for k in range(int(parts[2])):
                    idx, charge = int(parts[3 + 2*k]), int(parts[4 + 2*k])
                    if 1 <= idx <= na:
                        atoms[idx - 1] = (*atoms[idx - 1][:4], charge)
        frames.append((lines[0].strip() or path.stem, atoms, bonds))
    if not frames:
        raise ValueError("No SDF molecule was found")
    reference_atoms = [atom[0] for atom in frames[0][1]]
    reference_bonds = sorted(frames[0][2])
    for _, atoms, bonds in frames[1:]:
        if [atom[0] for atom in atoms] != reference_atoms or sorted(bonds) != reference_bonds:
            raise ValueError("Multiple SDF records must have the same atom order and bonds to be treated as conformers")
    return frames


def read_xyz(path):
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    frames, i = [], 0
    while i < len(lines):
        if not lines[i].strip():
            i += 1
            continue
        try:
            count = int(lines[i].strip())
        except ValueError as exc:
            raise ValueError("XYZ frame must begin with an atom count") from exc
        if not 0 < count <= 10000 or i + 2 + count > len(lines):
            raise ValueError("XYZ frame has an invalid or truncated atom count")
        atoms = []
        for line in lines[i + 2:i + 2 + count]:
            fields = line.split()
            if len(fields) < 4:
                raise ValueError("XYZ atom row needs element and three coordinates")
            atoms.append((element(fields[0]), *map(float, fields[1:4]), 0))
        frames.append((lines[i + 1].strip() or path.stem, atoms, infer_bonds(atoms)))
        i += 2 + count
    if not frames:
        raise ValueError("No XYZ frame was found")
    return frames


def read_pdb(path):
    atoms, serials, bonds = [], {}, set()
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.startswith(("ATOM  ", "HETATM")):
            if line[16:17] not in (" ", "A"):
                continue
            symbol = line[76:78].strip() or "".join(c for c in line[12:16] if c.isalpha())[:1]
            atoms.append((element(symbol), float(line[30:38]), float(line[38:46]), float(line[46:54]), 0))
            serials[int(line[6:11])] = len(atoms)
        elif line.startswith("CONECT"):
            fields = line[6:].split()
            if fields:
                for target in fields[1:]:
                    bonds.add(tuple(sorted((int(fields[0]), int(target)))))
    if not atoms:
        raise ValueError("PDB contains no ATOM/HETATM records")
    mapped = [(serials[a], serials[b], 1) for a, b in sorted(bonds) if a in serials and b in serials]
    return [(path.stem, atoms, mapped or infer_bonds(atoms))]


def read(path):
    ext = path.suffix.lower()
    if ext in (".sdf", ".mol"):
        return read_sdf(path), "sdf"
    if ext == ".xyz":
        return read_xyz(path), "xyz"
    if ext in (".pdb", ".ent"):
        return read_pdb(path), "pdb"
    raise ValueError(f"Unsupported molecular file extension {ext}")


def emit(key, *values):
    def enc(value):
        return base64.b64encode(str(value).encode("utf-8")).decode("ascii")
    print("\t".join((key, *(enc(v) for v in values))))


def inspect(path):
    frames, fmt = read(path)
    name, atoms, bonds = frames[0]
    emit("META", "molecule.format", fmt)
    emit("META", "molecule.name", name)
    emit("META", "molecule.atom_count", len(atoms))
    emit("META", "molecule.bond_count", len(bonds))
    emit("META", "molecule.conformer_count", len(frames))
    emit("META", "molecule.coordinates", "angstrom")
    emit("META", "molecule.elements", ",".join(sorted({a[0] for a in atoms})))
    emit("META", "molecule.net_formal_charge", sum(a[4] for a in atoms))
    for k, (title, frame_atoms, frame_bonds) in enumerate(frames):
        if len(frame_atoms) != len(atoms):
            raise ValueError("Conformer atom counts differ")
        emit("FRAME", k, title)
        for idx, (sym, x, y, z, charge) in enumerate(frame_atoms, 1):
            if not all(math.isfinite(v) for v in (x, y, z)):
                raise ValueError("Non-finite molecular coordinate")
            emit("ATOM", k, idx, sym, x, y, z, charge)
        for a, b, order in frame_bonds:
            emit("BOND", k, a, b, order)


def make_mesh(path, out, frame_index, style):
    import vtk
    frames, _ = read(path)
    if not 0 <= frame_index < len(frames):
        raise ValueError("Conformer index is out of range")
    _, atoms, bonds = frames[frame_index]
    if style not in ("ball_and_stick", "space_filling"):
        raise ValueError("Unknown molecular style")
    append = vtk.vtkAppendPolyData()
    for sym, x, y, z, _ in atoms:
        sphere = vtk.vtkSphereSource()
        sphere.SetCenter(x, y, z)
        sphere.SetRadius((VDW.get(sym, 1.7) if style == "space_filling" else .24 * VDW.get(sym, 1.7)))
        sphere.SetThetaResolution(18)
        sphere.SetPhiResolution(12)
        sphere.Update()
        poly = vtk.vtkPolyData()
        poly.DeepCopy(sphere.GetOutput())
        values = vtk.vtkFloatArray()
        values.SetName("element")
        values.SetNumberOfValues(poly.GetNumberOfPoints())
        values.Fill(float(NUMBER.get(sym, 0)))
        poly.GetPointData().AddArray(values)
        append.AddInputData(poly)
    for a, b, order in bonds:
        p, q = atoms[a - 1], atoms[b - 1]
        start, end = p[1:4], q[1:4]
        direction = [end[i] - start[i] for i in range(3)]
        distance = math.dist(start, end)
        if distance < 1e-6:
            continue
        offset_axis = [direction[1], -direction[0], 0]
        norm = math.sqrt(sum(v*v for v in offset_axis))
        if norm < 1e-6:
            offset_axis = [0, direction[2], -direction[1]]
            norm = math.sqrt(sum(v*v for v in offset_axis))
        offset_axis = [v / norm for v in offset_axis]
        cylinders = (min(max(order, 1), 3) if order != 4 else 2) if style == "ball_and_stick" else 1
        for branch in range(cylinders):
            shift = (branch - (cylinders - 1) / 2) * .15
            center = [(start[i] + end[i]) / 2 + shift * offset_axis[i] for i in range(3)]
            cylinder = vtk.vtkCylinderSource()
            cylinder.SetRadius((.09 if cylinders > 1 else .12) if style == "ball_and_stick" else .015)
            cylinder.SetHeight(distance)
            cylinder.SetResolution(12)
            cylinder.CappingOn()
            cylinder.Update()
            transform = vtk.vtkTransform()
            # vtkCylinderSource is aligned with +Y.
            axis = [direction[2], 0, -direction[0]]
            angle = math.degrees(math.acos(max(-1, min(1, direction[1] / distance))))
            transform.Translate(*center)
            if sum(v*v for v in axis) > 1e-12:
                transform.RotateWXYZ(angle, *axis)
            elif direction[1] < 0:
                transform.RotateX(180)
            filt = vtk.vtkTransformPolyDataFilter()
            filt.SetInputConnection(cylinder.GetOutputPort())
            filt.SetTransform(transform)
            filt.Update()
            poly = vtk.vtkPolyData()
            poly.DeepCopy(filt.GetOutput())
            values = vtk.vtkFloatArray()
            values.SetName("element")
            values.SetNumberOfValues(poly.GetNumberOfPoints())
            values.Fill(0)
            poly.GetPointData().AddArray(values)
            append.AddInputData(poly)
    append.Update()
    writer = vtk.vtkXMLPolyDataWriter()
    writer.SetFileName(str(out))
    writer.SetInputConnection(append.GetOutputPort())
    writer.SetDataModeToBinary()
    if not writer.Write():
        raise ValueError("VTK failed to write molecular display geometry")
    emit("OUT", out)


def resolve(kind, query, output):
    if kind not in ("name", "cid", "smiles", "inchi", "inchikey"):
        raise ValueError("Supported PubChem identifiers: name, cid, smiles, inchi, inchikey")
    if not query.strip() or len(query) > 4096:
        raise ValueError("A nonempty identifier up to 4096 characters is required")
    base = "https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound"
    headers = {"User-Agent": "GX-TXT-MoleculeViewer/1.0 (scientific interactive lookup)"}
    if kind == "cid":
        cid = int(query)
        if cid < 1:
            raise ValueError("CID must be positive")
    else:
        if kind in ("smiles", "inchi"):
            url = f"{base}/{kind}/cids/JSON"
            data = urllib.parse.urlencode({kind: query}).encode("utf-8")
            req = urllib.request.Request(url, data=data, headers=headers)
        else:
            url = f"{base}/{kind}/{urllib.parse.quote(query, safe='')}/cids/JSON"
            req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=30) as response:
            cids = json.load(response).get("IdentifierList", {}).get("CID", [])
        if not cids:
            raise ValueError("PubChem did not resolve the identifier")
        cid = int(cids[0])
    url = f"{base}/cid/{cid}/record/SDF?record_type=3d"
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=45) as response:
        content = response.read(16_000_001)
    if len(content) > 16_000_000:
        raise ValueError("PubChem structure exceeds 16 MB")
    output.write_bytes(content)
    read_sdf(output)
    emit("RESOLVED", cid, url)


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="action", required=True)
    q = sub.add_parser("inspect")
    q.add_argument("source", type=pathlib.Path)
    q = sub.add_parser("mesh")
    q.add_argument("source", type=pathlib.Path)
    q.add_argument("output", type=pathlib.Path)
    q.add_argument("--frame", type=int, default=0)
    q.add_argument("--style", default="ball_and_stick")
    q = sub.add_parser("resolve")
    q.add_argument("kind")
    q.add_argument("query")
    q.add_argument("output", type=pathlib.Path)
    args = p.parse_args()
    try:
        if args.action == "inspect":
            inspect(args.source)
        elif args.action == "mesh":
            make_mesh(args.source, args.output, args.frame, args.style)
        else:
            resolve(args.kind, args.query, args.output)
    except (ValueError, OSError, urllib.error.URLError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
