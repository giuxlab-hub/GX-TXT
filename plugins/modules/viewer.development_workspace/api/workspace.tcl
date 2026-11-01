# SPDX-License-Identifier: GPL-3.0-or-later
# Ordinary Viewer client. CORE owns policy, compiler, runtime, native views and packages.
namespace eval ::GX::ViewerDevelopmentWorkspace {variable s;array set s {project {} mode cpp file handlers.cpp dirty 0 baseline {} busy {} generation 0 windowGeneration 0 status {Open or create a restricted C++ project, or maintain an approved installed Viewer. No scientific Session is required.} preview {} find {}}}
source [file join [file dirname [info script]] project_files.tcl]
proc ::GX::ViewerDevelopmentWorkspace::safe {method args} {
    if {[catch {[namespace current]::$method {*}$args} result options]} {set ::GX::ViewerDevelopmentWorkspace::s(status) $result;log "$result\n";return [dict create status FAILED message $result]}
    return $result
}
proc ::GX::ViewerDevelopmentWorkspace::log {message} {
    set text .gxViewerDevelopment.bottom.output.text
    if {![winfo exists $text]} return
    $text configure -state normal;if {[string length [$text get 1.0 end]]>65536} {$text delete 1.0 end-32768c};$text insert end $message;$text see end;$text configure -state disabled
}
proc ::GX::ViewerDevelopmentWorkspace::text {} {variable s;return [expr {[info exists s(editor)]?$s(editor):{}}]}
proc ::GX::ViewerDevelopmentWorkspace::modified {{widget {}}} {
    variable s;if {![winfo exists [text]]} return
    if {$s(mode) in {cpp acquisition}} {projectDirty;return}
    set s(dirty) [expr {[::GX::sourceSurfaceGet [text]] ne $s(baseline)}]
    set s(status) "[file tail $s(project)] / $s(file) · [expr {$s(dirty)?{unsaved}:{saved}}]"
}
proc ::GX::ViewerDevelopmentWorkspace::prepare {} {
    variable s
    if {$s(mode) eq {acquisition}} {return [acqPrepare]}
    if {$s(mode) eq {cpp} && ![projectNotesReview]} {return 0}
    if {!$s(dirty)} {return 1}
    set answer [tk_messageBox -parent .gxViewerDevelopment -type yesnocancel -icon question -title {Unsaved developer source} -message [expr {$s(mode) eq {cpp}?{Save all changed project sources before continuing?}:{Save the current source before continuing?}}]]
    if {$answer eq {cancel}} {return 0};if {$answer eq {yes}} {if {$s(mode) eq {cpp}} {saveAll} else {save};if {$s(dirty)} {error {New edits arrived during Save; review them before continuing}}}
    return 1
}
proc ::GX::ViewerDevelopmentWorkspace::save {} {
    variable s
    if {$s(mode) eq {maintenance}} {return [maintenanceSave]}
    set note [projectNotesActive]
    if {$note ne {}} {return [::GX::sourceNoteEditorSaveSafe [dict get $s(notes) $note editor]]}
    if {$s(mode) eq {acquisition}} {return [acqSave]}
    return [projectSave]
}
proc ::GX::ViewerDevelopmentWorkspace::transfer {operation source {filename handlers.cpp}} {
    variable s;variable transferSerial;variable transfers
    if {$s(busy) ne {}} {error {Wait or cancel the current development request}}
    set id [incr transferSerial]
    set s(busy) [::GX::viewerDevelopmentRequest $operation $s(project) [list ::GX::ViewerDevelopmentWorkspace::transferred $id] [dict create file $filename source $source]]
    set s(status) "[string totitle $operation] through the project-write backend…";controls
    try {
        vwait ::GX::ViewerDevelopmentWorkspace::transfers($id)
        set response $transfers($id)
        if {![dict get $response ok]} {error "[::GX::datasetPublicationV2DictDefault $response code SOURCE_TRANSFER]: [dict get $response error]"}
        set result [dict get $response result]
        if {[dict get $result status] ni {SAVED PASS}} {
            log "$response\n";error "Source policy refused this import: $result"
        }
        return $result
    } finally {unset -nocomplain transfers($id);set s(busy) {};controls}
}
proc ::GX::ViewerDevelopmentWorkspace::transferred {id response} {
    variable transfers
    # Wake the caller even if its window was closed during cancellation.
    set transfers($id) $response
}
proc ::GX::ViewerDevelopmentWorkspace::read {name} {
    variable s
    if {$s(mode) eq {maintenance}} {if {![prepare]} return;return [maintenanceRead $name]}
    return [projectRead $name]
}
proc ::GX::ViewerDevelopmentWorkspace::selected {} {
    set name [lindex [.gxViewerDevelopment.body.left.files.tree selection] 0]
    if {$name ne {} && ![string match folder:* $name]} {safe read $name}
}
proc ::GX::ViewerDevelopmentWorkspace::project {path} {
    variable s
    set path [file normalize $path]
    if {[acqTarget $path]} {return [acqProject $path]}
    if {![prepare]} return
    acqReferenceRestore
    if {[file isfile [file join $path maintenance.json]]} {return [maintenanceProject $path]}
    if {![file isfile [file join $path project.json]]} {error {Choose a developer project containing project.json or maintenance.json}}
    if {$s(busy) ne {}} {::GX::scriptJobRequestCancel $s(busy) closed;set s(busy) {}}
    incr s(generation)
    set s(project) $path;set s(mode) cpp;set s(dirty) 0
    projectTabsReset
    set s(projectHash) [::GX::sha256File [file join $path project.json]]
    wm title .gxViewerDevelopment {Viewer Development Workspace · restricted C++}
    projectTreeRefresh
    set tree .gxViewerDevelopment.body.left.files.tree
    $tree selection set handlers.cpp;read handlers.cpp
    set s(status) "Project: $path"
    apiRefresh
    controls
}
proc ::GX::ViewerDevelopmentWorkspace::new {} {
    variable s;if {![prepare]} return
    set parent [tk_chooseDirectory -parent .gxViewerDevelopment -title {Choose the parent of a new C++ Viewer project}]
    if {$parent eq {}} return
    set project [file join $parent viewer_project_[clock seconds]]
    if {$s(busy) ne {}} {::GX::scriptJobRequestCancel $s(busy) closed;set s(busy) {}}
    incr s(generation)
    set s(newProject) $project
    set s(busy) [::GX::viewerDevelopmentRequest init $project [list ::GX::ViewerDevelopmentWorkspace::created $s(generation)] [dict create module_id viewer.project_[clock seconds]]]
    set s(status) {Creating the restricted C++ project under its project-write grant…}
    controls
}
proc ::GX::ViewerDevelopmentWorkspace::created {generation response} {
    variable s;if {![winfo exists .gxViewerDevelopment]||$generation!=$s(generation)} return
    set s(busy) {};controls
    if {![dict get $response ok]} {set s(status) [dict get $response error];log "$response\n";return}
    project [dict get $response result project]
}
proc ::GX::ViewerDevelopmentWorkspace::openProject {} {
    if {![prepare]} return
    set path [tk_chooseDirectory -parent .gxViewerDevelopment -title {Open C++ developer or trusted maintenance project}]
    if {$path ne {}} {project $path}
}
proc ::GX::ViewerDevelopmentWorkspace::request {operation} {
    variable s
    if {$s(mode) eq {acquisition}} {return [acqRun $operation]}
    if {$s(mode) eq {maintenance}} {
        if {$operation ni {validate export}} {error {C++ Build/Run/Preview/Test are unavailable in trusted Tcl maintenance; use approved candidate promotion and real GUI verification}}
        if {$s(dirty)} {save}
        set result [maintenanceWait maintenance_$operation {{}}]
        log "$result\n";diagnosticsShow $result
        set s(status) "[dict get $result status] · lexical/package checks only; real GUI/science NOT_TESTED"
        return $result
    }
    if {$s(project) eq {}} {error {Open or create a developer project first}}
    if {$s(busy) ne {}} {error {Wait or cancel the current development request}}
    if {$s(dirty)} {saveAll}
    if {$s(dirty)} {error {New edits arrived during Save All; save them before running the request}}
    if {$operation eq {export}} {if {![projectNotesReview]} return;projectNotesSnapshotExport}
    incr s(generation)
    set s(busy) [::GX::viewerDevelopmentRequest $operation $s(project) [list ::GX::ViewerDevelopmentWorkspace::completed $operation $s(project) $s(generation)]]
    set s(status) "[string totitle $operation] running through the shared restricted backend…";controls
}
proc ::GX::ViewerDevelopmentWorkspace::completed {operation project generation response} {
    variable s
    if {![winfo exists .gxViewerDevelopment]||$s(project) ne $project||$generation!=$s(generation)} return
    set s(busy) {};controls
    if {$operation ne {api}} {log "[string range $operation 0 32]: [string range $response 0 8191]\n\n"}
    if {![dict get $response ok]} {set s(status) "[::GX::datasetPublicationV2DictDefault $response code REQUEST_FAILED]: [dict get $response error]";return}
    set result [dict get $response result]
    set s(status) "$operation · [dict get $result status]"
    if {$operation eq {api}} {set s(catalog) [dict get $result apis];apiRefresh;return}
    set report $result
    if {[dict exists $result validation]} {set report [dict get $result validation]}
    diagnosticsShow $report
    if {$operation eq {export}&&[dict exists $result package]} {set s(status) "Candidate exported for review: [dict get $result package]"}
}
proc ::GX::ViewerDevelopmentWorkspace::diagnosticsShow {report} {
    set tree .gxViewerDevelopment.bottom.diagnostics.tree;$tree delete [$tree children {}]
    foreach row [::GX::datasetPublicationV2DictDefault $report diagnostics {}] {$tree insert {} end -values [list [dict get $row file] [dict get $row line] [dict get $row column] [dict get $row message]]}
    ::GX::uiFieldInspectionColumnsSchedule $tree {fill message}
}
proc ::GX::ViewerDevelopmentWorkspace::controls {} {
    variable s
    if {![winfo exists .gxViewerDevelopment]} return
    .gxViewerDevelopment.menus.edit entryconfigure {Find…} -state [expr {$s(busy) eq {}?{normal}:{disabled}}]
    .gxViewerDevelopment.menus.edit entryconfigure {Replace in Note…} -state [expr {[noteMenuHandle] ne {}?{normal}:{disabled}}]
    if {$s(mode) eq {acquisition}} {acqControls;return}
    foreach id {new open save saveall validate build demo test export} {.gxViewerDevelopment.toolbar.$id state [expr {$s(busy) eq {}?{!disabled}:{disabled}}]}
    .gxViewerDevelopment.toolbar.cancel state [expr {$s(busy) eq {}?{disabled}:{!disabled}}]
    if {[llength [info commands debugButtons]]} {debugButtons}
    if {$s(mode) eq {maintenance}} {
        foreach id {build demo test} {.gxViewerDevelopment.toolbar.$id state disabled}
        if {[winfo exists .gxViewerDevelopment.debugbar]} {foreach id {run start continue pause into over out stop} {.gxViewerDevelopment.debugbar.$id state disabled}}
    }
    set sourceState [expr {$s(mode) eq {cpp} && $s(project) ne {} && $s(busy) eq {}?{!disabled}:{disabled}}]
    foreach id {add import rename remove close} {.gxViewerDevelopment.toolbar.file_$id state $sourceState}
    foreach label {{New project file…} {Add existing file…} {Rename / move file…} {Remove project file…} {Close source tab}} {.gxViewerDevelopment.menus.file entryconfigure $label -state [expr {$sourceState eq {!disabled}?{normal}:{disabled}}]}
    foreach label {Build {Demo / Preview} Test {Enable installed native GUI testing} {Review saved Workspace upgrade…}} {
        .gxViewerDevelopment.menus.develop entryconfigure $label -state [expr {$s(mode) eq {maintenance}?{disabled}:{normal}}]
    }
}
proc ::GX::ViewerDevelopmentWorkspace::cancel {} {variable s;if {$s(busy) ne {}} {::GX::scriptJobRequestCancel $s(busy)}}
proc ::GX::ViewerDevelopmentWorkspace::demo {} {
    variable s
    if {$s(mode) eq {acquisition}} {return [acqRun run]};if {$s(project) eq {}} {error {Open a project first}}
    if {$s(mode) eq {maintenance}} {error {Tcl maintenance does not execute edited source; export and request normal candidate promotion}}
    if {$s(dirty)} {saveAll}
    if {$s(dirty)} {error {New edits arrived during Save All; save them before Preview}}
    if {$s(preview) ne {}&&[winfo exists $s(preview)]} {destroy $s(preview)}
    set s(preview) [::GX::viewerDevelopmentPreview $s(project)]
}
proc ::GX::ViewerDevelopmentWorkspace::diagnostic {} {
    variable s;set tree .gxViewerDevelopment.bottom.diagnostics.tree
    set item [lindex [$tree selection] 0];if {$item eq {}} return
    lassign [$tree item $item -values] file line column message
    read $file;set t [text];$t tag remove sel 1.0 end;$t tag add sel $line.0 $line.end;$t mark set insert $line.[expr {max(0,$column-1)}];$t see $line.0;focus $t
    set s(status) "$file:$line:$column · $message"
}
proc ::GX::ViewerDevelopmentWorkspace::apiRefresh {} {
    variable s
    set browser [apiBrowserWidget]
    ::GX::apiBrowserProjectSet $browser [expr {$s(mode) eq {maintenance}?{}:$s(project)}]
    ::GX::apiBrowserRefresh $browser
}
proc ::GX::ViewerDevelopmentWorkspace::apiBrowserWidget {} {return .gxViewerDevelopment.body.right.api.scroll.content.browser}
proc ::GX::ViewerDevelopmentWorkspace::apiSelect {} {::GX::apiBrowserSelect [apiBrowserWidget]}
proc ::GX::ViewerDevelopmentWorkspace::apiGuide {} {::GX::apiBrowserManual [apiBrowserWidget]}
proc ::GX::ViewerDevelopmentWorkspace::manual {} {::GX::documentationBrowserOpenModuleWindow viewer.development_workspace .gxViewerDevelopment}
proc ::GX::ViewerDevelopmentWorkspace::supportCatalog {} {
    set w [::GX::documentationBrowserOpenModuleWindow viewer.development_workspace .gxViewerDevelopment]
    ::GX::documentationBrowserManualShow $w [file join $::GX::scriptDir docs api CPP_SUPPORT_CATALOG.md]
    wm title $w {C/C++ support catalog — Viewer Development Workspace}
    return $w
}
proc ::GX::ViewerDevelopmentWorkspace::guiTesting {} {
    variable s
    if {$s(project) eq {} || $s(dirty) || $s(busy) ne {}} {error {Open a saved, idle project before enabling its installed native GUI tests}}
    set receipt [::GX::viewerDevelopmentGuiTestAttach $s(project)]
    set s(status) {Native GUI tests attached to this installed project and current Session. Author CLI actions are scoped to its new test window.}
    log $receipt
}
proc ::GX::ViewerDevelopmentWorkspace::find {direction} {variable s;::GX::sourceSurfaceFind [text] $s(find) $direction}
proc ::GX::ViewerDevelopmentWorkspace::importSource {} {
    variable s
    if {$s(mode) eq {acquisition}} {return [acqFileDialog import]};if {$s(project) eq {}} {error {Open a project first}};if {![prepare]} return
    if {$s(mode) eq {maintenance}} {error {Use the admitted Source Surface file; arbitrary source import is unavailable in maintenance mode}}
    set path [tk_getOpenFile -parent .gxViewerDevelopment -title {Import C++ source as data} -filetypes {{{C++ source} {.cpp .cc .cxx}} {{All files} *}}]
    if {$path eq {}} return
    if {![file isfile $path]||[file size $path]>65536} {error {Imported source must be an ordinary UTF-8 file within 64 KiB}}
    set f [::open $path rb];try {set source [encoding convertfrom utf-8 [::read $f 65537]]} finally {::close $f}
    transfer check_source $source
    read handlers.cpp;::GX::sourceSurfaceReplace [text] $source;modified
    set s(status) {C++ source passed the actual lexer/AST and profile checks and was imported for editing. No author code was generated or executed.}
}
proc ::GX::ViewerDevelopmentWorkspace::close {} {
    variable s;if {![prepare]} return
    if {$s(busy) ne {}} {::GX::scriptJobRequestCancel $s(busy) closed}
    if {$s(preview) ne {}&&[winfo exists $s(preview)]} {destroy $s(preview)}
    destroy .gxViewerDevelopment
}
proc ::GX::ViewerDevelopmentWorkspace::open {{context {}}} {
    variable s;set w .gxViewerDevelopment
    if {[winfo exists $w]} {
        raise $w
        if {[dict exists $context project] && [file normalize [dict get $context project]] ne $s(project)} {project [dict get $context project]}
        if {[dict exists $context maintenance_module]} {maintenanceDialog [dict get $context maintenance_module] [dict get $context maintenance_provider]}
        return $w
    }
    incr s(windowGeneration)
    toplevel $w;wm title $w {Viewer Development Workspace · restricted C++};wm geometry $w 1320x860+40+60;wm minsize $w 980 650
    menu $w.menus -tearoff 0;$w configure -menu $w.menus
    foreach {id label} {file File edit Edit view View develop Develop help Help} {menu $w.menus.$id -tearoff 0;$w.menus add cascade -label $label -underline 0 -menu $w.menus.$id}
    foreach {label command} {{New project…} new {Open project…} openProject {Import project package…} importProject {Save source} save {Save all sources} saveAll {New project file…} {projectFileDialog add} {Add existing file…} {projectFileDialog import} {Rename / move file…} {projectFileDialog rename} {Remove project file…} projectFileRemove {Close source tab} projectTabClose {Import C++ source…} importSource {Export candidate} {request export} Close close} {$w.menus.file add command -label $label -command [list ::GX::ViewerDevelopmentWorkspace::safe {*}$command]}
    $w.menus.file insert 2 command -label {New Acquisition project…} -command {::GX::ViewerDevelopmentWorkspace::safe acqBuilder 1}
    $w.menus.file insert 3 command -label {Acquisition project metadata/profiles…} -command {::GX::ViewerDevelopmentWorkspace::safe acqBuilder}
    $w.menus.file insert 4 command -label {Maintain installed Viewer…} -command {::GX::ViewerDevelopmentWorkspace::safe maintenanceDialog}
    foreach {label operation} {Undo undo Redo redo {Select all} select_all Copy copy Cut cut Paste paste} {$w.menus.edit add command -label $label -command [list ::GX::uiTextEdit $w $operation]}
    $w.menus.edit add command -label {Find…} -accelerator Ctrl+F -command {::GX::ViewerDevelopmentWorkspace::safe projectNotesSearch find}
    $w.menus.edit add command -label {Replace in Note…} -accelerator Ctrl+H -command {::GX::ViewerDevelopmentWorkspace::safe projectNotesSearch replace}
    $w.menus.edit add command -label {Edit Notes} -command {::GX::ViewerDevelopmentWorkspace::safe projectNotesShow}
    $w.menus.view add checkbutton -label {Show Notes} -variable ::GX::ViewerDevelopmentWorkspace::s(showNotes) -command {::GX::ViewerDevelopmentWorkspace::safe projectNotesToggle}
    ::GX::sourceNoteEditorMenusAttach $w.menus.edit $w.menus.view ::GX::ViewerDevelopmentWorkspace::noteMenuHandle
    foreach {label command} {Validate {request validate} Build {request build} {Demo / Preview} demo Test {request test} {Cancel request} cancel} {$w.menus.develop add command -label $label -command [list ::GX::ViewerDevelopmentWorkspace::safe {*}$command]}
    $w.menus.develop add command -label {C/C++ support catalog} -command [list ::GX::ViewerDevelopmentWorkspace::safe supportCatalog]
    $w.menus.develop add command -label {Enable installed native GUI testing} -command [list ::GX::ViewerDevelopmentWorkspace::safe guiTesting]
    $w.menus.develop add command -label {Review saved Workspace upgrade…} -command [list ::GX::ViewerDevelopmentWorkspace::safe workspaceUpgradeDialog]
    $w.menus.help add command -label {Developer manual} -command ::GX::ViewerDevelopmentWorkspace::manual
    $w.menus.help add command -label {About…} -command [list ::GX::documentationBrowserAboutModule viewer.development_workspace development_workspace $w]
    ttk::frame $w.toolbar;pack $w.toolbar -fill x -padx 5 -pady 1
    foreach {id label command} {new New new open Open openProject save Save save saveall {Save All} saveAll validate Validate {request validate} build Build {request build} demo Preview demo test Test {request test} export Export {request export} cancel Cancel cancel} {ttk::button $w.toolbar.$id -text $label -width 0 -command [list ::GX::ViewerDevelopmentWorkspace::safe {*}$command];pack $w.toolbar.$id -side left -padx 2}
    ttk::label $w.status -textvariable ::GX::ViewerDevelopmentWorkspace::s(status) -anchor w -wraplength 1250;pack $w.status -side bottom -fill x -padx 6 -pady 1
    ::GX::uiFieldComponentCreate $w.bottom tabs {} {} {};pack $w.bottom -side bottom -fill x -padx 6 -pady 1
    ttk::frame $w.bottom.diagnostics
    ttk::frame $w.bottom.output
    ttk::treeview $w.bottom.diagnostics.tree -columns {file line column message} -show headings -height 5
    foreach {id title width} {file File 120 line Line 55 column Column 70 message Diagnostic 650} {$w.bottom.diagnostics.tree heading $id -text $title;$w.bottom.diagnostics.tree column $id -width $width -minwidth $width -stretch [expr {$id eq {message}}]}
    ::text $w.bottom.output.text -height 7 -state disabled -wrap word
    ttk::scrollbar $w.bottom.diagnostics.vertical -command [list $w.bottom.diagnostics.tree yview]
    ttk::scrollbar $w.bottom.diagnostics.horizontal -orient horizontal -command [list $w.bottom.diagnostics.tree xview]
    $w.bottom.diagnostics.tree configure -yscrollcommand [list $w.bottom.diagnostics.vertical set] -xscrollcommand [list $w.bottom.diagnostics.horizontal set]
    pack $w.bottom.diagnostics.horizontal -side bottom -fill x;pack $w.bottom.diagnostics.vertical -side right -fill y;pack $w.bottom.diagnostics.tree -fill both -expand 1
    ttk::scrollbar $w.bottom.output.vertical -command [list $w.bottom.output.text yview]
    $w.bottom.output.text configure -yscrollcommand [list $w.bottom.output.vertical set]
    pack $w.bottom.output.vertical -side right -fill y;pack $w.bottom.output.text -fill both -expand 1
    $w.bottom add $w.bottom.diagnostics -text Diagnostics;$w.bottom add $w.bottom.output -text {Build / runtime output}
    bind $w.bottom.diagnostics.tree <Double-1> ::GX::ViewerDevelopmentWorkspace::diagnostic
    ttk::panedwindow $w.body -orient horizontal;pack $w.body -fill both -expand 1 -padx 6
    ttk::frame $w.body.left -width 205;pack propagate $w.body.left 0
    ttk::frame $w.body.center;::GX::uiFieldComponentCreate $w.body.right tabs {} {} {}
    $w.body add $w.body.left -weight 0;$w.body add $w.body.center -weight 1;$w.body add $w.body.right -weight 0
    ttk::label $w.body.left.title -text {Developer project} -font TkHeadingFont -width 1 -wraplength 180;pack $w.body.left.title -fill x
    bind $w.body.left.title <Configure> [list ::GX::_uiFieldComponentTextWrap $w.body.left.title 32767 %W %w]
    ttk::frame $w.body.left.files;pack $w.body.left.files -fill both -expand 1
    ttk::treeview $w.body.left.files.tree -show tree -height 12 -selectmode browse
    $w.body.left.files.tree column #0 -width 260 -minwidth 150 -stretch 0
    ttk::scrollbar $w.body.left.files.vertical -command [list $w.body.left.files.tree yview]
    ttk::scrollbar $w.body.left.files.horizontal -orient horizontal -command [list $w.body.left.files.tree xview]
    $w.body.left.files.tree configure -yscrollcommand [list $w.body.left.files.vertical set] -xscrollcommand [list $w.body.left.files.horizontal set]
    pack $w.body.left.files.horizontal -side bottom -fill x;pack $w.body.left.files.vertical -side right -fill y;pack $w.body.left.files.tree -fill both -expand 1
    bind $w.body.left.files.tree <<TreeviewSelect>> ::GX::ViewerDevelopmentWorkspace::selected
    foreach {id label command} {add {New file} {projectFileDialog add} import {Add file} {projectFileDialog import} rename {Rename / move} {projectFileDialog rename} remove Remove projectFileRemove close {Close tab} projectTabClose} {
        ttk::button $w.toolbar.file_$id -text $label -width 0 -command [list ::GX::ViewerDevelopmentWorkspace::safe {*}$command]
        pack $w.toolbar.file_$id -side left -padx 2 -pady 2
        bind $w.toolbar.file_$id <Enter> [list ::GX::plotsToolbarTipSchedule $w.toolbar.file_$id $label]
        bind $w.toolbar.file_$id <Leave> ::GX::plotsToolbarTipHide
    }
    ::GX::uiFieldComponentCreate $w.body.center.sources tabs {} {} {}
    pack $w.body.center.sources -fill both -expand 1
    set s(tabs) {};set s(notes) {};set s(showNotes) 0;set s(tabSerial) 0
    bind $w.body.center.sources <<NotebookTabChanged>> +::GX::ViewerDevelopmentWorkspace::projectTabSelected
    set s(baseline) "// Open or create a restricted C++ Viewer project.\n// The trusted SDK is supplied automatically; no scientific Session is needed.\n"
    set source [projectTabCreate Welcome $s(baseline) 0 cpp {}];set s(editor) $source
    ttk::frame $w.body.center.find
    ttk::label $w.body.center.find.label -text Find:
    ttk::entry $w.body.center.find.entry -width 8 -textvariable ::GX::ViewerDevelopmentWorkspace::s(find)
    ttk::button $w.body.center.find.previous -text Prev -width 0 -command {::GX::ViewerDevelopmentWorkspace::find backward}
    ttk::button $w.body.center.find.next -text Next -width 0 -command {::GX::ViewerDevelopmentWorkspace::find forward}
    pack $w.body.center.find.label $w.body.center.find.entry $w.body.center.find.previous $w.body.center.find.next -side left -padx 3 -pady 3
    pack $w.body.center.find -side bottom -fill x -before $w.body.center.sources
    ttk::frame $w.body.right.sdk;ttk::frame $w.body.right.profile
    $w.body.right add $w.body.right.sdk -text SDK;$w.body.right add $w.body.right.profile -text Profile
    set apiContent [::GX::uiFieldScrollableCreate $w.body.right.api 360]
    set apiBrowser [apiBrowserWidget]
    ::GX::apiBrowserCreate $apiBrowser Cpp [dict create presentation compact title {}]
    $apiBrowser.status configure -wraplength 320 -justify left
    bind $apiBrowser.status <Configure> +[list ::GX::_uiFieldComponentTextWrap $apiBrowser.status 32767 %W %w]
    pack $apiBrowser -in $apiContent -fill both -expand 1
    bind $apiBrowser <<ApiBrowserLayout>> [list ::GX::ViewerDevelopmentWorkspace::responsiveBody $w]
    $w.body.right add $w.body.right.api -text {API Browser}
    set s(apiVisible) 1
    $w.menus.view add checkbutton -label {API Browser tab} -variable ::GX::ViewerDevelopmentWorkspace::s(apiVisible) -command ::GX::ViewerDevelopmentWorkspace::apiPanelToggle
    set sdk [::GX::sourceSurfaceCreate $w.body.right.sdk.source {mode read_only language cpp}]
    pack $w.body.right.sdk.source -fill both -expand 1
    set f [::open [file join $::GX::scriptDir core development sdk gxtxt_viewer_sdk_v1.hpp] rb];try {::GX::sourceSurfaceSet $sdk [encoding convertfrom utf-8 [::read $f]]} finally {::close $f}
    ::text $w.body.right.profile.text -wrap word -width 36 -height 12
    $w.body.right.profile.text insert end {C++17 with the public SDK v1

Ordinary functions, pointers/references, user types, templates, inheritance/RTTI, recursion, callbacks/lambdas, allocation/RAII, exceptions, reviewed containers and project-local threads/fork are admitted.

Develop → C/C++ support catalog lists every currently admitted header, its review rationale, actual compiler/runtime budgets and all Host signatures. The same catalog is available through the public author CLI.

Canonical Dataset/Schema/Publication, Session/Workspace, History/Recovery, scientific execution/Jobs and Plot remain owned by public CORE services. Request a precise existing-owner extension when the typed SDK cannot express a required data flow. Scientific graphs use Plot v4; new v3 use is denied.

The same GUI/CLI backend owns admission, builds, native event lifetime and managed GDB/MI. Candidate export uses the normal Plugin Manager integration flow.}
    $w.body.right.profile.text configure -state disabled
    ttk::scrollbar $w.body.right.profile.vertical -command [list $w.body.right.profile.text yview]
    $w.body.right.profile.text configure -yscrollcommand [list $w.body.right.profile.vertical set]
    pack $w.body.right.profile.vertical -side right -fill y;pack $w.body.right.profile.text -fill both -expand 1
    $w.body.right configure -width 360
    bind $w.body.right <<NotebookTabChanged>> +[list ::GX::ViewerDevelopmentWorkspace::responsiveBody $w]
    bind $w.status <Configure> [list $w.status configure -wraplength %w]
    bind $w.toolbar <Configure> [list ::GX::ViewerDevelopmentWorkspace::toolbarLayout $w %w]
    after idle [list ::GX::ViewerDevelopmentWorkspace::initialLayout $w]
    ::GX::uiTextEditingAttach $w [list $source]
    bind $w <Control-s> {::GX::ViewerDevelopmentWorkspace::safe save;break}
    bind $w <Control-Shift-S> {::GX::ViewerDevelopmentWorkspace::safe saveAll;break}
    bind $w <F5> {::GX::ViewerDevelopmentWorkspace::safe request validate;break}
    bind $w <F6> {::GX::ViewerDevelopmentWorkspace::safe request build;break}
    bind $w <F7> {::GX::ViewerDevelopmentWorkspace::safe demo;break}
    bind $w <F8> {::GX::ViewerDevelopmentWorkspace::safe request test;break}
    bind $w <F1> ::GX::ViewerDevelopmentWorkspace::manual
    debugMount $w
    foreach tree [list $w.body.left.files.tree $w.bottom.diagnostics.tree $w.bottom.stack.tree $w.bottom.variables.tree] {
        ::GX::uiFieldInspectionColumnsFit $tree
        if {{#0} in [$tree cget -displaycolumns] || {tree} in [$tree cget -show]} {
            $tree column #0 -minwidth [expr {[font measure TkHeadingFont [$tree heading #0 -text]]+24}]
        }
    }
    bind $w <Configure> +[list ::GX::ViewerDevelopmentWorkspace::responsiveLayout $w %W %h]
    bind $w.body <Configure> +[list ::GX::ViewerDevelopmentWorkspace::responsiveBody $w]
    bind $w <Destroy> +[list ::GX::ViewerDevelopmentWorkspace::responsiveDispose $w %W]
    wm protocol $w WM_DELETE_WINDOW {::GX::ViewerDevelopmentWorkspace::safe close}
    controls
    if {[dict exists $context project]} {project [dict get $context project]}
    if {[dict exists $context maintenance_module]} {maintenanceDialog [dict get $context maintenance_module] [dict get $context maintenance_provider]}
    return $w
}
proc ::GX::ViewerDevelopmentWorkspace::initialLayout {w} {
    variable s
    if {![winfo exists $w]} return
    if {[info exists s(noteFocus)]} return
    set width [winfo width $w.body]
    if {$width<640} {after 100 [list ::GX::ViewerDevelopmentWorkspace::initialLayout $w];return}
    $w.body sashpos 0 205
    $w.body sashpos 1 [expr {$width-365}]
}
proc ::GX::ViewerDevelopmentWorkspace::toolbarLayout {w width} {
    set children [winfo children $w.toolbar]
    set needed 0;foreach child $children {incr needed [expr {[winfo reqwidth $child]+6}]}
    if {$needed>$width} {
        # File operations remain in the existing File menu, with the same
        # commands and dirty-source decisions. Keep primary actions on one row
        # rather than consuming the source/reference area with duplicate tools.
        foreach child $children {
            if {![string match $w.toolbar.file_* $child]} continue
            pack forget $child;grid remove $child
            set children [lsearch -all -inline -not -exact $children $child]
        }
    }
    ::GX::uiFieldControlsLayout $w.toolbar $width $children
}
proc ::GX::ViewerDevelopmentWorkspace::responsiveLayout {w actual height} {
    variable s
    if {$actual ne $w || ![winfo exists $w.bottom]} return
    if {[info exists s(layoutAfter)]} {after cancel $s(layoutAfter)}
    set s(layoutAfter) [after idle [list ::GX::ViewerDevelopmentWorkspace::responsiveApply $w]]
}
proc ::GX::ViewerDevelopmentWorkspace::responsiveDispose {w actual} {
    variable s
    if {$w ne $actual} return
    unset -nocomplain s(noteFocus)
    if {[info exists s(layoutAfter)]} {after cancel $s(layoutAfter);unset s(layoutAfter)}
}
proc ::GX::ViewerDevelopmentWorkspace::responsiveApply {w} {
    variable s
    unset -nocomplain s(layoutAfter)
    if {![winfo exists $w.bottom] || [winfo height $w.body]<100} return
    set tree $w.body.left.files.tree
    set key [list [font actual TkDefaultFont] [font actual TkHeadingFont] [ttk::style theme use] [winfo width $tree]]
    if {![info exists s(treeLayoutKey)] || $s(treeLayoutKey) ne $key} {
        set s(treeLayoutKey) $key
        ::GX::uiFieldInspectionColumnsSchedule $tree {recursive 1}
        ::GX::uiFieldInspectionColumnsSchedule $w.bottom.diagnostics.tree {fill message}
        ::GX::uiFieldInspectionColumnsSchedule $w.bottom.stack.tree
        ::GX::uiFieldInspectionColumnsSchedule $w.bottom.variables.tree {recursive 1 fill {#0 value}}
    }
    if {[info exists s(noteFocus)]} return
    set height [winfo height $w]
    set desired [expr {max(70,min(200,int($height*.18)))}]
    set browser [apiBrowserWidget]
    if {[winfo exists $browser]} {
        set needed [expr {6*[font metrics TkDefaultFont -linespace]+20}]
        # The existing reference Browser retains its own row/detail minima in
        # the shared UI Field scroll area, without forcing a taller OS window.
        if {[winfo ismapped $browser]} {
            set viewport $w.body.right.api.scroll
            set minimum [dict get [::GX::apiBrowserMinimumHeight $browser] browser]
            set extent [expr {max($minimum,[winfo height $viewport])}]
            if {[$viewport itemcget content -height]!=$extent} {$viewport itemconfigure content -height $extent}
        }
        set tree $w.bottom.diagnostics.tree
        set heading [font metrics TkHeadingFont -linespace]
        set row [expr {max(12,int(double([winfo reqheight $tree]-$heading-4)/max(1,[$tree cget -height])))}]
        set minimum [expr {$row+$heading+[winfo reqheight $w.bottom.diagnostics.horizontal]+4}]
        # Notebook -height is its content height; both sets of tabs also
        # consume client pixels. Measure them after ttk has allocated the panes.
        set bottomContent 0
        foreach pane [$w.bottom tabs] {set bottomContent [expr {max($bottomContent,[winfo reqheight $pane])}]}
        if {[$w.bottom cget -height]>0} {set bottomContent [$w.bottom cget -height]}
        set tabs [expr {[winfo reqheight $w.bottom]-$bottomContent}]
        set referenceContent 0
        foreach pane [$w.body.right tabs] {set referenceContent [expr {max($referenceContent,[winfo reqheight $pane])}]}
        set referenceTabs [expr {[winfo reqheight $w.body.right]-$referenceContent}]
        set referenceTabs [expr {max([font metrics TkDefaultFont -linespace]+8,$referenceTabs)}]
        set tabs [expr {max([font metrics TkDefaultFont -linespace]+8,$tabs)}]
        set chrome 0
        foreach child [pack slaves $w] {
            set options [pack info $child];set padding [dict get $options -pady]
            if {[llength $padding]==1} {set padding [expr {2*$padding}]} else {set padding [expr {[lindex $padding 0]+[lindex $padding 1]}]}
            incr chrome $padding
            if {$child ni [list $w.body $w.bottom]} {incr chrome [expr {[winfo reqheight $child]+2*[dict get $options -ipady]}]}
        }
        set required [expr {$chrome+$needed+$referenceTabs+$minimum+$tabs+8}]
        set minHeight [expr {max(650,$required)}]
        if {[wm minsize $w] ne [list 980 $minHeight]} {wm minsize $w 980 $minHeight}
        set budget [expr {$height-$chrome-$needed-$referenceTabs-$tabs-8}]
        set desired [expr {max($minimum,min($desired,$budget))}]
        if {[winfo ismapped $browser]} {::GX::apiBrowserCompactSchedule $browser}
    }
    if {[$w.bottom cget -height]!=$desired} {$w.bottom configure -height $desired}
}
proc ::GX::ViewerDevelopmentWorkspace::responsiveBody {w} {
    if {[winfo exists $w]} {responsiveLayout $w $w [winfo height $w]}
}
proc ::GX::ViewerDevelopmentWorkspace::dispatch {operation scene} {return [open [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
::GX::viewerBackendRegister viewer_development_workspace_tk ::GX::ViewerDevelopmentWorkspace::dispatch

source [file join [file dirname [info script]] debugger.tcl]

# Explicit native review and canonical duplicate; shared with the structured CLI.
proc ::GX::ViewerDevelopmentWorkspace::workspaceUpgradeDialog {} {
    variable s
    if {$s(project) eq {} || $s(dirty) || $s(busy) ne {}} {error {Open a saved project and finish its current request before reviewing a Workspace}}
    set design [::GX::viewerGuiDesignRead [file join $s(project) design.gxtxt-viewer]]
    set w .gxViewerDevelopment.workspaceUpgrade
    if {[winfo exists $w]} {raise $w;return $w}
    toplevel $w;wm title $w {Review saved Workspace upgrade};wm transient $w .gxViewerDevelopment;wm geometry $w 780x540;wm minsize $w 600 400
    ttk::label $w.notice -text {Select an earlier Workspace from this Session. Review proves unchanged C++ source, grants and existing callback ordinals. Apply creates an upgraded copy, preserving the original scientific source, Jobs and Datasets.} -wraplength 720 -padding 10
    grid $w.notice -row 0 -column 0 -columnspan 2 -sticky ew
    ttk::treeview $w.items -columns {identity} -show {tree headings} -height 5
    $w.items heading #0 -text {Saved Workspace};$w.items heading identity -text {Canonical ID}
    $w.items column identity -width 130 -stretch 0
    foreach item [::GX::sessionWorkspaceList] {
        if {[dict get $item module_id] eq [dict get $design module_id] && [dict get $item schema] eq {gxtxt.viewer_interface_state.v1}} {$w.items insert {} end -id [dict get $item id] -text [dict get $item name] -values [list [dict get $item id]]}
    }
    grid $w.items -row 1 -column 0 -columnspan 2 -sticky ew -padx 10
    ::text $w.report -wrap word -height 12 -state disabled -yscrollcommand [list $w.scroll set]
    ttk::scrollbar $w.scroll -orient vertical -command [list $w.report yview]
    grid $w.report -row 2 -column 0 -sticky nsew -padx {10 0} -pady 8
    grid $w.scroll -row 2 -column 1 -sticky ns -padx {0 10} -pady 8
    grid rowconfigure $w 2 -weight 1;grid columnconfigure $w 0 -weight 1
    ttk::frame $w.buttons;grid $w.buttons -row 3 -column 0 -columnspan 2 -sticky ew -padx 10 -pady 8
    ttk::button $w.buttons.review -text {Review selected} -command [list ::GX::ViewerDevelopmentWorkspace::safe workspaceUpgradeReview $w]
    ttk::button $w.buttons.apply -text {Create upgraded copy} -state disabled -command [list ::GX::ViewerDevelopmentWorkspace::safe workspaceUpgradeApply $w]
    ttk::button $w.buttons.close -text Close -command [list destroy $w]
    pack $w.buttons.review $w.buttons.apply -side left -padx 4;pack $w.buttons.close -side right
    bind $w.items <<TreeviewSelect>> [list $w.buttons.apply state disabled]
    bind $w <Configure> [list ::GX::ViewerDevelopmentWorkspace::workspaceUpgradeResize $w %W %w]
    return $w
}
proc ::GX::ViewerDevelopmentWorkspace::workspaceUpgradeResize {w actual width} {
    if {$actual eq $w && [winfo exists $w.notice]} {$w.notice configure -wraplength [expr {max(240,$width-32)}]}
}
proc ::GX::ViewerDevelopmentWorkspace::workspaceUpgradeReview {w} {
    variable s
    set id [lindex [$w.items selection] 0]
    if {$id eq {}} {error {Select a canonical saved Workspace}}
    $w.buttons.apply state disabled
    $w.report configure -state normal;$w.report delete 1.0 end;$w.report insert end {Reviewing through the public Development owner…};$w.report configure -state disabled
    set result [::GX::viewerDevelopmentWorkspaceReviewWait $s(project) $id]
    if {![winfo exists $w]} return
    set s(workspaceReview) [dict get $result review_id]
    $w.report configure -state normal;$w.report delete 1.0 end
    $w.report insert end "Review accepted for $id\n\nExisting components preserved: [dict get $result preserved_component_count]\nAppended controls: [join [dict get $result appended_components] {, }]\n\nOriginal Workspace remains unchanged. Every retained History state, including redo, is checked. Notes, preview and nested resources use normal Workspace export/import; a managed archive is added to the original resource store. No simulation or numerical operation runs.\n\nApply rechecks the Session lifetime, source revisions, project and original Workspace."
    $w.report configure -state disabled;$w.buttons.apply state !disabled
}
proc ::GX::ViewerDevelopmentWorkspace::workspaceUpgradeApply {w} {
    variable s
    $w.buttons.apply state disabled
    set result [::GX::viewerDevelopmentWorkspaceUpgrade $s(project) $s(workspaceReview)]
    $w.report configure -state normal;$w.report insert end "\n\nCreated [dict get $result workspace_id]. Original: [dict get $result original_workspace_id]. Open the new copy through Session Workspaces or the source-bound public workspace_open operation."
    $w.report configure -state disabled
    set s(status) "Created upgraded Workspace [dict get $result workspace_id]"
}

# Trusted existing-module source maintenance. The CORE backend supplies the
# opaque file list; ordinary restricted C++ projects retain their own policy.
proc ::GX::ViewerDevelopmentWorkspace::maintenanceWait {operation payload} {
    variable s;variable transferSerial;variable transfers
    if {$s(busy) ne {}} {error {Wait or cancel the current development request}}
    set id [incr transferSerial];set project $s(project);set generation $s(generation);set windowGeneration $s(windowGeneration)
    if {$operation eq {inspect}} {
        if {$payload ne {sdk_v1}} {error {This reference adapter admits only the fixed current-target SDK}}
        set options [dict create target sdk_v1]
    } else {set options [dict create request_json $payload]}
    set request [::GX::viewerDevelopmentRequest $operation $project [list ::GX::ViewerDevelopmentWorkspace::transferred $id] $options]
    set s(busy) $request;controls
    try {
        vwait ::GX::ViewerDevelopmentWorkspace::transfers($id)
        set response $transfers($id)
        if {$s(project) ne $project || $s(generation)!=$generation || $s(windowGeneration)!=$windowGeneration || ![winfo exists .gxViewerDevelopment]} {error {Maintenance response belongs to an earlier project/window; editor text was not accepted}}
        if {![dict get $response ok]} {error "[::GX::datasetPublicationV2DictDefault $response code MAINTENANCE]: [dict get $response error]"}
        return [dict get $response result]
    } finally {
        unset -nocomplain transfers($id)
        if {$s(busy) eq $request} {set s(busy) {}}
        if {[winfo exists .gxViewerDevelopment]} {controls}
    }
}
proc ::GX::ViewerDevelopmentWorkspace::maintenanceProject {path} {
    variable s
    if {$s(busy) ne {}} {error {Wait or cancel the current request before changing maintenance project}}
    set old [array get s];set windowGeneration $s(windowGeneration)
    set s(project) $path;set s(mode) maintenance;incr s(generation)
    set generation $s(generation)
    try {set result [maintenanceWait maintenance_inspect {{}}]} on error {message options} {
        # A replacement window owns its new state; never rewind its lifetime or
        # apply an earlier window's provisional project after cancellation.
        if {$s(windowGeneration)==$windowGeneration && $s(generation)==$generation && $s(project) eq $path} {array set s $old;controls}
        return -options $options $message
    }
    set s(maintenanceFiles) [dict get $result files];set s(dirty) 0
    projectTabsReset
    set s(editor) [projectTabCreate Maintenance {} 1 tcl {}]
    set tree .gxViewerDevelopment.body.left.files.tree;$tree delete [$tree children {}]
    dict for {id info} $s(maintenanceFiles) {$tree insert {} end -id $id -text "[dict get $info path] ([expr {[dict get $info limit]/1024}] KiB)[expr {[dict get $info exists]?{}:{ · not authored}}]"}
    set first [lindex [dict keys $s(maintenanceFiles)] 0]
    $tree selection set $first;maintenanceRead $first
    wm title .gxViewerDevelopment "Viewer Development Workspace · maintaining [dict get $result module]"
    set s(status) "Trusted source/document maintenance · candidate [dict get $result candidate_version] · Build/Preview/Debug unavailable; original preserved"
    apiRefresh;controls
}
proc ::GX::ViewerDevelopmentWorkspace::maintenanceRead {id} {
    variable s
    if {![dict exists $s(maintenanceFiles) $id]} {error {Choose an admitted maintenance source ID}}
    set result [maintenanceWait maintenance_inspect [format {{"file_id":%s}} [::GX::viewerDevelopmentJsonString $id]]]
    set source [dict get $result content]
    set s(file) $id;set s(baseline) $source;set s(maintenanceHash) [dict get $result sha256];set s(maintenanceExists) [dict get $result exists];set s(dirty) 0
    ::GX::sourceSurfaceConfigure [text] [dict create language [dict get $result language] mode editable]
    ::GX::sourceSurfaceSet [text] $source
    set s(status) "[dict get $s(maintenanceFiles) $id path] · [dict get $result language] · [expr {$s(maintenanceExists)?{existing file}:{not authored; Save creates this exact approved document}}] · editing does not execute"
}
proc ::GX::ViewerDevelopmentWorkspace::maintenanceSave {} {
    variable s
    if {![dict exists $s(maintenanceFiles) $s(file)]} {error {Choose an admitted maintenance source}}
    set source [::GX::sourceSurfaceGet [text]]
    set expected [expr {$s(maintenanceExists)?[::GX::viewerDevelopmentJsonString $s(maintenanceHash)]:{null}}]
    set payload [format {{"file_id":%s,"expected_sha256":%s,"content":%s}} [::GX::viewerDevelopmentJsonString $s(file)] $expected [::GX::viewerDevelopmentJsonString $source]]
    set result [maintenanceWait maintenance_save $payload]
    if {[dict get $result status] ne {SAVED}} {error {Maintenance save did not complete; editor text retained}}
    set s(baseline) $source;set s(maintenanceHash) [dict get $result sha256];set s(maintenanceExists) 1;set s(dirty) [expr {[::GX::sourceSurfaceGet [text]] ne $source}]
    dict set s(maintenanceFiles) $s(file) exists 1
    set info [dict get $s(maintenanceFiles) $s(file)]
    .gxViewerDevelopment.body.left.files.tree item $s(file) -text "[dict get $info path] ([expr {[dict get $info limit]/1024}] KiB)"
    set s(status) "Saved admitted source · [string range $s(maintenanceHash) 0 11] · not executed"
    return $result
}
proc ::GX::ViewerDevelopmentWorkspace::maintenanceDialog {{module {}} {provider {}}} {
    variable s
    if {![prepare]} return
    if {$s(busy) ne {}} {error {Wait or cancel the current development request}}
    set approved [::GX::viewerDevelopmentMaintenanceModules]
    if {![dict size $approved]} {error {No installed Viewers are admitted by the CORE maintenance policy}}
    set choices {};set s(maintenanceChoices) {}
    dict for {id definition} $approved {
        set label "[dict get $definition name] — $id"
        lappend choices $label;dict set s(maintenanceChoices) $label [list $id [dict get $definition provider]]
        if {$id eq $module && [dict get $definition provider] eq $provider} {set selected $label}
    }
    if {$module ne {} && ![info exists selected]} {error {Selected module/provider is outside the installed maintenance policy}}
    set s(maintenanceChoice) [expr {[info exists selected]?$selected:[lindex $choices 0]}]
    set w .gxMaintainViewer;catch {destroy $w}
    ::GX::uiFieldDialogCreate $w .gxViewerDevelopment {Maintain installed Viewer source} 690x250
    ttk::label $w.about -text {Create a private source snapshot of an approved installed Viewer. CORE admits a finite source list; all other resources, public APIs and native binaries are preserved. Save and lexical validation never execute Tcl. Candidate export does not install or prove GUI/scientific behavior.} -wraplength 650 -justify left
    ttk::combobox $w.choice -state readonly -values $choices -textvariable ::GX::ViewerDevelopmentWorkspace::s(maintenanceChoice) -width 75
    ::GX::uiFieldSelectorWithinViewer $w.choice $w
    ttk::button $w.create -text {Choose private project folder…} -command {::GX::ViewerDevelopmentWorkspace::safe maintenanceCreate}
    ttk::button $w.cancel -text Cancel -command [list ::GX::uiFieldDialogClose $w]
    pack $w.about $w.choice -fill x -padx 10 -pady 10;pack $w.create $w.cancel -side left -padx 10 -pady 8
    ::GX::uiFieldDialogPresent $w $w.choice 0
}
proc ::GX::ViewerDevelopmentWorkspace::maintenanceCreate {} {
    variable s
    lassign [dict get $s(maintenanceChoices) $s(maintenanceChoice)] module provider
    set parent [tk_chooseDirectory -parent .gxMaintainViewer -title {Parent folder for a new private Viewer maintenance project}]
    if {$parent eq {}} return
    set project [file join $parent ${module}_maintenance_[clock microseconds]]
    incr s(generation)
    set s(busy) [::GX::viewerDevelopmentMaintenanceCreate $module $provider $project [list ::GX::ViewerDevelopmentWorkspace::created $s(generation)]]
    set s(status) {Staging original source/resources through the CORE project-write owner…};controls
    ::GX::uiFieldDialogClose .gxMaintainViewer
}

# The common Notes menu always queries the currently selected source notebook.
proc ::GX::ViewerDevelopmentWorkspace::noteMenuHandle {} {
    variable s
    if {$s(busy) ne {} || $s(mode) ni {cpp acquisition}} {return {}}
    set name [projectNotesActive]
    if {$name eq {}} {return {}}
    return [dict get $s(notes) $name editor]
}
