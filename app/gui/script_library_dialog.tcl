# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX { variable scriptLibraryUi }

proc ::GX::scriptLibraryDialog {} {
    variable scriptLibraryUi
    set w .gxtxtScriptLibrary
    if {[winfo exists $w]} { raise $w; focus $w; return }
    toplevel $w
    wm title $w "GX-TXT Script Library"
    wm geometry $w 1160x800
    wm minsize $w 850 630
    ttk::panedwindow $w.body -orient horizontal
    pack $w.body -fill both -expand 1 -padx 7 -pady 7
    ttk::frame $w.body.left
    ttk::frame $w.body.right
    $w.body add $w.body.left -weight 1
    $w.body add $w.body.right -weight 3
    ttk::label $w.body.left.searchLabel -text "Search registered scripts"
    ttk::entry $w.body.left.search -textvariable ::GX::scriptLibraryUi(search)
    pack $w.body.left.searchLabel $w.body.left.search -fill x -padx 4 -pady 4
    bind $w.body.left.search <KeyRelease> ::GX::scriptLibraryRefresh
    ttk::treeview $w.body.left.tree -columns {scope language id version} -show {tree headings} -selectmode browse
    $w.body.left.tree heading #0 -text "Name"
    foreach {col title width} {scope Scope 70 language Language 70 id ID 135 version Version 70} {
        $w.body.left.tree heading $col -text $title
        $w.body.left.tree column $col -width $width -stretch 0
    }
    ttk::scrollbar $w.body.left.sy -orient vertical -command [list $w.body.left.tree yview]
    $w.body.left.tree configure -yscrollcommand [list $w.body.left.sy set]
    pack $w.body.left.sy -side right -fill y
    pack $w.body.left.tree -fill both -expand 1
    bind $w.body.left.tree <<TreeviewSelect>> ::GX::scriptLibrarySelect

    set f $w.body.right
    grid columnconfigure $f 1 -weight 1
    grid rowconfigure $f 9 -weight 1
    set row 0
    foreach {key label} {scope Scope language Language id {Stable ID} name {Display name} version Version description Description required_apis {Additional required APIs}} {
        ttk::label $f.l_$key -text "$label:"
        if {$key eq "scope"} {
            ttk::combobox $f.e_$key -textvariable ::GX::scriptLibraryUi($key) -values {user session} -state readonly
        } elseif {$key eq "language"} {
            ttk::combobox $f.e_$key -textvariable ::GX::scriptLibraryUi($key) -values {Octave Python} -state readonly
            bind $f.e_$key <<ComboboxSelected>> ::GX::scriptLibraryLanguageChanged
        } else {
            ttk::entry $f.e_$key -textvariable ::GX::scriptLibraryUi($key)
        }
        grid $f.l_$key -row $row -column 0 -sticky e -padx 5 -pady 3
        grid $f.e_$key -row $row -column 1 -sticky ew -padx 5 -pady 3
        incr row
    }
    ttk::label $f.sha -textvariable ::GX::scriptLibraryUi(identity) -wraplength 680
    grid $f.sha -row 7 -column 0 -columnspan 2 -sticky ew -padx 5 -pady 4
    ttk::label $f.parametersLabel -text "Parameters: name | type | required (0/1) | default | description"
    grid $f.parametersLabel -row 8 -column 0 -columnspan 2 -sticky w -padx 5
    text $f.parameters -height 5 -wrap none -undo 1
    grid $f.parameters -row 9 -column 0 -columnspan 2 -sticky nsew -padx 5 -pady 4
    ttk::label $f.codeLabel -textvariable ::GX::scriptLibraryUi(sourceLabel)
    grid $f.codeLabel -row 10 -column 0 -columnspan 2 -sticky w -padx 5
    text $f.code -height 17 -wrap none -undo 1 -font TkFixedFont
    ttk::scrollbar $f.codeY -orient vertical -command [list $f.code yview]
    ttk::scrollbar $f.codeX -orient horizontal -command [list $f.code xview]
    $f.code configure -yscrollcommand [list $f.codeY set] -xscrollcommand [list $f.codeX set]
    grid $f.code -row 11 -column 0 -columnspan 2 -sticky nsew -padx {5 0} -pady 4
    grid $f.codeY -row 11 -column 2 -sticky ns
    grid $f.codeX -row 12 -column 0 -columnspan 2 -sticky ew -padx 5
    grid rowconfigure $f 11 -weight 3
    ttk::frame $f.buttons
    set buttonIndex 0
    foreach {key label action} {newUser {New user} scriptLibraryNewUser newSession {New Session} scriptLibraryNewSession save Save scriptLibrarySave assign {Assign to Session} scriptLibraryAssign run Run scriptLibraryRun jobs {Script Jobs…} scriptJobsDialog import Import scriptLibraryImport export Export scriptLibraryExport remove {Delete selected...} scriptLibraryRemove close Close scriptLibraryClose} {
        ttk::button $f.buttons.$key -text $label -command [list ::GX::$action]
        grid $f.buttons.$key -row [expr {$buttonIndex / 5}] -column [expr {$buttonIndex % 5}] -sticky w -padx 2 -pady 2
        incr buttonIndex
    }
    grid $f.buttons -row 13 -column 0 -columnspan 2 -sticky ew
    ttk::label $f.status -textvariable ::GX::scriptLibraryUi(status) -wraplength 760
    grid $f.status -row 14 -column 0 -columnspan 2 -sticky ew -padx 5 -pady 3
    set scriptLibraryUi(search) ""
    scriptLibraryNewUser
    scriptLibraryRefresh
}

