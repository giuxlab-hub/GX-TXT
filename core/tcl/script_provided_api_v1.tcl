# SPDX-License-Identifier: GPL-3.0-or-later
# Read-only public host projection of the existing Registry/Project owner.
# Static declarations never authorize execution or grant consumed APIs.
proc ::GX::scriptRegistryProvidedApiInventory {reference {options {}} {session {}}} {
    if {[catch {dict size $options}]} {error {Provided API inventory options require a dictionary}}
    foreach key [dict keys $options] {if {$key ni {draft_sources draft_entrypoint expected_sha256 expected_revision expected_record_sha256 expected_owner_context}} {error {Unknown provided API inventory option}}}
    if {$session eq {} && [info exists ::GX::currentSession]} {set session $::GX::currentSession}
    set metadata [scriptRegistryDescribe $reference $session]
    _scriptRegistryExpectedCheck $metadata [_scriptRegistryExpectedFields $options]
    set expected [dict create expected_sha256 [dict get $metadata sha256] expected_revision [dict get $metadata revision] expected_record_sha256 [dict get $metadata record_sha256] expected_owner_context [dict get $metadata owner_context]]
    set draft [dict exists $options draft_sources]
    set entrypoint [expr {[dict get $metadata kind] eq {project}?[dict get $metadata entrypoint]:[scriptRegistrySourceName [dict get $metadata language]]}]
    if {$draft} {
        set sources [dict get $options draft_sources]
    } elseif {[dict get $metadata kind] eq {project}} {
        set sources [scriptRegistryProjectFiles $metadata]
    } else {
        set chosen [scriptRegistryReadChosenSource [dict get $metadata source_path]]
        if {[dict get $chosen sha256] ne [dict get $metadata sha256]} {error {Registered source changed before provided API inventory}}
        set sources [dict create $entrypoint [dict get $chosen source]]
    }
    if {[dict exists $options draft_entrypoint]} {
        if {!$draft} {error {A draft entrypoint requires the complete draft source map}}
        set entrypoint [dict get $options draft_entrypoint]
    }
    if {[catch {dict size $sources}] || [dict size $sources]<1 || [dict size $sources]>256} {error {Provided API inventory requires 1..256 source files}}
    set fields {};set total 0
    dict for {name source} $sources {
        set bytes [encoding convertto utf-8 $source];set size [string length $bytes]
        if {$size>4194304 || [string first \x00 $source]>=0} {error {Provided API source exceeds 4 MiB or contains NUL}}
        incr total $size
        lappend fields "[viewerDevelopmentJsonString $name]:[viewerDevelopmentJsonString [binary encode hex $bytes]]"
    }
    if {$total>16777216} {error {Provided API whole project exceeds 16 MiB}}
    set payload "\{\"language\":[viewerDevelopmentJsonString [dict get $metadata language]],\"entrypoint\":[viewerDevelopmentJsonString $entrypoint],\"sources_hex\":\{[join $fields ,]\}\}"
    set result [exec {*}[scriptProjectCommand provided_inventory] << $payload]
    # A read may span another process publishing a record or a Configuration
    # change. Do not return an apparently current inventory for a replaced owner.
    _scriptRegistryExpectedCheck [scriptRegistryDescribe $reference $session] $expected
    dict set result reference $reference
    dict set result registry_baseline $expected
    dict set result source_scope [expr {$draft?{unsaved_draft_preview}:{registered_snapshot}}]
    dict set result execution_authority none
    return $result
}
