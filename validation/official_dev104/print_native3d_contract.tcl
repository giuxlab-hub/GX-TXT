# SPDX-License-Identifier: GPL-3.0-or-later
# Public Native3D snapshot print consumption, not a Plot implementation test.
source [file join [file dirname [info script]] print_recipe_contract.tcl]
set plan [::GX::datasetPublicationV2Prepare $::GX::currentSession math.numeric {dataset_id print_xyz contract table.generic storage hdf5 structured_metadata {fixture.synthetic 1}}]
set writer [::GX::datasetPublicationV2OpenWriter $plan];::GX::datasetPublicationV2DeclareDimension $writer row 5
foreach axis {x y z} {::GX::datasetPublicationV2DeclareVariable $writer $axis {dtype float64 dimension_ids row unit m}}
foreach {axis values} {x {0 1 2 3 4} y {0 2 1 3 2} z {0 1 2 4 6}} {::GX::datasetPublicationV2WriteRange $writer $axis 0 $values};::GX::datasetPublicationV2Finalize $writer
::GX::graphNativeRendererRequire
set spec [::GX::PlotDatasetAPIv4::newSpec -graph_id plot.dataset.xyz -title {Native3D print reference}]
dict set spec graph_type cartesian_3d
dict set spec dataset_id print_xyz;foreach axis {x y z} {dict set spec ${axis}_variable_id $axis}
dict set spec config plot_type line3
set ref [::GX::PlotDatasetAPIv4::createPlotFromSpec $spec variant]
::GX::PlotDatasetAPIv4::render $ref
::GX::writeManifest [file join $::GX::currentSession metadata manifest.ini]
set graph [dict get [::GX::PlotDatasetAPIv4::artifacts $ref] graph_artifact]
set before [::GX::sha256File [::GX::datasetResolvePath $::GX::currentSession print_xyz]]
set artworkBefore [::GX::sha256File $graph]
set id [string range $graph [expr {[string length $::GX::currentSession]+1}] end]
set recipe [::GX::printRecipeNew]
dict set recipe items [list [dict create id print_native3d source_kind graph source_id $id presentation graph source_signature [::GX::printRecipeSourceSignature graph $id] options {} caption {Actual Native3D line; source coordinates in metres}]]
unset -nocomplain ::answer
::GX::printDocumentRequest compose [dict create session $::GX::currentSession payload [dict create recipe $recipe]] {apply {{response} {set ::answer $response}}}
set timer [after 180000 {set ::answer {ok 0 error {Finite Native3D print timeout}}}];vwait ::answer;after cancel $timer
if {![dict get $::answer ok]} {error [dict get $::answer error]}
set result [dict get $::answer result]
check {[dict get $result page_count]==1 && [file isfile [dict get $result pdf]]} actual_native3d_snapshot_print_page
check {[::GX::sha256File [::GX::datasetResolvePath $::GX::currentSession print_xyz]] eq $before && [::GX::sha256File $graph] eq $artworkBefore} original_native3d_dataset_and_graph_unchanged
set f [open [file join $out native3d_result.tcldict] w];puts $f [dict create status PASS checks $checks receipt $result source_sha256 $before graph_sha256 $artworkBefore];close $f
puts {PASS public Native3D print snapshot}
# Receipt PDF retained for independent inspection; allocation remains owner-held
# until this process exits, when the existing Resource owner marks it orphaned.
