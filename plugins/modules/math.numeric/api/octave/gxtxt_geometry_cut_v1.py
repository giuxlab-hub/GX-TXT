#!/usr/bin/env python3
"""Provider-owned VTK cutting backend for public NUMERIC_API geometry actions."""
# SPDX-License-Identifier: GPL-3.0-or-later
import hashlib
import json
import math
import pathlib
import shutil
import subprocess
import sys
import tempfile

import vtk


READERS = {
    ".stl": vtk.vtkSTLReader,
    ".obj": vtk.vtkOBJReader,
    ".vtp": vtk.vtkXMLPolyDataReader,
    ".vtu": vtk.vtkXMLUnstructuredGridReader,
    ".vti": vtk.vtkXMLImageDataReader,
}


def read_source(path, fmt):
    suffix = "." + (fmt or path.suffix.lstrip(".")).lower().lstrip(".")
    if suffix in (".step", ".stp"):
        gmsh = shutil.which("gmsh")
        if not gmsh:
            raise ValueError("STEP section requires the Gmsh/OpenCASCADE tessellation backend")
        with tempfile.TemporaryDirectory(prefix="gxtxt-step-section-") as temporary:
            stl = pathlib.Path(temporary) / "surface.stl"
            result = subprocess.run(
                [gmsh, str(path), "-2", "-format", "stl", "-o", str(stl), "-nopopup"],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=120,
            )
            if result.returncode or not stl.is_file() or stl.stat().st_size < 100:
                raise ValueError("STEP tessellation failed or produced no surface")
            reader = vtk.vtkSTLReader()
            reader.SetFileName(str(stl))
            reader.Update()
            data = vtk.vtkPolyData()
            data.DeepCopy(reader.GetOutput())
            if data.GetNumberOfPoints() == 0:
                raise ValueError("STEP tessellation produced no vertices")
            return data
    if suffix not in READERS:
        raise ValueError(f"VTK section backend does not support {suffix} payloads")
    reader = READERS[suffix]()
    reader.SetFileName(str(path))
    reader.Update()
    data = reader.GetOutput()
    if data is None or data.GetNumberOfPoints() == 0:
        raise ValueError("geometry payload contains no points")
    return data


