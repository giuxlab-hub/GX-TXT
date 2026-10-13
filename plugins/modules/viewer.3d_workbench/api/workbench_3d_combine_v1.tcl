# SPDX-License-Identifier: GPL-3.0-or-later
# Workflow orchestration only: every Boolean is the public Native3D kernel.
proc ::GX::Workbench3D::combineForm {} {
    variable model;variable selection;variable scene
    set choices {};set names {}
    dict for {id record} [dict get $model objects] {
        if {[dict get $record kind] ne "brep"||[dict get $record locked]} continue
        set label "[dict get $record name] · $id";lappend choices $label;dict set names $label $id
    }
    if {[llength $choices]<2} {error "Combine requires an unlocked B-Rep target and at least one unlocked B-Rep tool"}
    set selected [lmap id $selection {if {![dict exists $model objects $id]||[dict get $model objects $id kind] ne "brep"||[dict get $model objects $id locked]} continue;set id}]
    if {![llength $selected]} {set selected [dict values $names]}
    set target [lindex $selected 0];set label {}
    dict for {name id} $names {if {$id eq $target} {set label $name;break}}
    set tools [lrange $selected 1 end]
    if {$tools eq {}} {foreach id [dict values $names] {if {$id ne $target} {set tools [list $id];break}}}
    set fields [dict create target [dict create type choice label {Target body} values $choices] tools [dict create type string label {Tool body IDs (from selected tree rows)} required 1] mode [dict create type choice label {Boolean operation} values {Join Cut Intersect}] result_policy [dict create type choice label {Accepted result} values {{New derived body} {Replace target}}] keep_tools [dict create type boolean label {Keep tool bodies} default 1]]
    set initial [dict create target $label tools $tools mode Join result_policy {New derived body} keep_tools 1]
    ::GX::uiFieldFormCreate $::GX::Engine3D::window.combine "Preview B-Rep Combine" $fields $initial [list ::GX::Workbench3D::combinePreviewApply [::GX::native3DGeometrySceneInfo $scene] $names] $::GX::Engine3D::window
}
proc ::GX::Workbench3D::combinePreviewApply {captured names values} {
    variable scene;variable model;variable tokens;variable preview;variable status
    if {[::GX::native3DGeometrySceneInfo $scene] ne $captured} {error "Geometry document changed; reopen Combine"}
    set target [dict get $names [dict get $values target]];set tools [dict get $values tools]
    if {![llength $tools]||[llength $tools]>128} {error "Select 1–128 explicit tool bodies"}
    set unique {};foreach id $tools {if {$id ni $unique} {lappend unique $id}};set tools $unique
    foreach id [linsert $tools 0 $target] {
        if {![dict exists $model objects $id]||[dict get $model objects $id kind] ne "brep"||[dict get $model objects $id locked]} {error "Combine target/tool $id must be an unlocked B-Rep solid"}
        set info [call describe [dict create object_token [dict get $tokens $id]]]
        if {![dict get $info topology_valid]||![dict get $info closed]||![dict get $info volume_defined]} {error "Combine target/tool $id is not a validated closed solid"}
    }
    if {$target in $tools} {error "The target cannot also be a tool"}
    set mode [string tolower [dict get $values mode]];set resultToken {};set result {};set owned {}
    try {
        set base [dict get $tokens $target]
        foreach id $tools {
            set next [call boolean [dict create base $base tool [dict get $tokens $id] mode $mode]]
            set nextToken [dict get $next object_token]
            lappend owned $nextToken
            if {$resultToken ne {}} {call delete [dict create object_token $resultToken];set owned [lreplace $owned [lsearch -exact $owned $resultToken] [lsearch -exact $owned $resultToken]]}
            set result $next;set resultToken $nextToken;set base $nextToken
        }
        if {![dict get $result topology_valid]||![dict get $result closed]||![dict get $result volume_defined]||[dict get $result volume]<=0} {error "Combine produced no valid closed solid; source bodies are unchanged"}
        set record [snapshotObject $result]
        set snapshots {};foreach id [linsert $tools 0 $target] {dict set snapshots $id [dict get $model objects $id]}
        cancelPreview
        set parameters [dict create target $target tools $tools mode $mode result_policy [dict get $values result_policy] keep_tools [dict get $values keep_tools]]
        set preview [dict create operation combine receipt $result record $record source_snapshots $snapshots parameters $parameters scope_snapshot [::GX::native3DGeometrySceneInfo $scene]]
        renderResource [dict get $record display_geometry] operation_preview [dict create base_color {1;0.6;0.1} opacity .65]
        set owned {}
    } on error {message options} {
        foreach token $owned {if {[catch {call delete [dict create object_token $token]} cleanup]} {append message "; temporary Boolean cleanup failed: $cleanup"}}
        if {$preview ne {}} {append message "; the previous reviewed preview is retained"}
        return -options $options $message
    }
    set status "Reviewed $mode preview; source bodies unchanged. Use Accept preview or Cancel preview."
    ::GX::Engine3D::rerender
}
proc ::GX::Workbench3D::acceptCombinePreview {} {
    variable preview;variable model;variable tokens;variable nextName;variable selection;variable panel
    set before $model;set priorTokens $tokens;set parameters [dict get $preview parameters]
    set target [dict get $parameters target];set tools [dict get $parameters tools]
    set replace [expr {[dict get $parameters result_policy] eq "Replace target" ? $target : {}}]
    set removed {};set sources [dict get $preview source_snapshots]
    try {
        set id [installPreparedObject [dict get $preview receipt] [dict get $preview record] $nextName $replace]
        set bindings {};dict for {source record} $sources {foreach binding [dict get $record source_bindings] {if {$binding ni $bindings} {lappend bindings $binding}}}
        dict set model objects $id source_bindings $bindings
        dict set model objects $id provenance [dict create operation combine parameters $parameters source_snapshots $sources kernel NATIVE_3D_GEOMETRY_API_v1]
        if {![dict get $parameters keep_tools]} {
            foreach tool $tools {dict unset model objects $tool;dict unset tokens $tool;lappend removed $tool}
            dict for {constraint record} [dict get $model constraints] {
                if {[dict get $record object_id] in $removed} {dict set model constraints $constraint enabled 0;dict set model constraints $constraint status missing;dict set model constraints $constraint stale_reason {Combine removed the referenced tool body}}
            }
            dict for {group record} [dict get $model groups] {
                set members [lmap member [dict get $record members] {if {$member in $removed} continue;set member}]
                if {$members eq {}} {dict unset model groups $group} else {dict set model groups $group members $members}
            }
        }
        if {$replace ne {}} {
            # Boolean topology/frame changes invalidate previously attached
            # constraints until the user explicitly reviews their definition.
            dict for {constraint record} [dict get $model constraints] {
                if {[dict get $record object_id] eq $replace} {dict set model constraints $constraint enabled 0;dict set model constraints $constraint status stale;dict set model constraints $constraint stale_reason {Boolean changed target topology/frame}}
            }
        }
        if {$replace ne {}||$removed ne {}} {structuralCommit $before combine $parameters [linsert $tools 0 $target] [list $id] $priorTokens} else {commit $before combine $parameters [linsert $tools 0 $target] [list $id]}
    } on error {message options} {set model $before;set tokens $priorTokens;return -options $options $message}
    set preview {};set selection [list $id]
    $panel.objects selection set $id;$panel.objects see $id
    if {"operation_preview" in [::GX::viewerLayerIds viewer.3d_workbench workbench_3d]} {::GX::viewerLayerRemove viewer.3d_workbench workbench_3d operation_preview}
    ::GX::Engine3D::rerender
}
