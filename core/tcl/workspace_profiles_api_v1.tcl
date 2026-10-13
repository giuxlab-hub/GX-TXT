# GX-TXT Working Directory Profiles API v1
# SPDX-License-Identifier: GPL-3.0-or-later
# User-local working-directory profiles. Profiles never alter scientific data.

namespace eval ::GX {
    variable workspaceProfilesApiVersion 1
    variable workspaceProfileCatalog
    variable workspaceProfileCurrent ""
    variable workspaceDir
    array set workspaceDir {acquisition_dir "" session_root "" session_open_dir "" manifest_dir "" export_dir ""}
}

proc ::GX::workspaceProfilesPath {} {
    if {[info exists ::env(XDG_CONFIG_HOME)] && [string trim $::env(XDG_CONFIG_HOME)] ne ""} {
        set root $::env(XDG_CONFIG_HOME)
    } elseif {[info exists ::env(HOME)] && [string trim $::env(HOME)] ne ""} {
        set root [file join $::env(HOME) .config]
    } else {
        set root [pwd]
    }
    return [file join $root gxtxt_pipeline working_directory_profiles.ini]
}

proc ::GX::workspaceProfileFields {} { return {acquisition_dir session_root session_open_dir manifest_dir export_dir} }

proc ::GX::workspaceProfilesLoadCatalog {} {
    variable workspaceProfileCatalog
    array unset workspaceProfileCatalog *
    set p [workspaceProfilesPath]
    if {![file isfile $p]} { return {} }
    set d [parseIni $p]
    set names {}
    foreach k [dict keys $d] {
        if {[regexp {^profile\.(.+)\.name$} $k -> n]} { lappend names $n }
    }
    foreach n [lsort -dictionary -unique $names] {
        foreach f [workspaceProfileFields] {
            set k "profile.$n.$f"
            set workspaceProfileCatalog($n,$f) [expr {[dict exists $d $k] ? [dict get $d $k] : ""}]
        }
    }
    return [lsort -dictionary -unique $names]
}

proc ::GX::workspaceProfileNames {} {
    variable workspaceProfileCatalog
    workspaceProfilesLoadCatalog
    set out {}
    foreach k [array names workspaceProfileCatalog "*,session_root"] { lappend out [lindex [split $k ,] 0] }
    return [lsort -dictionary -unique $out]
}

# Save without applying: catalog edits must never overwrite the active chooser context.
proc ::GX::workspaceProfileSave {name values} {
    variable workspaceProfileCatalog
    set name [string trim $name]
    if {![regexp {^[A-Za-z0-9_.-]+$} $name]} {error {Enter a profile name using letters, digits, '.', '_' or '-'.}}
    set previous [array get workspaceProfileCatalog]
    try {
        foreach role [workspaceProfileFields] {
            set value [datasetPublicationV2DictDefault $values $role {}]
            if {[regexp {[\r\n]} $value] || ($value ne {} && [file pathtype $value] ne {absolute})} {error "Global directory '$role' requires an absolute, single-line path."}
            set workspaceProfileCatalog($name,$role) [workspaceNormalizeDir $value]
        }
        workspaceProfilesSaveCatalog
    } on error {message options} {
        array unset workspaceProfileCatalog *;array set workspaceProfileCatalog $previous
        return -options $options $message
    }
    workspaceProfilesRefreshGui
    return $name
}
proc ::GX::workspaceProfilesSaveCatalog {} {
    variable workspaceProfileCatalog
    variable workspaceProfileCurrent
    variable workspaceDir
    set p [workspaceProfilesPath];file mkdir [file dirname $p]
    set temp "$p.tmp.[pid].[clock clicks]";set fd {}
    try {
        set fd [open $temp w];fconfigure $fd -encoding utf-8 -translation lf
        puts $fd "; GX-TXT Working Directory Profiles API v1"
        puts $fd "\[registry\]";putKV $fd api_version 1;putKV $fd current $workspaceProfileCurrent
        foreach role [workspaceProfileFields] {putKV $fd "directory.$role" $workspaceDir($role)}
        set names {}
        foreach k [array names workspaceProfileCatalog "*,session_root"] {lappend names [lindex [split $k ,] 0]}
        foreach name [lsort -dictionary -unique $names] {
            puts $fd "\n\[profile.$name\]";putKV $fd name $name
            foreach role [workspaceProfileFields] {putKV $fd $role [expr {[info exists workspaceProfileCatalog($name,$role)] ? $workspaceProfileCatalog($name,$role) : {}}]}
        }
        close $fd;set fd {};file rename -force -- $temp $p
    } finally {if {$fd ne {}} {catch {close $fd}};if {[file exists $temp]} {file delete -- $temp}}
    return $p
}
# The existing profile INI is the single preferences authority. Additive applied
# context survives restart, while old catalogs without these keys stay valid.
proc ::GX::workspaceStorageRestore {} {
    variable workspaceProfileCurrent;variable workspaceDir;variable cfg
    if {![file isfile [workspaceProfilesPath]]} return
    set data [parseIni [workspaceProfilesPath]]
    workspaceProfilesLoadCatalog
    set workspaceProfileCurrent [datasetPublicationV2DictDefault $data registry.current {}]
    foreach role [workspaceProfileFields] {
        if {[dict exists $data registry.directory.$role]} {set workspaceDir($role) [dict get $data registry.directory.$role]}
    }
    if {$workspaceDir(session_root) ne {}} {set cfg(output_root) $workspaceDir(session_root)}
    if {$workspaceDir(export_dir) ne {}} {set cfg(export_dir) $workspaceDir(export_dir)}
}