proc ::GX::scriptLibraryClose {} {
    destroy .gxtxtScriptLibrary
    catch {scriptWorkspaceRefreshChoices}
}

proc ::GX::scriptLibraryNew {scope} {
    variable scriptLibraryUi
    set scriptLibraryUi(reference) ""
    set scriptLibraryUi(sha256) ""
    foreach {key value} [list scope $scope language Octave id "" name "" version 1.0.0 description "" required_apis "" identity {New registered script} status "Enter script metadata and source, then Save."] {
        set scriptLibraryUi($key) $value
    }
    set f .gxtxtScriptLibrary.body.right
    $f.parameters delete 1.0 end
    $f.code delete 1.0 end
    $f.code insert 1.0 "% Registered GX-TXT Octave script\nctx = gxtxt_context();\n"
    scriptLibraryUpdateLanguageControls
    $f.e_scope state !disabled
    $f.e_id state !disabled
    $f.e_language state !disabled
    set tree .gxtxtScriptLibrary.body.left.tree
    $tree selection remove [$tree selection]
}

proc ::GX::scriptLibraryLanguageChanged {} {
    set f .gxtxtScriptLibrary.body.right
    if {$::GX::scriptLibraryUi(reference) ne ""} return
    set code [string trim [$f.code get 1.0 end-1c]]
    if {$code eq {% Registered GX-TXT Octave script
ctx = gxtxt_context();} || $code eq {# Registered GX-TXT Python script
from gxtxt import gxtxt_context
ctx = gxtxt_context()}} {
        $f.code delete 1.0 end
        if {$::GX::scriptLibraryUi(language) eq "Python"} {
            $f.code insert 1.0 "# Registered GX-TXT Python script\nfrom gxtxt import gxtxt_context\nctx = gxtxt_context()\n"
        } else {
            $f.code insert 1.0 "% Registered GX-TXT Octave script\nctx = gxtxt_context();\n"
        }
    }
    scriptLibraryUpdateLanguageControls
}
proc ::GX::scriptLibraryUpdateLanguageControls {} {
    variable scriptLibraryUi
    set language $scriptLibraryUi(language)
    if {$language ni {Octave Python}} {set language Octave}
    set extension [expr {$language eq "Python" ? ".py" : ".m"}]
    set scriptLibraryUi(sourceLabel) "$language source (UTF-8)"
    set f .gxtxtScriptLibrary.body.right
    if {[winfo exists $f.buttons.import]} {$f.buttons.import configure -text "Import $extension"}
    if {[winfo exists $f.buttons.export]} {$f.buttons.export configure -text "Export $extension"}
}
proc ::GX::scriptLibraryNewUser {} { scriptLibraryNew user }
proc ::GX::scriptLibraryNewSession {} {
    if {$::GX::currentSession eq ""} {
        set ::GX::scriptLibraryUi(status) "Open a Session first."
        return
    }
    scriptLibraryNew session
}

