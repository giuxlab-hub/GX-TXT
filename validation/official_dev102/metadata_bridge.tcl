source [file join [file dirname [info script]] .. official_dev099 project_common.tcl]
try {
    set session [::GX::createNewSession metadata_bridge_dev102]
    set publication [::GX::datasetPublicationV2PublishSeries $session viewer.curve_digitizer {dataset_id shared_source contract table.generic storage csv x_values {1 2 3} y_values {4 5 6} x_variable {variable_id source_x unit s} y_variable {variable_id source_y unit V} structured_metadata {producer_fact original}}]
    ::GX::datasetMetadataAuthorizeContributors $session shared_source {analysis.python_script analysis.octave_script} [::GX::datasetRevisionToken shared_source $session]
    set python {from gxtxt import gxtxt_api_call as call, GXTXTBridgeError
M='DATASET_METADATA_API_v1'
call(M,'update',['shared_source',{'bridge_key':'Python created','python_key':'Python contribution'}])
try:call(M,'update',['shared_source',{'_gxtxt.framework.metadata_origins':'forged'}])
except GXTXTBridgeError:pass
else:raise AssertionError('Reserved contributor authority accepted')
try:call(M,'update',['shared_source',{'malformed':'value'},'User'])
except GXTXTBridgeError:pass
else:raise AssertionError('Caller-supplied author accepted')
assert call(M,'contributors',['shared_source'])['bridge_key']['original_contributor']=='module:analysis.python_script'
print('Python contributor verified',flush=True)}
    set octave {M='DATASET_METADATA_API_v1';
gxtxt_api_call(M,'update',{'shared_source',struct('bridge_key','Octave edited','octave_key','Octave contribution')});
c=gxtxt_api_call(M,'contributors',{'shared_source'});
assert(strcmp(c.bridge_key.original_contributor,'module:analysis.python_script'));
assert(strcmp(c.bridge_key.last_contributor,'module:analysis.octave_script'));
g=gxtxt_api_call(M,'groups',{'shared_source'});
disp('Octave contributor verified');}
    foreach {language code} [list Python $python Octave $octave] {
        set id contributor_[string tolower $language]
        ::GX::scriptRegistrySave session $id "Metadata contributor $language" $code [dict create language $language required_apis DATASET_METADATA_API_v1]
        set job [::GX::scriptJobSubmit session:$id {}]
        set terminal [::GX::scriptJobWait [dict get $job id] 60]
        save job_$language $terminal
        check {[dict get $terminal state] eq "COMPLETED"} "Actual $language Bridge authenticates its own contributing module"
    }
    set contributors [::GX::datasetMetadataContributors $session shared_source]
    check {[dict get $contributors bridge_key original_contributor] eq "module:analysis.python_script" && [dict get $contributors bridge_key last_contributor] eq "module:analysis.octave_script"} {Distinct registered modules retain creator versus latest editor}
    set metadata [::GX::datasetMetadataRead $session shared_source]
    ::GX::datasetPublicationV2PublishSeries $session viewer.curve_digitizer [dict create dataset_id shared_source contract table.generic storage auto replace_owned 1 x_values {1 2 3} y_values {4 5 6} x_variable {variable_id source_x unit s} y_variable {variable_id source_y unit V} structured_metadata $metadata]
    check {[::GX::datasetMetadataContributors $session shared_source] eq $contributors} {Same-owner republishing preserves all unchanged contributor identities}
    set archive [file join $::out portable.zip]
    ::GX::sessionPortableExport $session $archive
    ::GX::sessionPortableValidate $archive
    set imported [file join $::out imported]
    ::GX::sessionPortableImport $archive $imported
    ::GX::openSessionPath $imported
    check {[::GX::datasetMetadataContributors $imported shared_source] eq $contributors && [::GX::datasetField shared_source producer_module {}] eq "viewer.curve_digitizer"} {Portable Session import preserves contributor manifest and independent Dataset producer}
    check {[dict get [::GX::sessionInspectionDatasetPayload shared_source $imported] sha256] eq [dict get $publication sha256]} {Canonical scientific source bytes remain unchanged}
    save result [dict create status PASS checks $checks session $imported]
} on error {message options} {save result [dict create status FAIL checks $checks details [dict get $options -errorinfo]];puts stderr [dict get $options -errorinfo];exit 1}
exit
