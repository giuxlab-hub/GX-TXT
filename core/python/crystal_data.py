#!/usr/bin/env python3
"""CIF/CUBE scientific decoding and VTK representation for the crystal viewer.

The source files remain authoritative. This module creates disposable rendering
artifacts, and never changes an imported CIF or CUBE.
"""
from __future__ import annotations

import argparse
import ast
import base64
import hashlib
import json
import math
import re
import shlex
from pathlib import Path

BOHR = 0.529177210903
RADII = {"H": .31, "C": .76, "N": .71, "O": .66, "F": .57, "Na": 1.66,
         "Cl": 1.02, "Si": 1.11, "P": 1.07, "S": 1.05, "Ca": 1.76,
         "Ti": 1.60, "Fe": 1.24, "Cu": 1.32, "Br": 1.20, "Al": 1.21}
Z = {"H": 1, "C": 6, "N": 7, "O": 8, "F": 9, "Na": 11, "Al": 13,
     "Si": 14, "P": 15, "S": 16, "Cl": 17, "Ca": 20, "Ti": 22,
     "Fe": 26, "Cu": 29, "Br": 35}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def number(value):
    value = str(value).strip()
    value = re.sub(r"\([^)]*\)$", "", value)
    if value in ("?", ".", ""):
        raise ValueError("Required numeric CIF value is missing")
    result = float(value)
    if not math.isfinite(result):
        raise ValueError("Nonfinite scientific value")
    return result


def cif_tokens(data):
    lines = data.splitlines()
    prepared, blocks = [], {}
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith(";"):
            contents = [line[1:]]
            i += 1
            while i < len(lines) and not lines[i].startswith(";"):
                contents.append(lines[i]); i += 1
            if i == len(lines):
                raise ValueError("Unterminated CIF multiline value")
            marker = f"CIFMULTILINEVALUE{len(blocks)}END"
            blocks[marker] = "\n".join(contents).strip()
            prepared.append(marker)
        else:
            prepared.append(line)
        i += 1
    lex = shlex.shlex("\n".join(prepared), posix=True)
    lex.whitespace_split = True
    lex.commenters = "#"
    return [blocks.get(token, token) for token in lex]


