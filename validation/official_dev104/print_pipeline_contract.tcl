# SPDX-License-Identifier: GPL-3.0-or-later
# Real canonical sources through public Plot/Print/Resource owners, private only.
source [file join [file dirname [info script]] print_recipe_contract.tcl]
proc awaitPrint {operation arguments} {
    unset -nocomplain ::response
    set request [::GX::printDocumentRequest $operation $arguments {apply {{value} {set ::response $value}}}]
    set timer [after 180000 {set ::response {ok 0 error {Fixture wait timeout}}}]
    vwait ::response;after cancel $timer
    if {![dict get $::response ok]} {error [dict get $::response error]}
    return [dict get $::response result]
}
set before [::GX::sha256File [::GX::datasetResolvePath $::GX::currentSession print_table]]
::GX::graphNativeRendererRequire
set graphs {}
foreach title {{First real native Graph} {Second real native Graph}} {
    set spec [::GX::PlotDatasetAPIv4::newSpec -graph_id plot.dataset.xy -title $title]
    dict set spec panels [list [dict create id main title $title axes {} annotations {} series [list [dict create id source dataset_id print_table x_variable_id x y_variable_id y axis left]]]]
    set reference [::GX::PlotDatasetAPIv4::createPlotFromSpec $spec variant]
    ::GX::PlotDatasetAPIv4::render $reference
    lappend graphs [dict get [::GX::PlotDatasetAPIv4::artifacts $reference] graph_artifact]
}
set recipe [::GX::printRecipeNew];set items [list [dict create id print_table source_kind dataset source_id print_table presentation table source_signature [::GX::printRecipeSourceSignature dataset print_table] options {variables {x y} start 0 count 3} caption {Canonical metre/volt table}]]
set n 0
foreach graph $graphs {
    incr n;set id [string range $graph [expr {[string length $::GX::currentSession]+1}] end]
    lappend items [dict create id print_graph$n source_kind graph source_id $id presentation graph source_signature [::GX::printRecipeSourceSignature graph $id] options {} caption "Real native Graph $n"]
}
dict set recipe items $items
set heartbeat 0;set maxGap 0;set lastBeat [clock milliseconds]
proc beat {} {set now [clock milliseconds];set ::maxGap [expr {max($::maxGap,$now-$::lastBeat)}];set ::lastBeat $now;incr ::heartbeat;set ::beatTimer [after 10 beat]};beat
set document [awaitPrint compose [dict create session $::GX::currentSession payload [dict create recipe $recipe]]]
check {[dict get $document page_count]==3} actual_table_and_two_native_graph_pages
set common [dict merge [dict create source_resource [dict get $document resource_id]] [dict remove $document resource_id resource_path pages notices]]
set page [awaitPrint page [dict merge $common {page 1 width 600}]]
check {[file isfile [dict get $page path]] && [dict get $page pdf_sha256] eq [dict get $document pdf_sha256]} actual_pdf_page_preview
set thumbnails [awaitPrint thumbnails $common]
check {[llength [dict get $thumbnails paths]]==3} all_pdf_thumbnails
set destination [file join $out exported.pdf]
set exported [awaitPrint export [dict merge $common [dict create session $::GX::currentSession destination $destination replace 0]]]
check {[::GX::sha256File $destination] eq [dict get $document pdf_sha256]} reviewed_pdf_exact_export
check {[catch {awaitPrint export [dict merge $common [dict create session $::GX::currentSession destination $destination replace 0]]}]} no_overwrite_without_explicit_policy
check {[::GX::sha256File [::GX::datasetResolvePath $::GX::currentSession print_table]] eq $before} canonical_source_payload_unchanged
set annotation [::GX::annotationPathForPlot [lindex $graphs 0]]
if {[file exists $annotation]} {error {Expected a new unannotated private Graph}}
file mkdir [file dirname $annotation]
set f [open $annotation w];puts $f {Private negative fixture: added after the reviewed PDF};close $f
check {[catch {awaitPrint verify $common}]} newly_added_annotation_stale_rejected
file delete $annotation
set unchanged [awaitPrint verify $common];::GX::printDocumentRelease [dict get $unchanged resource_id]
# Deliberate private source corruption verifies actual bytes, not registry SHA.
set path [::GX::datasetResolvePath $::GX::currentSession print_table];set f [open $path ab];puts -nonewline $f PRIVATE_STALE_FIXTURE;close $f
check {[catch {awaitPrint verify $common}]} actual_source_sha_stale_rejected
# Page-only navigation remains usable from frozen PDF, without scientific reread.
set next [awaitPrint page [dict merge $common {page 2 width 400}]]
check {[file isfile [dict get $next path]]} frozen_page_navigation_does_not_read_source
foreach result [list $page $next $thumbnails $exported $document] {::GX::printDocumentRelease [dict get $result resource_id]}
after cancel $beatTimer
set f [open [file join $out pipeline_result.tcldict] w];puts $f [dict create status PASS cases $checks document $document heartbeat $heartbeat max_gap_ms $maxGap scientific_before $before];close $f
puts "PASS printing pipeline, max heartbeat $maxGap ms"
after 1200 {set ::cleanupWait 1};vwait ::cleanupWait