proc ::GX::workspaceNormalizeDir {p} {
    set p [string trim $p]
    if {$p eq ""} { return "" }
    return [file normalize $p]
}

proc ::GX::workspaceProfileCaptureCurrent {name} {
    variable workspaceProfileCatalog
    variable workspaceDir
    variable cfg
    set name [string trim $name]
    if {$name eq "" || ![regexp {^[A-Za-z0-9_.-]+$} $name]} { error "Profile name may contain only letters, digits, '.', '_' and '-'." }
    if {[string trim $workspaceDir(session_root)] eq ""} { set workspaceDir(session_root) $cfg(output_root) }
    if {[string trim $workspaceDir(export_dir)] eq ""} { set workspaceDir(export_dir) $cfg(export_dir) }
    foreach f [workspaceProfileFields] {
        set workspaceProfileCatalog($name,$f) [workspaceNormalizeDir [expr {[info exists workspaceDir($f)] ? $workspaceDir($f) : ""}]]
    }
    workspaceProfilesSaveCatalog
    workspaceProfilesRefreshGui
    return $name
}

proc ::GX::workspaceProfileApply {name} {
    variable workspaceProfileCatalog;variable workspaceProfileCurrent;variable workspaceDir;variable cfg
    workspaceProfilesLoadCatalog;set name [string trim $name]
    if {$name eq {} || ![info exists workspaceProfileCatalog($name,session_root)]} {error "Unknown working-directory profile '$name'."}
    set oldDirs [array get workspaceDir];set oldCfg [array get cfg];set oldName $workspaceProfileCurrent
    try {
        foreach role [workspaceProfileFields] {set workspaceDir($role) $workspaceProfileCatalog($name,$role)}
        set cfg(output_root) $workspaceDir(session_root);set cfg(export_dir) $workspaceDir(export_dir);set workspaceProfileCurrent $name
        workspaceProfilesSaveCatalog
    } on error {message options} {
        array unset workspaceDir *;array set workspaceDir $oldDirs;array unset cfg *;array set cfg $oldCfg;set workspaceProfileCurrent $oldName
        return -options $options $message
    }
    workspaceProfilesRefreshGui;catch {refreshManifestPreview}
    return $name
}

proc ::GX::workspaceProfileDelete {name} {
    variable workspaceProfileCatalog;variable workspaceProfileCurrent
    set name [string trim $name];set old [array get workspaceProfileCatalog];set current $workspaceProfileCurrent
    try {
        foreach key [array names workspaceProfileCatalog "$name,*"] {unset workspaceProfileCatalog($key)}
        if {$workspaceProfileCurrent eq $name} {set workspaceProfileCurrent {}}
        workspaceProfilesSaveCatalog
    } on error {message options} {
        array unset workspaceProfileCatalog *;array set workspaceProfileCatalog $old;set workspaceProfileCurrent $current
        return -options $options $message
    }
    workspaceProfilesRefreshGui
}

