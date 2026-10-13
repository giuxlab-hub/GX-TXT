#!/usr/bin/env python3
"""Persistent HDF5 writer for GX-TXT Dataset Publication API v2.

Numeric standard_octave blocks use one typed Base64 payload and are decoded
once with numpy.frombuffer. The protocol remains private to CORE.
"""
from __future__ import annotations
import argparse, base64, binascii, math, os, sys
from typing import Any

def b64(value: Any) -> str:
    return base64.b64encode(str(value).encode("utf-8")).decode("ascii")

def unb64(value: str) -> str:
    return base64.b64decode(value.encode("ascii"), validate=True).decode("utf-8")

def split_ints(value: str) -> list[int]:
    return [int(item) for item in value.split(";") if item != ""]

def split_shape(value: str, allow_unlimited: bool = False) -> tuple[int | None, ...]:
    out: list[int | None] = []
    for item in value.split(";") if value else []:
        if allow_unlimited and item == "*": out.append(None)
        else:
            number = int(item)
            if number < 0: raise ValueError("Shape entries must be non-negative")
            out.append(number)
    return tuple(out)

def parse_values(np: Any, dtype: Any, encoded: str, expected: int) -> Any:
    text = unb64(encoded); values = [] if text == "" else text.split("\x1f")
    if len(values) != expected:
        raise ValueError(f"Value count mismatch: expected {expected}, received {len(values)}")
    try:
        if dtype.kind in {"S", "U", "O"}: return np.asarray(values, dtype=dtype)
        if dtype.kind == "b":
            return np.asarray([{"0":False,"1":True,"false":False,"true":True}[v.lower()] for v in values], dtype=dtype)
        return np.asarray(values, dtype=dtype)
    except Exception as exc:
        raise ValueError(f"Values are incompatible with dtype {dtype}: {exc}") from exc

def binary_values(np: Any, target_dtype: Any, source_dtype_text: str, endian: str,
                  shape_text: str, encoded: str, expected: int) -> Any:
    supported={"float32","float64","int8","int16","int32","int64","uint8","uint16","uint32","uint64","bool"}
    if source_dtype_text not in supported: raise ValueError(f"Unsupported binary transport dtype {source_dtype_text}")
    if endian not in {"little","big"}: raise ValueError(f"Unsupported binary transport endian {endian}")
    shape=split_shape(shape_text); count=math.prod(shape) if shape else 1
    if count != expected: raise ValueError(f"Binary block shape mismatch: expected {expected} elements, received {count}")
    try: raw=base64.b64decode(encoded.encode("ascii"),validate=True)
    except (binascii.Error,ValueError) as exc: raise ValueError(f"Invalid Base64 binary block: {exc}") from exc
    source_dtype=np.dtype("bool" if source_dtype_text=="bool" else source_dtype_text)
    if source_dtype.itemsize>1: source_dtype=source_dtype.newbyteorder("<" if endian=="little" else ">")
    expected_bytes=count*source_dtype.itemsize
    if len(raw)!=expected_bytes: raise ValueError(f"Binary block byte length mismatch: expected {expected_bytes}, received {len(raw)}")
    source=np.frombuffer(raw,dtype=source_dtype,count=count)
    if target_dtype.kind in {"S","U","O"}: raise ValueError("Binary numeric block is incompatible with string dtype")
    native=source.astype(source.dtype.newbyteorder("="),copy=False)
    if target_dtype.kind=="b":
        if native.dtype.kind!="b" and not np.all((native==0)|(native==1)): raise ValueError("Values are incompatible with dtype bool")
    elif target_dtype.kind in {"i","u"}:
        if native.dtype.kind=="f" and (not np.all(np.isfinite(native)) or not np.all(native==np.trunc(native))):
            raise ValueError(f"Values are incompatible with dtype {target_dtype}")
        info=np.iinfo(target_dtype)
        if native.size and (np.any(native<info.min) or np.any(native>info.max)): raise ValueError(f"Values are outside dtype {target_dtype}")
    try: return native.astype(target_dtype,copy=False)
    except Exception as exc: raise ValueError(f"Values are incompatible with dtype {target_dtype}: {exc}") from exc

