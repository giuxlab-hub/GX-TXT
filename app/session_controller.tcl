# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::addLabeledEntry {parent row label varName {width 42}} {
    ttk::label $parent.l$row -text $label
    ttk::entry $parent.e$row -textvariable $varName -width $width
    grid $parent.l$row -row $row -column 0 -sticky e -padx 5 -pady 3
    grid $parent.e$row -row $row -column 1 -sticky ew -padx 5 -pady 3
}

proc ::GX::walkFiles {dir} {
    set out {}
    if {![file isdirectory $dir]} { return $out }
    foreach f [glob -nocomplain -directory $dir *] {
        if {[file isdirectory $f]} {
            set out [concat $out [walkFiles $f]]
        } elseif {[file isfile $f]} {
            lappend out $f
        }
    }
    return [lsort $out]
}

proc ::GX::currentChannelNames {} {
    variable ch
    set out {}
    for {set i 1} {$i <= 8} {incr i} {
        if {$ch($i,enabled) && [string trim $ch($i,name)] ne ""} { lappend out $ch($i,name) }
    }
    return $out
}

proc ::GX::findNodeFile {session node} {
    set safe [sanitize $node]
    foreach suffix {_rigol.csv _canonical.csv} {
        set p [file join $session channels "${safe}${suffix}"]
        if {[file isfile $p]} { return $p }
    }
    return ""
}

proc ::GX::findNodeRigol {session node} {
    set p [file join $session channels "[sanitize $node]_rigol.csv"]
    return [expr {[file isfile $p] ? $p : ""}]
}

proc ::GX::currentSessionDisplayName {} {
    variable currentSession
    if {$currentSession eq "" || ![file isdirectory $currentSession]} { return "No session open" }
    return [file tail [file normalize $currentSession]]
}

proc ::GX::currentSessionInfo {} {
    variable currentSession
    if {$currentSession eq "" || ![file isdirectory $currentSession]} { return {} }
    set path [file normalize $currentSession]
    return [dict create name [currentSessionDisplayName] path $path]
}

proc ::GX::showCurrentSessionInfo {} {
    set info [currentSessionInfo]
    if {![dict size $info]} {
        tk_messageBox -icon info -title "Session" -message "No session is open."
        return
    }
    tk_messageBox -icon info -title "Session" -message "Name: [dict get $info name]
Path: [dict get $info path]"
}

proc ::GX::updateSessionUi_v089_before_session_files {} {
    variable ui
    set ui(sessionPath) [currentSessionDisplayName]
}

proc ::GX::saveCurrentSessionConfig_v092_before_note_files {} {
    variable currentSession
    if {$currentSession eq "" || ![file isdirectory $currentSession]} {
        tk_messageBox -icon info -title "GX-TXT" -message "No session is open.\n\nA session is a folder created by PHASE 1 or New Session, or opened with Open Session."
        return
    }
    set mdir [file join $currentSession metadata]
    if {![file isdirectory $mdir]} { file mkdir $mdir }
    set mf [file join $mdir manifest.ini]
    if {[catch {writeManifest $mf} err]} {
        tk_messageBox -icon error -title "GX-TXT" -message "Unable to save session configuration:\n$err"
        return
    }
    guiLog "Session configuration saved: $mf"
    setStatus "Session configuration saved"
    catch {refreshManifestPreview}
    tk_messageBox -icon info -title "GX-TXT" -message "Configuration saved to session:\n$currentSession\n\nManifest:\n$mf"
}