proc ::GX::workspaceInitialDir {role {fallback ""}} {
    variable workspaceDir
    variable cfg
    if {[info exists workspaceDir($role)] && [string trim $workspaceDir($role)] ne "" && [file isdirectory $workspaceDir($role)]} { return $workspaceDir($role) }
    if {$role eq "session_root" && [string trim $cfg(output_root)] ne ""} { return $cfg(output_root) }
    if {$role eq "export_dir" && [string trim $cfg(export_dir)] ne ""} { return $cfg(export_dir) }
    if {$fallback ne "" && [file isdirectory $fallback]} { return $fallback }
    return [pwd]
}

proc ::GX::workspaceRememberDir {role path} {
    variable workspaceDir
    set p [string trim $path]
    if {$p eq ""} return
    if {[file isdirectory $p]} { set workspaceDir($role) [file normalize $p] } else { set workspaceDir($role) [file normalize [file dirname $p]] }
}

# Shared chooser policy for every CORE API loaded after this file.  Callers may
# provide an explicit -initialdir (for example, the directory of a populated
# module field); otherwise the selected Workspace role supplies it.
proc ::GX::workspaceValidateRole {role} {
    if {[lsearch -exact [workspaceProfileFields] $role] < 0} {
        error "Unknown working-directory profile role '$role'."
    }
    return $role
}

proc ::GX::_workspaceChooserArgs {role options} {
    workspaceValidateRole $role
    if {[lsearch -exact $options -initialdir] < 0} {
        lappend options -initialdir [workspaceInitialDir $role]
    }
    return $options
}

proc ::GX::workspaceOpenFile {role args} {
    set options [_workspaceChooserArgs $role $args]
    set selected [tk_getOpenFile {*}$options]
    if {$selected ne ""} { workspaceRememberDir $role [lindex $selected 0] }
    return $selected
}

proc ::GX::workspaceSaveFile {role args} {
    set options [_workspaceChooserArgs $role $args]
    set selected [tk_getSaveFile {*}$options]
    if {$selected ne ""} { workspaceRememberDir $role $selected }
    return $selected
}

# The unremembered primitive lets a caller validate a selected directory before
# committing it to profile runtime state (notably Open Session).
proc ::GX::_workspaceChooseDirectory {role args} {
    set options [_workspaceChooserArgs $role $args]
    return [tk_chooseDirectory {*}$options]
}

proc ::GX::workspaceChooseDirectory {role args} {
    set selected [_workspaceChooseDirectory $role {*}$args]
    if {$selected ne ""} { workspaceRememberDir $role $selected }
    return $selected
}

proc ::GX::workspaceProfilesRefreshGui {} {
    variable ui
    if {![llength [info commands winfo]]} return
    if {[info exists ui(workspaceProfileCombo)] && [winfo exists $ui(workspaceProfileCombo)] && [winfo class $ui(workspaceProfileCombo)] eq {TCombobox}} {
        $ui(workspaceProfileCombo) configure -values [workspaceProfileNames]
    }
    if {[llength [info commands storageProfilesRefresh]]} {
        storageProfilesRefresh .top.nb.configuration.sections.storage.profiles global
        storageProfilesRefresh .top.nb.sessionfiles.config.pages.storage private
    }
}

proc ::GX::workspaceProfileLoadFromBar {} {
    variable workspaceProfileCurrent
    if {[catch {workspaceProfileApply $workspaceProfileCurrent} err]} { tk_messageBox -icon error -title "GX-TXT" -message $err; return }
    setStatus "Working-directory profile loaded: $workspaceProfileCurrent"
}

proc ::GX::workspaceProfilesBrowseRole {role} {
    variable workspaceDir
    set d [tk_chooseDirectory -title "Choose $role" -initialdir [workspaceInitialDir $role]]
    if {$d ne ""} { set workspaceDir($role) [file normalize $d] }
}

