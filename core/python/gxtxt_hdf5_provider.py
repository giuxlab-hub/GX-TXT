#!/usr/bin/env python3
"""Persistent HDF5 read worker for Canonical Dataset API v2.

The line protocol is private to CORE. Scientific consumers see stable dataset
and variable IDs through Tcl and never receive HDF5 object paths or h5py
objects. One worker keeps one HDF5 file open for the lifetime of a CORE access
handle, so chunk iteration does not start a Python process per request.
"""

from __future__ import annotations

import argparse
import base64
import math
import os
import sys
from typing import Any


def b64(value: Any) -> str:
    if value is None:
        text = ""
    elif isinstance(value, bytes):
        text = value.decode("utf-8", "replace")
    elif hasattr(value, "tolist"):
        converted = value.tolist()
        text = ";".join(str(x) for x in converted) if isinstance(converted, list) else str(converted)
    else:
        text = str(value)
    return base64.b64encode(text.encode("utf-8")).decode("ascii")


def unb64(value: str) -> str:
    return base64.b64decode(value.encode("ascii")).decode("utf-8")


def attr(obj: Any, name: str, default: str = "") -> str:
    if name not in obj.attrs:
        return default
    value = obj.attrs[name]
    if isinstance(value, bytes):
        return value.decode("utf-8", "replace")
    if hasattr(value, "tolist"):
        value = value.tolist()
    if isinstance(value, (list, tuple)):
        return ";".join(str(x) for x in value)
    return str(value)


def scalar_text(value: Any) -> str:
    if hasattr(value, "item"):
        value = value.item()
    if isinstance(value, bytes):
        return value.decode("utf-8", "replace")
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        if math.isnan(value):
            return "NaN"
        if math.isinf(value):
            return "Inf" if value > 0 else "-Inf"
        return format(value, ".17g")
    return str(value)


