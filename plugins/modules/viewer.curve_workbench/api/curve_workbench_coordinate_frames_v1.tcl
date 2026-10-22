# SPDX-License-Identifier: GPL-3.0-or-later
# Native working frames are Workspace state. Canonical Dataset bindings remain
# immutable, and CORE owns every physical conversion and affine operation.
proc ::GX::CurveWorkbench::_coordinateConfigurationDefault {} {
    return {schema gxtxt.coordinate_configuration.v1 x_unit mm y_unit mm allow_heterogeneous 0}
}
proc ::GX::CurveWorkbench::_coordinateDimensions {units {relations {}}} {
    set dimensions {}
    set frame [::GX::_native2DCoordinateFrame $units $relations]
    foreach axis {x y} unit $units {
        if {[dict exists $frame coordinate_relations $axis canonical_unit]} {set unit [dict get $frame coordinate_relations $axis canonical_unit]}
        if {$unit eq {}} {lappend dimensions 1;continue}
        set definition [::GX::unitRegistryDefinition $unit]
        set canonical [dict get $definition canonical_unit]
        if {$canonical eq {}} {set canonical $unit}
        lappend dimensions [::GX::unitTclDimensionKey $canonical]
    }
    return $dimensions
}
proc ::GX::CurveWorkbench::_coordinateConfigurationNormalize {settings {relations {}}} {
    set settings [dict merge [_coordinateConfigurationDefault] $settings]
    foreach field [dict keys $settings] {if {$field ni {schema x_unit y_unit allow_heterogeneous}} {error "Unknown coordinate Configuration field: $field"}}
    if {[dict get $settings schema] ne {gxtxt.coordinate_configuration.v1}} {error {Unsupported coordinate Configuration schema}}
    set units [list [dict get $settings x_unit] [dict get $settings y_unit]]
    set allow [::GX::uiFieldNormalize {type boolean} [dict get $settings allow_heterogeneous]]
    set dimensions [_coordinateDimensions $units $relations]
    if {!$allow && [lindex $dimensions 0] ne [lindex $dimensions 1]} {return -code error -errorcode {GX COORDINATE HETEROGENEOUS_CONSENT_REQUIRED} {Axes have different physical dimensions. Enable Allow dimensionally heterogeneous axes explicitly in Workspace Configuration before using this frame.}}
    dict set settings allow_heterogeneous $allow
    return $settings
}
proc ::GX::CurveWorkbench::_coordinateWorkspaceEmpty {w} {
    variable st
    foreach field {curves images sketchFragments} {if {[info exists st($w,$field)] && [dict size $st($w,$field)]} {return 0}}
    return 1
}
proc ::GX::CurveWorkbench::_coordinateAxesAdmit {w units {relations {}}} {
    variable st
    set settings $st($w,coordinateConfiguration)
    dict set settings x_unit [lindex $units 0];dict set settings y_unit [lindex $units 1]
    _coordinateConfigurationNormalize $settings $relations
}
proc ::GX::CurveWorkbench::_coordinateConfigurationFields {} {
    return {x_unit {type string label {X stored coordinate unit (1 = dimensionless; empty = numeric)}} y_unit {type string label {Y stored coordinate unit (1 = dimensionless; empty = numeric)}} allow_heterogeneous {type boolean label {Allow dimensionally heterogeneous axes}}}
}
proc ::GX::CurveWorkbench::_coordinateConfigurationOpen {w} {
    variable st
    set st($w,coordinateConfigurationDraft) [_cadState $w]
    ::GX::uiFieldFormCreate $w.coordinateConfiguration {Workspace Configuration — physical axes} [_coordinateConfigurationFields] [dict remove $st($w,coordinateConfiguration) schema] [list ::GX::CurveWorkbench::_coordinateConfigurationApply $w $st($w,token)] $w
    ttk::label $w.coordinateConfiguration.note -text {Units define physical dimensions through the public Unit Registry. X and Y are homogeneous by default. Heterogeneous axes are an explicit scientific choice; distances and areas need compatible dimensions. Display units and zoom prefixes are presentation only. Stored units can change here only while the workspace contains no geometry; existing geometry requires an explicit conversion.} -wraplength 580
    pack $w.coordinateConfiguration.note -fill x -padx 10 -pady 8
}
proc ::GX::CurveWorkbench::_coordinateConfigurationApply {w token values} {
    variable st
    if {$token ne [::GX::interactiveDocumentSessionToken] || $token ne $st($w,token) || $st($w,coordinateConfigurationDraft) ne [_cadState $w]} {error {Workspace changed; reopen Configuration}}
    set relations {}
    if {$st($w,active) ne {}&&[dict exists $st($w,curves) $st($w,active)]} {
        set record [_record $w $st($w,active)]
        if {[list [dict get $values x_unit] [dict get $values y_unit]] eq [_coordinateUnits $record]} {set relations [_coordinateSourceRelations $record]}
    }
    set next [_coordinateConfigurationNormalize $values $relations]
    foreach field {x_unit y_unit} {if {![_coordinateWorkspaceEmpty $w] && [dict get $next $field] ne [dict get $st($w,coordinateConfiguration) $field]} {error {Configuration cannot reinterpret existing geometry; use an explicit working-coordinate conversion}}}
    if {![dict get $next allow_heterogeneous]} {dict for {id record} $st($w,curves) {set dimensions [_coordinateDimensions [_coordinateUnits $record] [_coordinateSourceRelations $record]];if {[lindex $dimensions 0] ne [lindex $dimensions 1]} {error {Existing heterogeneous geometry requires the explicit policy to remain enabled}}}}
    set before [_snapshotIds $w {}];set undo $st($w,undo);set redo $st($w,redo)
    try {
        set st($w,coordinateConfiguration) $next
        set st($w,sketchUnit) [dict get $next x_unit]
        _history $w $before {}
        _draw $w;_save $w
    } on error {message options} {_restoreSnapshot $w $before;set st($w,undo) $undo;set st($w,redo) $redo;return -options $options $message}
    set st($w,coordinateConfigurationDraft) [_cadState $w]
}
proc ::GX::CurveWorkbench::_coordinateSourceRelations {record} {
    if {[dict exists $record coordinate_relations]} {return [dict get $record coordinate_relations]}
    if {[dict exists $record coordinate_conversions]} {return {}}
    if {![dict exists $record source_descriptor]} {return {}}
    return [dict get [::GX::_native2DCoordinateFrame [_coordinateUnits $record] [::GX::native2DSourceCoordinateRelations [dict get $record source_descriptor] [dict get $record x] [dict get $record y]]] coordinate_relations]
}
proc ::GX::CurveWorkbench::_coordinateFrameKey {record} {
    return [list [_coordinateUnits $record] [_coordinateSourceRelations $record]]
}
proc ::GX::CurveWorkbench::_coordinateInFrame {w record} {
    variable st
    if {$st($w,active) eq {}||![dict exists $st($w,curves) $st($w,active)]} {return 1}
    return [expr {[_coordinateFrameKey $record] eq [_coordinateFrameKey [_record $w $st($w,active)]]}]
}
proc ::GX::CurveWorkbench::_coordinateRequireFrame {w ids} {
    foreach id $ids {if {![_coordinateInFrame $w [_record $w $id]]} {error {The selection spans different coordinate frames; select one frame or explicitly align compatible Dataset axes first}}}
}
proc ::GX::CurveWorkbench::_coordinatePlaneAdmit {w ids} {
    _coordinateRequireFrame $w $ids
    set frame {}
    foreach id $ids {
        set record [_record $w $id];set key [_coordinateFrameKey $record]
        if {$frame ne {}&&$key ne $frame} {error {The selection spans different complete coordinate frames}}
        set frame $key;_coordinateAxesAdmit $w [_coordinateUnits $record] [_coordinateSourceRelations $record]
    }
    return $frame
}
proc ::GX::CurveWorkbench::_coordinateRetainFrame {w record parents} {
    if {$parents eq {}} {return $record}
    set parent [_record $w [lindex $parents 0]];set frame [_coordinateFrameKey $parent]
    foreach id [lrange $parents 1 end] {if {[_coordinateFrameKey [_record $w $id]] ne $frame} {error {Derived geometry requires the same complete coordinate frame across its parents}}}
    dict set record coordinate_units [_coordinateUnits $parent]
    dict set record coordinate_relations [_coordinateSourceRelations $parent]
    set cache [_coordinateContext $w [lindex $parents 0]]
    if {[dict get $cache reason] ne {}} {error [dict get $cache reason]}
    set snapshot [dict get $cache context]
    if {$snapshot ne {}} {
        set variables {};set assumptions {};set mapping {}
        foreach axis {x y} {
            set original [_coordinateSnapshotVariable $parent $axis]
            dict set mapping $axis $original
            dict set variables $original [dict get $snapshot variables $original]
            if {[dict exists $parent source_assumed_units $original]} {dict set assumptions $original [dict get $parent source_assumed_units $original]}
            if {[dict exists $parent source_${axis}_name]} {dict set record source_${axis}_name [dict get $parent source_${axis}_name]}
        }
        dict set snapshot variables $variables
        dict set record coordinate_snapshot $snapshot
        dict set record coordinate_snapshot_variables $mapping
        if {$assumptions ne {}} {dict set record source_assumed_units $assumptions}
        if {[dict exists $parent coordinate_conversions]} {dict set record coordinate_conversions [dict get $parent coordinate_conversions]}
        _coordinateSnapshotValidate $record
    }
    return $record
}
proc ::GX::CurveWorkbench::_coordinateSnapshotVariable {record axis} {
    if {[dict exists $record coordinate_snapshot_variables $axis]} {return [dict get $record coordinate_snapshot_variables $axis]}
    return [dict get $record $axis]
}
proc ::GX::CurveWorkbench::_coordinateSnapshotValidate {record} {
    set relations [_coordinateSourceRelations $record]
    if {![dict exists $record coordinate_snapshot]} {
        if {$relations ne {}} {error {Retained nondefault coordinate relations require their frozen source snapshot}}
        return {}
    }
    set snapshot [dict get $record coordinate_snapshot]
    set assumptions [::GX::datasetPublicationV2DictDefault $record source_assumed_units {}]
    foreach axis {x y} unit [_coordinateUnits $record] index {0 1} {
        set vid [_coordinateSnapshotVariable $record $axis];set options [dict create unit $unit]
        if {[dict exists $assumptions $vid]} {dict set options source_unit_assumption [dict get $assumptions $vid]}
        # Validate through the existing snapshot owner, retaining original
        # Dataset identity/schema and any explicit undeclared-source meaning.
        ::GX::datasetCoordinateSnapshotValues $snapshot $vid {} $options
        set source [dict get $snapshot variables $vid source];set sourceUnit [dict get $source unit]
        if {[dict exists $assumptions $vid]} {
            set sourceUnit [dict get $assumptions $vid]
            set source [dict merge $source [::GX::unitRegistryDefinition $sourceUnit]]
            dict set source unit $sourceUnit
        }
        set sourceFrame [::GX::_native2DCoordinateFrame [lrepeat 2 $sourceUnit] [dict create x [dict remove [::GX::_native2DCoordinateVariableSchema $source] unit]]]
        set sourceRelation [::GX::datasetPublicationV2DictDefault [dict get $sourceFrame coordinate_relations] x {}]
        set expected [::GX::datasetPublicationV2DictDefault $relations $axis {}]
        if {$unit eq $sourceUnit} {
            if {$sourceRelation ne $expected} {error {Frozen coordinate snapshot contradicts the retained axis relation}}
            continue
        }
        if {$sourceRelation ne {}||$expected ne {}} {error {Normalize custom source relations explicitly before retaining a converted frame}}
        set current $sourceUnit
        foreach conversion [::GX::datasetPublicationV2DictDefault $record coordinate_conversions {}] {
            if {[dict exists $conversion source_units]} {
                set from [lindex [dict get $conversion source_units] $index];set to [lindex [dict get $conversion target_units] $index]
            } elseif {[dict exists $conversion source_unit]} {
                set from [dict get $conversion source_unit];set to [dict get $conversion target_unit]
            } else {error {Unknown retained coordinate conversion receipt}}
            if {$from ne $current} {error {Retained coordinate conversion chain does not match its frozen source}}
            set plan [::GX::unitRegistryAffinePlan $from $to]
            if {![dict get $plan affine]||[dict get $plan scale]<=0} {error {Retained coordinate conversion must use a positive affine public plan}}
            if {[dict exists $conversion source_units]} {
                set matrix [dict get $conversion matrix]
                if {[llength $matrix]!=6||[lindex $matrix 1]!=0||[lindex $matrix 2]!=0} {error {Coordinate conversion receipt is not a per-axis affine plan}}
                set scale [::GX::uiFieldNormalize {type number} [lindex $matrix [expr {$index==0?0:3}]]]
                set offset [::GX::uiFieldNormalize {type number} [lindex $matrix [expr {$index+4}]]]
            } else {
                set scale [::GX::uiFieldNormalize {type number} [dict get $conversion factor]];set offset 0
            }
            if {abs($scale-[dict get $plan scale])>1e-12*max(1,abs([dict get $plan scale]))||abs($offset-[dict get $plan offset])>1e-12*max(1,abs([dict get $plan offset]))} {error {Retained coordinate conversion contradicts the public Unit Registry plan}}
            set current $to
        }
        if {$current ne $unit} {error {Retained native units lack their explicit source conversion receipt}}
        ::GX::datasetCoordinateSnapshotAffinePlan $snapshot $vid $unit $options
    }
    return $snapshot
}
proc ::GX::CurveWorkbench::_coordinateSourceFrame {w record} {
    variable st
    set units [_coordinateUnits $record]
    _coordinateAxesAdmit $w $units [_coordinateSourceRelations $record]
    if {[_coordinateWorkspaceEmpty $w]} {return $units}
    set configured $st($w,coordinateConfiguration)
    set target [list [dict get $configured x_unit] [dict get $configured y_unit]]
    set existingRelations {}
    if {[dict size $st($w,curves)]} {
        set reference $st($w,active)
        if {$reference eq {}||![dict exists $st($w,curves) $reference]} {set reference [lindex [dict keys $st($w,curves)] 0]}
        set existingRelations [_coordinateSourceRelations [_record $w $reference]]
    }
    if {$units eq $target} {
        if {[_coordinateSourceRelations $record] ne $existingRelations} {error {Equal unit symbols have different frozen coordinate relations; explicitly normalize the Dataset before joining this workspace frame}}
        return $units
    }
    if {{} in $units || {} in $target} {error {Import cannot reinterpret numeric coordinates in a populated physical workspace; create a new workspace or explicitly declare the source meaning}}
    if {[_coordinateSourceRelations $record] ne {}||$existingRelations ne {}} {error {Normalize variable-specific source relations explicitly before importing into a populated frame}}
    ::GX::native2DComparisonFrame x $units $units [dict create output_units $target]
    return $target
}
proc ::GX::CurveWorkbench::_coordinateNormalizeSource {w id target} {
    variable st
    set record [_record $w $id];set source [_coordinateUnits $record]
    if {$source eq $target} {return {}}
    if {[dict get $record source] eq {}||[dict get $record edited]} {error {Axis alignment requires an untouched Dataset binding}}
    if {[_coordinateSourceRelations $record] ne {}} {error {Variable-specific coordinate relations require explicit Dataset Transform normalization before frame alignment}}
    set plan [::GX::native2DComparisonFrame x $source $source [dict create output_units $target]]
    set matrix [dict get $plan reference_matrix];set native [dict get $record native]
    set locked [dict get $record locked]
    ::GX::Native2D::core locked $st($w,scene) $native 0
    try {
        lassign $matrix a b c d tx ty
        if {$a!=1||$b!=0||$c!=0||$d!=1||$tx!=0||$ty!=0} {::GX::Native2D::core affine $st($w,scene) [list $native] $matrix 0}
    } finally {::GX::Native2D::core locked $st($w,scene) $native $locked}
    if {[_bulkRecord $record]} {
        dict set record geometry_resource [::GX::interactiveDocumentNative2DStore $st($w,document) $st($w,scene) $native]
    } else {
        _syncSamples $w $id;set record [_record $w $id];dict set record edited 0
    }
    dict unset record working_unit
    dict set record coordinate_units $target
    dict lappend record coordinate_conversions [dict create schema_version 1 operation align_dataset_axes source_units $source target_units $target matrix $matrix source_dataset_modified 0]
    dict set st($w,curves) $id $record
    dict unset st($w,coordinateCache) $id
    return $plan
}
proc ::GX::CurveWorkbench::_coordinateFrameSync {w {restoreView 1}} {
    variable st
    if {$st($w,active) eq {}||![dict exists $st($w,curves) $st($w,active)]} {return 0}
    set key [_coordinateFrameKey [_record $w $st($w,active)]]
    set previous {};if {[info exists st($w,coordinateFrameKey)]} {set previous $st($w,coordinateFrameKey)}
    set changed [expr {$previous ne $key}]
    if {$changed&&$previous ne {}} {
        dict set st($w,coordinateFrameViews) $previous [dict create view [::GX::Native2D::core view_requested $st($w,scene)] presentation [::GX::Native2D::core presentation $st($w,scene)] coordinate_view $st($w,coordinateView)]
    }
    set st($w,coordinateFrameKey) $key
    set st($w,sketchUnit) [lindex [_coordinateUnits [_record $w $st($w,active)]] 0]
    dict for {id record} $st($w,curves) {
        set visible [expr {[dict get $record visible]&&[_coordinateInFrame $w $record]}]
        ::GX::Native2D::core visible $st($w,scene) [dict get $record native] $visible
    }
    if {$restoreView&&$changed&&$previous ne {}} {
        if {[dict exists $st($w,coordinateFrameViews) $key]} {
            set saved [dict get $st($w,coordinateFrameViews) $key]
            ::GX::Native2D::core presentation $st($w,scene) [dict get $saved presentation]
            ::GX::Native2D::core view $st($w,scene) [dict get $saved view]
            set st($w,coordinateView) [dict get $saved coordinate_view]
            _coordinateMagnify $w 0
        } else {
            ::GX::Native2D::core fit $st($w,scene)
            _coordinateMagnify $w 1
        }
    }
    return $changed
}
proc ::GX::CurveWorkbench::_coordinateAlignOpen {w} {
    variable st
    set id [_active $w];set record [_record $w $id]
    if {[dict get $record source] eq {}||[dict get $record edited]} {error {Select an untouched Dataset source to align its working axes}}
    if {[_coordinateSourceRelations $record] ne {}} {error {Normalize variable-specific relations through Dataset Transform first}}
    set fields {};set values {}
    foreach axis {x y} unit [_coordinateUnits $record] {
        if {$unit eq {}} {error {Declare missing units through Dataset Variables before aligning this source}}
        set choices [list $unit]
        foreach candidate [::GX::unitSelectorCandidates] {
            if {![catch {set plan [::GX::unitRegistryAffinePlan $unit $candidate]}]&&[dict get $plan affine]&&[dict get $plan scale]>0} {lappend choices $candidate}
        }
        dict set fields $axis [dict create type choice label "[string toupper $axis] Native working unit" values [lsort -unique $choices]]
        dict set values $axis $unit
    }
    set st($w,coordinateAlignKey) [_coordinateKey $w $id]
    ::GX::uiFieldFormCreate $w.alignaxes {Align Dataset working axes} $fields $values [list ::GX::CurveWorkbench::_coordinateAlignApply $w $st($w,token) $id] $w
    ttk::label $w.alignaxes.note -text {This converts the Workspace's Native coordinates and records the frame. Original Dataset values, units and IDs remain unchanged. Matching working axes can share a viewport. Display units and calibration remain separate.} -wraplength 580
    pack $w.alignaxes.note -side top -fill x -before $w.alignaxes.viewport -padx 10 -pady 8
}
proc ::GX::CurveWorkbench::_coordinateAlignApply {w token id values} {
    variable st
    if {$token ne [::GX::interactiveDocumentSessionToken]||$token ne $st($w,token)||$id ne $st($w,active)||$st($w,coordinateAlignKey) ne [_coordinateKey $w $id]} {error {Source or coordinate context changed; reopen axis alignment}}
    set before [_snapshotIds $w [list $id]];set oldUndo $st($w,undo);set oldRedo $st($w,redo)
    try {
        _coordinateNormalizeSource $w $id [list [dict get $values x] [dict get $values y]]
        _coordinateFrameSync $w 0
        _selectionScene $w;::GX::Native2D::core fit $st($w,scene);_coordinateMagnify $w 1
        _history $w $before [list $id]
    } on error {message options} {_restoreSnapshot $w $before;set st($w,undo) $oldUndo;set st($w,redo) $oldRedo;return -options $options $message}
    set st($w,coordinateAlignKey) [_coordinateKey $w $id]
    _curveList $w;_pointList $w;_draw $w;_save $w
}
