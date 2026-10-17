# SPDX-License-Identifier: GPL-3.0-or-later
# SCRIPT_JOB_API_v1 view preferences, owned by existing user Configuration.
# Neither hidden IDs nor named layouts alter the durable Job journal.
proc ::GX::scriptJobViewColumns {} {return {reference language version revision state started finished duration session jobid}}
proc ::GX::scriptJobViewDefault {} {
    return [dict create scope all filter All show_hidden 0 sort created descending 1 columns [scriptJobViewColumns] widths {} geometry 1280x760 pane 0.5 xscroll 0 yscroll 0 selected {}]
}
proc ::GX::scriptJobViewValidate {value} {
    set defaults [scriptJobViewDefault]
    dict for {key unused} $value {if {![dict exists $defaults $key]} {error "Unknown Runner view field: $key"}}
    set value [dict merge $defaults $value]
    if {[dict get $value scope] ne "all" && ([file pathtype [dict get $value scope]] ne "absolute" || [regexp {[\r\n]} [dict get $value scope]])} {error {Runner scope requires all or an absolute Session path}}
    if {[dict get $value filter] ni {All Active Finished Failed Hidden}} {error {Invalid Runner state filter}}
    if {[dict get $value sort] ni {created name reference language version revision state started finished duration session jobid}} {error {Invalid Runner sort column}}
    foreach field {show_hidden descending} {
        if {![string is boolean -strict [dict get $value $field]]} {error "Invalid Runner boolean: $field"}
        dict set value $field [expr {[dict get $value $field] ? 1 : 0}]
    }
    foreach column [dict get $value columns] {if {$column ni [scriptJobViewColumns]} {error "Unknown Runner column: $column"}}
    if {[llength [dict get $value columns]] != [llength [lsort -unique [dict get $value columns]]]} {error {Duplicate Runner columns}}
    dict for {column width} [dict get $value widths] {
        if {$column ni [concat {#0} [scriptJobViewColumns]] || ![string is integer -strict $width] || $width<30 || $width>3000} {error {Invalid Runner column width}}
    }
    if {![regexp {^([0-9]{3,4})x([0-9]{3,4})([+-][0-9]{1,5}[+-][0-9]{1,5})?$} [dict get $value geometry]]} {error {Invalid Runner window geometry}}
    foreach field {pane xscroll yscroll} {
        set number [dict get $value $field]
        if {![string is double -strict $number] || [catch {expr {$number>=0 && $number<=1}} finite] || !$finite} {error "Invalid Runner layout fraction: $field"}
    }
    if {[dict get $value selected] ne {}} {scriptJobPresentationId [dict get $value selected]}
    return $value
}
proc ::GX::scriptJobPresentationId {id} {
    if {![regexp {^[A-Za-z0-9][A-Za-z0-9_.-]{0,191}$} $id]} {error {Invalid immutable Job ID}}
    return $id
}
proc ::GX::scriptJobPresentationDefault {} {return [dict create schema 1 hidden_ids {} workspaces {} current_id {} last_view [scriptJobViewDefault]]}
proc ::GX::scriptJobPresentationValidate {value} {
    if {[string bytelength $value]>2097152 || [catch {dict size $value}]} {error {Runner presentation must be a bounded dictionary}}
    set defaults [scriptJobPresentationDefault]
    dict for {key unused} $value {if {![dict exists $defaults $key]} {error "Unknown Runner presentation field: $key"}}
    set value [dict merge $defaults $value]
    if {[dict get $value schema] ne "1"} {error {Unsupported Runner presentation version}}
    set ids [lsort -unique [dict get $value hidden_ids]]
    if {[llength $ids]>20000} {error {Runner hidden filter exceeds 20000 IDs}}
    foreach id $ids {scriptJobPresentationId $id}
    dict set value hidden_ids $ids
    if {[dict size [dict get $value workspaces]]>128} {error {Runner workspace limit is 128}}
    set names {}
    dict for {id workspace} [dict get $value workspaces] {
        scriptJobPresentationId $id
        if {[lsort [dict keys $workspace]] ne {name view}} {error {Runner workspace contains non-view state}}
        set name [string trim [dict get $workspace name]]
        if {$name eq {} || [string length $name]>160 || [regexp {[\r\n]} $name] || $name in $names} {error {Runner workspace names must be unique single-line names of 1..160 characters}}
        lappend names $name
        dict set value workspaces $id [dict create name $name view [scriptJobViewValidate [dict get $workspace view]]]
    }
    if {[dict get $value current_id] ne {} && ![dict exists $value workspaces [dict get $value current_id]]} {dict set value current_id {}}
    dict set value last_view [scriptJobViewValidate [dict get $value last_view]]
    return $value
}
proc ::GX::scriptJobPresentationGet {} {
    configurationRegister scripts.job_presentation [dict create group {Runner view} label {Runner view preferences} type string default [scriptJobPresentationDefault] scope user validator ::GX::scriptJobPresentationValidate]
    return [scriptJobPresentationValidate [configurationGet scripts.job_presentation]]
}
proc ::GX::scriptJobPresentationCommit {value} {
    set before [scriptJobPresentationGet]
    set value [scriptJobPresentationValidate $value]
    configurationSet scripts.job_presentation $value
    if {[catch {configurationSave {scripts.job_presentation} 0} failure options]} {
        configurationSet scripts.job_presentation $before
        return -options $options $failure
    }
    return $value
}
proc ::GX::scriptJobViewRequest {view {offset 0}} {
    set view [scriptJobViewValidate $view]
    if {![string is integer -strict $offset] || $offset<0} {error {Invalid Runner page offset}}
    return [dict merge $view [dict create hidden_ids [dict get [scriptJobPresentationGet] hidden_ids] offset $offset limit 500]]
}
proc ::GX::scriptJobPresentationCall {operation request} {
    set rc [catch {exec {*}[scriptJobCommand $operation] << $request} response]
    if {[catch {dict get $response ok} ok]} {error $response}
    if {!$ok} {error [dict get $response error]}
    return [dict get $response result]
}
proc ::GX::scriptJobViewList {view {offset 0}} {return [scriptJobPresentationCall view_list [scriptJobViewRequest $view $offset]]}
proc ::GX::scriptJobHistoryHide {ids} {
    set ids [lsort -unique $ids]
    foreach id $ids {scriptJobPresentationId $id}
    # One authoritative read validates every requested ID/state before mutation.
    scriptJobPresentationCall history_validate [dict create ids $ids]
    set preferences [scriptJobPresentationGet]
    dict set preferences hidden_ids [lsort -unique [concat [dict get $preferences hidden_ids] $ids]]
    scriptJobPresentationCommit $preferences
    return $ids
}
proc ::GX::scriptJobHistoryRestore {ids} {
    set preferences [scriptJobPresentationGet];set hidden [dict get $preferences hidden_ids]
    foreach id $ids {
        scriptJobPresentationId $id
        if {$id ni $hidden} {error "Job is not hidden: $id"}
    }
    dict set preferences hidden_ids [lmap id $hidden {if {$id in $ids} continue;set id}]
    scriptJobPresentationCommit $preferences
    return $ids
}
proc ::GX::scriptJobHistoryCandidates {view} {
    set request [scriptJobViewRequest $view]
    return [scriptJobPresentationCall history_candidates $request]
}
proc ::GX::scriptJobWorkspaceSave {id name view} {
    set preferences [scriptJobPresentationGet]
    if {$id eq {}} {set id view_[pid]_[clock microseconds]} elseif {![dict exists $preferences workspaces $id]} {error {Runner workspace is unavailable}}
    dict set preferences workspaces $id [dict create name $name view [scriptJobViewValidate $view]]
    dict set preferences current_id $id;dict set preferences last_view $view
    scriptJobPresentationCommit $preferences
    return $id
}
proc ::GX::scriptJobWorkspaceRename {id name} {
    set preferences [scriptJobPresentationGet]
    if {![dict exists $preferences workspaces $id]} {error {Runner workspace is unavailable}}
    dict set preferences workspaces $id name $name
    scriptJobPresentationCommit $preferences
    return $id
}
proc ::GX::scriptJobWorkspaceDelete {id} {
    set preferences [scriptJobPresentationGet]
    if {![dict exists $preferences workspaces $id]} {error {Runner workspace is unavailable}}
    dict unset preferences workspaces $id
    if {[dict get $preferences current_id] eq $id} {dict set preferences current_id {}}
    scriptJobPresentationCommit $preferences
}
proc ::GX::scriptJobWorkspaceOpen {id} {
    set preferences [scriptJobPresentationGet]
    if {![dict exists $preferences workspaces $id]} {error {Runner workspace is unavailable}}
    set view [dict get $preferences workspaces $id view]
    dict set preferences current_id $id;dict set preferences last_view $view
    scriptJobPresentationCommit $preferences
    return $view
}
proc ::GX::scriptJobViewRemember {view {id {}}} {
    set preferences [scriptJobPresentationGet]
    if {$id ne {} && ![dict exists $preferences workspaces $id]} {error {Runner workspace is unavailable}}
    dict set preferences current_id $id;dict set preferences last_view [scriptJobViewValidate $view]
    scriptJobPresentationCommit $preferences
}