def parse_cif(path):
    tokens = cif_tokens(Path(path).read_text(encoding="utf-8", errors="replace"))
    scalars, loops = {}, []
    i = 0
    while i < len(tokens):
        token = tokens[i]
        if token.lower() == "loop_":
            i += 1; keys = []
            while i < len(tokens) and tokens[i].startswith("_"):
                keys.append(tokens[i].lower()); i += 1
            if not keys:
                raise ValueError("CIF loop has no columns")
            values = []
            while i < len(tokens) and not (tokens[i].startswith("_") or
                    tokens[i].lower() in ("loop_", "stop_") or
                    tokens[i].lower().startswith("data_")):
                values.append(tokens[i]); i += 1
            if len(values) % len(keys):
                raise ValueError("CIF loop has an incomplete row")
            loops.append((keys, [dict(zip(keys, values[j:j+len(keys)]))
                                for j in range(0, len(values), len(keys))]))
            continue
        if token.startswith("_") and i+1 < len(tokens):
            scalars[token.lower()] = tokens[i+1]
            i += 2; continue
        i += 1
    def field(*names, default=""):
        return next((scalars[n] for n in names if n in scalars), default)
    a, b, c = [number(field("_cell_length_" + x)) for x in "abc"]
    alpha, beta, gamma = [math.radians(number(field("_cell_angle_" + x)))
                           for x in ("alpha", "beta", "gamma")]
    ca, cb, cg, sg = math.cos(alpha), math.cos(beta), math.cos(gamma), math.sin(gamma)
    if abs(sg) < 1e-9:
        raise ValueError("Invalid crystallographic gamma angle")
    ax = (a, 0., 0.)
    bx = (b*cg, b*sg, 0.)
    czx, czy = c*cb, c*(ca-cb*cg)/sg
    czz2 = c*c-czx*czx-czy*czy
    if czz2 <= 0:
        raise ValueError("Invalid unit-cell geometry")
    cx = (czx, czy, math.sqrt(czz2))
    sites = []
    ops = []
    for keys, rows in loops:
        if "_atom_site_fract_x" in keys:
            for row in rows:
                label = row.get("_atom_site_label", f"site{len(sites)+1}")
                element = row.get("_atom_site_type_symbol", "")
                element = re.match(r"[A-Z][a-z]?", element or label)
                element = element.group() if element else "X"
                sites.append({"label": label, "element": element,
                              "fractional": [number(row[f"_atom_site_fract_{x}"]) for x in "xyz"],
                              "occupancy": number(row.get("_atom_site_occupancy", "1"))})
        for key in ("_space_group_symop_operation_xyz", "_symmetry_equiv_pos_as_xyz"):
            if key in keys:
                ops.extend(row[key] for row in rows)
    if not sites:
        raise ValueError("CIF has no fractional atom sites")
    if not ops:
        table = json.loads(Path(__file__).with_name("symmetry_groups.json").read_text())
        hall = field("_space_group_name_hall", "_symmetry_space_group_name_hall")
        hm = field("_space_group_name_h-m_alt", "_symmetry_space_group_name_h-m")
        n = field("_space_group_it_number", "_symmetry_int_tables_number")
        group = next((g for g in table if hall and g["hall"].replace(" ", "").lower() == hall.replace(" ", "").lower()), None)
        if group is None:
            group = next((g for g in table if hm and g["hm"].replace(" ", "").lower() == hm.replace(" ", "").lower()), None)
        if group is None and n:
            group = next((g for g in table if str(g["number"]) == n), None)
        if group is None:
            raise ValueError("CIF lacks symmetry operations and its space group is unknown")
        ops = group["ops"]
    return {"kind": "cif", "source_sha256": sha(path), "sites": sites,
            "operators": ops, "vectors": [ax,bx,cx],
            "cell": [a,b,c,math.degrees(alpha),math.degrees(beta),math.degrees(gamma)],
            "space_group": field("_space_group_name_h-m_alt", "_symmetry_space_group_name_h-m"),
            "space_group_number": field("_space_group_it_number", "_symmetry_int_tables_number"),
            "formula": field("_chemical_formula_sum"),
            "citation": field("_publ_section_title"),
            "doi": field("_journal_paper_doi"),
            "source_id": field("_cod_database_code", default=Path(path).stem)}


def eval_component(expression, xyz):
    expression = expression.lower().replace(" ", "")
    node = ast.parse(expression, mode="eval").body
    def visit(v):
        if isinstance(v, ast.Name) and v.id in "xyz": return xyz["xyz".index(v.id)]
        if isinstance(v, ast.Constant) and type(v.value) in (int,float): return float(v.value)
        if isinstance(v, ast.UnaryOp) and isinstance(v.op, ast.USub): return -visit(v.operand)
        if isinstance(v, ast.UnaryOp) and isinstance(v.op, ast.UAdd): return visit(v.operand)
        if isinstance(v, ast.BinOp):
            l,r = visit(v.left),visit(v.right)
            if isinstance(v.op, ast.Add): return l+r
            if isinstance(v.op, ast.Sub): return l-r
            if isinstance(v.op, ast.Div) and r != 0: return l/r
        raise ValueError("Unsupported symmetry operation")
    return visit(node)


def cart(frac, vectors):
    return [sum(frac[j]*vectors[j][i] for j in range(3)) for i in range(3)]


def expanded_atoms(model, repeats=1):
    if repeats not in (1,2,3): raise ValueError("Supercell is limited to 1, 2 or 3")
    unique = {}
    for site in model["sites"]:
        for op_index, op in enumerate(model["operators"]):
            parts = op.replace(" ", "").split(",")
            if len(parts) != 3: raise ValueError("Invalid three-axis symmetry operation")
            frac = [eval_component(x, site["fractional"]) % 1 for x in parts]
            key = (site["element"], *(round(x % 1, 6) for x in frac))
            if key not in unique:
                unique[key] = {"label": site["label"], "element": site["element"],
                               "occupancy": site["occupancy"], "fractional": frac,
                               "operator": op_index+1}
    atoms = []
    for i in range(repeats):
        for j in range(repeats):
            for k in range(repeats):
                for site in unique.values():
                    full = [site["fractional"][0]+i, site["fractional"][1]+j,
                            site["fractional"][2]+k]
                    atoms.append({**site, "fractional": full,
                                  "cartesian": cart(full, model["vectors"]),
                                  "cell_index": [i,j,k]})
    return atoms


