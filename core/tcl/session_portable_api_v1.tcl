# GX-TXT Portable Session API v1
# SPDX-License-Identifier: GPL-3.0-or-later
# Lossless Session transport with package-level integrity and transactional import.

namespace eval ::GX {
    variable sessionPortableApiVersion 1
}

proc ::GX::_sessionPortableRequireSession {{session ""}} {
    variable currentSession
    if {$session eq ""} { set session $currentSession }
    if {$session eq "" || ![file isdirectory $session]} { error "Portable Session API requires an existing Session." }
    set session [file normalize $session]
    if {![file isfile [file join $session metadata manifest.ini]]} { error "The Session is missing metadata/manifest.ini." }
    return $session
}

proc ::GX::_sessionPortableHelper {} {
    variable scriptDir
    set helper [file join $scriptDir core python session_portable_v1.py]
    if {![file isfile $helper]} { error "Portable Session helper is missing: $helper" }
    return $helper
}

proc ::GX::_sessionPortableParseOutput {text} {
    set result [dict create]
    foreach raw [split $text "\n"] {
        if {[string trim $raw] eq ""} continue
        set pos [string first "=" $raw]
        if {$pos < 1} { error "Invalid Portable Session helper response: $raw" }
        set key [string range $raw 0 [expr {$pos-1}]]
        set value [string range $raw [expr {$pos+1}] end]
        dict set result $key $value
    }
    return $result
}

proc ::GX::sessionPortableValidate {archive} {
    set archive [file normalize $archive]
    if {![file isfile $archive]} { error "Portable Session archive not found: $archive" }
    set cmd [list [runtimeToolRequired python] [_sessionPortableHelper] validate $archive]
    if {[catch {set out [exec {*}$cmd 2>@1]} err opts]} { return -options $opts $err }
    return [_sessionPortableParseOutput $out]
}

proc ::GX::sessionPortableDependencyDiagnostics {packageInfo} {
    variable moduleOrder
    set missing {}
    set different {}
    dict for {key value} $packageInfo {
        if {![regexp {^dependency\.([0-9]+)$} $key]} continue
        set pos [string last "|" $value]
        if {$pos < 0} { set id $value; set required "" } else {
            set id [string range $value 0 [expr {$pos-1}]]
            set required [string range $value [expr {$pos+1}] end]
        }
        if {$id eq ""} continue
        if {[lsearch -exact $moduleOrder $id] < 0} {
            lappend missing [dict create id $id required_version $required]
            continue
        }
        set have [moduleField $id version ""]
        if {$required ni {"" unknown missing} && $have ne "" && $have ne $required} {
            lappend different [dict create id $id required_version $required installed_version $have]
        }
    }
    set external {}
    dict for {key value} $packageInfo {
        if {![regexp {^external_dependency\.([0-9]+)$} $key]} continue
        set pos [string last "|" $value]
        if {$pos < 0} { lappend external [dict create path $value kind unknown] } else {
            lappend external [dict create path [string range $value 0 [expr {$pos-1}]] kind [string range $value [expr {$pos+1}] end]]
        }
    }
    return [dict create missing_plugins $missing version_differences $different external_dependencies $external]
}

proc ::GX::sessionPortableExport {session archive} {
    variable scriptDir
    variable version
    set session [_sessionPortableRequireSession $session]
    set archive [file normalize $archive]
    if {[string tolower [file extension $archive]] ne ".zip"} { append archive ".gxtxt-session.zip" }
    file mkdir [file dirname $archive]
    set drained [scientificHistoryPortableDrain $session]
    scientificHistoryPortableVerifySession $session [dict get $drained owned]
    set cmd [list [runtimeToolRequired python] [_sessionPortableHelper] export $session $archive $scriptDir $version --carrier-installation [installationIdentityCurrent]]
    foreach path [dict get $drained owned] {lappend cmd --history-owned $path}
    if {[catch {set out [exec {*}$cmd 2>@1]} err opts]} { return -options $opts $err }
    set result [_sessionPortableParseOutput $out]
    dict set result package_info [sessionPortableValidate $archive]
    return $result
}

proc ::GX::sessionPortableImport {archive destination} {
    variable scriptDir
    set packageInfo [sessionPortableValidate $archive]
    set destination [file normalize $destination]
    if {[file exists $destination]} { error "Destination Session already exists: $destination" }
    set worker [file join $scriptDir plugins modules acq.rigol_csv runtime gxtxt_csv_worker.m]
    set cmd [list [runtimeToolRequired python] [_sessionPortableHelper] import [file normalize $archive] $destination --worker-file $worker]
    if {[catch {set out [exec {*}$cmd 2>@1]} err opts]} { return -options $opts $err }
    set result [_sessionPortableParseOutput $out]
    dict set result package_info $packageInfo
    dict set result diagnostics [sessionPortableDependencyDiagnostics $packageInfo]
    return $result
}

proc ::GX::sessionPortableGuiExport {} {
    variable currentSession
    if {[catch {set session [_sessionPortableRequireSession]} err]} {
        tk_messageBox -icon info -title "Export Session" -message $err
        return
    }
    set name [file tail $session]
    set f [workspaceSaveFile export_dir -title "Export GX-TXT Session" -initialfile "${name}.gxtxt-session.zip" -defaultextension .zip -filetypes {{{GX-TXT portable Session} {.zip}} {{All files} *}}]
    if {$f eq ""} return
    if {[catch {set r [sessionPortableExport $session $f]} err]} {
        tk_messageBox -icon error -title "Session export failed" -message $err
        return
    }
    set info [dict get $r package_info]
    set msg "Portable Session created:\n[dict get $r archive]\n\nSHA-256: [dict get $r sha256]\nFiles: [dict get $r file_count]"
    if {[dict get $info external_dependency_count] ne "0"} { append msg "\n\nWarning: the package records [dict get $info external_dependency_count] unresolved external dependency/dependencies. Review the package diagnostics before archival transfer." }
    tk_messageBox -icon info -title "Session exported" -message $msg
}

