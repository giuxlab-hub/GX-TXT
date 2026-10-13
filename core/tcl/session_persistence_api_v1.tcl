# GX-TXT Session Persistence API v1.
# Commit the current framework-owned Session state without exposing raw
# Manifest keys or permitting writes to another Session.
namespace eval ::GX { variable sessionPersistenceApiVersion 1 }

proc ::GX::sessionPersistenceCommit {} {
    set session [sessionInspectionCurrentSession]
    set target [file join $session metadata manifest.ini]
    set temporary "${target}.tmp.[pid].[clock clicks]"
    set state [manifestString]
    try {
        set fd [open $temporary w]
        fconfigure $fd -encoding utf-8 -translation lf
        puts -nonewline $fd $state
        close $fd
        set fd ""
        # A malformed intermediate Manifest must not replace the current one.
        set parsed [parseIni $temporary]
        if {![dict exists $parsed pipeline.format] || [dict get $parsed pipeline.format] ne "2"} {
            error "Current Session Manifest is not Format 2"
        }
        file rename -force -- $temporary $target
    } on error {problem options} {
        if {[info exists fd] && $fd ne ""} {catch {close $fd}}
        catch {file delete -force -- $temporary}
        return -options $options $problem
    }
    return [dict create session $session manifest_path $target sha256 [sha256File $target]]
}
