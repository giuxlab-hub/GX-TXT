source [file join [file dirname [info script]] .. official_dev099 project_common.tcl]
try {
    set session [::GX::createNewSession replicate_dev102]
    ::GX::modulePublicApiActivate curve.replicate_analysis CURVE_REPLICATE_ANALYSIS_API_v1
    set traces {};set sourceHashes {}
    foreach {number offset} {1 -1 2 0 3 1} {
        set id source_$number
        ::GX::datasetPublicationV2PublishSeries $session viewer.curve_digitizer [dict create dataset_id $id contract table.generic storage csv x_values {0 1 2 3 4} y_values [lmap x {0 1 2 3 4} {expr {2*$x+$offset}}] x_variable {variable_id arbitrary_coordinate unit mm} y_variable {variable_id arbitrary_measurement unit mm}]
        dict set sourceHashes $id [::GX::sha256File [::GX::datasetResolvePath $session $id]]
        lappend traces [dict create dataset_id $id x_variable_id arbitrary_coordinate y_variable_id arbitrary_measurement physical_feature_id edge_A curve_key physical_edge observation_id observation_$number point_set_id clicked_$number calibration_realization_id calibration_$number source_group_id instrument_A frame_id laboratory]
    }
    set request [dict create analysis_id independent_yx method yx design repeatability reference_frame {id laboratory declaration explicit_user_verified x_unit mm y_unit mm} traces $traces grid_points 11 localization_uncertainty 0 calibration_uncertainty 0.2]
    check {[::GX::moduleField curve.replicate_analysis default_enabled {}] eq "0"} {01 independent public discovery with legacy Analysis default-off}
    set prepared [::GX::Replicate::preflight $request]
    check {[dict get $prepared independent_observation_count]==3} {05 three genuine digitizations count as three independent observations}
    set invalid $request;dict set invalid traces [lreplace $traces 1 1 [dict replace [lindex $traces 1] physical_feature_id edge_B]]
    check {[catch {::GX::Replicate::preflight $invalid}]} {04 distinct physical features cannot be pooled}
    dict set invalid traces [list [lindex $traces 0] [dict replace [lindex $traces 1] dataset_id source_1 physical_feature_id edge_B]]
    check {[catch {::GX::Replicate::preflight $invalid}]} {04 two different edges inside one Dataset remain separate physical features}
    dict set invalid traces [lreplace $traces 1 1 [dict replace [lindex $traces 1] frame_id unrelated]]
    check {[catch {::GX::Replicate::preflight $invalid}]} {07 incompatible physical coordinate frames refuse}
    dict set invalid traces [lreplace $traces 1 1 [dict replace [lindex $traces 1] point_set_id clicked_1 observation_id observation_1]]
    check {[catch {::GX::Replicate::preflight $invalid}]} {06 calibration realizations cannot masquerade as independent observations}
    set ticket [::GX::Replicate::submit $request]
    set job [::GX::scriptJobWait [dict get $ticket job_id] 180]
    save job $job;save ticket $ticket
    check {[dict get $job state] eq "COMPLETED"} {02 real public managed scientific Job completes without Analysis enablement}
    set result [::GX::Replicate::result $ticket]
    save scientific_result $result
    set columns [dict get $result columns]
    check {abs([lindex [dict get $columns y_mean] 5]-4)<1e-10 && abs([lindex [dict get $columns y_std] 5]-1)<1e-10} {03 arbitrary Variable IDs yield independently verified mean and sample dispersion}
    check {[dict get $result qualifications localization_uncertainty]==0 && [dict get $result qualifications calibration_uncertainty]==0.2} {08 exact zero localization uncertainty remains distinct from calibration uncertainty}
    check {[dict get $result qualifications shared_calibration_covariance] eq "unavailable"} {09 shared systematic uncertainty is qualified and never reduced by replicate count}
    set publication [::GX::Replicate::publish $ticket];save publication $publication
    check {[dict size [dict get $publication outputs]]==3 && [llength [dict get $publication dataset_ids]]==3} {10 profile, original/aligned traces and feature summary publish atomically}
    set traceOutput [::GX::Replicate::describe_output [dict get $publication outputs traces]]
    check {[dict exists $traceOutput metadata replicate.trace_stage]} {Original source row identity and explicit derived-sample sentinel remain durable}
    set forged $ticket;dict set forged request grid_points 12
    check {[catch {::GX::Replicate::result $forged}]} {Mutated study tickets cannot adopt a completed Job}
    check {[catch {::GX::Replicate::publish $ticket}]} {11 independent study output is create-only by default}
    set secondRequest $request;dict set secondRequest analysis_id second_independent_study
    set secondTicket [::GX::Replicate::submit $secondRequest]
    ::GX::scriptJobWait [dict get $secondTicket job_id] 180
    set secondPublication [::GX::Replicate::publish $secondTicket]
    check {[dict get $publication dataset_id] ne [dict get $secondPublication dataset_id] && [::GX::datasetNamespaceGet $session [dict get $publication dataset_id]] ne [::GX::datasetNamespaceGet $session [dict get $secondPublication dataset_id]]} {11 two studies preserve independent canonical result IDs and study namespaces}
    set rollbackRequest [dict replace $request analysis_id atomic_rollback]
    set rollbackTicket [::GX::Replicate::submit $rollbackRequest];::GX::scriptJobWait [dict get $rollbackTicket job_id] 180
    ::GX::datasetPublicationV2PublishSeries $session math.numeric {dataset_id replicate.atomic_rollback.summary contract table.generic storage csv x_values {0 1} y_values {7 8} x_variable {variable_id x unit mm} y_variable {variable_id y unit mm}}
    set foreignSha [::GX::sha256File [::GX::datasetResolvePath $session replicate.atomic_rollback.summary]]
    check {[catch {::GX::Replicate::publish $rollbackTicket}] && [::GX::datasetField replicate.atomic_rollback.profile id {}] eq {} && [::GX::datasetField replicate.atomic_rollback.traces id {}] eq {} && [::GX::sha256File [::GX::datasetResolvePath $session replicate.atomic_rollback.summary]] eq $foreignSha} {Atomic multi-product failure rolls back earlier products and preserves the foreign Dataset}
    set cancelled [::GX::Replicate::submit [dict replace $request analysis_id cancelled_study]]
    ::GX::Replicate::cancel $cancelled;set cancelledJob [::GX::scriptJobWait [dict get $cancelled job_id] 30]
    check {[dict get $cancelledJob state] eq {CANCELLED} && [catch {::GX::Replicate::result $cancelled}]} {02 existing managed cancellation prevents adoption and publication}
    ::GX::sessionPersistenceCommit
    ::GX::createNewSession other_session_token_guard
    check {[catch {::GX::Replicate::result $ticket}]} {02 another Session cannot adopt the previous study ticket}
    ::GX::openSessionPath $session
    check {[catch {::GX::Replicate::result $ticket}]} {02 a previous Session-lifetime ticket cannot mutate the reopened Session}
    set output [::GX::Replicate::describe_output [dict get $publication dataset_id]]
    check {[dict get $output metadata replicate.study analysis_id] eq "independent_yx" && [dict exists $output metadata replicate.source_rows]} {12 durable source-complete interpretation reconstructs after Session reopen}
    dict for {id hash} $sourceHashes {check {[::GX::sha256File [::GX::datasetResolvePath $session $id]] eq $hash} "Canonical source $id is unchanged"}
    save result [dict create status PASS checks $checks session $session]
} on error {message options} {save result [dict create status FAIL checks $checks details [dict get $options -errorinfo]];puts stderr [dict get $options -errorinfo];exit 1}
exit
