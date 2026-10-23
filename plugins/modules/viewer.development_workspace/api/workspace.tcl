# SPDX-License-Identifier: GPL-3.0-or-later
# Ordinary Viewer client. CORE owns policy, compiler, runtime, native views and packages.
namespace eval ::GX::ViewerDevelopmentWorkspace {variable s;array set s {project {} mode cpp file handlers.cpp dirty 0 baseline {} busy {} generation 0 windowGeneration 0 status {Open or create a restricted C++ project, or maintain an approved installed Viewer. No scientific Session is required.} preview {} find {}}}
proc ::GX::ViewerDevelopmentWorkspace::safe {method args} {
    if {[catch {[namespace current]::$method {*}$args} result options]} {set ::GX::ViewerDevelopmentWorkspace::s(status) $result;log "$result\n";return [dict create status FAILED message $result]}
    return $result
}
proc ::GX::ViewerDevelopmentWorkspace::log {message} {
    set text .gxViewerDevelopment.bottom.output.text
    if {![winfo exists $text]} return
    $text configure -state normal;if {[string length [$text get 1.0 end]]>65536} {$text delete 1.0 end-32768c};$text insert end $message;$text see end;$text configure -state disabled
}
proc ::GX::ViewerDevelopmentWorkspace::text {} {return .gxViewerDevelopment.body.center.source.text}
proc ::GX::ViewerDevelopmentWorkspace::modified {} {
    variable s;if {![winfo exists [text]]} return
    set s(dirty) [expr {[::GX::sourceSurfaceGet [text]] ne $s(baseline)}]
    set s(status) "[file tail $s(project)] / $s(file) · [expr {$s(dirty)?{unsaved}:{saved}}]"
}
proc ::GX::ViewerDevelopmentWorkspace::prepare {} {
    variable s
    if {!$s(dirty)} {return 1}
    set answer [tk_messageBox -parent .gxViewerDevelopment -type yesnocancel -icon question -title {Unsaved developer source} -message {Save the current source before continuing?}]
    if {$answer eq {cancel}} {return 0};if {$answer eq {yes}} {save}
    return 1
}
proc ::GX::ViewerDevelopmentWorkspace::save {} {
    variable s
    if {$s(mode) eq {maintenance}} {return [maintenanceSave]}
    if {$s(project) eq {}||$s(file) ni {handlers.cpp project.json}} {error {Choose an editable project source first}}
    set source [::GX::sourceSurfaceGet [text]]
    transfer save $source $s(file)
    set s(baseline) $source;set s(dirty) [expr {[::GX::sourceSurfaceGet [text]] ne $source}];set s(status) "Saved $s(file) · [string range [::GX::sha256File [file join $s(project) $s(file)]] 0 11]"
    if {$s(file) eq {project.json}} {apiRefresh}
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
    variable s;if {![prepare]} return
    if {$s(mode) eq {maintenance}} {return [maintenanceRead $name]}
    set roots [dict create handlers.cpp [file join $s(project) handlers.cpp] project.json [file join $s(project) project.json] design.gxtxt-viewer [file join $s(project) design.gxtxt-viewer] validation.json [file join $s(project) derived validation.json] build.json [file join $s(project) derived build.json] adapter.cpp [file join $::GX::scriptDir core development sdk trusted_adapter_v1.cpp]]
    if {![dict exists $roots $name]} {error {Unknown project browser file}}
    set path [dict get $roots $name]
    if {![file isfile $path]||[file type $path] eq {link}||[file size $path]>4194304} {error {Project file is unavailable or exceeds its bound}}
    set f [::open $path rb];try {set source [encoding convertfrom utf-8 [::read $f 4194305]]} finally {::close $f}
    set s(file) $name;set s(baseline) $source;set s(dirty) 0
    set language [expr {[string match *.cpp $name] ? {cpp} : ([string match *.json $name] ? {javascript} : {tcl})}]
    ::GX::sourceSurfaceConfigure [text] [dict create language $language mode [expr {$name in {handlers.cpp project.json}?{editable}:{read_only}}]]
    ::GX::sourceSurfaceSet [text] $source
    set s(status) "$name · [expr {$name in {handlers.cpp project.json}?{editable}:{read-only generated/design source}}]"
}
proc ::GX::ViewerDevelopmentWorkspace::selected {} {
    set name [lindex [.gxViewerDevelopment.body.left.files.tree selection] 0]
    if {$name ne {}} {safe read $name}
}
proc ::GX::ViewerDevelopmentWorkspace::project {path} {
    variable s
    if {![prepare]} return
    set path [file normalize $path]
    if {[file isfile [file join $path maintenance.json]]} {return [maintenanceProject $path]}
    if {![file isfile [file join $path project.json]]} {error {Choose a developer project containing project.json or maintenance.json}}
    if {$s(busy) ne {}} {::GX::scriptJobRequestCancel $s(busy) closed;set s(busy) {}}
    incr s(generation)
    set s(project) $path;set s(mode) cpp;set s(dirty) 0
    wm title .gxViewerDevelopment {Viewer Development Workspace · restricted C++}
    set tree .gxViewerDevelopment.body.left.files.tree;$tree delete [$tree children {}]
    foreach {name label} {handlers.cpp {C++ handlers} project.json {Project / facilities / tests} design.gxtxt-viewer {Builder design (read-only)} validation.json {Validation report} build.json {Build manifest} adapter.cpp {Trusted C++ adapter}} {$tree insert {} end -id $name -text $label}
    ::GX::uiFieldInspectionColumnsSchedule $tree
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
    if {$s(dirty)} {save}
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
    ::GX::uiFieldInspectionColumnsSchedule $tree
}
proc ::GX::ViewerDevelopmentWorkspace::controls {} {
    variable s
    if {![winfo exists .gxViewerDevelopment]} return
    foreach id {validate build demo test export} {.gxViewerDevelopment.toolbar.$id state [expr {$s(busy) eq {}?{!disabled}:{disabled}}]}
    .gxViewerDevelopment.toolbar.cancel state [expr {$s(busy) eq {}?{disabled}:{!disabled}}]
    if {[llength [info commands debugButtons]]} {debugButtons}
    if {$s(mode) eq {maintenance}} {
        foreach id {build demo test} {.gxViewerDevelopment.toolbar.$id state disabled}
        if {[winfo exists .gxViewerDevelopment.debugbar]} {foreach id {run start continue pause into over out stop} {.gxViewerDevelopment.debugbar.$id state disabled}}
    }
    foreach label {Build {Demo / Preview} Test {Enable installed native GUI testing} {Review saved Workspace upgrade…}} {
        .gxViewerDevelopment.menus.develop entryconfigure $label -state [expr {$s(mode) eq {maintenance}?{disabled}:{normal}}]
    }
}
proc ::GX::ViewerDevelopmentWorkspace::cancel {} {variable s;if {$s(busy) ne {}} {::GX::scriptJobRequestCancel $s(busy)}}
proc ::GX::ViewerDevelopmentWorkspace::demo {} {
    variable s;if {$s(project) eq {}} {error {Open a project first}}
    if {$s(mode) eq {maintenance}} {error {Tcl maintenance does not execute edited source; export and request normal candidate promotion}}
    if {$s(dirty)} {save}
    if {$s(preview) ne {}&&[winfo exists $s(preview)]} {destroy $s(preview)}
    set s(preview) [::GX::viewerDevelopmentPreview $s(project)]
}
proc ::GX::ViewerDevelopmentWorkspace::diagnostic {} {
    variable s;set tree .gxViewerDevelopment.bottom.diagnostics.tree
    set item [lindex [$tree selection] 0];if {$item eq {}} return
    lassign [$tree item $item -values] file line column message
    read handlers.cpp;set t [text];$t tag remove sel 1.0 end;$t tag add sel $line.0 $line.end;$t mark set insert $line.[expr {max(0,$column-1)}];$t see $line.0;focus $t
    set s(status) "$file:$line:$column · $message"
}
proc ::GX::ViewerDevelopmentWorkspace::apiRefresh {} {
    variable s
    set browser .gxViewerDevelopment.body.left.apiSplit.browser
    ::GX::apiBrowserProjectSet $browser [expr {$s(mode) eq {maintenance}?{}:$s(project)}]
    ::GX::apiBrowserRefresh $browser
}
proc ::GX::ViewerDevelopmentWorkspace::apiSelect {} {::GX::apiBrowserSelect .gxViewerDevelopment.body.left.apiSplit.browser}
proc ::GX::ViewerDevelopmentWorkspace::apiGuide {} {::GX::apiBrowserManual .gxViewerDevelopment.body.left.apiSplit.browser}
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
    variable s;if {$s(project) eq {}} {error {Open a project first}};if {![prepare]} return
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
        if {[dict exists $context maintenance_module]} {maintenanceDialog [dict get $context maintenance_module] [dict get $context maintenance_provider]}
        return $w
    }
    incr s(windowGeneration)
    toplevel $w;wm title $w {Viewer Development Workspace · restricted C++};wm geometry $w 1320x860+40+60;wm minsize $w 980 650
    menu $w.menus -tearoff 0;$w configure -menu $w.menus
    foreach {id label} {file File edit Edit view View develop Develop help Help} {menu $w.menus.$id -tearoff 0;$w.menus add cascade -label $label -underline 0 -menu $w.menus.$id}
    foreach {label command} {{New project…} new {Open project…} openProject {Save source} save {Import C++ source…} importSource {Export candidate} {request export} Close close} {$w.menus.file add command -label $label -command [list ::GX::ViewerDevelopmentWorkspace::safe {*}$command]}
    $w.menus.file insert 2 command -label {Maintain installed Viewer…} -command {::GX::ViewerDevelopmentWorkspace::safe maintenanceDialog}
    foreach {label operation} {Undo undo Redo redo {Select all} select_all Copy copy Cut cut Paste paste} {$w.menus.edit add command -label $label -command [list ::GX::uiTextEdit $w $operation]}
    foreach {label command} {Validate {request validate} Build {request build} {Demo / Preview} demo Test {request test} {Cancel request} cancel} {$w.menus.develop add command -label $label -command [list ::GX::ViewerDevelopmentWorkspace::safe {*}$command]}
    $w.menus.develop add command -label {C/C++ support catalog} -command [list ::GX::ViewerDevelopmentWorkspace::safe supportCatalog]
    $w.menus.develop add command -label {Enable installed native GUI testing} -command [list ::GX::ViewerDevelopmentWorkspace::safe guiTesting]
    $w.menus.develop add command -label {Review saved Workspace upgrade…} -command [list ::GX::ViewerDevelopmentWorkspace::safe workspaceUpgradeDialog]
    $w.menus.help add command -label {Developer manual} -command ::GX::ViewerDevelopmentWorkspace::manual
    $w.menus.help add command -label {About…} -command [list ::GX::documentationBrowserAboutModule viewer.development_workspace development_workspace $w]
    ttk::frame $w.toolbar;pack $w.toolbar -fill x -padx 5 -pady 5
    foreach {id label command} {new New new open Open openProject save Save save validate Validate {request validate} build Build {request build} demo Preview demo test Test {request test} export Export {request export} cancel Cancel cancel} {ttk::button $w.toolbar.$id -text $label -width 0 -command [list ::GX::ViewerDevelopmentWorkspace::safe {*}$command];pack $w.toolbar.$id -side left -padx 2}
    ttk::label $w.status -textvariable ::GX::ViewerDevelopmentWorkspace::s(status) -anchor w -wraplength 1250;pack $w.status -side bottom -fill x -padx 6 -pady 5
    ttk::notebook $w.bottom;pack $w.bottom -side bottom -fill x -padx 6 -pady 3
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
    ttk::frame $w.body.left;ttk::frame $w.body.center;ttk::notebook $w.body.right
    $w.body add $w.body.left -weight 0;$w.body add $w.body.center -weight 1;$w.body add $w.body.right -weight 0
    ttk::label $w.body.left.title -text {Developer project} -font TkHeadingFont;pack $w.body.left.title -fill x
    ttk::frame $w.body.left.files;pack $w.body.left.files -fill both -expand 1
    ttk::treeview $w.body.left.files.tree -show tree -height 12 -selectmode browse
    $w.body.left.files.tree column #0 -width 260 -minwidth 150 -stretch 0
    ttk::scrollbar $w.body.left.files.vertical -command [list $w.body.left.files.tree yview]
    ttk::scrollbar $w.body.left.files.horizontal -orient horizontal -command [list $w.body.left.files.tree xview]
    $w.body.left.files.tree configure -yscrollcommand [list $w.body.left.files.vertical set] -xscrollcommand [list $w.body.left.files.horizontal set]
    pack $w.body.left.files.horizontal -side bottom -fill x;pack $w.body.left.files.vertical -side right -fill y;pack $w.body.left.files.tree -fill both -expand 1
    bind $w.body.left.files.tree <<TreeviewSelect>> ::GX::ViewerDevelopmentWorkspace::selected
    ::GX::apiBrowserMount $w.body.left Cpp
    $w.menus.view add checkbutton -label {API Browser} -variable ::GX::ApiBrowser::state($w.body.left.apiSplit,visible) -command [list ::GX::apiBrowserToggle $w.body.left]
    set source [::GX::sourceSurfaceCreate $w.body.center.source {mode read_only language cpp}]
    set s(baseline) "// Open or create a restricted C++ Viewer project.\n// The trusted SDK is supplied automatically; no scientific Session is needed.\n"
    ::GX::sourceSurfaceSet $source $s(baseline)
    pack $w.body.center.source -fill both -expand 1
    bind $source <<Modified>> +::GX::ViewerDevelopmentWorkspace::modified
    ttk::frame $w.body.center.find
    ttk::label $w.body.center.find.label -text Find:
    ttk::entry $w.body.center.find.entry -width 8 -textvariable ::GX::ViewerDevelopmentWorkspace::s(find)
    ttk::button $w.body.center.find.previous -text Prev -width 0 -command {::GX::ViewerDevelopmentWorkspace::find backward}
    ttk::button $w.body.center.find.next -text Next -width 0 -command {::GX::ViewerDevelopmentWorkspace::find forward}
    pack $w.body.center.find.label $w.body.center.find.entry $w.body.center.find.previous $w.body.center.find.next -side left -padx 3 -pady 3
    pack $w.body.center.find -side bottom -fill x -before $w.body.center.source
    ttk::frame $w.body.right.sdk;ttk::frame $w.body.right.profile
    $w.body.right add $w.body.right.sdk -text SDK;$w.body.right add $w.body.right.profile -text Profile
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
    bind $w.status <Configure> [list $w.status configure -wraplength %w]
    bind $w.toolbar <Configure> [list ::GX::uiFieldControlsLayout $w.toolbar %w]
    after idle [list ::GX::ViewerDevelopmentWorkspace::initialLayout $w]
    ::GX::uiTextEditingAttach $w [list $source]
    bind $w <Control-s> {::GX::ViewerDevelopmentWorkspace::safe save;break}
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
    wm protocol $w WM_DELETE_WINDOW {::GX::ViewerDevelopmentWorkspace::safe close}
    controls
    if {[dict exists $context project]} {project [dict get $context project]}
    if {[dict exists $context maintenance_module]} {maintenanceDialog [dict get $context maintenance_module] [dict get $context maintenance_provider]}
    return $w
}
proc ::GX::ViewerDevelopmentWorkspace::initialLayout {w} {
    if {![winfo exists $w]} return
    set width [winfo width $w.body]
    if {$width<640} {after 100 [list ::GX::ViewerDevelopmentWorkspace::initialLayout $w];return}
    $w.body sashpos 0 205
    $w.body sashpos 1 [expr {$width-365}]
}
proc ::GX::ViewerDevelopmentWorkspace::responsiveLayout {w actual height} {
    if {$actual ne $w || ![winfo exists $w.bottom]} return
    # Keep source usable when fonts and wrapped command bars need more room.
    # All bottom panels retain their ordinary scrollbars and View toggles.
    set desired [expr {max(60,min(200,int($height*.18)))}]
    set browser $w.body.left.apiSplit.browser
    if {[winfo exists $browser] && [winfo ismapped $browser] && [winfo height $w.body]>100} {
        # The same Browser owner specifies its real font/chrome budget. Give
        # useful reference lines priority over surplus diagnostic rows while
        # keeping two diagnostic rows and their ordinary scrollbars available.
        set minimum [::GX::apiBrowserMinimumHeight $browser]
        set tree $w.bottom.diagnostics.tree
        set heading [font metrics TkHeadingFont -linespace]
        set row [expr {max(12,int(double([winfo reqheight $tree]-$heading-4)/max(1,[$tree cget -height])))}]
        set bottomMinimum [expr {2*$row+$heading+[winfo reqheight $w.bottom.diagnostics.horizontal]+4}]
        set page [$w.bottom select]
        set chrome [expr {max(0,[winfo height $w.bottom]-[winfo height $page])}]
        set budget [expr {[winfo height $w.body]+[winfo height $w.bottom]-$chrome-[dict get $minimum browser]-[dict get $minimum explorer]}]
        # At the supported minimum client height, wrapped bars and notebook
        # tabs may leave room for one diagnostic row. Keep its real header and
        # scrollbars rather than clipping the selected API reference. Larger
        # windows retain the usual two or more rows.
        if {$budget<$bottomMinimum} {set bottomMinimum [expr {$row+$heading+[winfo reqheight $w.bottom.diagnostics.horizontal]+4}]}
        set desired [expr {max($bottomMinimum,min($desired,$budget))}]
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
    set request [::GX::viewerDevelopmentRequest $operation $project [list ::GX::ViewerDevelopmentWorkspace::transferred $id] [dict create request_json $payload]]
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
