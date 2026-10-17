# Registered callable declarations share the existing Script Registry owner.
# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::scriptRegistryCallablesValidate {callables} {
    if {[catch {dict size $callables}]||[dict size $callables]>64} {error {Script callables must be a dictionary of at most 64 declarations}}
    set result {}
    dict for {id declaration} $callables {
        if {![regexp {^[A-Za-z][A-Za-z0-9_]{0,63}$} $id]} {error {Invalid registered callable ID}}
        if {[catch {dict size $declaration}]||[lsort [dict keys $declaration]] ne {contract declaration entrypoint}} {error {Callable requires exactly entrypoint, contract and declaration}}
        set entry [dict get $declaration entrypoint]
        if {![regexp {^[A-Za-z][A-Za-z0-9_]{0,63}$} $entry]} {error {Callable entrypoint must be a single public function identifier}}
        if {![regexp {^[a-z][a-z0-9_.]*[.]v[1-9][0-9]*$} [dict get $declaration contract]]} {error {Callable contract must be an explicit versioned scientific identity}}
        set encoded [dict get $declaration declaration]
        if {[string length $encoded]>1048576||![regexp {^[A-Za-z0-9+/=]*$} $encoded]} {error {Callable declaration must be a bounded inert scientific recipe envelope}}
        set data [scientificRecipeDataDecode $encoded [dict get $declaration contract]]
        dict set result $id [dict create entrypoint $entry contract [dict get $declaration contract] declaration $encoded]
    }
    return $result
}
proc ::GX::scriptRegistryCallableDescribe {reference callableId {session {}}} {
    if {$session eq {}} {set session $::GX::currentSession}
    if {$session eq {}||![file isdirectory $session]} {error {Open a Session before resolving a registered callable}}
    set m [scriptRegistryDescribe $reference $session]
    if {![dict exists $m callables $callableId]} {error {Registered callable is unavailable in this script revision}}
    set declaration [dict get $m callables $callableId]
    return [dict merge $declaration [dict create reference $reference callable_id $callableId language [dict get $m language] version [dict get $m version] revision [dict get $m revision] source_sha256 [dict get $m sha256] declaration_sha256 [datasetStorageSha256Text $session $declaration]]]
}
proc ::GX::scriptRegistryCallableList {{session {}}} {
    set result {}
    foreach script [scriptRegistryList all $session] {
        set reference [dict get $script scope]:[dict get $script id]
        foreach id [dict keys [dict get $script callables]] {
            lappend result [dict merge [scriptRegistryCallableDescribe $reference $id $session] [dict create name [dict get $script name]]]
        }
    }
    return $result
}
proc ::GX::scriptCallableInvocationValidate {reference invocation session} {
    foreach key {callable_id source_sha256 revision declaration_sha256 consumer_api consumer_operation payload_json} {
        if {![dict exists $invocation $key]} {error "Callable invocation requires $key"}
    }
    if {[dict size $invocation]!=7} {error {Unknown callable invocation field}}
    set current [scriptRegistryCallableDescribe $reference [dict get $invocation callable_id] $session]
    foreach key {source_sha256 revision declaration_sha256} {
        if {[dict get $current $key] ne [dict get $invocation $key]} {error "Registered callable $key changed; review the current script and declaration before submitting"}
    }
    if {![regexp {^[A-Z][A-Z0-9_]*_API_v[1-9][0-9]*$} [dict get $invocation consumer_api]]||![regexp {^[a-z][a-z0-9_]*$} [dict get $invocation consumer_operation]]} {error {Callable consumer must be a public API operation}}
    set payload [dict get $invocation payload_json]
    if {[string bytelength $payload]>1048576||[regexp {[\r\n\x00]} $payload]} {error {Callable payload must be one line of bounded JSON control data}}
    # Decode in the language runner; no user JSON or source is evaluated in Tcl.
    return [dict merge $invocation [dict create entrypoint [dict get $current entrypoint] contract [dict get $current contract]]]
}