def parse_cube(path):
    with Path(path).open(encoding="ascii", errors="replace") as f:
        comment1, comment2 = f.readline().strip(), f.readline().strip()
        header = f.readline().split()
        if len(header) < 4: raise ValueError("Incomplete CUBE atom header")
        natoms = int(header[0]); origin = [float(x)*BOHR for x in header[1:4]]
        if natoms < 0: raise ValueError("Orbital CUBE arrays are not electron density")
        counts, axes = [], []
        for _ in range(3):
            row = f.readline().split(); n = int(row[0])
            if abs(n) < 2 or abs(n) > 512: raise ValueError("Unsupported CUBE grid dimension")
            counts.append(abs(n))
            scale = BOHR if n > 0 else 1.
            axes.append([float(x)*scale for x in row[1:4]])
        if math.prod(counts) > 16_000_000:
            raise ValueError("CUBE grid exceeds the 16-million-value display limit")
        atoms = []
        for index in range(natoms):
            row = f.readline().split()
            z = int(float(row[0])); element = next((e for e,v in Z.items() if v == z), str(z))
            atoms.append({"label": f"{element}{index+1}", "element": element,
                          "occupancy": 1., "fractional": None,
                          "cartesian": [float(x)*BOHR for x in row[2:5]],
                          "operator": 1, "cell_index": [0,0,0]})
        import numpy as np
        values = np.fromstring(f.read().replace("D", "E").replace("d", "e"), sep=" ")
    total = math.prod(counts)
    if len(values) != total or not np.all(np.isfinite(values)):
        raise ValueError("CUBE scalar count or finite-value check failed")
    values = values.reshape(counts)
    return {"kind": "cube", "source_sha256": sha(path), "atoms": atoms,
            "counts": counts, "axes": axes, "origin": origin, "values": values,
            "range": [float(values.min()), float(values.max())],
            "field_unit": "e/Bohr^3" if "e/Bohr^3" in comment1 else "source CUBE unit",
            "description": comment1, "generator": comment2}


def write_poly(path, points, lines=None, scalars=None, strings=None):
    import vtk
    poly = vtk.vtkPolyData(); pts = vtk.vtkPoints()
    for point in points: pts.InsertNextPoint(*point)
    poly.SetPoints(pts)
    cells = vtk.vtkCellArray()
    if lines:
        for u,v in lines:
            cell = vtk.vtkLine(); cell.GetPointIds().SetId(0,u); cell.GetPointIds().SetId(1,v)
            cells.InsertNextCell(cell)
        poly.SetLines(cells)
    else:
        for i in range(len(points)):
            cell = vtk.vtkVertex(); cell.GetPointIds().SetId(0,i); cells.InsertNextCell(cell)
        poly.SetVerts(cells)
    for name, values in (scalars or {}).items():
        arr = vtk.vtkFloatArray(); arr.SetName(name)
        for value in values: arr.InsertNextValue(value)
        poly.GetPointData().AddArray(arr)
    for name, values in (strings or {}).items():
        arr = vtk.vtkStringArray(); arr.SetName(name)
        for value in values: arr.InsertNextValue(value)
        poly.GetPointData().AddArray(arr)
    writer = vtk.vtkXMLPolyDataWriter(); writer.SetFileName(str(path)); writer.SetInputData(poly)
    writer.SetDataModeToBinary()
    if not writer.Write(): raise RuntimeError("VTK polydata write failed")


def bond_pairs(atoms):
    pairs = []
    for i,a in enumerate(atoms):
        for j in range(i+1,len(atoms)):
            b = atoms[j]
            r = RADII.get(a["element"],.9)+RADII.get(b["element"],.9)
            d2 = sum((x-y)**2 for x,y in zip(a["cartesian"],b["cartesian"]))
            if .16 < d2 < (1.2*r)**2: pairs.append((i,j))
    return pairs


