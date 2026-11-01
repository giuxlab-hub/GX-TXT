# SPDX-License-Identifier: GPL-3.0-or-later
# Bounded host transactions subordinate to the existing Script Registry owner.
proc ::GX::_scriptRegistryPinned {metadata} {
    set expected {}
    foreach field {sha256 revision record_sha256 owner_context} {dict set expected expected_$field [dict get $metadata $field]}
    return $expected
}
proc ::GX::_scriptRegistryLock {path} {
    if {[catch {set handle [open $path {WRONLY CREAT EXCL}]}]} {error {Another Script source owner transaction is in progress}}
    file lstat $path identity
    return [list $path $handle $identity(dev) $identity(ino)]
}
proc ::GX::_scriptRegistryUnlock {lock} {
    lassign $lock path handle device inode
    close $handle
    # A Project deletion moves its open lock with the old record. Never remove
    # a lock belonging to a later record that reused the canonical name.
    if {![catch {file lstat $path actual}] && $actual(type) eq {file} && $actual(dev)==$device && $actual(ino)==$inode} {file delete -- $path}
}
proc ::GX::scriptRegistryCopySnapshot {reference targetId expected {session {}}} {
    if {[lsort [dict keys $expected]] ne {expected_owner_context expected_record_sha256 expected_revision expected_sha256}} {error {Copy Snapshot requires the complete reviewed Script identity}}
    set source [scriptRegistryDescribe $reference $session]
    return [_scriptRegistrySnapshot $reference [dict get $source scope] $targetId $expected $session]
}
proc ::GX::_scriptRegistrySnapshot {reference targetScope targetId expected session} {
    set source [scriptRegistryDescribe $reference $session]
    _scriptRegistryExpectedCheck $source $expected
    set pinned [_scriptRegistryPinned $source]
    set sourceScope [dict get $source scope]
    if {$targetScope ne $sourceScope && !($sourceScope eq {user} && $targetScope eq {session})} {error {Unsupported Script snapshot scope transition}}
    set target [scriptRegistryPath $targetScope $targetId $session]
    set sourceRoot [scriptRegistryPath $sourceScope [dict get $source id] $session]
    if {$target eq $sourceRoot} {error {Choose a distinct new Script identity}}
    file mkdir [file dirname $target]
    set targetOwner [scriptRegistryOwnerContext $targetScope $session]
    file stat [file dirname $sourceRoot] sourceOwner
    file stat [file dirname $target] destinationOwner
    set pending [file join [file dirname $target] ".$targetId.snapshot-[pid]-[clock clicks].pending"]
    set locks {};set staged 0
    try {
        foreach path [lsort -unique [list [_scriptAuthoringLockPath $source $session] [file join [file dirname $target] .$targetId.registry-lock]]] {
            lappend locks [_scriptRegistryLock $path]
        }
        _scriptRegistryExpectedCheck [scriptRegistryDescribe $reference $session] $pinned
        if {[file exists $target]} {error {Target Script identity already exists}}
        exec {*}[scriptProjectCommand stage_registry $pending $target]
        file lstat $pending pendingIdentity
        set staged 1
        set next [dict remove $source record_sha256 owner_context]
        dict set next scope $targetScope;dict set next id $targetId
        dict set next revision 1;dict set next created_at {};dict set next updated_at {}
        dict set next source_scope $sourceScope;dict set next source_id [dict get $source id]
        dict set next source_sha256 [dict get $source sha256]
        dict set next source_authoring_v1 {}
        set code {}
        if {[dict get $source kind] eq {project}} {
            set project [scriptProjectWrite $pending [dict get $source language] [dict get $source entrypoint] [scriptRegistryProjectFiles $source]]
            dict set next project_revision [dict get $project project_sha256]
        } else {
            set channel [open [dict get $source source_path] rb]
            try {set code [encoding convertfrom utf-8 [read $channel]]} finally {close $channel}
        }
        if {[_scriptAuthoringPointer $source] ne {}} {
            set clone [_scriptAuthoringCall $pending [dict create operation clone pointer [_scriptAuthoringPointer $source] source_root $sourceRoot source_files [_scriptAuthoringFiles $source]]]
            dict set next source_authoring_v1 [dict get $clone pointer]
        }
        set saved [_scriptRegistryWritePrepared $next $code $session {} $pending]
        if {[dict get $saved sha256] ne [dict get $source sha256]} {error {Prepared Script snapshot source bytes differ}}
        _scriptRegistryExpectedCheck [scriptRegistryDescribe $reference $session] $pinned
        if {[scriptRegistryOwnerContext $targetScope $session] ne $targetOwner} {error {Destination Script Registry owner changed before publication}}
        exec {*}[scriptProjectCommand publish_registry $pending $target snapshot $sourceRoot [dict get $source record_sha256] [dict get $source sha256] $sourceOwner(dev) $sourceOwner(ino) $destinationOwner(dev) $destinationOwner(ino) [expr {[dict get $source kind] eq {project}}]]
        set staged 0
        # Preserve the exact commit receipt instead of rereading a later writer.
        foreach field {project_manifest project_root source_path} {
            if {[dict exists $saved $field] && [string first "$pending/" [dict get $saved $field]]==0} {dict set saved $field "$target/[string range [dict get $saved $field] [expr {[string length $pending]+1}] end]"}
        }
        if {[dict exists $saved admitted_sources]} {
            dict set saved admitted_sources [lmap path [dict get $saved admitted_sources] {string cat $target/ [string range $path [expr {[string length $pending]+1}] end]}]
        }
        after idle ::GX::_scriptRegistryRefresh
        return $saved
    } finally {
        if {$staged && ![catch {file lstat $pending actual}] && $actual(type) eq {directory} && $actual(dev)==$pendingIdentity(dev) && $actual(ino)==$pendingIdentity(ino)} {file delete -force -- $pending}
        foreach lock [lreverse $locks] {_scriptRegistryUnlock $lock}
    }
}
proc ::GX::_scriptRegistryRemoveGuarded {reference session expected checkDependencies} {
    set metadata [scriptRegistryDescribe $reference $session]
    _scriptRegistryExpectedCheck $metadata $expected
    set pinned [_scriptRegistryPinned $metadata]
    set root [scriptRegistryPath [dict get $metadata scope] [dict get $metadata id] $session]
    set lock [_scriptRegistryLock [_scriptAuthoringLockPath $metadata $session]]
    try {
        _scriptRegistryExpectedCheck [scriptRegistryDescribe $reference $session] $pinned
        if {$checkDependencies} {
            set dependencies [resourceLifecycleScriptDependencies $reference]
            if {[llength $dependencies]} {error "Cannot delete Script with active dependencies:\n[join $dependencies \n]"}
        }
        file stat [file dirname $root] owner
        exec {*}[scriptProjectCommand remove_registry $root [dict get $metadata record_sha256] [dict get $metadata sha256] $owner(dev) $owner(ino) [expr {[dict get $metadata kind] eq {project}}]]
        after idle ::GX::_scriptRegistryRefresh
    } finally {_scriptRegistryUnlock $lock}
    return $reference
}
