# TASK210 diagnostic fault only. The real source/native/publication owners run.
if {[llength $argv]!=4} {error {Expected REAL_WORKER FRAMEWORK OWNED_REQUEST FAULT_PLAN}}
lassign $argv realWorker framework ownedRequest faultPlan
namespace eval ::Task210VideoFault {variable destination {};variable receipt {};variable installed 0;variable expectedPublicationSha {}}
# Python writes an adjacent inert Tcl dictionary, not executable instructions.
set channel [open ${faultPlan}.tcldict rb]
try {set plan [encoding convertfrom utf-8 [read $channel 16385]]} finally {close $channel}
if {[string bytelength $plan]>16384} {error {Diagnostic plan exceeds its bound}}
dict size $plan
set ::Task210VideoFault::destination [dict get $plan destination]
set ::Task210VideoFault::receipt [dict get $plan receipt]
set ::Task210VideoFault::expectedPublicationSha [dict get $plan publication_source_sha256]
proc ::Task210VideoFault::published {command code result operation} {
    variable destination;variable receipt
    if {$code!=0 || [llength $command]!=5 || [lindex $command 2] ne $destination} return
    if {[lindex $command 4] ne {create_only} || [dict get $result files document sha256] ne [lindex $command 3] || ![file isfile $destination]} {error {Diagnostic publication identity differs}}
    set out [dict create schema gxtxt.task210.video_real_commit_fault.v1 intervention {execution-trace exits AFTER actual FilePublication returned success, BEFORE worker terminal emission} destination $destination actual_publication $result]
    set f [open $receipt {WRONLY CREAT EXCL}]
    try {fconfigure $f -encoding utf-8 -translation lf;puts -nonewline $f $out;flush $f} finally {close $f}
    # Do not return a fabricated result or remove bytes. The normal surviving
    # host must observe EOF and use its existing exact read-only reconciliation.
    exit 91
}
proc ::Task210VideoFault::sourced {command code result operation} {
    variable installed;variable expectedPublicationSha
    if {$installed || $code!=0 || [llength $command]!=2 || [file normalize [lindex $command 1]] ne [file join $::Task210VideoFault::framework gxtxt_pipeline.tcl]} return
    set owner [file join $::Task210VideoFault::framework core tcl file_publication_api_v1.tcl]
    if {[::GX::sha256File $owner] ne $expectedPublicationSha || ![llength [info procs ::GX::filePublicationCopy]]} {error {Diagnostic requires the pinned real FilePublication owner}}
    trace add execution ::GX::filePublicationCopy leave ::Task210VideoFault::published
    set installed 1
}
set ::Task210VideoFault::framework [file normalize $framework]
trace add execution ::source leave ::Task210VideoFault::sourced
set argv [list $framework $ownedRequest]
set argv0 $realWorker
source $realWorker
