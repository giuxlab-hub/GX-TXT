"""Trusted local transport: descriptor-relative, no-follow scientific source access."""
# SPDX-License-Identifier: GPL-3.0-or-later
import base64
import codecs
import hashlib
import os
from pathlib import Path
import stat
import sys
from gxtxt_scientific_execution import tvalue


def open_scoped(root,relative):
    parts=Path(relative).parts
    if Path(relative).is_absolute() or any(p in ('.','..') for p in parts):raise ValueError('Invalid scoped source entry')
    # Every path component is opened relative to an already validated descriptor.
    path=Path(root)
    fd=os.open('/',os.O_RDONLY|os.O_DIRECTORY)
    try:
        for part in path.parts[1:]:
            new=os.open(part,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW,dir_fd=fd);os.close(fd);fd=new
        for index,part in enumerate(parts):
            flags=os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK
            if index<len(parts)-1:flags|=os.O_DIRECTORY
            new=os.open(part,flags,dir_fd=fd);os.close(fd);fd=new
        return fd
    except BaseException:
        os.close(fd);raise


def signature(info):return [info.st_dev,info.st_ino,info.st_size,info.st_mtime_ns,info.st_ctime_ns]
def operate(root,operation,relative,offset,count,expected,destination=""):
    fd=open_scoped(root,relative)
    try:
        before=os.fstat(fd)
        if operation=='list':
            if not stat.S_ISDIR(before.st_mode):raise ValueError('Source scope entry is not a directory')
            names=[]
            with os.scandir(fd) as listing:
                for item in listing:
                    names.append(item.name)
                    if len(names)>10000:raise ValueError('Directory exceeds the 10000-entry metadata budget; authorize a narrower scope')
            names.sort()
            result=[]
            for name in names[offset:offset+count]:
                info=os.stat(name,dir_fd=fd,follow_symlinks=False)
                kind='file' if stat.S_ISREG(info.st_mode) else ('directory' if stat.S_ISDIR(info.st_mode) else 'unsupported')
                result.append({'name':name,'relative':str(Path(relative)/name),'kind':kind,'size_bytes':info.st_size,'identity':signature(info)})
            return {'entries':result,'next_offset':offset+len(result),'total_entries':len(names),'content_authorization':False}
        if not stat.S_ISREG(before.st_mode) or before.st_nlink!=1:raise ValueError('Scientific source must be a single-link regular file')
        if operation=='inspect':return {'identity':signature(before),'size_bytes':before.st_size}
        digest=hashlib.sha256()
        decoder=codecs.getincrementaldecoder('utf-8')('strict') if operation=='text' else None
        target=None
        if operation=='copy':
            if before.st_size>67108864:raise ValueError('Local copy exceeds the 64 MiB managed preparation budget; use verified reference')
            target=os.open(destination,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600)
        try:
            while True:
                chunk=os.read(fd,1048576)
                if not chunk:break
                digest.update(chunk)
                if decoder is not None:decoder.decode(chunk)
                if target is not None:
                    view=memoryview(chunk)
                    while view:view=view[os.write(target,view):]
            if decoder is not None:decoder.decode(b'',final=True)
            if target is not None:os.fsync(target)
        finally:
            if target is not None:os.close(target)
        sha=digest.hexdigest()
        if expected and sha!=expected:raise ValueError('Scientific source SHA changed')
        os.lseek(fd,offset,os.SEEK_SET);raw=os.read(fd,count)
        if signature(os.fstat(fd))!=signature(before):raise ValueError('Scientific source changed during verified read')
        return {'identity':signature(before),'sha256':sha,'size_bytes':before.st_size,'bytes_base64':base64.b64encode(raw).decode(),'next_offset':offset+len(raw)}
    finally:os.close(fd)

if __name__=='__main__':
    try:
        root,operation,relative,offset,count,expected=sys.argv[1:7]
        destination=sys.argv[7] if len(sys.argv)>7 else ""
        offset=int(offset);count=int(count)
        if offset<0 or count<1 or count>(500 if operation=='list' else 1048576):raise ValueError('Source request exceeds bounded page')
        print(tvalue({'ok':True,'result':operate(root,operation,relative,offset,count,expected,destination)}))
    except BaseException as exc:
        print(tvalue({'ok':False,'error':str(exc)}));sys.exit(1)