proc ::GX::_sessionPortableImportDialogCommit {w archive} {
    variable ui
    variable cfg
    set name [string trim $ui(portableImportName)]
    if {$name eq ""} { tk_messageBox -parent $w -icon error -title "Import Session" -message "Enter a destination Session name."; return }
    set safe [sanitize $name]
    set root [string trim $cfg(output_root)]
    if {$root eq ""} { tk_messageBox -parent $w -icon error -title "Import Session" -message "Set Session root before importing a Session."; return }
    set destination [file join [file normalize $root] $safe]
    if {[file exists $destination]} { tk_messageBox -parent $w -icon error -title "Import Session" -message "A Session named '$safe' already exists. Choose another name."; return }
    if {[catch {set r [sessionPortableImport $archive $destination]} err]} { tk_messageBox -parent $w -icon error -title "Session import failed" -message $err; return }
    destroy $w
    if {[catch {openSessionPath [dict get $r session]} err]} { tk_messageBox -icon error -title "Session imported" -message "The Session was imported, but could not be opened:\n$err"; return }
    set diag [dict get $r diagnostics]
    set message "Session imported and opened:\n[dict get $r session]"
    set missing [dict get $diag missing_plugins]
    set versions [dict get $diag version_differences]
    set external [dict get $diag external_dependencies]
    if {[llength $missing]} {
        append message "\n\nMissing plugin dependencies:"
        foreach rec $missing { append message "\n- [dict get $rec id] [dict get $rec required_version]" }
    }
    if {[llength $versions]} {
        append message "\n\nPlugin version differences:"
        foreach rec $versions { append message "\n- [dict get $rec id]: package [dict get $rec required_version], installed [dict get $rec installed_version]" }
    }
    if {[llength $external]} {
        append message "\n\nRecorded external dependencies: [llength $external]."
    }
    tk_messageBox -icon [expr {[llength $missing] || [llength $external] ? "warning" : "info"}] -title "Session imported" -message $message
}

proc ::GX::sessionPortableGuiImport {} {
    variable cfg
    variable ui
    if {[string trim $cfg(output_root)] eq ""} { tk_messageBox -icon info -title "Import Session" -message "Set Session root before importing a Session."; return }
    set archive [workspaceOpenFile session_open_dir -title "Import GX-TXT Session" -filetypes {{{GX-TXT portable Session} {.zip}} {{All files} *}}]
    if {$archive eq ""} return
    if {[catch {set info [sessionPortableValidate $archive]} err]} { tk_messageBox -icon error -title "Invalid portable Session" -message $err; return }
    set suggested [dict get $info session_name]
    if {$suggested eq ""} { set suggested "imported-session" }
    set ui(portableImportName) $suggested
    set w .gxPortableSessionImport
    catch {destroy $w}
    toplevel $w
    wm title $w "Import Session"
    wm transient $w .
    grid columnconfigure $w 1 -weight 1
    ttk::label $w.archiveL -text "Portable archive:"
    ttk::label $w.archive -text [file tail $archive]
    ttk::label $w.rootL -text "Session root:"
    ttk::label $w.root -text [file normalize $cfg(output_root)]
    ttk::label $w.nameL -text "Destination Session name:"
    ttk::entry $w.name -textvariable ::GX::ui(portableImportName) -width 42
    ttk::frame $w.buttons
    ttk::button $w.buttons.import -text "Import" -command [list ::GX::_sessionPortableImportDialogCommit $w $archive]
    ttk::button $w.buttons.cancel -text "Cancel" -command [list destroy $w]
    grid $w.archiveL -row 0 -column 0 -sticky e -padx 6 -pady 5
    grid $w.archive -row 0 -column 1 -sticky w -padx 6 -pady 5
    grid $w.rootL -row 1 -column 0 -sticky e -padx 6 -pady 5
    grid $w.root -row 1 -column 1 -sticky w -padx 6 -pady 5
    grid $w.nameL -row 2 -column 0 -sticky e -padx 6 -pady 5
    grid $w.name -row 2 -column 1 -sticky ew -padx 6 -pady 5
    pack $w.buttons.import $w.buttons.cancel -side left -padx 4
    grid $w.buttons -row 3 -column 0 -columnspan 2 -pady 8
    bind $w.name <Return> [list ::GX::_sessionPortableImportDialogCommit $w $archive]
    bind $w <Escape> [list destroy $w]
    focus $w.name
}

# Generic host staging for transactions that commit additional organizational state.
# Existing two-argument Import keeps its contract; extraction/validation/relocation
# remain owned by the same Portable authority.
proc ::GX::sessionPortableStageImport {archive destination staging} {
    variable scriptDir
    set info [sessionPortableValidate $archive]
    set destination [file normalize $destination];set staging [file normalize $staging]
    if {[file exists $destination] || [file exists $staging] || $destination eq $staging} {error {Portable staging requires distinct unused staging and final destinations.}}
    set worker [file join $scriptDir plugins modules acq.rigol_csv runtime gxtxt_csv_worker.m]
    set result [_sessionPortableParseOutput [exec [runtimeToolRequired python] [_sessionPortableHelper] import [file normalize $archive] $staging --worker-file $worker --logical-destination $destination 2>@1]]
    dict set result package_info $info
    dict set result diagnostics [sessionPortableDependencyDiagnostics $info]
    dict set result logical_destination $destination
    return $result
}

source [file join [file dirname [info script]] scientific_history_portable.tcl]