proc ::GX::scriptLibraryRefresh {} {
    variable scriptLibraryUi
    set w .gxtxtScriptLibrary.body.left.tree
    if {![winfo exists $w]} return
    set search [string tolower [string trim $scriptLibraryUi(search)]]
    $w delete [$w children {}]
    foreach m [scriptRegistryList] {
        set reference "[dict get $m scope]:[dict get $m id]"
        set haystack [string tolower "$reference [dict get $m language] [dict get $m name] [dict get $m description]"]
        if {$search ne "" && [string first $search $haystack] < 0} continue
        $w insert {} end -id $reference -text [dict get $m name] \
            -values [list [dict get $m scope] [dict get $m language] [dict get $m id] [dict get $m version]]
    }
    catch {scriptWorkspaceRefreshChoices}
    # Registry inventory changed/refreshed. Update open editors' Explorer rows
    # through their existing owners, without loading a document or draft buffer.
    foreach refresh {::GX::PythonScriptEditorUI::_refreshDocuments ::GX::OctaveScriptEditorUI::_refreshDocuments} {
        if {[llength [info commands $refresh]]} {catch {{*}$refresh}}
    }
}

proc ::GX::scriptLibrarySelect {} {
    variable scriptLibraryUi
    set tree .gxtxtScriptLibrary.body.left.tree
    set selected [$tree selection]
    if {[llength $selected] != 1} return
    set reference [lindex $selected 0]
    if {[catch {set m [scriptRegistryDescribe $reference]} reason]} {
        set scriptLibraryUi(status) "Open failed: $reason"
        return
    }
    set scriptLibraryUi(reference) $reference
    foreach key {scope language id name version description sha256} { set scriptLibraryUi($key) [dict get $m $key] }
    set scriptLibraryUi(required_apis) [dict get $m explicit_apis]
    set scriptLibraryUi(identity) "Revision [dict get $m revision] | SHA-256 [dict get $m sha256] | required APIs [dict get $m required_apis] | [dict get $m source_scope]:[dict get $m source_id]"
    set f .gxtxtScriptLibrary.body.right
    $f.e_scope state disabled
    $f.e_id state disabled
    $f.e_language state disabled
    $f.parameters delete 1.0 end
    dict for {name descriptor} [dict get $m parameters] {
        $f.parameters insert end "$name | [dict get $descriptor type] | [dict get $descriptor required] | [dict get $descriptor default] | [dict get $descriptor description]\n"
    }
    set ch [open [dict get $m source_path] r]
    fconfigure $ch -encoding utf-8
    try { set code [read $ch] } finally { close $ch }
    $f.code delete 1.0 end
    $f.code insert 1.0 $code
    scriptLibraryUpdateLanguageControls
    set scriptLibraryUi(status) "Loaded $reference"
}

proc ::GX::scriptLibraryParametersFromEditor {} {
    set t .gxtxtScriptLibrary.body.right.parameters
    set params [dict create]
    foreach line [split [$t get 1.0 end-1c] "\n"] {
        if {[string trim $line] eq ""} continue
        set parts [split $line |]
        if {[llength $parts] < 2 || [llength $parts] > 5} { error "Each parameter needs name | type | required | default | description." }
        while {[llength $parts] < 5} { lappend parts "" }
        lassign [lmap part $parts {string trim $part}] name type required default description
        if {$required eq ""} { set required 0 }
        dict set params $name [dict create type $type required $required default $default description $description]
    }
    return $params
}