proc ::GX::workspaceProfilesDialog {} {
    variable workspaceDir
    variable workspaceProfileCurrent
    if {[string trim $workspaceDir(session_root)] eq ""} { set workspaceDir(session_root) $::GX::cfg(output_root) }
    if {[string trim $workspaceDir(export_dir)] eq ""} { set workspaceDir(export_dir) $::GX::cfg(export_dir) }
    set w .workspace_profiles
    catch {destroy $w}; toplevel $w; wm title $w "Working directory profiles"
    grid columnconfigure $w 1 -weight 1
    ttk::label $w.lp -text "Profile"
    ttk::combobox $w.profile -textvariable ::GX::workspaceProfileCurrent -values [workspaceProfileNames] -width 28
    ttk::button $w.load -text "Load" -command ::GX::workspaceProfileLoadFromBar
    grid $w.lp -row 0 -column 0 -sticky e -padx 5 -pady 5; grid $w.profile -row 0 -column 1 -sticky ew -padx 5 -pady 5; grid $w.load -row 0 -column 2 -padx 5 -pady 5
    set r 1
    foreach {role label} {acquisition_dir "Acquisition / source directory" session_root "Session root" session_open_dir "Open-session directory" manifest_dir "Manifest directory" export_dir "Export / PDF directory"} {
        ttk::label $w.l$r -text $label
        ttk::entry $w.e$r -textvariable ::GX::workspaceDir($role)
        ttk::button $w.b$r -text "Browse..." -command [list ::GX::workspaceProfilesBrowseRole $role]
        grid $w.l$r -row $r -column 0 -sticky e -padx 5 -pady 3; grid $w.e$r -row $r -column 1 -sticky ew -padx 5 -pady 3; grid $w.b$r -row $r -column 2 -padx 5 -pady 3
        incr r
    }
    ttk::label $w.note -text "Loading a profile changes dialog starting directories and Session root / Export directory. It never changes the currently open session." -wraplength 760 -justify left
    grid $w.note -row $r -column 0 -columnspan 3 -sticky ew -padx 5 -pady 7; incr r
    ttk::frame $w.buttons
    ttk::button $w.buttons.apply -text "Apply current values" -command {set ::GX::cfg(output_root) $::GX::workspaceDir(session_root); set ::GX::cfg(export_dir) $::GX::workspaceDir(export_dir); ::GX::refreshManifestPreview}
    ttk::button $w.buttons.save -text "Save / update profile" -command {if {[catch {::GX::workspaceProfileCaptureCurrent $::GX::workspaceProfileCurrent} e]} {tk_messageBox -icon error -message $e} else {tk_messageBox -icon info -message "Working-directory profile saved."}}
    ttk::button $w.buttons.delete -text "Delete profile" -command {if {$::GX::workspaceProfileCurrent ne ""} {::GX::workspaceProfileDelete $::GX::workspaceProfileCurrent}}
    ttk::button $w.buttons.close -text "Close" -command [list destroy $w]
    pack $w.buttons.apply $w.buttons.save $w.buttons.delete $w.buttons.close -side left -padx 4
    grid $w.buttons -row $r -column 0 -columnspan 3 -pady 8
}

# Apply profile-aware initial directories without changing public commands.
proc ::GX::chooseInput_v088_before_acquisition_handler_api {} {
    variable cfg
    set p [workspaceOpenFile acquisition_dir -title "Acquisition CSV" -filetypes {{{CSV} {.csv}} {{All files} *}}]
    if {$p eq ""} return
    set cfg(input_csv) [file normalize $p]
    if {$cfg(output_root) eq ""} { set cfg(output_root) [file join [file dirname $cfg(input_csv)] GXTXT_sessions] }
    catch {refreshCsvPreview}
}
proc ::GX::chooseInput {} {
    return [::GX::chooseInput_v088_before_acquisition_handler_api]
}

proc ::GX::chooseOutput {} {
    variable cfg; variable workspaceDir
    set p [workspaceChooseDirectory session_root -title "Session root folder"]
    if {$p ne ""} { set cfg(output_root) [file normalize $p]; set workspaceDir(session_root) $cfg(output_root) }
}

