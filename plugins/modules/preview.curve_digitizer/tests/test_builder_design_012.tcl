set ::env(GXTXT_PREVIEW_TEST_LEGACY) 1
namespace eval ::GX {}
proc ::GX::datasetPublicationV2DictDefault {d key fallback} {
    if {[dict exists $d $key]} {return [dict get $d $key]}
    return $fallback
}
proc ::GX::_datasetMetadataValidateKey {key} {
    if {![regexp {^[A-Za-z0-9][A-Za-z0-9._-]*$} $key]} {error {Invalid metadata key}}
}
proc ::GX::_datasetPreviewProviderContracts {raw} {
    set values [split $raw {;}]
    if {![llength $values]} {error {Empty preview contracts}}
    foreach value $values {
        if {![regexp {^[A-Za-z0-9][A-Za-z0-9_.:-]*$} $value]} {
            error {Invalid canonical Dataset contract ID}
        }
    }
    return $values
}
if {![info exists ::env(GXTXT_FRAMEWORK_ROOT)]} {
    error {Set GXTXT_FRAMEWORK_ROOT to the DEV111 framework root to run the Builder design validation}
}
set root [file join $::env(GXTXT_FRAMEWORK_ROOT) core tcl]
foreach file {ui_field_viewer_regions_v1.tcl viewer_gui_icons_v1.tcl viewer_gui_visibility_v1.tcl viewer_gui_transform_v1.tcl viewer_gui_numeric_v1.tcl viewer_gui_scientific_v1.tcl viewer_gui_plot_bindings_v1.tcl viewer_gui_plot_series_v1.tcl viewer_gui_tex_v1.tcl viewer_gui_em_v1.tcl viewer_gui_pcb_source_v1.tcl viewer_gui_scientific_netlist_v1.tcl viewer_gui_workbench_v1.tcl viewer_gui_catalog_v1.tcl viewer_gui_semantic_context_v1.tcl viewer_gui_design_v1.tcl} {
    source [file join $root $file]
}
set f [open [file join [file dirname [info script]] .. gui design.tcldict] rb]
set design [encoding convertfrom utf-8 [read $f]];close $f
if {[catch {::GX::viewerGuiDesignValidate $design} reason opts]} {
    puts "DESIGN_REFUSED: $reason"
    puts [string range [dict get $opts -errorinfo] 0 1200]
    exit 1
}
puts "DESIGN_VALIDATED_BY_PRODUCTION_CORE: [dict get $design module_id]"

proc ::GX::uiFieldNormalize {descriptor value} {return $value}
set f [open [file join [file dirname [info script]] .. gui table_design.tcldict] rb]
set design [encoding convertfrom utf-8 [read $f]];close $f
if {[catch {::GX::viewerGuiDesignValidate $design} reason opts]} {
    puts "TABLE_DESIGN_REFUSED: $reason"
    puts [string range [dict get $opts -errorinfo] 0 1200]
    exit 1
}
puts "TABLE_DESIGN_VALIDATED_BY_PRODUCTION_CORE"
