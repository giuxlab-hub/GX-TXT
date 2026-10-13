#!/usr/bin/env tclsh
# Usage: tclsh test_dataset_curve_fit.tcl <dev-031-framework> <new-output-dir>
# Creates one disposable real CSV-backed GX-TXT Dataset and tests the viewer API.
# SPDX-License-Identifier: GPL-3.0-or-later
if {[llength $argv] != 2} {error "Usage: tclsh test_dataset_curve_fit.tcl <framework> <new-output-dir>"}
lassign $argv root out
set root [file normalize $root];set out [file normalize $out]
if {[file exists $out]} {error "Output directory exists: $out"}
file mkdir [file join $out metadata] [file join $out datasets]
set mf [open [file join $out metadata manifest.ini] w];puts $mf {[pipeline]};puts $mf {format=2};close $mf
set csv [open [file join $out datasets source.csv] w]
puts $csv {x,y_linear,y_poly,y_exp,y_power,y_gauss,group,quality}
for {set i 1} {$i <= 9} {incr i} {
    set linear [expr {2.0*$i+1.0}]
    set poly [expr {3.0*$i*$i+2.0*$i+1.0}]
    set expy [expr {2.0*exp(0.18*$i)+0.4}]
    set power [expr {1.7*pow($i,1.35)}]
    set gauss [expr {4.0*exp(-0.5*pow(($i-5.0)/1.4,2))+0.5}]
    set group [expr {$i <= 5 ? "alpha" : "beta"}]
    puts $csv [join [list $i $linear $poly $expy $power $gauss $group $i] ,]
}
close $csv
set csv [open [file join $out datasets unsorted.csv] w]
puts $csv {x,y_linear,y_poly,y_exp,y_power,y_gauss,group,quality}
foreach x {3 1 2 2 4} {
    puts $csv [join [list $x [expr {2*$x+1}] [expr {3*$x*$x+2*$x+1}] [expr {2*exp(0.18*$x)+0.4}] [expr {1.7*pow($x,1.35)}] [expr {4*exp(-0.5*pow(($x-2.0)/1.4,2))+0.5}] alpha 1] ,]
}
close $csv
set argv0 __not_main__
source [file join $root gxtxt_pipeline.tcl]
::GX::defaults
::GX::loadModuleCatalog
set ::GX::currentSession $out
::GX::datasetRegistryClear
set fields [list kind table.generic contract table.generic format csv storage_provider csv path datasets/source.csv canonical_delimiter comma var_count 8 row_count 9 variable_schema_api_version 3]
set ids {x y_linear y_poly y_exp y_power y_gauss group quality}
set index 0
foreach id $ids {
    incr index
    set isText [expr {$id eq "group"}]
    lappend fields var${index}_variable_id $id var${index}_enabled 1 var${index}_canonical $id var${index}_unit {} var${index}_value_kind [expr {$isText ? "text" : "number"}] var${index}_dtype [expr {$isText ? "string" : "float64"}] var${index}_rank 1 var${index}_shape 9 var${index}_dimension_ids row var${index}_axis_kind explicit
    lappend fields var${index}_coordinate_role [expr {$id eq "x" ? "coordinate" : "data"}]
}
::GX::datasetRegister source $fields
set unsortedFields [string map [list datasets/source.csv datasets/unsorted.csv {row_count 9} {row_count 5} {_shape 9} {_shape 5}] $fields]
::GX::datasetRegister unsorted $unsortedFields
::GX::saveDatasetRegistry $out
set ::env(GX2D_TCL_LIBRARY) [file join $out gx2dtcl.so]
# The test runner builds the adapter into its disposable output directory.
exec cmake -S [file join $root core native2d] -B [file join $out native-build] -DBUILD_TESTING=OFF
exec cmake --build [file join $out native-build] --target gx2dtcl
set ::env(GX2D_TCL_LIBRARY) [file join $out native-build gx2dtcl[info sharedlibextension]]
::GX::modulePublicApiActivate viewer.dataset_curve_fit DATASET_CURVE_FIT_API_v1
set api ::GX::DatasetCurveFit
proc require {test message} {if {![uplevel 1 [list expr $test]]} {error $message}}
require {[${api}::filterMatch number 3 = 3]} "numeric equality"
require {[${api}::filterMatch number 3 != 4]} "numeric inequality"
require {[${api}::filterMatch number 3 < 4]} "numeric less"
require {[${api}::filterMatch number 3 <= 3]} "numeric less equal"
require {[${api}::filterMatch number 3 > 2]} "numeric greater"
require {[${api}::filterMatch number 3 >= 3]} "numeric greater equal"
require {[${api}::filterMatch number 3 between {2 4}]} "numeric between"
require {[${api}::filterMatch text alpha = alpha]} "text equality"
require {[${api}::filterMatch text alpha != beta]} "text inequality"
require {[${api}::filterMatch text alpha contains ph]} "text contains"
require {[${api}::filterMatch text alpha LIKE {a%a}]} "text LIKE"
set key [${api}::new]
set filters [list [dict create variable quality operator between value {2 7}] [dict create variable group operator LIKE value {a%}]]
set sourceId [${api}::loadSource $key source x y_linear $filters]
set sourceBefore [${api}::sourcePoints $key]
require {[llength $sourceBefore] == 4 && [lindex [lindex $sourceBefore 0] 0] == 2} "Dataset filter or source curve"
set scene $::GX::DatasetCurveFit::state($key,selectionScene)
set selectionId $::GX::DatasetCurveFit::state($key,selectionObject)
set nearest [::GX::Native2D::core nearest $scene {2 5} 0.1]
require {[dict get $nearest object] == $selectionId && [dict get $nearest index] == 0} "CORE nearest result"
set hit [::GX::Native2D::core hit $scene $selectionId {2 5} 0.1]
require {[dict get $hit index] == 0} "CORE hit-test result"
require {[::GX::Native2D::core hit $scene $selectionId {100 100} 0.1] eq {}} "CORE hit-test miss"
::GX::Native2D::core rect $scene {2.4 5.7 2.6 6.3} replace
require {[${api}::selectedIndices $key] eq {}} "segment crossing selected data points outside rectangle"
set rectId [::GX::Native2D::core rect $scene {1.9 4.9 3.1 7.1} replace]
require {$rectId > 0 && [llength [${api}::selectedIndices $key]] >= 2} "CORE rectangle selection"
${api}::clearSelection $key
foreach i {0 1 2} {${api}::selectPoint $key $i add}
require {[${api}::selectedIndices $key] eq {0 1 2}} "CORE point selection"
set fit [${api}::preview $key linear selected {1 10 10}]
require {[dict get $fit train_n] == 3 && [llength [dict get $fit fitted]] == 10} "fit selection/output separation"
require {[llength [lindex [dict get $fit residual] 0]] == 4} "residual row must include fitted Y"
require {[lindex [lindex [dict get $fit fitted] 0] 0] == 1 && [lindex [lindex [dict get $fit fitted] end] 0] == 10} "Numerical output grid endpoints"
require {abs([dict get $fit train_rmse]) < 1e-9} "selected linear fit"
${api}::selectPoint $key 3 add
require {[catch {${api}::accept $key}]} "stale fit-point selection was accepted"
${api}::selectPoint $key 3 subtract
set fittedId [${api}::accept $key]
require {$fittedId != $sourceId && [${api}::sourcePoints $key] eq $sourceBefore} "accept changed source"
require {[catch {${api}::accept $key}]} "duplicate acceptance was allowed"
set count [${api}::exportCsv $key [file join $out fit.csv]]
require {$count == 10 && [file exists [file join $out fit.csv]]} "CORE CSV export"
set fd [open [file join $out fit.csv] r];set heading [gets $fd];close $fd
require {[string first fitted_y_linear $heading] >= 0 && [string first fit_model $heading] >= 0} "CSV fitted-value provenance"
${api}::setFitVisible $key $fittedId 0
require {![dict get [lindex $::GX::DatasetCurveFit::state($key,records) 0] visible]} "accepted fit visibility"
${api}::setFitVisible $key $fittedId 1
${api}::preview $key linear all source
set secondId [${api}::accept $key]
require {$secondId != $fittedId && [llength $::GX::DatasetCurveFit::state($key,records)] == 2 && [${api}::sourcePoints $key] eq $sourceBefore} "multiple accepted fits changed source"
set ::GX::DatasetCurveFit::state($key,y) y_poly
require {[catch {${api}::preview $key linear all source}]} "stale source preview was allowed"
require {[catch {${api}::exportCsv $key [file join $out stale.csv]}]} "stale source export was allowed"
set ::GX::DatasetCurveFit::state($key,y) y_linear
${api}::deleteFit $key $fittedId
require {[llength $::GX::DatasetCurveFit::state($key,records)] == 1 && [${api}::sourcePoints $key] eq $sourceBefore} "accepted fit deletion changed source"
${api}::deleteFit $key $secondId
require {[llength $::GX::DatasetCurveFit::state($key,records)] == 0 && [${api}::sourcePoints $key] eq $sourceBefore} "accepted fit cleanup changed source"
${api}::loadSource $key unsorted x y_linear {}
set unsorted [${api}::sourcePoints $key]
set orderedFit [${api}::preview $key linear all source]
require {[lmap row [dict get $orderedFit fitted] {lindex $row 0}] eq {1 2 3 4}} "source-domain fit X was not sorted and deduplicated"
require {[llength [dict get $orderedFit residual]] == 5 && [${api}::sourcePoints $key] eq $unsorted} "unsorted source row identity changed"
foreach {model y degree initial} {
    linear y_linear 1 {}
    polynomial y_poly 2 {}
    exponential y_exp 1 {2 0.15 0.3}
    power_law y_power 1 {1 1}
    gaussian y_gauss 1 {4 5 1 0.5}
} {
    ${api}::loadSource $key source x $y {}
    set result [${api}::preview $key $model all source $degree $initial]
    require {[dict get $result train_n] == 9 && [llength [dict get $result residual]] == 9} "$model result dimensions"
    require {[dict get $result train_rmse] < 1e-3} "$model RMSE"
    require {[dict get $result train_r2] > 0.999} "$model R squared"
    require {[dict get $result converged]} "$model convergence"
    require {[string first {y = } [${api}::formula $result]] == 0} "$model formula"
    puts "PASS $model"
}
if {[info exists ::env(DISPLAY)] && $::env(DISPLAY) ne ""} {
    set w [${api}::open [dict create dataset_id source]]
    update
    set ::GX::DatasetCurveFit::state($w,y) y_linear
    ${api}::_uiLoad $w
    update
    require {[winfo exists $w.canvas] && [$w.canvas find all] ne {}} "viewer canvas did not render"
    lassign [${api}::_screen $w 1 3] sx sy
    ${api}::_mouseDown $w $sx $sy 0
    ${api}::_mouseUp $w $sx $sy 0
    require {[${api}::selectedIndices $w] eq {0}} "graphical CORE point selection"
    lassign [${api}::_screen $w 2 5] sx2 sy2
    ${api}::_mouseDown $w $sx2 $sy2 1
    ${api}::_mouseUp $w $sx2 $sy2 1
    require {[${api}::selectedIndices $w] eq {0 1}} "graphical additive CORE selection"
    ${api}::_mouseDown $w $sx2 $sy2 1
    ${api}::_mouseUp $w $sx2 $sy2 1
    require {[${api}::selectedIndices $w] eq {0}} "graphical subtractive CORE selection"
    lassign [${api}::_screen $w 1.4 3.8] cx0 cy0
    lassign [${api}::_screen $w 1.6 4.2] cx1 cy1
    ${api}::_mouseDown $w $cx0 $cy0 0
    ${api}::_mouseUp $w $cx1 $cy1 0
    require {[${api}::selectedIndices $w] eq {}} "graphical segment crossing selected outside points"
    lassign [${api}::_screen $w 2 5] rx0 ry0
    lassign [${api}::_screen $w 4 9] rx1 ry1
    ${api}::_mouseDown $w $rx0 $ry0 0
    ${api}::_mouseMove $w $rx1 $ry1
    require {[llength [$w.canvas find withtag selection_drag]] == 1} "selection rectangle was not visible during drag"
    ${api}::_mouseUp $w $rx1 $ry1 0
    require {[llength [${api}::selectedIndices $w]] >= 2} "graphical CORE rectangle selection"
    set selectedBefore [${api}::selectedIndices $w]
    set ::GX::DatasetCurveFit::state($w,rectMode) Add
    lassign [${api}::_screen $w 7 15] ax0 ay0
    lassign [${api}::_screen $w 8 17] ax1 ay1
    ${api}::_mouseDown $w $ax0 $ay0 0
    ${api}::_mouseUp $w $ax1 $ay1 0
    require {[llength [${api}::selectedIndices $w]] > [llength $selectedBefore]} "additive rectangle did not extend selection"
    ${api}::_uiRemoveLastRect $w
    require {[${api}::selectedIndices $w] eq $selectedBefore} "removing additive rectangle did not restore selection"
    set ::GX::DatasetCurveFit::state($w,rectMode) Subtract
    ${api}::_mouseDown $w $rx0 $ry0 0
    ${api}::_mouseUp $w $rx1 $ry1 0
    require {[llength [${api}::selectedIndices $w]] < [llength $selectedBefore]} "subtractive rectangle did not remove points"
    ${api}::_uiRemoveLastRect $w
    set beforeZoom $::GX::DatasetCurveFit::state($w,bounds)
    ${api}::_zoom $w 0.7
    require {$::GX::DatasetCurveFit::state($w,bounds) ne $beforeZoom} "zoom did not change view bounds"
    ${api}::_resetView $w
    require {$::GX::DatasetCurveFit::state($w,viewBounds) eq {}} "fit-view reset failed"
    ${api}::_uiPreview $w
    ${api}::_uiAccept $w
    require {$::GX::DatasetCurveFit::state($w,accepted) ne ""} "GUI accept"
    set ::GX::DatasetCurveFit::state($w,domain) range
    foreach {field value} {min 0 max 10 samples 11} {set ::GX::DatasetCurveFit::state($w,$field) $value}
    ${api}::_uiPreview $w
    ${api}::_uiAccept $w
    require {[llength $::GX::DatasetCurveFit::state($w,records)] == 2} "GUI range accept"
    ${api}::_uiFitAction $w delete
    require {$::GX::DatasetCurveFit::state($w,preview) eq {} && $::GX::DatasetCurveFit::state($w,report) eq {}} "deleted fit left a misleading preview report"
    lassign [${api}::_screen $w 1 3] sx sy
    ${api}::_mouseDown $w $sx $sy 0
    ${api}::_mouseUp $w $sx $sy 0
    require {[${api}::selectedIndices $w] eq {0}} "source hit-test beneath accepted fit"
    ${api}::_closeWindow $w
    set w [${api}::open [dict create dataset_id source]]
    update
    require {[llength [${api}::sourcePoints $w]] == 9 && [llength $::GX::DatasetCurveFit::state($w,records)] == 1} "Session viewer state did not restore"
    set sourceDocument $::GX::DatasetCurveFit::state($w,documentId)
    set sourcePayload [dict get [::GX::interactiveDocumentRead $sourceDocument] payload]
    ${api}::open [dict create dataset_id unsorted]
    update
    require {$::GX::DatasetCurveFit::state($w,dataset) eq "unsorted" &&
        $::GX::DatasetCurveFit::state($w,documentId) eq ""} "Different Dataset reused an unrelated saved document"
    ${api}::_uiLoad $w
    set otherDocument $::GX::DatasetCurveFit::state($w,documentId)
    require {$otherDocument ne "" && $otherDocument ne $sourceDocument} "Different Dataset did not create its own document"
    require {[dict get [::GX::interactiveDocumentRead $sourceDocument] payload] eq $sourcePayload} "Original Dataset document changed"
    require {[dict get [dict get [::GX::interactiveDocumentRead $otherDocument] payload] dataset] eq "unsorted"} "New document has the wrong Dataset"
    set otherPayload [dict get [::GX::interactiveDocumentRead $otherDocument] payload]
    # The Dataset combobox updates the textvariable before its selection
    # callback runs. A contextual open during that interval must still switch
    # the loaded Dataset and its document association.
    set ::GX::DatasetCurveFit::state($w,dataset) source
    ${api}::open [dict create dataset_id source]
    update
    require {$::GX::DatasetCurveFit::state($w,documentId) eq $sourceDocument &&
        [llength [${api}::sourcePoints $w]] == 9} "Context open kept the other Dataset's document"
    require {[dict get [::GX::interactiveDocumentRead $otherDocument] payload] eq $otherPayload} "Second Dataset document changed"
    set ::GX::DatasetCurveFit::state($w,dataset) unsorted
    ${api}::_uiDataset $w
    require {$::GX::DatasetCurveFit::state($w,documentId) eq ""} "Combobox switch retained the previous Dataset document ID"
    ${api}::open [dict create dataset_id unsorted]
    update
    require {$::GX::DatasetCurveFit::state($w,documentId) eq $otherDocument &&
        [llength [${api}::sourcePoints $w]] == 5} "Context open did not restore the selected Dataset document"
    require {[dict get [::GX::interactiveDocumentRead $sourceDocument] payload] eq $sourcePayload} "Source document changed during Dataset switches"
    ${api}::_closeWindow $w
    set w [${api}::open [dict create dataset_id source]]
    update
    require {$::GX::DatasetCurveFit::state($w,documentId) eq $sourceDocument &&
        [llength $::GX::DatasetCurveFit::state($w,records)] == 1} "Requested source Dataset did not restore its own document"
    ${api}::_closeWindow $w
    set w [${api}::open [dict create dataset_id unsorted]]
    update
    require {$::GX::DatasetCurveFit::state($w,documentId) eq $otherDocument &&
        [llength [${api}::sourcePoints $w]] == 5} "Requested second Dataset did not restore its own document"
    ${api}::_closeWindow $w
    require {[llength [::GX::interactiveDocumentList viewer.dataset_curve_fit dataset_curve_fit]] == 2} "Dataset switching created duplicate documents"
    require {[dict get [::GX::interactiveDocumentRead $sourceDocument] payload] eq $sourcePayload} "Reopen changed the source Dataset document"
    require {[dict get [::GX::interactiveDocumentRead $otherDocument] payload] eq $otherPayload} "Reopen changed the second Dataset document"
    puts "PASS Tk viewer canvas and graphical CORE selection"
}
${api}::close $key
puts "PASS real Dataset, all filters, CORE selection and immutable source, five Numeric fits, residuals, CSV"
exit 0
