# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::sessionStorageProfilesPath {{session {}}} {
    if {$session eq {}} {set session $::GX::currentSession}
    if {$session eq {} || ![file isdirectory [file join $session metadata]]} {error {Open a valid Session to manage private Storage Profiles.}}
    return [file join [file normalize $session] metadata storage_profiles.ini]
}
proc ::GX::sessionStorageProfilesRead {{session {}}} {
    set path [sessionStorageProfilesPath $session]
    if {![file exists $path]} {return [dict create version 1 active {} profiles {}]}
    set data [parseIni $path]
    set profiles [datasetPublicationV2DictDefault $data storage_profiles.profiles {}]
    set active [datasetPublicationV2DictDefault $data storage_profiles.active {}]
    if {[catch {dict size $profiles}] || ($active ne {} && ![dict exists $profiles $active])} {error {Invalid Session Storage Profiles registry.}}
    dict for {name values} $profiles {sessionStorageProfileValidate $name $values}
    return [dict create version 1 active $active profiles $profiles]
}
proc ::GX::sessionStorageProfileValidate {name values} {
    if {![regexp {^[A-Za-z0-9_.-]+$} $name]} {error {Profile name may contain letters, digits, '.', '_' and '-'.}}
    dict for {role path} $values {
        workspaceValidateRole $role
        if {[regexp {[\r\n]} $path]} {error {Directory paths must be single-line.}}
        if {[string match @session/* $path]} {
            set rel [string range $path 9 end]
            if {[file pathtype $rel] ne {relative} || {..} in [file split $rel]} {error {Unsafe Session-relative directory.}}
        } elseif {$path ne {} && [file pathtype $path] ne {absolute}} {error {Use an absolute path or @session/relative/path.}}
    }
}
proc ::GX::_sessionStorageProfilesWrite {data {session {}}} {
    set path [sessionStorageProfilesPath $session]
    set out "\[storage_profiles\]\n"
    foreach key {version active profiles} {appendKV out $key [dict get $data $key]}
    set temp "$path.tmp.[pid].[clock clicks]"
    try {noteWriteUtf8 $temp $out;file rename -force -- $temp $path} finally {if {[file exists $temp]} {file delete -- $temp}}
    return $data
}
proc ::GX::sessionStorageProfileSave {name values {session {}}} {
    sessionStorageProfileValidate $name $values
    set data [sessionStorageProfilesRead $session]
    set complete {};foreach role [workspaceProfileFields] {dict set complete $role [datasetPublicationV2DictDefault $values $role {}]}
    dict set data profiles $name $complete
    _sessionStorageProfilesWrite $data $session
    return $name
}
proc ::GX::sessionStorageProfileCopyGlobal {global name {session {}}} {
    workspaceProfilesLoadCatalog
    if {$global ni [workspaceProfileNames]} {error "Unknown global Storage Profile '$global'."}
    set values {};foreach role [workspaceProfileFields] {dict set values $role $::GX::workspaceProfileCatalog($global,$role)}
    return [sessionStorageProfileSave $name $values $session]
}
proc ::GX::sessionStorageProfileApply {name {session {}}} {
    set data [sessionStorageProfilesRead $session]
    if {$name ne {} && ![dict exists $data profiles $name]} {error "Unknown private Storage Profile '$name'."}
    dict set data active $name;_sessionStorageProfilesWrite $data $session
    if {$session eq {} || [file normalize $session] eq $::GX::currentSession} {
        _sessionStorageProfileRuntimeRefresh
    }
    return $name
}
proc ::GX::sessionStorageProfileDelete {name {session {}}} {
    set data [sessionStorageProfilesRead $session]
    if {[dict exists $data profiles $name]} {dict unset data profiles $name}
    set wasActive [expr {[dict get $data active] eq $name}]
    if {$wasActive} {dict set data active {}}
    _sessionStorageProfilesWrite $data $session
    if {$wasActive} {sessionStorageProfileApply {} $session}
}
proc ::GX::sessionStorageProfileEffective {role {session {}}} {
    workspaceValidateRole $role
    if {$session eq {}} {set session $::GX::currentSession}
    if {$session eq {}} {return {}}
    set data [sessionStorageProfilesRead $session];set active [dict get $data active]
    if {$active eq {}} {return {}}
    set path [dict get $data profiles $active $role]
    if {[string match @session/* $path]} {return [file normalize [file join $session [string range $path 9 end]]]}
    return $path
}
rename ::GX::workspaceInitialDir ::GX::workspaceInitialDir_before_storage082
proc ::GX::workspaceInitialDir {role {fallback {}}} {
    set value [sessionStorageProfileEffective $role]
    if {$value ne {} && [file isdirectory $value]} {return $value}
    return [workspaceInitialDir_before_storage082 $role $fallback]
}
# Host runtime mirrors the same effective directory policy as native choosers.
# Read-only refresh never writes a private registry or modifies global profiles.
proc ::GX::_sessionStorageProfileRuntimeRefresh {} {
    foreach {role key} {session_root output_root export_dir export_dir} {set ::GX::cfg($key) [workspaceInitialDir $role]}
}
# Recognize Session-owned directories even when an imported private absolute path
# still refers to an earlier carrier's Session on the same host. Shared storage
# roots remain reusable; directories inside scientific Sessions do not.
proc ::GX::_sessionStorageProfileSessionOwnedPath {path} {
    set parent [file normalize $path]
    while {1} {
        if {[file isdirectory [file join $parent channels]] && [file isfile [file join $parent metadata manifest.ini]]} {return 1}
        set next [file dirname $parent];if {$next eq $parent} {return 0};set parent $next
    }
}
# Worker calls this before committing a preparation clone. Unsafe source-relative
# absolute values are omitted; explicit @session/ values naturally resolve in the new Session.
proc ::GX::_sessionStorageProfilesPrepareClone {source stage} {
    if {![file exists [file join $source metadata storage_profiles.ini]]} return
    set data [sessionStorageProfilesRead $source]
    dict for {name values} [dict get $data profiles] {
        dict for {role path} $values {
            if {$path ne {} && ![string match @session/* $path] && ([_datasetDeletePathWithin $path $source] || [_sessionStorageProfileSessionOwnedPath $path])} {dict set data profiles $name $role {}}
        }
    }
    _sessionStorageProfilesWrite $data $stage
}
rename ::GX::openSessionPath ::GX::openSessionPath_before_storage082
proc ::GX::openSessionPath {path} {
    set result [openSessionPath_before_storage082 $path]
    if {$::GX::currentSession eq [file normalize $path]} {
        _sessionStorageProfileRuntimeRefresh
    }
    return $result
}