def write_structure(out, atoms, vectors=None, repeats=1):
    out.mkdir(parents=True,exist_ok=True)
    points = [a["cartesian"] for a in atoms]
    if atoms:
        write_poly(out/"atoms.vtp",points,scalars={"atomic_number":[Z.get(a["element"],0) for a in atoms],
                  "radius_A":[max(.23,RADII.get(a["element"],.9)*.46) for a in atoms],
                  "occupancy":[a["occupancy"] for a in atoms]},
                  strings={"site_label":[a["label"] for a in atoms]})
    pairs=bond_pairs(atoms)
    if pairs: write_poly(out/"bonds.vtp",points,lines=pairs)
    if vectors:
        v=[[x*repeats for x in vec] for vec in vectors]
        corners=[cart((i,j,k),v) for i in (0,1) for j in (0,1) for k in (0,1)]
        edges=[(i,j) for i in range(8) for j in range(i+1,8) if (i^j) in (1,2,4)]
        write_poly(out/"cell.vtp",corners,lines=edges)
        axis_points=[[0,0,0],v[0],v[1],v[2]]
        write_poly(out/"axes.vtp",axis_points,lines=[(0,1),(0,2),(0,3)])
    return len(pairs)


def write_density(out, cube, axis="z", fraction=.5, contour=None):
    import vtk
    from vtk.util.numpy_support import numpy_to_vtk
    import numpy as np
    counts=cube["counts"]; image=vtk.vtkImageData(); image.SetDimensions(*counts)
    image.SetOrigin(*cube["origin"])
    spacing=[math.sqrt(sum(x*x for x in v)) for v in cube["axes"]]
    image.SetSpacing(*spacing)
    direction=vtk.vtkMatrix3x3()
    for col,vec in enumerate(cube["axes"]):
        for row in range(3): direction.SetElement(row,col,vec[row]/spacing[col])
    image.SetDirectionMatrix(direction)
    arr=numpy_to_vtk(np.asarray(cube["values"],dtype=np.float32).ravel(order="F"),deep=True)
    arr.SetName("electron_density"); image.GetPointData().SetScalars(arr)
    writer=vtk.vtkXMLImageDataWriter();writer.SetFileName(str(out/"density.vti"))
    writer.SetInputData(image);writer.SetDataModeToBinary()
    if not writer.Write(): raise RuntimeError("VTK image write failed")
    bounds=image.GetBounds(); idx="xyz".index(axis)
    plane=vtk.vtkPlane(); origin=[(bounds[2*i]+bounds[2*i+1])/2 for i in range(3)]
    origin[idx]=bounds[2*idx]+fraction*(bounds[2*idx+1]-bounds[2*idx])
    normal=[0.,0.,0.];normal[idx]=1.
    plane.SetOrigin(*origin);plane.SetNormal(*normal)
    cut=vtk.vtkCutter();cut.SetCutFunction(plane);cut.SetInputData(image);cut.Update()
    sliced=cut.GetOutput()
    if sliced.GetNumberOfPoints():
        w=vtk.vtkXMLPolyDataWriter();w.SetFileName(str(out/"slice.vtp"));w.SetInputData(sliced);w.Write()
        if contour is not None:
            c=vtk.vtkContourFilter();c.SetInputData(sliced);c.SetValue(0,contour);c.Update()
            if c.GetOutput().GetNumberOfPoints():
                w=vtk.vtkXMLPolyDataWriter();w.SetFileName(str(out/"contour.vtp"));w.SetInputData(c.GetOutput());w.Write()
    return {"slice_value": float(np.mean(cube["values"][tuple(counts[i]//2 if i==idx else slice(None) for i in range(3))])),
            "slice_location_A": origin[idx]}


def summarize(path):
    if Path(path).suffix.lower() == ".cif":
        m=parse_cif(path);a=expanded_atoms(m)
        return {"kind":"cif","source_sha256":m["source_sha256"],"source_id":m["source_id"],
                "formula":m["formula"],"space_group":m["space_group"],
                "space_group_number":m["space_group_number"],"site_count":len(m["sites"]),
                "expanded_count":len(a),"operator_count":len(m["operators"]),
                "cell":m["cell"],"citation":m["citation"],"doi":m["doi"]}
    m=parse_cube(path)
    return {"kind":"cube","source_sha256":m["source_sha256"],"atom_count":len(m["atoms"]),
            "dimensions":m["counts"],"range":m["range"],"field_unit":m["field_unit"],
            "description":m["description"],"generator":m["generator"]}


def sample_cube(path, xyz):
    import numpy as np
    m=parse_cube(path)
    axes=np.asarray(m["axes"],dtype=float).T
    ijk=np.linalg.solve(axes,np.asarray(xyz,dtype=float)-np.asarray(m["origin"]))
    if np.any(ijk<0) or np.any(ijk>np.asarray(m["counts"])-1):
        return {"inside":False,"cartesian_A":list(xyz),"field_unit":m["field_unit"]}
    base=np.floor(ijk).astype(int)
    upper=np.minimum(base+1,np.asarray(m["counts"])-1)
    weights=ijk-base
    value=0.
    for dx in (0,1):
        for dy in (0,1):
            for dz in (0,1):
                picks=[dx,dy,dz]
                indices=[upper[i] if picks[i] else base[i] for i in range(3)]
                factor=math.prod(weights[i] if picks[i] else 1-weights[i] for i in range(3))
                value+=factor*m["values"][tuple(indices)]
    return {"inside":True,"cartesian_A":list(xyz),"fractional_grid_index":ijk.tolist(),
            "value":float(value),"field_unit":m["field_unit"]}


def render(path,out,repeats=1,axis="z",fraction=.5,contour=None):
    out=Path(out);out.mkdir(parents=True,exist_ok=True)
    if Path(path).suffix.lower()==".cif":
        m=parse_cif(path);atoms=expanded_atoms(m,repeats)
        bonds=write_structure(out,atoms,m["vectors"],repeats)
        result={**summarize(path),"display_count":len(atoms),"bond_count":bonds,"atoms":atoms}
    else:
        m=parse_cube(path);atoms=m["atoms"]
        bonds=write_structure(out,atoms)
        density=write_density(out,m,axis,fraction,contour)
        result={**summarize(path),"display_count":len(atoms),"bond_count":bonds,
                "atoms":atoms,**density}
    (out/"representation.json").write_text(json.dumps(result,indent=2)+"\n")
    return result


def main():
    p=argparse.ArgumentParser();p.add_argument("action",choices=("inspect","render","sample"))
    p.add_argument("source",type=Path);p.add_argument("--out",type=Path)
    p.add_argument("--supercell",type=int,default=1);p.add_argument("--slice-axis",default="z")
    p.add_argument("--slice-fraction",type=float,default=.5);p.add_argument("--contour",type=float)
    p.add_argument("--xyz",type=float,nargs=3)
    p.add_argument("--tcl",action="store_true")
    args=p.parse_args()
    if args.action=="inspect": result=summarize(args.source)
    elif args.action=="sample":
        if args.xyz is None: p.error("sample requires --xyz x y z")
        result=sample_cube(args.source,args.xyz)
    else: result=render(args.source,args.out,args.supercell,args.slice_axis,args.slice_fraction,args.contour)
    if args.tcl:
        def encoded(value):
            if isinstance(value,(list,dict)): value=json.dumps(value,ensure_ascii=False)
            return base64.b64encode(str(value).encode("utf-8")).decode("ascii")
        print("GXCRYSTAL1")
        atoms=result.pop("atoms",[])
        for key,value in result.items(): print("M\t"+encoded(key)+"\t"+encoded(value))
        for index,atom in enumerate(atoms):
            for key in ("label","element","occupancy","fractional","cartesian","operator","cell_index"):
                print("A\t"+str(index)+"\t"+encoded(key)+"\t"+encoded(atom.get(key,"")))
        print("OK")
    else:
        print(json.dumps(result,ensure_ascii=False))


if __name__=="__main__": main()
