set prior [lindex $argv 2]
source [file join [file dirname [info script]] .. official_dev099 project_common.tcl]
try {
    set session [file join $out session];file copy $prior $session;::GX::openSessionPath $session
    set traces {};foreach n {1 2 3} {lappend traces [dict create dataset_id source_$n x_variable_id arbitrary_coordinate y_variable_id arbitrary_measurement physical_feature_id edge_A curve_key physical_edge observation_id observation_$n point_set_id clicked_$n calibration_realization_id calibration_$n source_group_id instrument_A frame_id laboratory]}
    set request [dict create analysis_id bridge_public method yx design repeatability reference_frame {id laboratory declaration explicit_user_verified x_unit mm y_unit mm} traces $traces grid_points 11]
    set encoded [binary encode base64 -maxlen 0 $request]
    foreach language {Python Octave} {
        if {$language eq {Python}} {
            set code [string map [list @REQUEST@ $encoded] {from gxtxt import gxtxt_api_call as call
api='CURVE_REPLICATE_ANALYSIS_API_v1'
assert 'xy_path' in call(api,'capabilities',[])['methods']
request=call(api,'preflight_encoded',['@REQUEST@'])
ticket=call(api,'submit',[request])
state=call(api,'status',[ticket])
job=call('SCRIPT_EXECUTION_API_v1','job_wait',[state['id'],180])
assert job['state']=='COMPLETED', job
result=call(api,'result',[ticket])
assert abs(result['columns']['y_mean'][5]-4)<1e-10
assert result['qualifications']['shared_calibration_covariance']=='unavailable'
assert len(result['original_traces']['0']['points'])==5 and result['original_traces']['0']['source_rows']==[0,1,2,3,4]
print('PUBLIC_REPLICATE_PYTHON_PASS',flush=True)}]
        } else {
            set code [string map [list @REQUEST@ $encoded] {api='CURVE_REPLICATE_ANALYSIS_API_v1';
request=gxtxt_api_call(api,'preflight_encoded',{'@REQUEST@'});
ticket=gxtxt_api_call(api,'submit',{request});
state=gxtxt_api_call(api,'status',{ticket});
job=gxtxt_api_call('SCRIPT_EXECUTION_API_v1','job_wait',{state.id,180});
assert(strcmp(job.state,'COMPLETED'));
result=gxtxt_api_call(api,'result',{ticket});
y=result.columns.y_mean;if(iscell(y)),y=cell2mat(y);endif;
assert(abs(y(6)-4)<1e-10);
assert(strcmp(result.qualifications.shared_calibration_covariance,'unavailable'));
disp('PUBLIC_REPLICATE_OCTAVE_PASS');}]
        }
        set sid bridge_[string tolower $language]
        ::GX::scriptRegistrySave session $sid "Public Replicate $language" $code [dict create language $language required_apis {CURVE_REPLICATE_ANALYSIS_API_v1;SCRIPT_EXECUTION_API_v1}]
        set outer [::GX::scriptJobSubmit session:$sid {}]
        set job [::GX::scriptJobWait [dict get $outer id] 240];save job_$language $job
        set log [::GX::scriptJobLogRead [dict get $outer id] 0 65536];save log_$language $log
        check {[dict get $job state] eq {COMPLETED}} "$language public Replicate API uses supervised owned child wait and returns numeric scientific results"
    }
    save result [dict create status PASS checks $checks session $session]
} on error {message options} {save result [dict create status FAIL checks $checks details [dict get $options -errorinfo]];puts stderr [dict get $options -errorinfo];exit 1}
exit
