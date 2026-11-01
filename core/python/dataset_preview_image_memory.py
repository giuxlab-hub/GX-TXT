#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Bounded RAM-only image conversion for the existing Dataset Preview owner."""
import base64, hashlib, os, subprocess, sys, tkinter
from gxtxt_job_supervisor import request_process_group, tcl_result

def convert(request):
    maximum=int(request['max_bytes']); width=int(request['width']); height=int(request['height'])
    if not (1<=maximum<=67108864 and 1<=width<=4096 and 1<=height<=4096):
        raise ValueError('Invalid memory preview limits')
    encoded=request['data_base64']
    if len(encoded)>4*((maximum+2)//3): raise ValueError('Image exceeds preview byte limit')
    data=base64.b64decode(encoded,validate=True)
    if not data or len(data)>maximum: raise ValueError('Image exceeds preview byte limit')
    if data.startswith(b'\xff\xd8\xff'): coder='jpeg:-'
    elif data.startswith(b'\x89PNG\r\n\x1a\n'): coder='png:-'
    elif data.startswith((b'GIF87a',b'GIF89a')): coder='gif:-[0]'
    else: raise ValueError('Unsupported memory image format')
    # Fixed raster coders only: no filenames, delegates, URLs, SVG or response paths.
    # Disk/map caches are disabled in both probes; all pipe bytes remain in RAM.
    limits=['-limit','thread','1','-limit','memory','128MiB','-limit','map','0','-limit','disk','0','-limit','time','6']
    env=dict(os.environ,MAGICK_TEMPORARY_PATH='/nonexistent/gxtxt-memory-preview')
    def run(args, bound):
        process=subprocess.Popen([request['tool'],*limits,*args],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,env=env)
        try: result,_=process.communicate(data,timeout=8)
        except subprocess.TimeoutExpired:
            process.kill();process.communicate();raise ValueError('Memory image preview timed out') from None
        if process.returncode or len(result)>bound: raise ValueError('Memory image preview failed within resource limits')
        return result
    dimensions=run(['-ping',coder,'-format','%w %h','info:'],128).decode('ascii').split()
    if len(dimensions)!=2: raise ValueError('Invalid image dimensions')
    original_width,original_height=map(int,dimensions)
    if min(original_width,original_height)<1 or original_width*original_height>40000000:
        raise ValueError('Image exceeds preview pixel limit')
    png=run([coder,'-thumbnail',f'{width}x{height}>','-strip','PNG32:-'],width*height*5+65536)
    if not png.startswith(b'\x89PNG\r\n\x1a\n'): raise ValueError('Invalid image preview result')
    w=int.from_bytes(png[16:20],'big');h=int.from_bytes(png[20:24],'big')
    if not (1<=w<=width and 1<=h<=height): raise ValueError('Image preview exceeds display dimensions')
    return dict(data_base64=base64.b64encode(png).decode(),media_type='image/png',original_sha256=hashlib.sha256(data).hexdigest(),preview_sha256=hashlib.sha256(png).hexdigest(),width=w,height=h,original_width=original_width,original_height=original_height)

def main():
    request_process_group()
    try:
        wire=sys.stdin.buffer.read(90000001)
        if len(wire)>90000000: raise ValueError('Image request exceeds memory limit')
        tcl=tkinter.Tcl();items=tcl.splitlist(wire.decode('utf-8'))
        if len(items)%2: raise ValueError('Malformed image request')
        result=dict(ok=1,result=convert(dict(zip(items[::2],items[1::2]))))
    except Exception:
        # Never include vendor content, command text, input bytes or tool diagnostics.
        result=dict(ok=0,error='Image preview unavailable: unsupported data or resource limit.')
    sys.stdout.write(tcl_result(result))
if __name__=='__main__': main()
