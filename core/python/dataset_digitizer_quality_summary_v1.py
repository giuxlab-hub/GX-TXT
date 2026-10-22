"""Bounded presentation of the public published Quality v2 JSON; no recomputation."""
# SPDX-License-Identifier: GPL-3.0-or-later
import base64
import json
import sys

def unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate Quality report field')
        result[key] = value
    return result

raw = sys.stdin.read(8_388_609)
if len(raw) > 8_388_608:
    raise ValueError('Quality report exceeds the bounded presentation limit')
report = json.loads(raw, object_pairs_hook=unique, parse_constant=lambda _: (_ for _ in ()).throw(ValueError('Nonfinite Quality JSON')))
if str(report.get('schema_version')) != '2' or report.get('producer') != 'viewer.curve_digitizer':
    raise ValueError('Unsupported published Quality schema or producer')
lines = []
rows = []
def text(value):
    if value is None:
        return 'Not supplied'
    if isinstance(value, bool):
        return 'Yes' if value else 'No'
    if isinstance(value, (dict, list)):
        return json.dumps(value, ensure_ascii=False, separators=(', ', ': '))
    return str(value)
def emit(label, value, explanation, unit=''):
    rows.append(dict(label=label,value=text(value),unit=unit,meaning=explanation))
    lines.append(f'{label}: {text(value)}. {explanation}')

emit('Point origins', report.get('point_origins'), 'Recorded manual/assisted origins describe acquisition, not accuracy.')
segments = report.get('segments', {})
emit('Segment report coverage', f"{segments.get('returned', 'unknown')} of {segments.get('total', 'unknown')}; truncated={text(segments.get('truncated'))}", 'The overlay uses canonical raster columns, independently of this bounded diagnostic report.')
evidence = report.get('image_evidence', {})
emit('Local image evidence available', evidence.get('available'), evidence.get('limitations', 'Image structure is not a measurement of physical error.'))
if evidence.get('available'):
    emit('Image evidence sampling', f"{evidence.get('sampled_segment_count', 'unknown')} segments; complete={text(evidence.get('sampling_complete'))}", f"Reported method: {evidence.get('method', 'not supplied')}; contrast threshold {evidence.get('threshold_uint8', 'not supplied')} in 8-bit intensity units.")
for curve in report.get('curves', [])[:64]:
    identity = f"{curve.get('curve_label', 'Unnamed')} [{curve.get('curve_id', 'identity unavailable')}]"
    spacing = curve.get('spacing_px', {})
    for statistic in ('minimum', 'median', 'maximum'):
        emit(f'Curve {identity} {statistic} point spacing', spacing.get(statistic), 'Published source-raster distance between recorded points; not physical uncertainty.', 'px')
    emit(f'Curve {identity} observations', f"outside-image points {curve.get('point_outside_image_count', 'unknown')}; monotonicity {text(curve.get('monotonicity_violations'))}; flags {text(curve.get('flag_counts'))}", 'Warnings depend on declared ordering and image evidence; they are not measured errors.')
    emit(f'Curve {identity} local visible fraction', curve.get('raster_evidence_visible_fraction'), 'Reported local contrast evidence; crossings, labels and grid lines can resemble the intended curve.')
for calibration in report.get('calibrations', [])[:64]:
    identity = f"{calibration.get('label', 'Unnamed')} [{calibration.get('measurement_id', 'identity unavailable')}]"
    emit(f'Calibration {identity} geometry', f"valid={text(calibration.get('geometry_valid'))}; homography condition {calibration.get('homography_condition', 'not supplied')}", 'Condition depends on coordinate scale and does not validate accuracy.')
    emit(f'Calibration {identity} control reprojection RMS', calibration.get('four_control_reprojection_rms'), 'Reported mapping-coordinate residual for the same four controls; this is not independent calibration verification or physical sigma.')
    emit(f'Calibration {identity} independent verification', calibration.get('independent_verification'), 'Unavailable verification cannot be interpreted as zero error.')
spread = report.get('calibration_realization_spread', {})
if spread.get('available'):
    for axis in ('x', 'y'):
        emit(f'{axis.upper()} calibration realization spread', f"{text(spread.get(axis + '_range'))} {spread.get('axis_units', {}).get(axis, '')}", 'Descriptive differences across selected calibration realizations; not a standard uncertainty.')
else:
    emit('Calibration realization spread', 'Unavailable', 'No dispersion estimate is invented from a missing or single realization.')
flagged = [s for s in segments.get('records', []) if s.get('flags')]
for segment in flagged[:32]:
    emit(f"Segment {segment.get('curve_id', 'unknown')} / {segment.get('segment_index', 'unknown')}", f"flags {text(segment.get('flags'))}; {text(segment.get('raster_start'))} to {text(segment.get('raster_end'))} px; evidence {text(segment.get('raster_evidence'))}", 'Published segment observation, not recomputed by Preview.')
if len(flagged) > 32:
    emit('Additional flagged segments', len(flagged) - 32, 'See the full published report for remaining records.')
if '--table' in sys.argv[1:]:
    from gxtxt_job_supervisor import tcl_result
    print(tcl_result(dict(schema='gxtxt.published_quality_presentation.v1',rows=rows,summary='\n'.join(lines))))
else:
    for line in lines:
        print(base64.b64encode(line.encode('utf-8')).decode('ascii'))