class Writer:
    def __init__(self,path:str)->None:
        try:
            import h5py; import numpy as np
        except Exception as exc: raise RuntimeError(f"HDF5 writer dependency unavailable: {exc}") from exc
        self.h5py=h5py; self.np=np; self.path=path; self.file=h5py.File(path,"w")
        self.elements_written=0; self.max_request_elements=0; self.append_calls=0; self.hyperslab_elements_written=0
        self.binary_blocks=0; self.binary_bytes=0; self.created:dict[str,str]={}
    def emit(self,*parts:Any)->None: print("\t".join(str(part) for part in parts),flush=True)
    def record(self,count:int,hyperslab:bool=False)->None:
        self.elements_written+=count; self.max_request_elements=max(self.max_request_elements,count)
        if hyperslab:self.hyperslab_elements_written+=count
    def create(self,parts:list[str])->None:
        if len(parts)!=16: raise ValueError("Invalid CREATE request")
        (locator,dtype_text,shape_text,maxshape_text,chunks_text,variable_id,name,unit,semantic_role,dimension_ids,coordinate_role,axis_kind,axis_origin,axis_step,group_id)=[unb64(item) for item in parts[1:]]
        if variable_id in self.created: raise ValueError(f"Duplicate variable_id {variable_id}")
        shape=split_shape(shape_text);maxshape=split_shape(maxshape_text,True)
        if len(shape)!=len(maxshape): raise ValueError("Shape/maxshape rank mismatch")
        chunks=split_shape(chunks_text) if chunks_text else None
        if chunks and len(chunks)!=len(shape): raise ValueError("Chunk rank mismatch")
        parent=os.path.dirname(locator)
        if parent and parent!="/":self.file.require_group(parent)
        dtype=self.h5py.string_dtype("utf-8") if dtype_text=="string" else self.np.dtype(dtype_text)
        ds=self.file.create_dataset(locator,shape=shape,maxshape=maxshape,chunks=chunks,dtype=dtype)
        attrs={"gxtxt_variable_id":variable_id,"gxtxt_name":name,"gxtxt_unit":unit,"gxtxt_semantic_role":semantic_role,"gxtxt_dimension_ids":dimension_ids,"gxtxt_coordinate_role":coordinate_role,"gxtxt_axis_kind":axis_kind,"gxtxt_axis_origin":axis_origin,"gxtxt_axis_step":axis_step,"gxtxt_group_id":group_id}
        for key,value in attrs.items():ds.attrs[key]=value
        self.created[variable_id]=locator;self.emit("OK","CREATED")
    def dataset(self,locator:str)->Any:
        if locator not in self.file or not isinstance(self.file[locator],self.h5py.Dataset):raise ValueError("Unknown writer variable")
        return self.file[locator]
    def decode_block(self,parts:list[str],start:int,ds:Any,expected:int)->Any:
        source_dtype,endian,shape_text,encoded=parts[start:start+4]
        values=binary_values(self.np,ds.dtype,source_dtype,endian,shape_text,encoded,expected)
        self.binary_blocks+=1;self.binary_bytes+=len(base64.b64decode(encoded));return values
    def write(self,parts:list[str],binary:bool=False)->None:
        locator=unb64(parts[1]);shape=split_shape(unb64(parts[2]));ds=self.dataset(locator)
        if tuple(ds.shape)!=shape:raise ValueError(f"Complete write shape mismatch: expected {ds.shape}, received {shape}")
        count=math.prod(shape) if shape else 1;values=self.decode_block(parts,3,ds,count) if binary else parse_values(self.np,ds.dtype,parts[3],count)
        ds[...]=values.reshape(shape);self.record(count);self.emit("OK","WRITTEN",count)
    def range_write(self,parts:list[str],binary:bool=False)->None:
        locator=unb64(parts[1]);start=int(parts[2]);ds=self.dataset(locator)
        if ds.ndim!=1:raise ValueError("Range write requires a rank-1 variable")
        if binary:
            block_shape=split_shape(parts[5]);count=math.prod(block_shape) if block_shape else 1;values=self.decode_block(parts,3,ds,count)
        else:
            text=unb64(parts[3]);count=0 if text=="" else len(text.split("\x1f"));values=parse_values(self.np,ds.dtype,parts[3],count)
        if start<0 or start+count>ds.shape[0]:raise ValueError("Range write is outside the variable")
        ds[start:start+count]=values;self.record(count);self.emit("OK","WRITTEN",count)
    def append(self,parts:list[str],binary:bool=False)->None:
        locator=unb64(parts[1]);axis=int(parts[2]);block_shape=split_shape(unb64(parts[3]));ds=self.dataset(locator)
        if axis<0 or axis>=ds.ndim or ds.maxshape[axis] is not None:raise ValueError("Append dimension is not extendible")
        if len(block_shape)!=ds.ndim:raise ValueError("Append block rank mismatch")
        for idx,size in enumerate(block_shape):
            if idx!=axis and size!=ds.shape[idx]:raise ValueError("Append block shape mismatch")
        count=math.prod(block_shape) if block_shape else 1;values=self.decode_block(parts,4,ds,count) if binary else parse_values(self.np,ds.dtype,parts[4],count)
        old=ds.shape[axis];shape=list(ds.shape);shape[axis]+=block_shape[axis];ds.resize(tuple(shape));target=[slice(None)]*ds.ndim;target[axis]=slice(old,shape[axis]);ds[tuple(target)]=values.reshape(block_shape)
        self.append_calls+=1;self.record(count);self.emit("OK","APPENDED",block_shape[axis],count,";".join(str(x) for x in ds.shape))
    def hyperslab(self,parts:list[str],binary:bool=False)->None:
        locator=unb64(parts[1]);starts=split_ints(unb64(parts[2]));counts=split_ints(unb64(parts[3]));ds=self.dataset(locator)
        if len(starts)!=ds.ndim or len(counts)!=ds.ndim:raise ValueError("Hyperslab rank mismatch")
        slices=[]
        for size,start,count in zip(ds.shape,starts,counts):
            if start<0 or count<0 or start+count>size:raise ValueError("Hyperslab is outside the variable")
            slices.append(slice(start,start+count))
        count=math.prod(counts) if counts else 1;values=self.decode_block(parts,4,ds,count) if binary else parse_values(self.np,ds.dtype,parts[4],count)
        ds[tuple(slices)]=values.reshape(tuple(counts));self.record(count,True);self.emit("OK","WRITTEN",count)
    def stats(self)->None:self.emit("OK","STATS",os.getpid(),self.elements_written,self.max_request_elements,self.append_calls,self.hyperslab_elements_written,self.binary_blocks,self.binary_bytes)
    def validate(self)->None:
        self.file.flush()
        for variable_id,locator in self.created.items():
            if locator not in self.file:raise ValueError(f"Missing HDF5 object for {variable_id}")
        self.emit("OK","VALID",len(self.created),os.path.getsize(self.path))
    def close(self)->None:self.file.flush();self.file.close()

