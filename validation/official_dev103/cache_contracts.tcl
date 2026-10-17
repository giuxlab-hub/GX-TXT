# Public Preview/cache/publication lifecycle in a fresh private Session.
lassign $argv root out
set root [file normalize $root];set out [file normalize $out]
if {[file exists $out]} {error {Fresh output required}}
file mkdir $out
foreach name {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT} {set ::env($name) [file join $out $name]}
set argv0 __dev103_cache_contracts__;source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
set ::GX::cfg(output_root) [file join $out sessions]
set checks {}
proc check {condition label} {if {![uplevel 1 [list expr $condition]]} {error "FAIL $label"};lappend ::checks $label;puts "PASS $label";flush stdout}
proc save {name value} {set f [open [file join $::out $name.tcldict] w];puts $f $value;close $f}
proc waitCache {key} {
    set deadline [expr {[clock milliseconds]+180000}]
    while {[clock milliseconds]<$deadline} {
        set status [::GX::datasetPreviewCacheStatus $key]
        if {[dict get $status status] ne "preparing"} {return $status}
        after 50 [list set ::cacheTick 1];vwait ::cacheTick
    }
    error {Cache preparation timed out}
}
try {
    set session [::GX::createNewSession cache_contracts]
    set definition {dataset_id signal contract table.generic storage csv x_values {0 1 2 3} y_values {0 1 4 9} x_variable {variable_id x unit s} y_variable {variable_id y unit V}}
    set began [clock milliseconds]
    ::GX::datasetPublicationV2PublishSeries $session math.numeric $definition
    set publicationMs [expr {[clock milliseconds]-$began}]
    set key [::GX::datasetPreviewCacheKey signal]
    check {[dict exists $::GX::PreviewCache::tasks $key]} {Successful canonical publication schedules standard Preview after commit}
    set response [waitCache $key];save first_prepare $response
    check {[dict get $response status] eq "ready"} {Managed preparation produces a reusable standard scientific view}
    set representation [::GX::datasetPreviewCacheRead signal $key]
    check {[dict get $representation kind] eq "native2d"} {Standard cache contains an actual prepared native Plot model}
    set jobs [llength [::GX::scriptJobList]]
    set began [clock microseconds];set reused [::GX::datasetPreviewCacheRequest signal];set hitMs [expr {([clock microseconds]-$began)/1000.}]
    check {$reused eq $key && [llength [::GX::scriptJobList]]==$jobs} {Cache hit launches no scientific Job}
    set canonical [dict get [::GX::sessionInspectionDatasetPayload signal $session] sha256]
    set path [file join [::GX::datasetPreviewCachePath $session $key] representation.tcldict]
    set f [open $path a];puts $f damaged;close $f
    check {[::GX::datasetPreviewCacheRead signal $key] eq {}} {Damaged representation fails SHA verification}
    ::GX::datasetPreviewCacheClear $session [list $key]
    check {[dict get [::GX::sessionInspectionDatasetPayload signal $session] sha256] eq $canonical} {Cache clear preserves exact canonical payload}
    ::GX::datasetPreviewCacheRequest signal;check {[dict get [waitCache $key] status] eq "ready"} {Evicted or damaged cache regenerates through the same managed owner}
    set directory [::GX::datasetPreviewCachePath $session $key]
    set artifact [lindex [glob -nocomplain -directory $directory *.png] 0]
    check {$artifact ne {}} {Prepared standard graphical artifact is present}
    set f [open $artifact a];puts $f damaged;close $f
    check {[::GX::datasetPreviewCacheRead signal $key] eq {}} {Damaged derived PNG fails artifact SHA verification}
    ::GX::datasetPreviewCacheClear $session [list $key]
    dict set definition replace_owned 1;dict set definition y_values {0 2 8 18}
    ::GX::datasetPublicationV2PublishSeries $session math.numeric $definition
    set replacement [::GX::datasetPreviewCacheKey signal]
    check {$replacement ne $key && [::GX::datasetPreviewCacheRead signal $key] eq {}} {Authoritative replacement invalidates the exact previous source key}
    check {[dict get [waitCache $replacement] status] eq "ready"} {Replacement receives a fresh postcommit native Preview}
    set context [::GX::datasetCoordinateRead $session signal]
    ::GX::datasetCoordinateUpdate $session signal {y {calibration_factor 2}} [dict get $context revision]
    check {[::GX::datasetPreviewCacheKey signal] ne $replacement} {Coordinate calibration dependency invalidates prepared representation}
    # An invalid image is a valid opaque file publication. Preview failure must
    # not roll back that canonical commit or pretend to have graphical content.
    set bad [file join $out unavailable.png];set f [open $bad w];puts $f {not a PNG};close $f
    set published [::GX::datasetFilePublicationPublish $session viewer.curve_digitizer [dict create dataset_id invalid_image contract image.raster format png source_file $bad storage_kind binary media_type image/png]]
    set badKey [::GX::datasetPreviewCacheKey invalid_image]
    set outcome [waitCache $badKey]
    check {[::GX::datasetField invalid_image id] eq "invalid_image"} {Preview failure never reverses successful File Publication}
    save unsupported_preview $outcome
    # Session switch while a worker is being admitted: cancellation is retained
    # even when its durable Job ID arrives after the request.
    set pending [::GX::datasetPreviewCacheRequest signal {x y y x}]
    ::GX::datasetPreviewCacheCancel $pending
    set other [::GX::createNewSession another_session]
    set outcome [waitCache $pending];save cancelled $outcome
    check {[dict get $outcome status] eq "error" && [dict get [::GX::scriptJobDescribe [dict get $outcome job_id]] state] eq "CANCELLED"} {Cancellation during admission reaches the original managed Job after Session switch}
    ::GX::openSessionPath $session
    set current [::GX::datasetPreviewCacheRequest signal];check {[dict get [waitCache $current] status] eq "ready"} {Reopened Session regenerates its current calibrated Preview}
    ::GX::openSessionPath $other;::GX::openSessionPath $session
    check {[::GX::datasetPreviewCacheRead signal $current] ne {}} {Persistent source-verified cache survives Session reopening}
    save inventory [::GX::datasetPreviewCacheInventory $session]
    save result [dict create status PASS checks $checks publication_ms $publicationMs hit_ms $hitMs session $session]
} on error {message options} {save result [dict create status FAIL checks $checks details [dict get $options -errorinfo]];puts stderr [dict get $options -errorinfo];exit 1}
