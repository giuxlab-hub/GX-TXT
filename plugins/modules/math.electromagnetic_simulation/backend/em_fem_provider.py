"""Trusted Scientific Execution provider; science remains in native C++.

The durable CORE driver owns admission, subprocesses, resource budgets and
scratch/output lifetime. tkinter.Tcl is only the existing Tcl/native ABI loader;
no Tk window or second scheduler is created. GPL-3.0-or-later.
"""
from pathlib import Path
import shutil
import hashlib
import tkinter

_LIMIT = 64 * 1024 * 1024


def _dict(tcl, value):
    values = tcl.splitlist(str(value))
    if len(values) % 2:
        raise ValueError("Native EM result is not a dictionary")
    return dict(zip(values[::2], values[1::2]))


def run(context):
    native = Path(__file__).resolve().parents[1] / "native" / "bin" / "emfem.so"
    tcl = tkinter.Tcl()
    tcl.call("load", str(native), "Emfem")
    parameters = tuple(item for pair in context.parameters.items() for item in pair)
    prepared = _dict(tcl, tcl.call("::GX::EMNative::core", "prepare", parameters))
    model = prepared["model"]
    for name, value in _dict(tcl, prepared["inputs"]).items():
        if name not in {"model.geo", "model.pro"}:
            raise ValueError("Unexpected native model input role")
        (context.scratch / name).write_text(value, encoding="utf-8")
    versions = {}
    for tool in ("gmsh", "getdp"):
        receipt = context.run(tool, ["-version"])
        versions[tool] = receipt["stdout"].strip()[:250]
        if not versions[tool] or receipt["truncated"]:
            raise ValueError("Solver version receipt is unavailable or truncated")
    context.run("gmsh", ["model.geo", "-2", "-format", "msh2", "-o", "model.msh", "-nopopup", "-v", "3"])
    solve = context.run("getdp", ["model.pro", "-msh", "model.msh", "-solve", prepared["solve"]])
    context.run("getdp", ["model.pro", "-msh", "model.msh", "-pos", prepared["post"]])
    magnetic = context.parameters["kind"] == "magnetostatic_2d"
    names = {"mesh": "model.msh", "scalar": "Az.pos" if magnetic else "V.pos", "vector": "B.pos" if magnetic else "E.pos"}
    if magnetic:
        names["auxiliary"] = "H.pos"
    files = {}
    for role, name in names.items():
        path = context.scratch / name
        if path.is_symlink() or not path.is_file() or path.stat().st_size > _LIMIT:
            raise ValueError("Missing or oversized approved native solver output")
        files[role] = path.read_text(encoding="utf-8", errors="strict")
    files["solver_log"] = solve["stdout"]
    result = tcl.call("::GX::EMNative::core", "parse", model, tuple(item for pair in files.items() for item in pair))
    result = tcl.call("dict", "replace", result, "schema", "GXTXT_EM_FEM_RESULT_v1", "model", model,
                      "solver_versions", tuple(item for pair in versions.items() for item in pair),
                      "native_sha256", hashlib.sha256(native.read_bytes()).hexdigest())
    parsed = _dict(tcl, result)
    receipt = _dict(tcl, parsed["receipt"])
    if float(receipt["independent_relative_weak_residual"]) > 1e-7:
        raise ValueError("Independent FEM weak residual exceeds declared 1e-7 criterion")
    (context.output / "typed_result.tcldict").write_text(str(result), encoding="utf-8")
    context.publish_output("typed_result.tcldict", "typed_result", "GXTXT_EM_FEM_RESULT_v1")
    for name in ["model.geo", "model.pro", *names.values()]:
        shutil.copyfile(context.scratch / name, context.output / name)
        context.publish_output(name, {"model.msh": "mesh", "model.geo": "source_geometry", "model.pro": "source_formulation", names["scalar"]: "scalar_field", names["vector"]: "vector_field", "H.pos": "auxiliary_field"}[name], Path(name).suffix.lstrip("."))
    (context.output / "solver_receipt.txt").write_text(solve["stdout"], encoding="utf-8")
    context.publish_output("solver_receipt.txt", "solver_log", "text")
    context.summary({"validation": "native_mesh_field_and_independent_residual_checked", "problem": context.parameters["kind"], "field_association": receipt["field_association"],
                     "mesh_nodes": int(receipt["mesh_nodes"]), "mesh_triangles": int(receipt["mesh_triangles"]),
                     "independent_relative_weak_residual": float(receipt["independent_relative_weak_residual"]),
                     "solver_residual_absolute": float(receipt["solver_residual_absolute"]), "solver_versions": versions})