proc ::GX::openSessionPath_before_project_api_v1 {path} {
    variable currentSession
    set d [file normalize $path]
    if {![file isdirectory [file join $d channels]]} {
        error "The selected folder does not contain channels/: $d"
    }
    # Real Session open includes folders without a Manifest. Reject inconsistent
    # saved Preview dependencies before switching owners or refreshing consumers.
    set selectionData [_modulePreviewOpenPreflight $d]
    _modulePreviewReset
    # A channels-only Session has no Manifest to reset presentation state.
    set ::GX::cfg(analysis_hidden_modules) {}
    # A preview image belongs to the Session that supplied its source PNG.
    # Clear it before loading the next Manifest or rebuilding graph discovery.
    catch {clearGraphPreview}
    # Reset previous-Session script source projections before loading target
    # Manifest bindings. Identical script IDs/SHA do not identify a Session.
    scriptAnalysisResetSessionState $d
    set currentSession $d
    set mf [file join $d metadata manifest.ini]
    if {[file isfile $mf]} {
        if {[catch {
            if {[llength [_modulePreviewSelectionIds]]} {
                _modulePreviewWithLoadContext $mf session $selectionData [list ::GX::loadManifest $mf]
            } else {loadManifest $mf}
        } err opts]} {
            if {[info exists ::GX::sessionCreationOpenTarget] && $::GX::sessionCreationOpenTarget eq $d} {
                return -options $opts $err
            }
            guiLog "Session opened but manifest was not loaded: $err"
        } else {
            guiLog "Session manifest loaded: $mf"
        }
    }
    guiLog "Current session: $currentSession"
    updateSessionUi
    catch {refreshResults}
    catch {refreshAnalysisStatus}
    catch {refreshGraphs}
    catch {discoverPrinters}
    return $currentSession
}

proc ::GX::chooseSession_v087_before_workspace_profiles {} {
    set initial ""
    if {[info exists ::GX::cfg(output_root)] && [file isdirectory $::GX::cfg(output_root)]} { set initial $::GX::cfg(output_root) }
    if {$initial ne ""} {
        set d [tk_chooseDirectory -title "Open GX-TXT session" -initialdir $initial]
    } else {
        set d [tk_chooseDirectory -title "Open GX-TXT session"]
    }
    if {$d eq ""} return
    if {[catch {openSessionPath $d} err]} {
        tk_messageBox -icon error -title "GX-TXT" -message $err
        return
    }
}

proc ::GX::createNewSession {name {projectId ""} {copyDocumentation 1}} {
    variable cfg
    variable currentSession
    if {![string is boolean -strict $copyDocumentation]} {error {Copy documentation must be a boolean.}}
    _experimentDocumentsBeforeCreation
    set normalRoot [string trim $cfg(output_root)]
    set root $normalRoot
    if {$projectId ne ""} {set root [projectSessionsRoot $projectId]}
    if {$root eq ""} {error {Set Session root or load a Workspace profile before creating a session.}}
    set root [file normalize $root]
    set requested [string trim $name]
    if {$requested eq ""} {error {Enter a session name.}}
    set safe [sanitize $requested]
    set saved [_sessionCreationSavedState]
    set documentation [_experimentDocumentsSnapshot]
    file mkdir $root
    set record {}
    try {
        set record [_sessionCreationReserve $root $safe]
        foreach {key filename} [experimentNoteSpecs] {set cfg($key) [expr {$copyDocumentation ? [dict get $documentation $key] : ""}]}
        set cfg(session_name) $safe
        set cfg(output_root) [dict get $record stage_parent]
        set cfg(experiment_id) [experimentGenerateId]
        set cfg(experiment_project_id) $projectId
        set cfg(experiment_project) [expr {$projectId ne "" ? [projectField $projectId name] : ""}]
        set cfg(experiment_project_legacy) ""
        set cfg(experiment_name) $requested
        set session [file normalize [makeSession]]
        set record [_sessionCreationClaim $record $session]
        set eid $cfg(experiment_id)
        defaults
        loadModuleCatalog
        set cfg(output_root) $normalRoot
        set cfg(session_name) $safe
        set cfg(experiment_id) $eid
        set cfg(experiment_project_id) $projectId
        set cfg(experiment_project) [expr {$projectId ne "" ? [projectField $projectId name] : ""}]
        set cfg(experiment_project_legacy) ""
        set cfg(experiment_name) $requested
        set currentSession $session
        experimentDocumentsLoad $session
        set cfg(session_origin) [_originCreate session_experiment]
        loadDatasetRegistry $session
        if {[llength [info commands ::GX::datasetSelectionLoadRegistry]]} {datasetSelectionLoadRegistry $session}
        writeManifest [file join $session metadata manifest.ini]
        set record [_sessionCreationPromote $record]
        set session [dict get $record target]
        set currentSession $session
        writeManifest [file join $session metadata manifest.ini]
        _sessionCreationOpen $record
        updateSessionUi
        guiLog "New session created: $session"
        setStatus "Session created: [file tail $session]"
        return $session
    } on error {message options} {
        _sessionCreationFailure $message $options $record $saved $root
    }
}

