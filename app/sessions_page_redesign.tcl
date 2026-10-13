# Sessions page: files, registered scripts and read-only Manifest inspection.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX { variable sessionsUi }

proc ::GX::sessionConfigGroup {section} {
    switch -glob -- $section {
        pipeline - session - documentation_api { return General }
        runtime - graphics - parallel_execution { return Runtime }
        experiment - project* { return Experiment }
        instrument* { return Instrumentation }
        acquisition - source_variables - dataset* { return {Datasets / source variables} }
        module_state - module_config* - module_binding* - module_source* - module_plot* { return Modules }
        default { return Other }
    }
}

proc ::GX::sessionConfigRefresh {} {
    variable currentSession
    variable sessionsUi
    set tree .top.nb.sessionfiles.config.pages.structured.tree
    set raw .top.nb.sessionfiles.config.pages.raw.text
    if {![winfo exists $tree] || ![winfo exists $raw]} return
    $tree delete [$tree children {}]
    $raw configure -state normal
    $raw delete 1.0 end
    set path [expr {$currentSession eq "" ? "" : [file join $currentSession metadata manifest.ini]}]
    if {$path eq "" || ![file isfile $path]} {
        set sessionsUi(configStatus) "No saved Session manifest is available."
        $raw insert end "No saved Session manifest is available."
        $raw configure -state disabled
        return
    }
    set fd [open $path r]
    fconfigure $fd -encoding utf-8 -translation auto
    try { set text [read $fd 4194305] } finally { close $fd }
    if {[string length $text] > 4194304} {
        set sessionsUi(configStatus) "Manifest exceeds the 4 MiB inspection limit."
        $raw insert end $sessionsUi(configStatus)
        $raw configure -state disabled
        return
    }
    $raw insert end $text
    $raw configure -state disabled
    if {[catch {set ini [parseIni $path]} reason]} {
        set sessionsUi(configStatus) "Manifest parse error: $reason"
        return
    }
    foreach full [lsort -dictionary [dict keys $ini]] {
        if {![regexp {^(.+)\.([^.]+)$} $full -> section key]} continue
        set group [sessionConfigGroup $section]
        set groupId "group:$group"
        if {![$tree exists $groupId]} { $tree insert {} end -id $groupId -text $group -open 1 }
        set sectionId "section:$section"
        if {![$tree exists $sectionId]} { $tree insert $groupId end -id $sectionId -text $section -open 0 }
        $tree insert $sectionId end -text $key -values [list [dict get $ini $full]]
    }
    set sessionsUi(configStatus) "Saved Session manifest: $path (read-only)"
}

proc ::GX::sessionPageSelect {{section {}}} {
    set f .top.nb.sessionfiles
    if {![winfo exists $f.navigation]} return
    if {$section eq {}} {set section [lindex {files scripts workspaces config parameters experiment instrumentation} [$f.navigation current]]}
    if {$section eq {}} {set section files}
    set index [lsearch -exact {files scripts workspaces config parameters experiment instrumentation} $section];if {$index>=0} {$f.navigation current $index}
    if {[winfo exists .top.nb.exp]} {grid remove .top.nb.exp}
    if {[winfo exists .top.nb.instr]} {grid remove .top.nb.instr}
    # Keep the established widget identities and operation references; mapping
    # one section into the shared area never replaces Session state.
    foreach child {left right scripts scriptInfo config workspaceArea parameters} {
        if {[winfo exists $f.$child]} {grid remove $f.$child}
    }
    switch $section {
        instrumentation {
            if {[winfo exists .top.nb.instr]} {
                grid .top.nb.instr -in $f.content -row 0 -column 0 -columnspan 2 -sticky nsew
                raise .top.nb.instr
            }
        }
        experiment {
            # Keep the real, dynamically rebuilt panel and all callback paths.
            # Tk permits a sibling to be managed in a descendant of its parent.
            if {[winfo exists .top.nb.exp]} {
                grid .top.nb.exp -in $f.content -row 0 -column 0 -columnspan 2 -sticky nsew
                raise .top.nb.exp
            }
        }
        files {
            grid $f.left -in $f.content -row 0 -column 0 -columnspan 1 -sticky nsew
            grid $f.right -in $f.content -row 0 -column 1 -columnspan 1 -sticky nsew
        }
        scripts {
            grid $f.scripts -in $f.content -row 0 -column 0 -columnspan 2 -sticky nsew
            grid $f.scriptInfo -in $f.content -row 1 -column 0 -columnspan 2 -sticky ew
        }
        config {
            if {[winfo exists $f.config]} {
                grid $f.config -in $f.content -row 0 -column 0 -columnspan 2 -sticky nsew
                sessionConfigRefresh
            }
        }
        parameters {
            if {![winfo exists $f.parameters]} {ttk::frame $f.parameters;parameterEditorBuild $f.parameters session}
            grid $f.parameters -in $f.content -row 0 -column 0 -columnspan 2 -sticky nsew
            parameterEditorAction $f.parameters refresh
        }
        workspaces {
            if {[winfo exists $f.workspaceArea]} {grid $f.workspaceArea -in $f.content -row 0 -column 0 -columnspan 2 -sticky nsew}
        }
    }
}
proc ::GX::sessionConfigToggle {} {sessionPageSelect config}

