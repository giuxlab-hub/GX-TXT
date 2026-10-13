# SPDX-License-Identifier: GPL-3.0-or-later
# Immutable source bindings are persisted as bindings. Runtime numeric caches
# are disposable acceleration resources, not a saved second geometry authority.
proc ::GX::CurveWorkbench::_persistCurve {w record} {
    variable st
    if {[dict exists $record native]} {
        set definition [::GX::Native2D::core sketch_definition $st($w,scene) [dict get $record native]]
        if {$definition ne {}} {dict set record sketch_definition $definition}
        dict set record direction [::GX::Native2D::core direction_marker $st($w,scene) [dict get $record native]]
    }
    set saved [dict remove $record native source_token]
    if {[dict get $record source] ne {}&&![dict get $record edited]&&[dict exists $record source_request]} {
        dict set saved point_count [_pointCount $record]
        dict set saved samples {};dict set saved dataset_binding_only 1
        foreach key {geometry_resource row_resource gap_resource} {dict unset saved $key}
    }
    return $saved
}
# The saved working unit describes the Native coordinate frame, while the
# Dataset binding retains its original variables/units. Restore that explicit
# frame conversion through Native affine math before adopting a read-only actor.
proc ::GX::CurveWorkbench::_restoreSourceFrame {w record native} {
    variable st
    if {![dict exists $record working_unit]} return
    set target [dict get $record working_unit];set factors {}
    foreach axis {x y} {
        set variable [dict get $record $axis];set source [dict get [::GX::datasetVariableById [dict get $record source] $variable] unit]
        if {$source eq {}} {set source [::GX::datasetPublicationV2DictDefault [::GX::datasetPublicationV2DictDefault $record source_assumed_units {}] $variable {}]}
        if {$source eq {}} {error {The saved Dataset coordinate frame requires its explicit source-unit assumption}}
        ::GX::unitRegistryConversionPlan $source $target
        lappend factors [expr {[::GX::unitRegistryIntrinsicScale $source]/[::GX::unitRegistryIntrinsicScale $target]}]
    }
    lassign $factors fx fy
    if {$fx!=1||$fy!=1} {::GX::Native2D::core affine $st($w,scene) [list $native] [list $fx 0 0 $fy 0 0] 0}
}
proc ::GX::CurveWorkbench::_restoreDatasetBinding {w record input} {
    variable st
    set native [::GX::native2DLoadNumericRowsWithGaps $st($w,scene) [dict get $input xy_file] [dict get $input break_before_file]]
    try {
        _restoreSourceFrame $w $record $native
        # Exact source-row locators and large numeric transport reuse existing
        # document resources in memory; _persistCurve excludes these caches.
        dict set record geometry_resource [::GX::interactiveDocumentNative2DStore $st($w,document) $st($w,scene) $native]
        dict set record row_resource [::GX::interactiveDocumentResourceImportNumeric $st($w,document) [dict get $input source_rows_file] [dict create format uint64_le row_count [dict get $input row_count]]]
        dict set record gap_resource [::GX::interactiveDocumentResourceImportNumeric $st($w,document) [dict get $input break_before_file] [dict create format native2d.uint8_break_before_v1 point_count [dict get $input row_count]]]
        dict set record point_count [dict get $input row_count]
        dict set record locked 1
        return [_addRecord_backing057_base $w $record $native]
    } on error {message options} {::GX::Native2D::core delete $st($w,scene) $native;return -options $options $message}
}
rename ::GX::CurveWorkbench::_addRecord ::GX::CurveWorkbench::_addRecord_backing057_base
proc ::GX::CurveWorkbench::_addRecord {w record {native {}}} {
    variable st
    if {[dict get $record source] ne {}&&![dict get $record edited]} {dict set record locked 1}
    if {$native ne {}||![::GX::datasetPublicationV2DictDefault $record dataset_binding_only 0]} {tailcall _addRecord_backing057_base $w $record $native}
    set state [::GX::curveSourceValidateSnapshot [_session] [dict get $record source_descriptor]]
    if {![dict get $state valid]} {error "Dataset binding unavailable: [dict get $record source] ([dict get $state status]); original source is required to restore this untouched curve"}
    set source [::GX::curveSourceOpen [_session] [dict get $record source_request]]
    try {
        if {[dict get $record point_count]<=65536} {
            set exact [_sourceSamples $source [dict get $record source] [dict get $record order]]
            dict set record samples [dict get $exact samples];dict set record breaks [dict get $exact breaks]
            set native [::GX::Native2D::core add $st($w,scene) [lmap sample [dict get $record samples] {list [dict get $sample x] [dict get $sample y]}]]
            try {
                _restoreSourceFrame $w $record $native
                set samples {};foreach sample [dict get $record samples] point [::GX::Native2D::core points $st($w,scene) $native] {dict set sample x [lindex $point 0];dict set sample y [lindex $point 1];lappend samples $sample}
                dict set record samples $samples
                return [_addRecord_backing057_base $w $record $native]
            } on error {message options} {::GX::Native2D::core delete $st($w,scene) $native;return -options $options $message}
        }
        dict set record source_token $source
        set result [::GX::curveSourceWithNumericInput $source [list ::GX::CurveWorkbench::_restoreDatasetBinding $w $record]]
        set source {};return $result
    } finally {if {$source ne {}} {::GX::curveSourceClose $source}}
}