class Worker:
    def __init__(self, path: str) -> None:
        try:
            import h5py  # type: ignore
            import numpy as np  # type: ignore
        except Exception as exc:  # pragma: no cover - exercised by Tcl failure probe
            raise RuntimeError(f"HDF5 provider dependency unavailable: {exc}") from exc
        self.h5py = h5py
        self.np = np
        self.path = path
        self.file = h5py.File(path, "r")
        self.payload_elements_read = 0
        self.prefix_elements_scanned = 0
        self.max_request_elements = 0
        self.metadata_payload_elements = 0
        self.binary_blocks_read = 0
        self.binary_bytes_read = 0
        self.text_values_serialized = 0

    def emit(self, *parts: Any) -> None:
        print("\t".join(str(part) for part in parts), flush=True)

    def metadata(self) -> None:
        variables: list[tuple[str, Any]] = []
        groups: list[str] = []

        def visitor(name: str, obj: Any) -> None:
            locator = "/" + name if name else "/"
            if isinstance(obj, self.h5py.Dataset):
                variables.append((locator, obj))
            elif isinstance(obj, self.h5py.Group) and name:
                groups.append(locator)

        self.file.visititems(visitor)
        self.emit("OK", "META", len(variables), len(groups))
        for locator, ds in variables:
            shape = ";".join(str(x) for x in ds.shape)
            chunks = "" if ds.chunks is None else ";".join(str(x) for x in ds.chunks)
            group_id = attr(ds, "gxtxt_group_id", os.path.dirname(locator).strip("/").replace("/", "."))
            fields = [
                locator,
                str(ds.dtype),
                shape,
                chunks,
                ds.compression or "",
                attr(ds, "gxtxt_name", locator.rsplit("/", 1)[-1]),
                attr(ds, "gxtxt_unit"),
                attr(ds, "gxtxt_semantic_role"),
                attr(ds, "gxtxt_dimension_ids"),
                attr(ds, "gxtxt_coordinate_role", "data"),
                attr(ds, "gxtxt_axis_kind", "explicit"),
                attr(ds, "gxtxt_axis_origin"),
                attr(ds, "gxtxt_axis_step"),
                group_id,
                attr(ds, "gxtxt_variable_id"),
            ]
            self.emit("VAR", *(b64(field) for field in fields))
        for group in groups:
            self.emit("GROUP", b64(group))
        self.emit("END")

    def data_response(self, ds: Any, data: Any) -> None:
        arr = self.np.asarray(data)
        flat = arr.reshape(-1)
        values = "\x1f".join(scalar_text(value) for value in flat)
        count = int(flat.size)
        self.payload_elements_read += count
        self.text_values_serialized += count
        self.max_request_elements = max(self.max_request_elements, count)
        shape = ";".join(str(x) for x in arr.shape)
        self.emit("OK", "DATA", b64(str(ds.dtype)), b64(shape), count, b64(values))

    def binary_data_response(self, data: Any) -> None:
        arr = self.np.ascontiguousarray(self.np.asarray(data))
        dtype = arr.dtype
        key = (dtype.kind, dtype.itemsize)
        names = {
            ("f", 4): "float32", ("f", 8): "float64",
            ("i", 1): "int8", ("i", 2): "int16", ("i", 4): "int32", ("i", 8): "int64",
            ("u", 1): "uint8", ("u", 2): "uint16", ("u", 4): "uint32", ("u", 8): "uint64",
            ("b", 1): "bool",
        }
        if key not in names:
            raise ValueError(f"HDF5 dtype {dtype} has no typed binary read transport")
        byteorder = dtype.byteorder
        if byteorder == "=":
            endian = sys.byteorder
        elif byteorder == ">":
            endian = "big"
        else:
            endian = "little"
        raw = arr.tobytes(order="C")
        count = int(arr.size)
        self.payload_elements_read += count
        self.binary_blocks_read += 1
        self.binary_bytes_read += len(raw)
        self.max_request_elements = max(self.max_request_elements, count)
        shape = ";".join(str(x) for x in arr.shape)
        payload = base64.b64encode(raw).decode("ascii")
        self.emit("OK", "BDATA", names[key], endian, b64(shape), count, len(raw), payload)

    def binary_read(self, locator: str, start: int, count: int) -> None:
        if locator not in self.file or not isinstance(self.file[locator], self.h5py.Dataset):
            raise ValueError("Unknown provider variable")
        ds = self.file[locator]
        if ds.ndim == 0:
            if start != 0 or count not in (-1, 1):
                raise ValueError("Scalar read requires start=0 and count=1")
            self.binary_data_response(ds[()])
            return
        if ds.ndim != 1:
            raise ValueError("Range reads require a rank-1 variable; use hyperslab for multidimensional data")
        if start < 0 or start > ds.shape[0]:
            raise ValueError("Range start is outside the variable")
        stop = ds.shape[0] if count < 0 else start + count
        if stop < start or stop > ds.shape[0]:
            raise ValueError("Range count is outside the variable")
        self.binary_data_response(ds[start:stop])

    def read(self, locator: str, start: int, count: int) -> None:
        if locator not in self.file or not isinstance(self.file[locator], self.h5py.Dataset):
            raise ValueError("Unknown provider variable")
        ds = self.file[locator]
        if ds.ndim == 0:
            if start != 0 or count not in (-1, 1):
                raise ValueError("Scalar read requires start=0 and count=1")
            self.data_response(ds, ds[()])
            return
        if ds.ndim != 1:
            raise ValueError("Range reads require a rank-1 variable; use hyperslab for multidimensional data")
        if start < 0 or start > ds.shape[0]:
            raise ValueError("Range start is outside the variable")
        stop = ds.shape[0] if count < 0 else start + count
        if stop < start or stop > ds.shape[0]:
            raise ValueError("Range count is outside the variable")
        self.data_response(ds, ds[start:stop])

    def hyperslab(self, locator: str, starts: list[int], counts: list[int]) -> None:
        if locator not in self.file or not isinstance(self.file[locator], self.h5py.Dataset):
            raise ValueError("Unknown provider variable")
        ds = self.file[locator]
        if len(starts) != ds.ndim or len(counts) != ds.ndim:
            raise ValueError("Hyperslab start/count rank does not match the variable")
        slices = []
        for size, start, count in zip(ds.shape, starts, counts):
            if start < 0 or count < 0 or start + count > size:
                raise ValueError("Hyperslab is outside the variable")
            slices.append(slice(start, start + count))
        self.data_response(ds, ds[tuple(slices)])

    def binary_hyperslab(self, locator: str, starts: list[int], counts: list[int]) -> None:
        if locator not in self.file or not isinstance(self.file[locator], self.h5py.Dataset):
            raise ValueError("Unknown provider variable")
        ds = self.file[locator]
        if len(starts) != ds.ndim or len(counts) != ds.ndim:
            raise ValueError("Hyperslab start/count rank does not match the variable")
        slices = []
        for size, start, count in zip(ds.shape, starts, counts):
            if start < 0 or count < 0 or start + count > size:
                raise ValueError("Hyperslab is outside the variable")
            slices.append(slice(start, start + count))
        self.binary_data_response(ds[tuple(slices)])

    def stats(self) -> None:
        self.emit(
            "OK",
            "STATS",
            os.getpid(),
            self.metadata_payload_elements,
            self.payload_elements_read,
            self.prefix_elements_scanned,
            self.max_request_elements,
            self.binary_blocks_read,
            self.binary_bytes_read,
            self.text_values_serialized,
        )

    def close(self) -> None:
        self.file.close()


def main() -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--file", required=True)
    args = parser.parse_args()
    try:
        worker = Worker(args.file)
    except Exception as exc:
        print(f"ERROR\t{b64(exc)}", flush=True)
        return 2
    worker.emit("OK", "READY", os.getpid())
    try:
        for raw in sys.stdin:
            parts = raw.rstrip("\n").split("\t")
            command = parts[0].upper()
            try:
                if command == "META":
                    worker.metadata()
                elif command == "READ":
                    worker.read(unb64(parts[1]), int(parts[2]), int(parts[3]))
                elif command == "BREAD":
                    worker.binary_read(unb64(parts[1]), int(parts[2]), int(parts[3]))
                elif command == "HYPER":
                    starts = [int(x) for x in unb64(parts[2]).split(";") if x != ""]
                    counts = [int(x) for x in unb64(parts[3]).split(";") if x != ""]
                    worker.hyperslab(unb64(parts[1]), starts, counts)
                elif command == "BHYPER":
                    starts = [int(x) for x in unb64(parts[2]).split(";") if x != ""]
                    counts = [int(x) for x in unb64(parts[3]).split(";") if x != ""]
                    worker.binary_hyperslab(unb64(parts[1]), starts, counts)
                elif command == "STATS":
                    worker.stats()
                elif command == "CLOSE":
                    worker.emit("OK", "CLOSED")
                    break
                else:
                    raise ValueError("Unknown provider command")
            except Exception as exc:
                worker.emit("ERROR", b64(exc))
    finally:
        worker.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
