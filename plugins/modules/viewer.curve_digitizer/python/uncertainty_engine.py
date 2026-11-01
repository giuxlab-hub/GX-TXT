# SPDX-License-Identifier: GPL-3.0-or-later
"""Reviewed physical uncertainty for a fixed curve-digitizer calibration.

Scientific design imported from GX-TXT dev097's digitization linearization,
not from its older UI. Analytic derivatives follow the current Project model.

The caller owns source integrity, Session identity, and ordered row identity.
No uncertainty is inferred from pixel dimensions or visual quality scores.
"""
from __future__ import annotations
import json
import math
import zlib
import base64
import hashlib
import numpy as np

class UncertaintyError(ValueError):
    pass

MAX_POINTS = 4096
MAX_FACTOR_BYTES = 1024 * 1024


def review_fingerprint(config):
    """Re-review after a scientific source, point/order or calibration change.

    The exact Session Interactive Document SHA is guarded separately by CORE;
    presentation, notes and publish names cannot invalidate a physical
    declaration. Only factual scientific inputs are fingerprinted here.
    """
    owned={key: config.get(key) for key in (
        'source','axes','calibration','calibration_measurements',
        'scale_reference','curve_ordering','curves')}
    payload=json.dumps(owned,ensure_ascii=False,sort_keys=True,
                       separators=(',',':'),allow_nan=False).encode('utf-8')
    return hashlib.sha256(payload).hexdigest()

def checked_spec(spec, *, scale_bar=False, dual_y=False):
    if not isinstance(spec, dict):
        raise UncertaintyError('Uncertainty declaration must be a structured object.')
    mode = spec.get('mode', 'none')
    if mode == 'none':
        return {'mode': 'none'}
    if mode not in ('pixel_calibration', 'physical_override'):
        raise UncertaintyError('Select pixel_calibration, physical_override or none.')
    rationale = str(spec.get('rationale', '')).strip()
    if not rationale or len(rationale) > 2048:
        raise UncertaintyError('An explicit uncertainty rationale (up to 2048 characters) is required.')
    out = {'mode': mode, 'rationale': rationale}
    def numbers(name, n, positive=False):
        value = spec.get(name)
        if not isinstance(value, (list, tuple)) or len(value) != n:
            raise UncertaintyError(f'{name} requires exactly {n} numbers.')
        try:
            a = np.asarray(value, dtype=np.float64)
        except (ValueError, TypeError) as exc:
            raise UncertaintyError(f'{name} contains invalid values.') from exc
        if not np.isfinite(a).all() or np.any(a <= 0 if positive else a < 0):
            raise UncertaintyError(f'{name} must contain finite {"positive" if positive else "nonnegative"} values.')
        return a.tolist()
    if mode == 'physical_override':
        out['override_standard_uncertainty'] = numbers('override_standard_uncertainty', 3 if dual_y else 2, True)
    else:
        d = spec.get('pixel_distribution', '')
        if d not in ('rectangular_full_width', 'normal_standard_uncertainty'):
            raise UncertaintyError('Specify pixel uncertainty distribution explicitly.')
        out['pixel_distribution'] = d
        out['pixel_scale'] = numbers('pixel_scale', 2) # exactly zero is a valid declared localization uncertainty
        out['calibration_standard_uncertainty'] = numbers('calibration_standard_uncertainty', 14 if dual_y else 12)
        if scale_bar and any(out['calibration_standard_uncertainty']):
            raise UncertaintyError('SEM scale-bar uncertainty requires a distinct length/endpoints model. Use physical_override or hold all declared 12/14 calibration inputs fixed at zero.')
    return out


def propagate(project, pixels, spec, *, scale_bar=False, axis_ids=None):
    dual_y = project.y2_axis is not None
    spec = checked_spec(spec, scale_bar=scale_bar, dual_y=dual_y)
    if spec['mode'] == 'none':
        return None
    pixels = np.asarray(pixels, dtype=np.float64)
    if pixels.ndim != 2 or pixels.shape[1] != 2 or not 1 <= len(pixels) <= MAX_POINTS or not np.isfinite(pixels).all():
        raise UncertaintyError(f'Uncertainty review requires 1..{MAX_POINTS} finite original pixel pairs.')
    lin = project.calibration_linearization(pixels, axis_ids=axis_ids)
    n = len(pixels)
    m = len(lin['calibration_ids'])
    if spec['mode'] == 'physical_override':
        physical = np.asarray(spec['override_standard_uncertainty'], dtype=np.float64)
        local = np.zeros((n, 2, 2), dtype=np.float64)
        local[:,0,0] = physical[0]
        if dual_y:
            axis_ids = list(axis_ids)
            local[:,1,1] = [physical[1] if axis == 'y1' else physical[2]
                             for axis in axis_ids]
        else:
            local[:,1,1] = physical[1]
        shared = np.zeros((2*n, m), dtype=np.float64)
    else:
        pixel_sigma = np.asarray(spec['pixel_scale'], dtype=np.float64)
        if spec['pixel_distribution'] == 'rectangular_full_width':
            pixel_sigma /= math.sqrt(12.)
        # local per-observation derivative; shared calibration derivative
        local = lin['point_jacobian'].reshape(n, 2, 2) * pixel_sigma[None,None,:]
        shared = lin['calibration_jacobian'] * np.asarray(spec['calibration_standard_uncertainty'])[None,:]
    # Every row (X_i,Y_i) has local covariance + shared calibration covariance.
    blocks = local @ np.swapaxes(local, 1, 2)
    sh = shared.reshape(n,2,m)
    blocks += sh @ np.swapaxes(sh,1,2)
    if not np.isfinite(blocks).all():
        raise UncertaintyError('Non-finite propagated uncertainty.')
    varx = np.maximum(blocks[:,0,0],0)
    vary = np.maximum(blocks[:,1,1],0)
    shared_nonzero = bool(np.any(np.abs(shared) > 0))
    cxy = blocks[:,0,1]
    return {
        'sigma_x': np.sqrt(varx).tolist(),
        'sigma_y': np.sqrt(vary).tolist(),
        'covariance_xy': cxy.tolist(),
        'local_factors': local,
        'shared_factors': shared,
        'coordinates': lin['coordinates'],
        'condition_number': float(lin['condition_number']),
        'calibration_ids': lin['calibration_ids'],
        'calibration_units': lin['calibration_units'],
        'units': lin['coordinate_units'],
        'axis_ids': list(axis_ids) if axis_ids is not None else ['y1'] * n,
        'shared_calibration': shared_nonzero,
        'within_point_correlation': bool(np.any(np.abs(cxy) > np.finfo(float).eps*64)),
        'mode': spec['mode'],
        'spec': spec,
    }


