#!/usr/bin/env python3
"""Repack an Octave HDF5 snapshot with portable chunked gzip numeric arrays."""

import argparse
from pathlib import Path

import h5py


def copy_attributes(source, target):
    for name, value in source.attrs.items():
        target.attrs[name] = value


def copy_group(source, target):
    copy_attributes(source, target)
    for name, item in source.items():
        if isinstance(item, h5py.Group):
            copy_group(item, target.create_group(name))
        elif isinstance(item, h5py.Dataset):
            options = {}
            if item.shape and item.size > 128 and item.dtype.kind in "biufc":
                options = {"chunks": True, "compression": "gzip", "compression_opts": 4, "shuffle": True}
            new = target.create_dataset(name, data=item[()], dtype=item.dtype, **options)
            copy_attributes(item, new)
        else:
            raise TypeError(f"Unsupported HDF5 object: {item.name}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    if args.destination.exists():
        parser.error("destination already exists")
    with h5py.File(args.source, "r") as source, h5py.File(args.destination, "x") as destination:
        copy_group(source, destination)
    print(f"Repacked {args.source} -> {args.destination}")


if __name__ == "__main__":
    main()