def main()->int:
    parser=argparse.ArgumentParser(add_help=False);parser.add_argument("--file",required=True);args=parser.parse_args()
    try:writer=Writer(args.file)
    except Exception as exc:print(f"ERROR\t{b64(exc)}",flush=True);return 2
    writer.emit("OK","READY",os.getpid())
    try:
        for raw in sys.stdin:
            parts=raw.rstrip("\n").split("\t");command=parts[0].upper()
            try:
                if command=="CREATE":writer.create(parts)
                elif command=="WRITE":writer.write(parts)
                elif command=="BWRITE":writer.write(parts,True)
                elif command=="RANGE":writer.range_write(parts)
                elif command=="BRANGE":writer.range_write(parts,True)
                elif command=="APPEND":writer.append(parts)
                elif command=="BAPPEND":writer.append(parts,True)
                elif command=="HYPER":writer.hyperslab(parts)
                elif command=="BHYPER":writer.hyperslab(parts,True)
                elif command=="FLUSH":writer.file.flush();writer.emit("OK","FLUSHED")
                elif command=="VALIDATE":writer.validate()
                elif command=="STATS":writer.stats()
                elif command=="CLOSE":writer.emit("OK","CLOSED");break
                else:raise ValueError("Unknown writer command")
            except Exception as exc:writer.emit("ERROR",b64(exc))
    finally:writer.close()
    return 0
if __name__=="__main__":raise SystemExit(main())
