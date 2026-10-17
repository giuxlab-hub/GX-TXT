lassign $argv root out
set root [file normalize $root];set out [file normalize $out]
if {[file exists $out]} {error {Evidence output exists}}
file mkdir $out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT} {set ::env($key) [file join $out $key]}
set argv0 __dev102_core_contracts__;source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
set ::GX::cfg(output_root) [file join $out sessions]
set checks {}
proc check {expression label} {
    if {![uplevel 1 [list expr $expression]]} {error "FAIL $label"}
    lappend ::checks $label;puts "PASS $label";flush stdout
}
proc publish {id storage {required {}}} {
    set plan [::GX::datasetPublicationV2Prepare $::session viewer.curve_digitizer [dict create dataset_id $id contract table.generic storage $storage capabilities_required $required replace_owned 1 structured_metadata {unprefixed_module_value original}]]
    set writer [::GX::datasetPublicationV2OpenWriter $plan]
    try {
        ::GX::datasetPublicationV2DeclareDimension $writer row 0 {extendible 1}
        foreach {vid name values} {arbitrary_x X {0 1 2} arbitrary_y Y {4 5 6}} {
            ::GX::datasetPublicationV2DeclareVariable $writer $vid [dict create name $name dtype float64 unit mm dimension_ids row]
        }
        ::GX::datasetPublicationV2Append $writer row {arbitrary_x {0 1 2} arbitrary_y {4 5 6}}
        return [::GX::datasetPublicationV2Finalize $writer]
    } on error {message options} {catch {::GX::datasetPublicationV2Abort $writer};return -options $options $message}
}
try {
    set session [::GX::createNewSession dev102_core]
    foreach storage {csv hdf5} {
        set id replacement_$storage
        set original [publish $id $storage]
        set path [dict get $original path]
        set replacement [publish $id auto]
        check {[dict get $replacement storage_provider] eq $storage && [dict get $replacement path] eq $path} "$storage automatic replacement retains canonical provider, path and ID"
        check {[dict get $replacement sha256] eq [dict get $original sha256]} "$storage exact values retained"
        set opposite [expr {$storage eq "csv"?"hdf5":"csv"}]
        check {[catch {publish $id $opposite}]} "$storage explicit provider conflict refuses migration"
        set before [::GX::sha256File [file join $session $path]]
        proc rejectPublication {id} {publish $id auto;error {Deliberate post-publication transaction failure}}
        set failed [catch {::GX::datasetAuthorityTransaction $session rejectPublication $id}]
        check {$failed && [::GX::sha256File [file join $session $path]] eq $before} "$storage authority rollback preserves payload"
    }
    check {[catch {publish replacement_csv auto {multidimensional}} reason] && [string match {*migration*} $reason]} {CSV capability incompatibility gives migration diagnostic}
    set fresh [publish new_auto auto]
    check {[dict get $fresh storage_provider] eq "hdf5"} {New unknown-size publication retains ordinary auto policy}
    set id replacement_csv
    check {[catch {::GX::_datasetPrivateWithModule math.numeric ::GX::datasetMetadataUpdate $session $id {second_module_value 17}}]} {Foreign module cannot self-authorize a contribution}
    ::GX::datasetMetadataAuthorizeContributors $session $id {math.numeric} [::GX::datasetRevisionToken $id $session]
    ::GX::_datasetPrivateWithModule math.numeric ::GX::datasetMetadataUpdate $session $id {second_module_value 17}
    ::GX::datasetMetadataUpdate $session $id {user_value annotation}
    ::GX::_datasetMetadataPublicationWrite $session $id [dict merge [::GX::datasetMetadataRead $session $id] {system_value integrity}] viewer.curve_digitizer {}
    set producer [::GX::datasetField $id producer_module {}]
    set groups [::GX::datasetMetadataGroups $session $id]
    check {[dict exists $groups module:viewer.curve_digitizer unprefixed_module_value] && [dict exists $groups module:math.numeric second_module_value] && [dict exists $groups User user_value] && [dict exists $groups System system_value]} {Actual contributors are independent of original producer}
    check {![dict exists $groups module:viewer.scientific_worksheet] && ![dict exists $groups Unclassified]} {Absent contributor groups are not invented}
    ::GX::_datasetPrivateWithModule math.numeric ::GX::datasetMetadataUpdate $session $id {unprefixed_module_value revised}
    set contributors [::GX::datasetMetadataContributors $session $id]
    check {[dict get $contributors unprefixed_module_value original_contributor] eq "module:viewer.curve_digitizer" && [dict get $contributors unprefixed_module_value last_contributor] eq "module:math.numeric"} {Creator and latest modifier remain distinct}
    ::GX::datasetMetadataUpdate $session $id {unrelated value}
    check {[dict get [::GX::datasetMetadataContributors $session $id] unprefixed_module_value] eq [dict get $contributors unprefixed_module_value]} {Unrelated writes preserve attribution revision}
    set historical [::GX::_datasetMetadataReadAll $session $id]
    dict set historical historical_value legacy
    ::GX::_datasetMetadataWriteAll $session $id $historical
    check {[dict exists [::GX::datasetMetadataGroups $session $id] Unclassified historical_value]} {Unverified historical metadata remains Unclassified}
    ::GX::datasetMetadataUpdate $session $id {historical_value corrected}
    check {[dict get [::GX::datasetMetadataContributors $session $id] historical_value original_contributor] eq "Unclassified"} {Editing historical metadata does not invent a creator}
    check {[catch {::GX::datasetMetadataUpdate $session $id {_gxtxt.framework.metadata_origins forged}}]} {Public caller cannot forge contributor manifest}
    set before [::GX::_datasetMetadataReadAll $session $id]
    proc failWrite {} {::GX::datasetMetadataUpdate $::session replacement_csv {rollback_value invalid};error {Deliberate transaction failure}}
    check {[catch {::GX::datasetAuthorityTransaction $session failWrite}] && [::GX::_datasetMetadataReadAll $session $id] eq $before} {Failed transaction rolls back values and attribution atomically}
    ::GX::sessionPersistenceCommit
    ::GX::openSessionPath $session
    check {[::GX::datasetField $id producer_module {}] eq $producer && [dict get [::GX::datasetMetadataContributors $session $id] unprefixed_module_value last_contributor] eq "module:math.numeric"} {Reopen retains producer and independent contributor identities}
    set report [dict create status PASS checks $checks session $session]
} on error {message options} {
    set report [dict create status FAIL checks $checks details [dict get $options -errorinfo]]
    puts stderr [dict get $options -errorinfo]
}
set fd [open [file join $out result.tcldict] w];puts $fd $report;close $fd
exit [expr {[dict get $report status] ne "PASS"}]