proc ::GX::scriptLibrarySave {} {
    variable scriptLibraryUi
    set f .gxtxtScriptLibrary.body.right
    set code [$f.code get 1.0 end-1c]
    if {$scriptLibraryUi(reference) ne ""} {
        set registered [scriptRegistryDescribe $scriptLibraryUi(reference)]
        set scriptLibraryUi(language) [dict get $registered language]
    }
    set options [dict create language $scriptLibraryUi(language) version $scriptLibraryUi(version) description $scriptLibraryUi(description) \
        required_apis $scriptLibraryUi(required_apis)]
    if {[catch {
        dict set options parameters [scriptLibraryParametersFromEditor]
        if {$scriptLibraryUi(reference) eq ""} {
            set result [scriptRegistrySave $scriptLibraryUi(scope) $scriptLibraryUi(id) $scriptLibraryUi(name) $code $options]
        } else {
            set result [scriptRegistryUpdate $scriptLibraryUi(scope) $scriptLibraryUi(id) $scriptLibraryUi(sha256) \
                [dict merge $options [dict create name $scriptLibraryUi(name)]] $code]
        }
    } reason]} {
        set scriptLibraryUi(status) "Save failed: $reason"
        return
    }
    set scriptLibraryUi(reference) "[dict get $result scope]:[dict get $result id]"
    set scriptLibraryUi(sha256) [dict get $result sha256]
    set scriptLibraryUi(identity) "Revision [dict get $result revision] | SHA-256 [dict get $result sha256] | required APIs [dict get $result required_apis]"
    set scriptLibraryUi(status) "Saved $scriptLibraryUi(reference)"
    scriptLibraryRefresh
    catch {sessionScriptExplorerPopulate}
    $f.e_scope state disabled
    $f.e_id state disabled
    $f.e_language state disabled
    scriptLibraryUpdateLanguageControls
}

proc ::GX::scriptLibraryAssign {} {
    variable scriptLibraryUi
    if {$scriptLibraryUi(reference) eq ""} { set scriptLibraryUi(status) "Save the script first."; return }
    if {$scriptLibraryUi(scope) ne "user"} { set scriptLibraryUi(status) "Select a user-library script to assign."; return }
    if {[catch {scriptRegistryAssignToSession $scriptLibraryUi(id)} reason]} {
        set scriptLibraryUi(status) "Assign failed: $reason"; return
    }
    scriptLibraryRefresh
    catch {scriptAnalysisRefresh}
    catch {sessionScriptExplorerPopulate}
    set scriptLibraryUi(status) "Session now owns a snapshot of user:$scriptLibraryUi(id)."
}

proc ::GX::scriptLibraryRun {} {
    variable scriptLibraryUi
    if {$scriptLibraryUi(reference) eq ""} { set scriptLibraryUi(status) "Select a registered script first."; return }
    set ::GX::scriptWorkspaceChoice $scriptLibraryUi(reference)
    scriptWorkspaceRunDialog
}

proc ::GX::scriptLibraryAskId {} {
    set w .gxtxtScriptLibrary.askId
    catch {destroy $w}
    toplevel $w
    wm title $w "Register scientific script"
    ttk::label $w.label -text "Stable script ID"
    ttk::entry $w.entry -textvariable ::GX::scriptLibraryUi(importId)
    ttk::button $w.ok -text OK -command {set ::GX::scriptLibraryUi(askDone) 1}
    ttk::button $w.cancel -text Cancel -command {set ::GX::scriptLibraryUi(askDone) 0}
    pack $w.label $w.entry -fill x -padx 10 -pady 5
    pack $w.ok $w.cancel -side left -padx 10 -pady 8
    set ::GX::scriptLibraryUi(importId) ""
    set ::GX::scriptLibraryUi(askDone) -1
    focus $w.entry
    tkwait variable ::GX::scriptLibraryUi(askDone)
    set id [expr {$::GX::scriptLibraryUi(askDone) ? $::GX::scriptLibraryUi(importId) : ""}]
    destroy $w
    return $id
}

proc ::GX::scriptLibraryImport {} {
    variable scriptLibraryUi
    if {$scriptLibraryUi(language) eq "Python"} {
        set types {{{Python source} {.py}} {{Octave source} {.m}} {{Scientific scripts} {.py .m}} {{All files} {*}}}
    } else {
        set types {{{Octave source} {.m}} {{Python source} {.py}} {{Scientific scripts} {.m .py}} {{All files} {*}}}
    }
    set path [tk_getOpenFile -filetypes $types]
    if {$path eq ""} return
    switch -- [string tolower [file extension $path]] {
        .m { set language Octave }
        .py { set language Python }
        default { set scriptLibraryUi(status) "Import requires a .m or .py file."; return }
    }
    set id [scriptLibraryAskId]
    if {$id eq ""} return
    set ch [open $path r]
    fconfigure $ch -encoding utf-8
    try { set code [read $ch] } finally { close $ch }
    set scope $scriptLibraryUi(scope)
    if {[catch {set result [scriptRegistrySave $scope $id [file rootname [file tail $path]] $code \
        [dict create language $language description "Imported from [file tail $path]"]]} reason]} {
        set scriptLibraryUi(status) "Import failed: $reason"; return
    }
    scriptLibraryRefresh
    set tree .gxtxtScriptLibrary.body.left.tree
    $tree selection set "$scope:$id"
    scriptLibrarySelect
    set scriptLibraryUi(status) "Registered $scope:$id."
}

