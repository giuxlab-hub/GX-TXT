# SPDX-License-Identifier: GPL-3.0-or-later
# Projections and comparisons of the EXISTING Registry owner, never new grants.
proc ::GX::scriptRegistryIdentityApiInfo {} {
    return [dict create schema gxtxt.script_registry_identity.v1 host_only 1 \
        projections {record_sha256 owner_context} \
        guarded_operations {scriptRegistryUpdate scriptRegistryProjectUpdate scriptRegistryProjectExport scriptRegistryCopySnapshot scriptRegistryAssignToSession scriptRegistryRemove resourceLifecycleDeleteScript} \
        expected_fields {expected_sha256 expected_revision expected_record_sha256 expected_owner_context}]
}
proc ::GX::scriptRegistryOwnerContext {scope {session {}}} {
    set root [scriptRegistryRoot $scope $session]
    return [_scriptRegistryOwnerContextAtRoot $scope $root]
}
proc ::GX::_scriptRegistryOwnerContextAtRoot {scope root} {
    if {[file exists $root]} {
        file stat $root info
        if {$info(type) ne {directory}} {error {Script Registry root is not a directory}}
        set identity [list $info(dev) $info(ino)]
    } else {set identity absent}
    # Stable across edits/Session switches for the same User Registry; changes
    # when configuration or the physical registered root is replaced. Native
    # lifetime admission separately enforces the actual opaque Session token.
    return [scriptRegistryHashBytes [encoding convertto utf-8 [list $scope [file normalize $root] $identity]]]
}
proc ::GX::_scriptRegistryIdentityFinalize {scope id session retries originalHash metadata} {
    set path [file join [scriptRegistryPath $scope $id $session] script.ini]
    if {[scriptRegistryHash $path] ne $originalHash} {
        if {$retries>=3} {error {Registered metadata keeps changing during read; retry after editing completes}}
        return [_scriptRegistryRead $scope $id $session [expr {$retries+1}]]
    }
    dict set metadata record_sha256 $originalHash
    dict set metadata owner_context [scriptRegistryOwnerContext $scope $session]
    return $metadata
}
proc ::GX::_scriptRegistryExpectedFields {metadata} {
    set expected {}
    foreach key {expected_sha256 expected_revision expected_record_sha256 expected_owner_context} {
        if {[dict exists $metadata $key]} {dict set expected $key [dict get $metadata $key]}
    }
    return $expected
}
proc ::GX::_scriptRegistryExpectedCheck {metadata expected} {
    if {[catch {dict size $expected}]} {error {Expected Script identity must be a dictionary}}
    dict for {key value} $expected {
        switch $key {
            expected_revision {
                if {![string is integer -strict $value] || $value<1 || $value ne [dict get $metadata revision]} {error {Script metadata revision changed; review and retry}}
            }
            expected_sha256 - expected_record_sha256 - expected_owner_context {
                if {![regexp {^[0-9a-f]{64}$} $value]} {error {Expected Script identity requires an exact SHA-256 projection}}
                set actual [dict get $metadata [dict get {expected_sha256 sha256 expected_record_sha256 record_sha256 expected_owner_context owner_context} $key]]
                if {$value ne $actual} {error {Script source, full record or Registry owner changed; review and retry}}
            }
            default {error {Unknown expected Script identity field}}
        }
    }
}