def compact_factors(local_rows, shared_rows):
    """Portable exact float64 binary factor retention, original row order.

    Store *factor loadings*, not a dense covariance; reader reconstructs
    C_ij = delta_ij L_i L_i^T + S_i S_j^T. Bytes use little endian.
    """
    l = np.concatenate(local_rows, axis=0).astype('<f8')
    s = np.concatenate(shared_rows, axis=0).astype('<f8')
    m = s.shape[1]
    if (l.shape[0]*2 != s.shape[0] or l.shape[1:] != (2,2)
            or m not in (12, 14) or not np.isfinite(l).all() or not np.isfinite(s).all()):
        raise UncertaintyError('Uncertainty factors are not aligned to publication rows.')
    data = l.tobytes(order='C') + s.tobytes(order='C')
    compressed = zlib.compress(data, 9)
    encoded = base64.b64encode(compressed).decode('ascii')
    if len(encoded) > MAX_FACTOR_BYTES:
        raise UncertaintyError('Compressed factor resource exceeds the bounded metadata contract. Publish fewer points per Dataset.')
    return {'format':'zlib-base64-float64-le-v1' if m == 12 else 'zlib-base64-float64-le-v2',
            'shape_local':[l.shape[0],2,2],
            'shape_shared':[s.shape[0],m], 'raw_sha256': hashlib.sha256(data).hexdigest(),
            'payload': encoded}


def decode_factors(record):
    fmt = record.get('format')
    width = 12 if fmt == 'zlib-base64-float64-le-v1' else 14 if fmt == 'zlib-base64-float64-le-v2' else 0
    if width == 0:
        raise UncertaintyError('Unsupported factor format.')
    n = int(record['shape_local'][0])
    shared_rows, shared_width = map(int, record['shape_shared'])
    if (not 1 <= n <= MAX_POINTS or shared_rows != 2*n or shared_width != width
            or list(record['shape_local']) != [n,2,2]):
        raise UncertaintyError('Invalid retained factor shape.')
    # Bounded decompression, including maliciously oversized compressed input.
    compressed=base64.b64decode(record['payload'],validate=True)
    if len(compressed)>MAX_FACTOR_BYTES:
        raise UncertaintyError('Compressed factor resource exceeds its bounded contract.')
    expected = n*4*8+2*n*width*8
    inflater = zlib.decompressobj()
    buf = inflater.decompress(compressed, expected+1)
    if (len(buf)!=expected or inflater.unconsumed_tail or inflater.unused_data
            or not inflater.eof or inflater.flush(1)
            or hashlib.sha256(buf).hexdigest()!=record['raw_sha256']):
        raise UncertaintyError('Retained factors failed integrity or byte-count check.')
    a = np.frombuffer(buf[:n*4*8],dtype='<f8').reshape(n,2,2).copy()
    b = np.frombuffer(buf[n*4*8:],dtype='<f8').reshape(2*n,width).copy()
    if not np.isfinite(a).all() or not np.isfinite(b).all():
        raise UncertaintyError('Nonfinite retained factors.')
    return a,b


def covariance_from_factors(record, axis='y'):
    local, shared = decode_factors(record)
    n = len(local)
    if n > 512:
        raise UncertaintyError('Full covariance materialization is bounded to 512 rows; use retained factors for larger datasets.')
    if axis not in ('x','y'):
        raise UncertaintyError('Select physical X or Y covariance.')
    k = 0 if axis=='x' else 1
    # Each point contributes independent variance, all points share a low rank term.
    ix = np.arange(n)
    var = np.sum(local[:,k,:]**2,axis=1)
    v = shared.reshape(n,2,shared.shape[1])[:,k,:]
    cov = v @ v.T
    cov[ix,ix] += var
    return cov