proc ::GX::newSessionDialogCommit {w} {
    variable ui
    set projectId [expr {[info exists ui(newSessionProjectIds)] && [dict exists $ui(newSessionProjectIds) $ui(newSessionProject)] ? [dict get $ui(newSessionProjectIds) $ui(newSessionProject)] : ""}]
    set copyDocumentation [expr {[info exists ui(newSessionCopyDocumentation)] ? $ui(newSessionCopyDocumentation) : 1}]
    if {[catch {
        if {$copyDocumentation && [info exists ui(newSessionDocumentationSource)] && $ui(newSessionDocumentationSource) ne $::GX::currentSession} {
            error {The source Session changed. Reopen New Session to choose its documentation.}
        }
        set session [createNewSession $ui(newSessionName) $projectId $copyDocumentation]
    } err opts]} {
        if {[dict exists $opts -errorcode] && [dict get $opts -errorcode] eq {GXTXT SESSION CANCELLED}} {return}
        tk_messageBox -parent $w -icon error -title "New Session" -message $err
        return
    }
    destroy $w
    tk_messageBox -icon info -title "New Session" -message "Session created:
$session"
}

proc ::GX::newSessionProjectChoices {{preferredId ""}} {
    variable ui
    set choices [list "Standalone Session"]
    set ui(newSessionProjectIds) [dict create "Standalone Session" ""]
    foreach id [projectIds] {
        set label "[projectField $id name] ($id)"
        lappend choices $label
        dict set ui(newSessionProjectIds) $label $id
    }
    if {$preferredId eq ""} { set preferredId [projectCurrentId] }
    set ui(newSessionProject) "Standalone Session"
    if {$preferredId ne "" && [projectExists $preferredId]} {
        set ui(newSessionProject) "[projectField $preferredId name] ($preferredId)"
    }
    return $choices
}

proc ::GX::newSessionDialog_before_session_generators_v1 {} {
    variable cfg
    variable ui
    if {[string trim $cfg(output_root)] eq ""} {
        tk_messageBox -icon info -title "New Session" -message "Set Session root or load a Workspace profile before creating a session."
        return
    }
    set root [file normalize $cfg(output_root)]
    set ui(newSessionName) ""
    set w .gxNewSession
    catch {destroy $w}
    toplevel $w
    wm title $w "New Session"
    wm transient $w .
    grid columnconfigure $w 1 -weight 1
    ttk::label $w.rootLabel -text "Session root:"
    ttk::label $w.root -text $root
    ttk::label $w.nameLabel -text "Session name:"
    ttk::entry $w.name -textvariable ::GX::ui(newSessionName) -width 36
    ttk::frame $w.buttons
    ttk::button $w.buttons.create -text "Create" -command [list ::GX::newSessionDialogCommit $w]
    ttk::button $w.buttons.cancel -text "Cancel" -command [list destroy $w]
    grid $w.rootLabel -row 0 -column 0 -sticky e -padx 6 -pady 6
    grid $w.root -row 0 -column 1 -sticky w -padx 6 -pady 6
    grid $w.nameLabel -row 1 -column 0 -sticky e -padx 6 -pady 6
    grid $w.name -row 1 -column 1 -sticky ew -padx 6 -pady 6
    pack $w.buttons.create $w.buttons.cancel -side left -padx 4
    grid $w.buttons -row 2 -column 0 -columnspan 2 -pady 8
    bind $w.name <Return> [list ::GX::newSessionDialogCommit $w]
    bind $w <Escape> [list destroy $w]
    focus $w.name
    grab $w
    tkwait window $w
}