def main(request_path, result_path):
    request = json.loads(pathlib.Path(request_path).read_text(encoding="utf-8"))
    path = pathlib.Path(request["path"]).resolve(strict=True)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    expected = request.get("sha256", "").lower()
    if expected and expected != digest:
        raise ValueError("geometry payload SHA-256 differs from Dataset identity")
    data = read_source(path, request.get("format", ""))
    action = request["action"]
    if action in ("mesh_smooth", "mesh_remesh", "mesh_boolean"):
        source = vtk.vtkPolyData()
        if isinstance(data, vtk.vtkPolyData):
            source.DeepCopy(data)
        else:
            geometry = vtk.vtkGeometryFilter()
            geometry.SetInputData(data)
            geometry.Update()
            source.DeepCopy(geometry.GetOutput())
        triangulate = vtk.vtkTriangleFilter()
        triangulate.SetInputData(source)
        triangulate.Update()
        source.DeepCopy(triangulate.GetOutput())
        if action == "mesh_smooth":
            iterations = int(request.get("iterations", 20))
            if not 1 <= iterations <= 100:
                raise ValueError("mesh smoothing iterations must be 1..100")
            process = vtk.vtkWindowedSincPolyDataFilter()
            process.SetInputData(source)
            process.SetNumberOfIterations(iterations)
            process.SetPassBand(0.1)
            process.BoundarySmoothingOff()
            process.Update()
        elif action == "mesh_remesh":
            iterations = int(request.get("iterations", 1))
            if not 1 <= iterations <= 4:
                raise ValueError("subdivision iterations must be 1..4")
            process = vtk.vtkLoopSubdivisionFilter()
            process.SetInputData(source)
            process.SetNumberOfSubdivisions(iterations)
            process.Update()
        else:
            second_path = pathlib.Path(request["second_path"]).resolve(strict=True)
            second = read_source(second_path, "")
            if not isinstance(second, vtk.vtkPolyData):
                raise ValueError("mesh boolean requires a surface mesh second operand")
            second_triangles = vtk.vtkTriangleFilter()
            second_triangles.SetInputData(second)
            second_triangles.Update()
            process = vtk.vtkBooleanOperationPolyDataFilter()
            operation = request.get("method", "union")
            if operation == "union":
                process.SetOperationToUnion()
            elif operation == "intersection":
                process.SetOperationToIntersection()
            elif operation == "difference":
                process.SetOperationToDifference()
            else:
                raise ValueError("mesh boolean method must be union, intersection or difference")
            process.SetInputData(0, source)
            process.SetInputData(1, second_triangles.GetOutput())
            process.Update()
        result_mesh = process.GetOutput()
        if result_mesh is None or result_mesh.GetNumberOfPoints() == 0:
            raise ValueError("mesh processing produced no surface")
        output_path = pathlib.Path(request["output_path"]).resolve()
        if output_path.suffix.lower() != ".vtp" or output_path.exists() or not output_path.parent.is_dir():
            raise ValueError("mesh processing output_path must be a new .vtp file in an existing directory")
        writer = vtk.vtkXMLPolyDataWriter()
        writer.SetFileName(str(output_path))
        writer.SetInputData(result_mesh)
        if writer.Write() != 1:
            raise ValueError("mesh processing output write failed")
        result = {
            "path": str(output_path),
            "sha256": hashlib.sha256(output_path.read_bytes()).hexdigest(),
            "source_sha256": digest,
            "points": result_mesh.GetNumberOfPoints(),
            "cells": result_mesh.GetNumberOfCells(),
            "status": "processed",
        }
        pathlib.Path(result_path).write_text(json.dumps(result, allow_nan=False), encoding="utf-8")
        return
    plane = vtk.vtkPlane()
    plane.SetOrigin(*request["origin"])
    plane.SetNormal(*request["normal"])
    cutter = vtk.vtkCutter()
    cutter.SetCutFunction(plane)
    cutter.SetInputData(data)
    cutter.Update()
    cut = cutter.GetOutput()
    if action == "volume_slice":
        if not isinstance(data, (vtk.vtkImageData, vtk.vtkUniformGrid, vtk.vtkStructuredGrid)):
            raise ValueError("volume_slice requires an actual scalar grid")
        scalars = cut.GetPointData().GetScalars()
        if scalars is None and cut.GetPointData().GetNumberOfArrays():
            scalars = cut.GetPointData().GetArray(0)
        if scalars is None:
            raise ValueError("volume has no point scalar field to slice")
        points = [list(cut.GetPoint(i)) for i in range(cut.GetNumberOfPoints())]
        values = [float(scalars.GetTuple1(i)) for i in range(len(points))]
        if not all(math.isfinite(v) for v in values):
            raise ValueError("slice contains nonfinite scalar samples")
        result = {
            "points": points,
            "scalar": values,
            "field_name": scalars.GetName() or "scalar",
            "status": "empty" if not points else "sliced",
            "sha256": digest,
        }
    elif action == "mesh_section":
        if isinstance(data, vtk.vtkImageData):
            raise ValueError("mesh_section requires a surface or mesh; use volume_slice for VTI")
        strip = vtk.vtkStripper()
        strip.SetInputData(cut)
        strip.JoinContiguousSegmentsOn()
        strip.Update()
        lines = strip.GetOutput()
        points, segment_id, source_cell_id = [], [], []
        for index in range(lines.GetNumberOfCells()):
            cell = lines.GetCell(index)
            count = cell.GetNumberOfPoints()
            if count < 2:
                continue
            for j in range(count):
                point = lines.GetPoint(cell.GetPointId(j))
                points.append(list(point))
                segment_id.append(index + 1)
                source_cell_id.append(-1)
        result = {
            "points": points,
            "segment_id": segment_id,
            "source_cell_id": source_cell_id,
            "status": "empty" if not points else "intersected",
            "sha256": digest,
        }
    else:
        raise ValueError("unsupported geometry action")
    pathlib.Path(result_path).write_text(json.dumps(result, allow_nan=False), encoding="utf-8")


if __name__ == "__main__":
    try:
        main(sys.argv[1], sys.argv[2])
    except Exception as exc:
        pathlib.Path(sys.argv[2]).write_text(json.dumps({"error": str(exc)}), encoding="utf-8")
