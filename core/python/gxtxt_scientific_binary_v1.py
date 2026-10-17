"""CORE bulk transport to provider-owned Octave public functions.

One worker belongs to one Script Bridge, hence one job. Provider bindings own
the function/argument mapping; this module contains no scientific algorithms.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations
import json, math, os, re, select, shutil, subprocess, tempfile, time, uuid
from pathlib import Path
import numpy as np

MAX_BYTES = 512 * 1024 * 1024
DTYPES = {name: np.dtype(name).newbyteorder('<').str for name in (
    'bool', 'int8', 'uint8', 'int16', 'uint16', 'int32', 'uint32',
    'int64', 'uint64', 'float32', 'float64', 'complex64', 'complex128')}

def shape_checked(shape, itemsize=8):
    if not isinstance(shape, (list, tuple)) or not 1 <= len(shape) <= 16:
        raise ValueError("binary shape must have 1..16 dimensions")
    if any(isinstance(x,bool) or not isinstance(x,(int,np.integer)) or x < 0 for x in shape):
        raise ValueError("binary shape requires nonnegative integer dimensions")
    count=math.prod(shape)
    if count * itemsize > MAX_BYTES: raise ValueError("binary payload exceeds 512 MiB limit")
    return count

def open_buffer(root, descriptor):
    """Return a validated owner-local descriptor FD, dtype and element count.

    The caller owns the FD. Validation does not materialize numerical values.
    """
    version = descriptor.get('version')
    if version not in (1, 2) or descriptor.get('order') != 'F' or descriptor.get('endian') != 'little':
        raise ValueError('unsupported binary descriptor version/order/endian')
    if version == 1 and descriptor.get('dtype') not in ('float32', 'float64'):
        raise ValueError('descriptor v1 supports only float32/float64')
    dtype=DTYPES.get(descriptor.get('dtype'))
    if dtype is None: raise ValueError('unsupported binary dtype')
    count=shape_checked(descriptor['shape'],np.dtype(dtype).itemsize)
    size=count*np.dtype(dtype).itemsize
    if descriptor.get('count') != count or descriptor.get('byte_count') != size: raise ValueError('binary count/byte count mismatch')
    name=descriptor.get('resource_id','')
    if not re.fullmatch(r'[a-f0-9]{32}\.bin',name): raise ValueError('invalid binary resource ID')
    path=Path(root)/name
    fd=os.open(path,os.O_RDONLY | getattr(os,'O_NOFOLLOW',0))
    try:
        import stat
        s=os.fstat(fd)
        if not stat.S_ISREG(s.st_mode) or s.st_size != size or (hasattr(os,'getuid') and s.st_uid != os.getuid()): raise ValueError('invalid binary resource owner/type/size')
    except BaseException:
        os.close(fd)
        raise
    return fd, dtype, count

def validate_buffer(root, descriptor):
    fd, _, _ = open_buffer(root, descriptor)
    os.close(fd)

def wire_descriptor(descriptor):
    """Normalize exact integral JSON dimensions emitted by Octave.

    JSON numbers such as 2e6 are integers in the array contract. Fractional,
    nonfinite, boolean and text dimensions remain invalid; no truncation.
    """
    result = dict(descriptor)
    shape = result.get('shape')
    if not isinstance(shape, list): raise ValueError('binary wire shape must be an array')
    result['shape'] = [int(x) if isinstance(x,float) and math.isfinite(x) and x.is_integer() else x for x in shape]
    return result

def read_buffer(root, descriptor):
    """Read one writable, bounded numeric allocation after owner validation."""
    fd, dtype, count = open_buffer(root, descriptor)
    try:
        # One writable, bounded numeric allocation. No intermediate bytes
        # object, per-element Python objects, or copy in the receiving client.
        with os.fdopen(fd,'rb',closefd=False) as stream:
            array=np.fromfile(stream,dtype=dtype,count=count)
            extra=stream.read(1)
        if array.size!=count or extra: raise ValueError('binary payload length changed')
    finally: os.close(fd)
    return array.reshape(descriptor['shape'],order='F')

def write_buffer(root, array):
    array=np.asarray(array)
    dtype=array.dtype.name
    if dtype not in DTYPES: raise ValueError('unsupported binary dtype')
    array=np.asarray(array,dtype=DTYPES[dtype]);shape=list(array.shape) or [1,1]
    if len(shape)==1:shape.append(1)
    count=shape_checked(shape,array.dtype.itemsize);name=uuid.uuid4().hex+'.bin';path=Path(root)/name
    with path.open('xb') as stream:stream.write(array.tobytes(order='F'))
    return dict(version=2,dtype=dtype,endian='little',order='F',shape=shape,count=count,byte_count=count*array.dtype.itemsize,resource_id=name)

def native(value):
    """Turn a Signal typed node into native data, preserving column order."""
    from gxtxt_script_bridge_server import NumericArray
    if not isinstance(value,dict) or 'kind' not in value:raise ValueError('scientific argument needs a typed kind')
    kind=value['kind']
    if kind=='empty':return np.empty((0,1))
    if kind=='text':return str(value['value'])
    if kind=='struct':return {k:native(v) for k,v in value['fields'].items()}
    if kind=='cell':return [native(v) for v in value['items']]
    if kind=='uniform':
        count=value['count']
        if isinstance(count,float) and math.isfinite(count) and count.is_integer():count=int(count)
        shape_checked([count,1])
        if count<1 or not math.isfinite(float(value['start'])) or not math.isfinite(float(value['step'])) or float(value['step'])<=0:raise ValueError('invalid uniform grid')
        return {'__gxtxt_uniform__':True,'start':float(value['start']),'step':float(value['step']),'count':count}
    if kind!='array':raise ValueError('unsupported scientific typed node')
    dims=value['shape'];dims=dims.values.tolist() if isinstance(dims,NumericArray) else dims
    # Shape cells decode as native integer scalars; disallow truncation.
    dims=[int(x) if float(x).is_integer() else x for x in dims]
    count=shape_checked(dims)
    if count<1:raise ValueError('scientific shape dimensions must be positive')
    real=value['real'];real=real.values if isinstance(real,NumericArray) else real
    array=np.asarray(real,dtype=float).reshape(-1,order='F')
    if array.size!=count or not np.isfinite(array).all():raise ValueError('scientific array shape mismatch or nonfinite input')
    array=array.reshape(dims,order='F')
    if 'imaginary' in value:
        imag=value['imaginary'];imag=imag.values if isinstance(imag,NumericArray) else imag
        imag=np.asarray(imag,dtype=float).reshape(-1,order='F')
        if imag.size!=count or not np.isfinite(imag).all():raise ValueError('imaginary shape mismatch or nonfinite input')
        return {'__gxtxt_complex__':True,'real':array,'imaginary':imag.reshape(dims,order='F')}
    return array

class Worker:
    def __init__(self,host):
        self.host=host;self.resource=None
        try:
            from gxtxt_resource_manager import ResourceManager
            self.manager=ResourceManager();self.resource=self.manager.allocate('scientific_transport',kind='directory',job_id=host.run_id,session=host.session)
            self.root=Path(self.resource['path'])
        except ImportError:
            self.root=Path(tempfile.mkdtemp(prefix='gxtxt-scientific-'))
        self.forward_resources = os.environ.get('GXTXT_BRIDGE_TYPED_DESCRIPTORS') == '1' and bool(os.environ.get('GXTXT_BRIDGE_WORKSPACE'))
        self.output_root = Path(os.environ['GXTXT_BRIDGE_WORKSPACE']) if self.forward_resources else self.root
        self.stats=dict(starts=1,calls=0,input_binary_bytes=0,input_forwarded_bytes=0,output_binary_bytes=0,output_forwarded_bytes=0,control_bytes=0,worker_seconds=0,decode_seconds=0,compute_seconds=0,encode_seconds=0)
        self.log=(self.root/'worker.log').open('w')
        framework=Path(__file__).resolve().parents[2]
        command=host.config.get('runtime','octave_cmd',fallback='') or shutil.which('octave-cli') or shutil.which('octave')
        if not command:raise RuntimeError('GNU Octave executable unavailable')
        env=os.environ.copy()
        threads=env.get('GXTXT_JOB_INTERNAL_THREADS','1')
        for key in ('OMP_NUM_THREADS','OPENBLAS_NUM_THREADS','MKL_NUM_THREADS','VECLIB_MAXIMUM_THREADS','NUMEXPR_NUM_THREADS'):env[key]=threads
        # Local process backend only. Worker stays in the supervisor-owned job
        # process group. Future Windows uses the common Job API/Job Objects;
        # remote dispatch and a second worker pool are intentionally excluded.
        self.process=subprocess.Popen([command,'--quiet','--no-gui',str(framework/'core/octave/gxtxt_scientific_binary_worker_v1.m'),str(framework),str(self.root),str(self.output_root)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=self.log,text=True,encoding='utf-8',env=env)

    def pack(self,value):
        from gxtxt_script_bridge_server import NumericArray, ResourceNumericArray
        if isinstance(value, ResourceNumericArray) and self.forward_resources:
            validate_buffer(value.root, value.descriptor)
            self.stats['input_forwarded_bytes'] += value.descriptor['byte_count']
            return {'kind':'binary', 'source':'execution', 'descriptor':value.descriptor}
        if isinstance(value,NumericArray):value=np.asarray(value.values).reshape(value.shape,order='F')
        # The legacy number node is binary64 in Octave. Preserve large integer
        # scalar identities through the existing typed buffer contract instead.
        if isinstance(value,(int,np.integer)) and not isinstance(value,(bool,np.bool_)) and abs(int(value))>2**53:
            integer=int(value)
            if not -(2**63)<=integer<2**64:raise ValueError('integer scalar exceeds the int64/uint64 transport range')
            value=np.asarray([[integer]],dtype=np.int64 if integer<0 else np.uint64)
        if isinstance(value,np.ndarray):
            d=write_buffer(self.root,value);self.stats['input_binary_bytes']+=d['byte_count'];return {'kind':'binary','descriptor':d}
        if isinstance(value,dict):return {'kind':'struct','fields':{k:self.pack(v) for k,v in value.items()}}
        if isinstance(value,(list,tuple)):return {'kind':'cell','items':[self.pack(x) for x in value]}
        if isinstance(value,str):return {'kind':'text','value':value}
        if isinstance(value,(bool,int,float,np.generic)):return {'kind':'number','value':str(value) if not isinstance(value,bool) else str(int(value))}
        raise ValueError('unsupported scientific transport value')

    def unpack(self,value):
        from gxtxt_script_bridge_server import NumericArray, ResourceNumericArray
        k=value['kind']
        if k=='binary':
            d=wire_descriptor(value['descriptor'])
            self.stats['output_binary_bytes']+=d['byte_count']
            if self.forward_resources:
                self.stats['output_forwarded_bytes'] += d['byte_count']
                return ResourceNumericArray.from_descriptor(self.output_root, d)
            array=read_buffer(self.root,d);return NumericArray(array.ravel(order='F'),d['shape'])
        if k=='struct':return {key:self.unpack(v) for key,v in value['fields'].items()}
        if k=='cell':return [self.unpack(x) for x in value['items']]
        if k=='text':return value['value']
        if k=='logical':return bool(value['value'])
        if k=='number':return float(value['value'])
        raise ValueError('unsupported scientific result')

    def call(self,function,args,projection=None):
        from gxtxt_script_bridge_server import BridgeError
        if self.process.poll() is not None:raise BridgeError('GXTXT:ScientificTransport:WorkerExit','scientific worker exited; explicit rerun required')
        try:
            request={'function':function,'args':[self.pack(x) for x in args],'projection':projection or []}
            payload=json.dumps(request,separators=(',',':'));self.stats['control_bytes']+=len(payload);self.stats['calls']+=1
            partial=self.root/'request.partial';partial.write_text(payload,encoding='utf-8');partial.replace(self.root/'request.json')
            response_path=self.root/'response.json';deadline=time.monotonic()+3600
            while not response_path.is_file():
                if self.process.poll() is not None:raise BridgeError('GXTXT:ScientificTransport:WorkerExit','scientific worker exited')
                if time.monotonic()>deadline:
                    self.close();raise BridgeError('GXTXT:ScientificTransport:Timeout','scientific worker timed out')
                time.sleep(.005)
            line=response_path.read_text(encoding='utf-8');response_path.unlink()
            if not line:raise BridgeError('GXTXT:ScientificTransport:WorkerExit','scientific worker closed its response channel')
            response=json.loads(line);self.stats['control_bytes']+=len(line);self.stats['worker_seconds']+=response.get('seconds',0)
            for key in ('decode_seconds','compute_seconds','encode_seconds'):self.stats[key]+=response.get(key,0)
            if not response['ok']:raise BridgeError(response.get('identifier') or 'GXTXT:ScientificTransport:Remote',response['message'])
            return self.unpack(response['value'])
        finally:
            # Only resources created in this private active context are eligible.
            for path in self.root.glob('*.bin'):
                if re.fullmatch(r'[a-f0-9]{32}\.bin',path.name) and not path.is_symlink():path.unlink(missing_ok=True)

    def close(self):
        if getattr(self,'process',None):
            if self.process.poll() is None:
                (self.root/'stop').touch()
                self.process.stdin.close()
                try:self.process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    self.process.terminate()
                    try:self.process.wait(timeout=2)
                    except subprocess.TimeoutExpired:self.process.kill();self.process.wait()
            self.process.stdout.close();self.process=None
        self.log.close()
        output=Path(self.host.config.get('runtime','output_dir',fallback=str(self.host.runtime_path.parent)))
        path=output/'scientific_transport.json';partial=output/'scientific_transport.json.tmp'
        partial.write_text(json.dumps(self.stats,sort_keys=True),encoding='utf-8');partial.replace(path)
        if self.resource:
            self.manager.release(self.resource['id']);self.manager.cleanup([self.resource['id']])
        else:shutil.rmtree(self.root)

def call(host,function,args,projection=None):
    worker=host.handles.get('scientific_binary_worker')
    if worker is None:
        worker=Worker(host);host.handles['scientific_binary_worker']=worker
    return worker.call(function,args,projection)
