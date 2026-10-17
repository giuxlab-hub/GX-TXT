# Tcl contract test: the Curve Digitalizer is a pure CONFIGURATION_API_v1
# client; the host retains the authoritative store and collision checks.
proc assert {truth msg} {if {![uplevel 1 [list expr $truth]]} {error "FAIL: $msg"}}
namespace eval ::GX {variable mockcfg;variable mockSession a;variable moduleId viewer.curve_digitizer}
proc ::GX::viewerBackendRegister {args} {}
set root [file normalize [file join [file dirname [info script]] ..]]
# Parse the descriptor's declared config schema, not a second hardcoded list.
set descriptor [read [open [file join $root module.ini] r]]
set section {} ;set defaults [dict create];set types [dict create];set allfields {}
foreach line [split $descriptor \n] {
    if {[regexp {^\[([^]]+)\]$} [string trim $line] -> sec]} {set section $sec;continue}
    if {[regexp {^([^=]+)=(.*)$} $line -> key value]} {
        if {$section eq "config" && $key eq "fields"} {set allfields [split $value {;}]}
        if {[string match config.* $section]} {
            set k [string range $section 7 end]
            if {$key eq "default"} {dict set defaults $k $value}
            if {$key eq "type"} {dict set types $k $value}
        }
    }
}
assert {[llength $allfields] == 22} {twenty-two declared config fields}
foreach k $allfields {assert {[dict exists $defaults $k]} "missing default for $k"}
set ::GX::mockcfg $defaults
proc ::GX::configurationModuleFields {module} {
    if {$module ne "viewer.curve_digitizer"} {error unknown}
    set fields [dict create]
    foreach k [dict keys $::GX::mockcfg] {
        dict set fields module.viewer.curve_digitizer.$k [dict create module_key $k]
    }
    return $fields
}
proc ::GX::configurationResolve {id} {
    set key [lindex [split $id .] end]
    return [dict create effective [dict get $::GX::mockcfg $key] origin factory]
}
proc ::GX::configurationCommit {changes} {
    set updates [dict create]
    foreach change $changes {
        assert {[dict get $change scope] eq "session"} {must use CORE Session scope}
        set key [lindex [split [dict get $change id] .] end]
        if {[dict get $change expected] ne [dict get $::GX::mockcfg $key]} {error "Configuration conflict for $key"}
        dict set updates $key [dict get $change value]
    }
    dict for {k v} $updates {dict set ::GX::mockcfg $k $v}
}
proc ::GX::interactiveDocumentSessionToken {} {return session_token_1}
source [file join $root api curve_digitizer_viewer_api_v1.tcl]
set data [::GX::CurveDigitizer::_settingsRows]
set entries [split $data \n]
assert {[llength $entries] == 22} {all fields discoverable through Configuration API}
set proposed [join [list snap_radius [::GX::CurveDigitizer::_b64e 3] [::GX::CurveDigitizer::_b64e 11]] \t]
set result [::GX::CurveDigitizer::_settingsCommit session_token_1 $proposed]
assert {[dict get $::GX::mockcfg snap_radius] eq "11"} {committed through CORE}
set code [catch {::GX::CurveDigitizer::_settingsCommit session_token_1 $proposed} reason]
assert {$code == 1 && [string match {*Configuration conflict*} $reason]} {stale writes must fail}
set code [catch {::GX::CurveDigitizer::_settingsCommit stale_session_token $proposed} reason]
assert {$code == 1 && [string match {*Session changed*} $reason]} {Session swap must fail}
assert {[dict get $::GX::mockcfg snap_radius] eq "11"} {failed commits are inert}
assert {[dict get $::GX::mockcfg scale_unit] eq "µm"} {UTF-8 unit retained}
puts "PASS CORE config schema discovery, twenty-two fields, Session commit, conflict detection, Session guard, UTF-8"