proc ::GX::scriptLibraryExport {} {
    variable scriptLibraryUi
    if {$scriptLibraryUi(reference) eq ""} return
    if {[catch {set m [scriptRegistryDescribe $scriptLibraryUi(reference)]} reason]} { set scriptLibraryUi(status) "Export failed: $reason"; return }
    set extension [expr {[dict get $m language] eq "Python" ? ".py" : ".m"}]
    set filetype [expr {[dict get $m language] eq "Python" ? "Python source" : "Octave source"}]
    set path [tk_getSaveFile -defaultextension $extension -filetypes [list [list $filetype [list $extension]]]]
    if {$path eq ""} return
    if {[file exists $path]} { set scriptLibraryUi(status) "Export target already exists: $path"; return }
    if {[catch {
        file copy -- [dict get $m source_path] $path
    } reason]} { set scriptLibraryUi(status) "Export failed: $reason"; return }
    set scriptLibraryUi(status) "Exported $scriptLibraryUi(reference) to $path"
}

proc ::GX::scriptLibraryRemove {} {
    variable scriptLibraryUi
    if {$scriptLibraryUi(reference) eq ""} return
    scriptLibraryRemoveReference $scriptLibraryUi(reference)
}

proc ::GX::scriptLibraryRemoveReference {reference} {
    variable scriptLibraryUi
    if {$reference eq ""} {return 0}
    if {[catch {
        set script [scriptRegistryDescribe $reference]
        set dependencies [resourceLifecycleScriptDependencies $reference]
    } reason]} {
        if {[winfo exists .gxtxtScriptLibrary]} {set scriptLibraryUi(status) "Delete failed: $reason"}
        tk_messageBox -type ok -icon error -title "Delete script" -message $reason
        return 0
    }
    set name [dict get $script name]
    set id [dict get $script id]
    set scope [dict get $script scope]
    set language [dict get $script language]
    if {[llength $dependencies]} {
        set message "Cannot delete $scope script '$name' (ID $id, $language).\n\nActive Analysis references:\n"
        foreach dependency $dependencies {append message "  • $dependency\n"}
        append message "\nDetach these Analysis references and save the Session before deleting the script. Historical execution snapshots and provenance remain."
        if {[winfo exists .gxtxtScriptLibrary]} {set scriptLibraryUi(status) "Deletion refused: active Analysis references exist."}
        tk_messageBox -type ok -icon warning -title "Script is in use" -message $message
        return 0
    }
    set message "Delete $scope script '$name'?\n\nStable ID: $scope:$id\nLanguage: $language\n\nWILL delete: this registry record and its registry-owned source file.\nWILL preserve: historical execution snapshots and provenance in Sessions, other scripts, and all external source files."
    if {[tk_messageBox -type yesno -default no -icon warning -title "Delete script" -message $message] ne "yes"} {return 0}
    if {[catch {resourceLifecycleDeleteScript $reference} reason]} {
        if {[winfo exists .gxtxtScriptLibrary]} {set scriptLibraryUi(status) "Delete failed: $reason"}
        tk_messageBox -type ok -icon error -title "Delete script failed" -message $reason
        return 0
    }
    if {[winfo exists .gxtxtScriptLibrary]} {
        if {[info exists scriptLibraryUi(reference)] && $scriptLibraryUi(reference) eq $reference} {scriptLibraryNewUser}
        scriptLibraryRefresh
        set scriptLibraryUi(status) "Deleted $reference. Historical execution snapshots remain."
    }
    catch {sessionScriptExplorerPopulate}
    catch {scriptWorkspaceRefreshChoices}
    catch {scriptAnalysisRefresh}
    catch {refreshManifestPreview}
    return 1
}
