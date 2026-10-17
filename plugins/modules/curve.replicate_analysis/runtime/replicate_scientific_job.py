"""Replicate orchestration: all interpolation, statistics and geometry use CORE."""
# SPDX-License-Identifier: GPL-3.0-or-later
import numpy as np
from gxtxt import gxtxt_api_call as call

API='CURVE_REPLICATE_ANALYSIS_API_v1'
N='NUMERIC_API_v1'
S='STATISTICAL_RESULT_SEMANTICS_API_v1'
C='CURVE_SOURCE_API_v1'
request=call(API,'preflight_encoded',['@REQUEST_BASE64@'])
frame=request['reference_frame']
traces=[]
original_traces={}
row_receipts={}
topology=None
landmark=None
source_groups=[]
for trace_index,trace in enumerate(request['traces']):
    source_request={k:trace[k] for k in ('dataset_id','x_variable_id','y_variable_id','order_variable_id','filters') if k in trace}
    source_request['display_budget']=65536
    source=call(C,'open',[source_request])
    try:
        description=call(C,'describe',[source])
        if description['row_count']>65536:raise ValueError('Study source exceeds the explicit 65536-point per-trace bound')
        # Full canonical pages, never a reduced display proxy as science.
        chunks=[];rows=[]
        for start in range(0,description['row_count'],4096):
            page=call(C,'page',[source,start,min(4096,description['row_count']-start)])
            chunks.append(np.asarray(page['rows']))
            rows.extend(page['source_rows'])
        points=np.vstack(chunks)
    finally:call(C,'close',[source])
    if len(points)<3 or not np.isfinite(points).all():raise ValueError('A source requires at least three finite ordered points')
    for axis,variable in enumerate(('x_variable_id','y_variable_id')):
        converted=[]
        target=frame['x_unit'] if request['method']=='xy_path' else frame['x_unit' if axis==0 else 'y_unit']
        for start in range(0,len(points),4096):
            receipt=call('DATASET_METADATA_API_v1','coordinate_values',[trace['dataset_id'],trace[variable],points[start:start+4096,axis],{'mode':'effective','unit':target}])
            converted.extend(np.asarray(receipt['values']).reshape(-1))
        points[:,axis]=converted
    row_receipts[str(trace_index)]=dict(dataset_id=trace['dataset_id'],source_rows=rows,
        observation_id=trace['observation_id'],point_set_id=trace['point_set_id'],calibration_realization_id=trace['calibration_realization_id'],curve_key=trace['curve_key'])
    original_traces[str(trace_index)]=dict(points=points.tolist(),source_rows=rows,descriptor=description,identity=trace)
    if request['method']=='xy_path':
        if request.get('correspondence')!='anchored_source_arclength':raise ValueError('XY consensus requires explicit anchored_source_arclength correspondence')
        if topology is None:topology=trace['topology'];landmark=trace['landmark_id']
        if topology!=trace['topology'] or landmark!=trace['landmark_id']:raise ValueError('Topology and corresponding physical start landmark must agree')
        if topology=='closed':
            if np.array_equal(points[0],points[-1]):points=points[:-1]
            phase=trace['phase_index']
            if not 0<=phase<len(points):raise ValueError('Source phase landmark index is outside the ordered path')
            points=np.roll(points,-phase,axis=0)
            if trace['direction']=='reverse':points=np.vstack((points[:1],points[:0:-1]))
        elif trace['direction']=='reverse':points=points[::-1]
        call('NATIVE_2D_GEOMETRY_API_v1','path_validate',[points,topology])
        model=call(N,'curve_model_fit',['parametric_spline',points[:,0],points[:,1],dict(topology=topology,parameterization='path_length')])
        grid=np.linspace(0.,1.,request['grid_points'])
        evaluated=call(N,'curve_model_evaluate',[model,grid])
        points=np.column_stack((np.asarray(evaluated['x']).reshape(-1),np.asarray(evaluated['y']).reshape(-1)))
        call('NATIVE_2D_GEOMETRY_API_v1','path_validate',[points,topology])
    else:
        if not np.all(np.diff(points[:,0])>0):raise ValueError('Y(X) requires strictly increasing X; use xy_path for vertical/returning/closed curves')
    traces.append(points)
    source_groups.append(trace['source_group_id'])
    print('Prepared observation',trace['observation_id'],'calibration',trace['calibration_realization_id'],flush=True)