proc ::GX::chooseSession_v092_before_note_files {} {
    set d [_workspaceChooseDirectory session_open_dir -title "Open GX-TXT session"]
    if {$d eq ""} return
    if {[catch {openSessionPath $d} err]} {
        tk_messageBox -icon error -title "GX-TXT" -message $err
        return
    }
    workspaceRememberDir session_open_dir $d
}

proc ::GX::saveManifestDialog {} {
    if {[catch {channelSpec} err]} { tk_messageBox -icon error -message $err; return }
    set p [workspaceSaveFile manifest_dir -title "Export configuration manifest" -defaultextension .ini -filetypes {{{Manifest INI} {.ini}} {{All files} *}}]
    if {$p eq ""} return
    if {[catch {writeManifest $p} err]} { tk_messageBox -icon error -message $err }
}

proc ::GX::loadManifestDialog {} {
    set p [workspaceOpenFile manifest_dir -title "Load configuration manifest only" -filetypes {{{Manifest INI} {.ini}} {{All files} *}}]
    if {$p eq ""} return
    if {[catch {loadManifest $p} err]} { tk_messageBox -icon error -message $err; return }
    catch {refreshCsvPreview}; catch {refreshManifestPreview}; catch {refreshModuleCatalog}; catch {refreshCustomCompareTree}; catch {guiLog "Manifest loaded: $p"}; catch {setStatus "Manifest loaded"}
}

proc ::GX::genericCsvBatchAddMultiple_v088_before_acquisition_handler_batch {} {
    set paths [workspaceOpenFile acquisition_dir -multiple 1 -filetypes {{{CSV / text tables} {.csv .txt .tsv}} {{All files} *}}]
    if {![llength $paths]} return
    foreach p $paths { genericCsvBatchAdd $p }
}
proc ::GX::genericCsvBatchAddMultiple {} {
    return [::GX::genericCsvBatchAddMultiple_v088_before_acquisition_handler_batch]
}

proc ::GX::genericCsvBatchBrowse_v088_before_acquisition_handler_batch {i} {
    variable genericCsvBatch
    set p [workspaceOpenFile acquisition_dir -filetypes {{{CSV / text tables} {.csv .txt .tsv}} {{All files} *}}]
    if {$p eq ""} return
    set genericCsvBatch($i,path) $p
    if {![info exists genericCsvBatch($i,dataset_id)] || [string trim $genericCsvBatch($i,dataset_id)] eq "" || [string match "dataset.*" $genericCsvBatch($i,dataset_id)]} { set genericCsvBatch($i,dataset_id) [genericCsvAutoDatasetId $p] }
    catch {genericCsvBatchClearVariables $i}; catch {genericCsvBatchEnsureVariables $i 1}; catch {refreshManifestPreview}; catch {genericCsvBatchRender}
}
proc ::GX::genericCsvBatchBrowse {i} {
    return [::GX::genericCsvBatchBrowse_v088_before_acquisition_handler_batch $i]
}

proc ::GX::launchGui_v090_before_plot_region {} {
    variable ui
    ::GX::launchGui_v087_before_workspace_profiles
    workspaceProfilesLoadCatalog
    if {[winfo exists .top.sessionbar]} {
        ttk::separator .top.sessionbar.wssep -orient vertical
        ttk::label .top.sessionbar.wslab -text "Workspace:"
        ttk::combobox .top.sessionbar.ws -textvariable ::GX::workspaceProfileCurrent -values [workspaceProfileNames] -state readonly -width 16
        set ui(workspaceProfileCombo) .top.sessionbar.ws
        ttk::button .top.sessionbar.wsload -text "Load" -command ::GX::workspaceProfileLoadFromBar
        ttk::button .top.sessionbar.wsedit -text "Directories..." -command ::GX::workspaceProfilesDialog
        pack .top.sessionbar.wssep .top.sessionbar.wslab .top.sessionbar.ws .top.sessionbar.wsload .top.sessionbar.wsedit -side left -padx 3
    }
}
