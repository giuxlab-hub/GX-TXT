# SPDX-License-Identifier: GPL-3.0-or-later
# Multi-target workflow; all profile/extrusion/Boolean geometry is Native3D.
proc ::GX::Workbench3D::extrusionTargetsForm {} {
    variable extrusionTargets;variable keepExtrusionTool;variable selection;variable model
    set ids $extrusionTargets
    if {$ids eq {}} {foreach id $selection {if {[dict exists $model objects $id]&&[dict get $model objects $id kind] eq "brep"} {lappend ids $id}}}
    set fields [dict create targets [dict create type string label {Affected B-Rep body IDs (empty uses main target)}] keep_tool [dict create type boolean label {Keep the extruded tool as a separate local body}]]
    ::GX::uiFieldFormCreate $::GX::Engine3D::window.extrusionTargets "Extrusion target settings" $fields [dict create targets $ids keep_tool $keepExtrusionTool] ::GX::Workbench3D::extrusionTargetsApply $::GX::Engine3D::window
}
proc ::GX::Workbench3D::extrusionTargetsApply {values} {
    variable model;variable extrusionTargets;variable keepExtrusionTool
    set unique {}
    foreach id [dict get $values targets] {
        if {![dict exists $model objects $id]||[dict get $model objects $id kind] ne "brep"||[dict get $model objects $id locked]} {error "Target $id must be an unlocked accepted B-Rep"}
        if {$id ni $unique} {lappend unique $id}
    }
    if {[llength $unique]>128} {error "Extrusion supports at most 128 explicit targets"}
    set extrusionTargets $unique;set keepExtrusionTool [dict get $values keep_tool]
}
proc ::GX::Workbench3D::extrudeMultiPreview {} {
    variable model;variable profile;variable profileTokens;variable distance;variable mode;variable target;variable tokens
    variable extrusionTargets;variable keepExtrusionTool;variable preview;variable scene;variable status
    if {![dict exists $profileTokens $profile]} {error "Load or select a validated closed profile"}
    if {$mode ni {new join cut intersect}} {error "Choose New, Join, Cut or Intersect"}
    set targets $extrusionTargets;if {$targets eq {}&&$mode ne "new"} {set targets [list $target]}
    if {$mode eq "new"} {set targets {}}
    set sources {}
    foreach id $targets {
        if {![dict exists $tokens $id]||[dict get $model objects $id kind] ne "brep"||[dict get $model objects $id locked]} {error "Extrusion target $id must be an unlocked B-Rep"}
        dict set sources $id [dict get $model objects $id]
    }
    set d [::GX::uiFieldNormalize {type number required 1} $distance]
    set owned {};set results {};set toolEntry {};set canceledOld 0
    try {
        set tool [call extrude [dict create profile_token [dict get $profileTokens $profile] distance $d]]
        lappend owned [dict get $tool object_token]
        if {$mode eq "new"} {
            lappend results [dict create target {} receipt $tool record [snapshotObject $tool]]
        } else {
            foreach id $targets {
                set result [call boolean [dict create base [dict get $tokens $id] tool [dict get $tool object_token] mode $mode]]
                lappend owned [dict get $result object_token]
                if {![dict get $result topology_valid]||![dict get $result closed]||![dict get $result volume_defined]||[dict get $result volume]<=0} {error "Target $id produced no valid closed positive-volume solid; all sources are unchanged"}
                lappend results [dict create target $id receipt $result record [snapshotObject $result]]
            }
            if {$keepExtrusionTool} {set toolEntry [dict create receipt $tool record [snapshotObject $tool]]} else {call delete [dict create object_token [dict get $tool object_token]];set owned [lrange $owned 1 end]}
        }
        cancelPreview;set canceledOld 1
        set prepared [dict create operation extrude_multi results $results tool $toolEntry profile_snapshot [dict get $model profiles $profile] source_snapshots $sources parameters [dict create profile_id $profile distance $d mode $mode targets $targets keep_tool $keepExtrusionTool] scope_snapshot [::GX::native3DGeometrySceneInfo $scene]]
        set i 0;foreach result $results {renderResource [dict get $result record display_geometry] operation_preview_$i [dict create base_color {1;0.6;0.1} opacity .65];incr i}
        if {$toolEntry ne {}} {renderResource [dict get $toolEntry record display_geometry] operation_preview_tool [dict create base_color {0.2;0.7;1} opacity .3]}
        set preview $prepared
        set owned {}
    } on error {message options} {
        foreach object $owned {if {[catch {call delete [dict create object_token $object]} cleanup]} {append message "; temporary extrusion cleanup failed: $cleanup"}}
        if {$canceledOld} {foreach id [::GX::viewerLayerIds viewer.3d_workbench workbench_3d] {if {[string match operation_preview_* $id]&&[catch {::GX::viewerLayerRemove viewer.3d_workbench workbench_3d $id} cleanup]} {append message "; preview presentation cleanup failed: $cleanup"}}} elseif {$preview ne {}} {append message "; previous reviewed preview retained"}
        return -options $options $message
    }
    set status "Reviewed [llength $results] extrusion result(s); all sources unchanged. Accept or Cancel preview."
    ::GX::Engine3D::rerender
}
proc ::GX::Workbench3D::cancelMultiExtrusion {} {
    variable preview;variable module;variable provider
    set failed {};set messages {}
    foreach entry [dict get $preview results] {if {[catch {call delete [dict create object_token [dict get $entry receipt object_token]]} message]} {lappend failed $entry;lappend messages $message}}
    dict set preview results $failed
    if {[dict get $preview tool] ne {}} {if {[catch {call delete [dict create object_token [dict get $preview tool receipt object_token]]} message]} {lappend messages $message} else {dict set preview tool {}}}
    if {$messages ne {}} {error "Preview cleanup failed; unreleased results remain owned for retry: [join $messages {; }]"}
    set preview {}
    foreach id [::GX::viewerLayerIds $module $provider] {if {[string match operation_preview_* $id]} {::GX::viewerLayerRemove $module $provider $id}}
}
proc ::GX::Workbench3D::acceptMultiExtrusion {} {
    variable preview;variable model;variable tokens;variable nextName;variable selection;variable panel;variable cleanupNotice
    set before $model;set priorTokens $tokens;set parameters [dict get $preview parameters];set ids {};set targets [dict get $parameters targets]
    set grouped 0;foreach id $targets {if {[dict get $before objects $id group] ne {}} {set grouped 1}}
    try {
        foreach entry [dict get $preview results] {
            set replace [dict get $entry target]
            set name [expr {$replace eq {}?$nextName:[dict get $before objects $replace name]}]
            set id [installPreparedObject [dict get $entry receipt] [dict get $entry record] $name $replace]
            set bindings [dict get $preview profile_snapshot source_bindings]
            if {$replace ne {}} {foreach binding [dict get $before objects $replace source_bindings] {if {$binding ni $bindings} {lappend bindings $binding}}}
            dict set model objects $id source_bindings $bindings
            dict set model objects $id provenance [dict create operation extrude parameters $parameters target_id $replace profile_snapshot [dict get $preview profile_snapshot] source_snapshots [dict get $preview source_snapshots]]
            lappend ids $id
        }
        if {[dict get $preview tool] ne {}} {
            set entry [dict get $preview tool];set id [installPreparedObject [dict get $entry receipt] [dict get $entry record] "$nextName — extrusion tool"]
            dict set model objects $id source_bindings [dict get $preview profile_snapshot source_bindings]
            dict set model objects $id provenance [dict create operation extrusion_tool parameters $parameters profile_snapshot [dict get $preview profile_snapshot]]
            lappend ids $id
        }
        dict for {id record} [dict get $model constraints] {if {[dict get $record object_id] in $targets} {dict set model constraints $id enabled 0;dict set model constraints $id status stale;dict set model constraints $id stale_reason {Extrusion Boolean changed target topology/frame}}}
        if {$grouped} {structuralCommit $before extrude $parameters [linsert $targets 0 [dict get $parameters profile_id]] $ids $priorTokens} else {commit $before extrude $parameters [linsert $targets 0 [dict get $parameters profile_id]] $ids}
    } on error {message options} {set model $before;set tokens $priorTokens;return -options $options $message}
    set preview {};set selection $ids
    if {!$grouped} {
        foreach id $targets {if {[catch {call delete [dict create object_token [dict get $priorTokens $id]]} cleanup]} {append cleanupNotice "previous target $id cleanup failed: $cleanup; "}}
    }
    foreach id [::GX::viewerLayerIds viewer.3d_workbench workbench_3d] {if {[string match operation_preview_* $id]} {::GX::viewerLayerRemove viewer.3d_workbench workbench_3d $id}}
    $panel.objects selection set $ids;$panel.objects see [lindex $ids 0]
    ::GX::Engine3D::rerender
}
