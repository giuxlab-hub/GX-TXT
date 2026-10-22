# SPDX-License-Identifier: GPL-3.0-or-later
# Private existing-owner creation lifecycle. No scientific or Project writes.
namespace eval ::GX {}
proc ::GX::_sessionCreationHost {operation args} {
    if {$operation ni {reserve claim probe promote abort inspect}} {error {Unknown private creation operation}}
    if {[llength [info commands ::GX::runtimeToolRequired]]} {
        set python [list [runtimeToolRequired python]]
    } else {
        set python [auto_execok python3]
        if {$python eq {}} {set python [auto_execok python]}
    }
    if {$python eq {}} {error {Session creation requires the supported Python runtime}}
    set encoded {}
    foreach value $args {lappend encoded [binary encode base64 -maxlen 0 [encoding convertto utf-8 $value]]}
    # Base64 protects paths/names/tokens from Tcl exec redirection semantics.
    # Returned dictionary data is never eval'd or sourced.
    set response [exec -- {*}$python -B [file join $::GX::scriptDir core python session_experiment_files.py] $operation {*}$encoded]
    if {[catch {dict size $response}] || ![dict exists $response schema] ||
        [dict get $response schema] ne {gxtxt.session_creation.v1}} {error {Invalid private creation response}}
    return $response
}
proc ::GX::_sessionCreationToken {record} {
    if {[catch {dict size $record}] || ![dict exists $record schema] ||
        [dict get $record schema] ne {gxtxt.session_creation.v1} || ![dict exists $record claim]} {
        error {Expected inert private Session creation record}
    }
    return [dict get $record claim]
}
proc ::GX::_sessionCreationReserve {root safeName} {return [_sessionCreationHost reserve $root $safeName [pid]]}
proc ::GX::_sessionCreationClaim {record actualSession} {return [_sessionCreationHost claim [_sessionCreationToken $record] $actualSession]}
proc ::GX::_sessionCreationProbe {session} {return [_sessionCreationHost probe $session]}
proc ::GX::_sessionCreationPromote {record} {return [_sessionCreationHost promote [_sessionCreationToken $record]]}
proc ::GX::_sessionCreationAbort {record} {return [_sessionCreationHost abort [_sessionCreationToken $record]]}
proc ::GX::_sessionCreationInspect {record} {return [_sessionCreationHost inspect [_sessionCreationToken $record]]}