proc ::GX::buildSessionFileExplorerGui {} {
    variable sessionsUi
    ::GX::buildSessionFileExplorerGui_before_sessions_page
    set nb .top.nb
    set f $nb.sessionfiles
    if {![winfo exists $f]} return
    $nb tab $f -text Sessions
    if {[winfo exists $f.config]} return
    ttk::menubutton $f.bar.jobDetails -text Jobs -menu $f.bar.jobDetails.menu
    menu $f.bar.jobDetails.menu -tearoff 0 -postcommand [list ::GX::sessionJobsMenuStates $f.bar.jobDetails.menu]
    $f.bar.jobDetails.menu add command -label {Open selected job details…} -command ::GX::sessionFileExplorerOpenRun
    $f.bar.jobDetails.menu add command -label {Open Script Jobs Manager…} -command ::GX::scriptJobsDialog
    $f.bar.jobDetails.menu add command -label {Run registered script…} -command ::GX::scriptLibraryDialog
    $f.bar.jobDetails.menu add command -label {Rerun selected job…} -command ::GX::sessionJobsRerun
    pack $f.bar.jobDetails -side left -padx 4 -before $f.bar.info
    bind $::GX::ui(sessionFileTree) <Double-1> {if {[::GX::sessionFileExplorerRunSelected] ne {}} {::GX::sessionFileExplorerOpenRun} else {::GX::sessionFileExplorerOpenSelected}}
    ttk::scrollbar $f.left.sx -orient horizontal -command [list $::GX::ui(sessionFileTree) xview]
    $::GX::ui(sessionFileTree) configure -xscrollcommand [list $f.left.sx set]
    $::GX::ui(sessionFileTree) column #0 -width 950 -stretch 0
    grid $f.left.sx -row 1 -column 0 -sticky ew
    ttk::button $f.scripts.actions.delete -text "Delete selected..." -command {
        set id [::GX::sessionScriptExplorerSelected]
        if {$id ne ""} { ::GX::scriptLibraryRemoveReference "session:$id" }
    }
    pack $f.scripts.actions.delete -fill x -padx 3 -pady 3
    ttk::labelframe $f.config -text "Session configuration and Manifest"
    grid columnconfigure $f.config 0 -weight 1
    grid rowconfigure $f.config 0 -weight 1
    ttk::notebook $f.config.pages
    grid $f.config.pages -row 0 -column 0 -sticky nsew
    ttk::frame $f.config.pages.structured
    ttk::frame $f.config.pages.raw
    $f.config.pages add $f.config.pages.structured -text "Structured view"
    $f.config.pages add $f.config.pages.raw -text "Raw INI"
    ttk::treeview $f.config.pages.structured.tree -columns {value} -show {tree headings} -height 8
    $f.config.pages.structured.tree heading #0 -text "Section / setting"
    $f.config.pages.structured.tree heading value -text "Saved value"
    $f.config.pages.structured.tree column #0 -width 330
    $f.config.pages.structured.tree column value -width 540
    ttk::scrollbar $f.config.pages.structured.sy -orient vertical -command [list $f.config.pages.structured.tree yview]
    $f.config.pages.structured.tree configure -yscrollcommand [list $f.config.pages.structured.sy set]
    pack $f.config.pages.structured.sy -side right -fill y
    pack $f.config.pages.structured.tree -fill both -expand 1
    text $f.config.pages.raw.text -wrap none -font TkFixedFont -state disabled -height 10
    ttk::scrollbar $f.config.pages.raw.sy -orient vertical -command [list $f.config.pages.raw.text yview]
    $f.config.pages.raw.text configure -yscrollcommand [list $f.config.pages.raw.sy set]
    pack $f.config.pages.raw.sy -side right -fill y
    pack $f.config.pages.raw.text -fill both -expand 1
    ttk::label $f.config.status -textvariable ::GX::sessionsUi(configStatus) -anchor w
    grid $f.config.status -row 1 -column 0 -sticky ew -padx 5 -pady 3
    sessionConfigRefresh
    sessionPageSelect
}

proc ::GX::updateSessionUi {} {
    set result [::GX::updateSessionUi_before_sessions_page]
    catch {sessionConfigRefresh}
    return $result
}

proc ::GX::onNotebookChanged_before_run_plan {nb} {
    set result [::GX::onNotebookChanged_before_sessions_page $nb]
    if {[$nb select] eq "$nb.sessionfiles"} { catch {sessionConfigRefresh} }
    return $result
}