if request['method']=='yx':
    lower=max(p[0,0] for p in traces);upper=min(p[-1,0] for p in traces)
    if lower>=upper:raise ValueError('Replicate curves have no common valid X domain')
    grid=np.linspace(lower,upper,request['grid_points'])
    aligned=[]
    for points in traces:
        response=call(N,'interpolate',[points[:,0],points[:,1],grid,dict(method='linear',extrapolation='error')])
        # Numeric interpolate returns a reconstructible interpolation receipt.
        if isinstance(response,dict):response=response.get('yq',response.get('y',response.get('values')))
        aligned.append(np.column_stack((grid,np.asarray(response).reshape(-1))))
    traces=aligned

X=np.column_stack([p[:,0] for p in traces]);Y=np.column_stack([p[:,1] for p in traces])
groups=list(dict.fromkeys(source_groups));source_ids=np.array([groups.index(g)+1 for g in source_groups],dtype=float)
sampling='independent_traces' if request['design']=='repeatability' else 'unspecified'
summary=call(N,'replicate_xy_summary',[X,Y,source_ids,dict(sampling_model=sampling)])
columns={'parameter':grid}
units={'parameter':frame['x_unit'] if request['method']=='yx' else '1'}
records={}
mapping=call(S,'numeric_field_map',['replicate_summary'])
field_columns={'y_mean':'mean','y_median':'median','y_std':'std','y_sem':'sem','sigma_within':'within','sigma_between':'between','sigma_total':'total','components_identifiable':'components_available','between_clamped':'between_clamped','n':'n','n_sources':'n_sources','within_df':'within_df','component_coefficient':'component_coefficient','lower_std':'lower_std','upper_std':'upper_std','lower_sem':'lower_sem','upper_sem':'upper_sem','lower_total':'lower_total','upper_total':'upper_total'}
for axis in ('x','y'):
    raw=summary[axis]
    unit=frame['x_unit'] if request['method']=='xy_path' or axis=='x' else frame['y_unit']
    scalar={key:np.asarray(raw[key]).reshape(-1)[0].item() for key in mapping}
    scalar.update({key:raw[key] for key in ('mode','sampling_model','component_method')})
    prototype=call(S,'from_numeric',['math.numeric.replicate_profile','replicate_summary',scalar,dict(y_unit=unit),{},dict(analysis_id=request['analysis_id'],study_design=request['design'],correspondence=request.get('correspondence','common_x_grid'))])
    bindings={}
    fields=call(S,'numeric_fields',[prototype])
    for key,suffix in field_columns.items():
        vid=axis+'_'+suffix
        data=np.asarray(raw[key]).reshape(-1)
        columns[vid]=np.full(len(grid),data[0]) if len(data)==1 else data
        semantic=mapping[key];bindings[semantic]=vid
        units[vid]=fields[key]['unit_text'] if key in fields else (unit if key not in ('n','n_sources','within_df','component_coefficient','components_identifiable','between_clamped') else '1')
    records[axis+'_profile']=call(S,'bind_columns',[prototype,bindings,len(grid)])
columns['covariance_xy']=np.asarray(summary['covariance_xy']).reshape(-1)
units['covariance_xy']=frame['x_unit']+'^2' if request['method']=='xy_path' else frame['x_unit']+'*'+frame['y_unit']
metadata=call(S,'publication_metadata',[records])
result=dict(analysis_id=request['analysis_id'],columns=columns,units=units,metadata=metadata,
            original_traces=original_traces,aligned_traces={str(i):p.tolist() for i,p in enumerate(traces)},roles=dict(parameter='parameter',x='x_mean',y='y_mean',x_dispersion='x_std',y_dispersion='y_std',covariance_xy='covariance_xy'),source_rows=row_receipts,
            qualifications=dict(design=request['design'],independent_observations=request['independent_observation_count'],shared_calibration_covariance='unavailable',confidence_interval='unavailable',prediction_interval='unavailable',localization_uncertainty=request.get('localization_uncertainty','unspecified'),calibration_uncertainty=request.get('calibration_uncertainty','unspecified'),covariance_definition=summary['covariance_method'],topology=topology or 'yx'))
print('GXTXT_REPLICATE_RESULT:'+call(API,'encode_result',[result]),flush=True)
