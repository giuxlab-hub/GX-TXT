# SPDX-License-Identifier: GPL-3.0-or-later
# Ordinary Viewer client. CORE owns policy, compiler, runtime, native views and packages.
namespace eval ::GX::ViewerDevelopmentWorkspace {variable s;array set s {project {} file handlers.cpp dirty 0 baseline {} busy {} generation 0 status {Open or create a restricted C++ project. No scientific Session is required.} preview {} find {}}}
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
    if {$s(project) eq {}||$s(file) ni {handlers.cpp project.json}} {error {Choose an editable project source first}}
    set source [::GX::sourceSurfaceGet [text]]
    transfer save $source $s(file)
    set s(baseline) $source;set s(dirty) [expr {[::GX::sourceSurfaceGet [text]] ne $source}];set s(status) "Saved $s(file) · [string range [::GX::sha256File [file join $s(project) $s(file)]] 0 11]"
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
    set roots [dict create handlers.cpp [file join $s(project) handlers.cpp] project.json [file join $s(project) project.json] design.gxtxt-viewer [file join $s(project) design.gxtxt-viewer] validation.json [file join $s(project) derived validation.json] build.json [file join $s(project) derived build.json] adapter.cpp [file join $::GX::scriptDir core development sdk trusted_adapter_v1.cpp]]
    if {![dict exists $roots $name]} {error {Unknown project browser file}}
    set path [dict get $roots $name]
    if {![file isfile $path]||[file type $path] eq {link}||[file size $path]>4194304} {error {Project file is unavailable or exceeds its bound}}
    set f [::open $path rb];try {set source [encoding convertfrom utf-8 [::read $f 4194305]]} finally {::close $f}
    set s(file) $name;set s(baseline) $source;set s(dirty) 0
    set language [expr {[string match *.cpp $name] ? {c} : ([string match *.json $name] ? {javascript} : {tcl})}]
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
    if {![file isfile [file join $path project.json]]} {error {Choose a developer project containing project.json}}
    if {$s(busy) ne {}} {::GX::scriptJobRequestCancel $s(busy) closed;set s(busy) {}}
    incr s(generation)
    set s(project) $path;set s(dirty) 0
    set tree .gxViewerDevelopment.body.left.files.tree;$tree delete [$tree children {}]
    foreach {name label} {handlers.cpp {C++ handlers} project.json {Project / facilities / tests} design.gxtxt-viewer {Builder design (read-only)} validation.json {Validation report} build.json {Build manifest} adapter.cpp {Trusted C++ adapter}} {$tree insert {} end -id $name -text $label}
    $tree selection set handlers.cpp;read handlers.cpp
    set s(status) "Project: $path"
    request api
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
    set path [tk_chooseDirectory -parent .gxViewerDevelopment -title {Open restricted C++ Viewer project}]
    if {$path ne {}} {project $path}
}
proc ::GX::ViewerDevelopmentWorkspace::request {operation} {
    variable s
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
    set tree .gxViewerDevelopment.bottom.diagnostics.tree;$tree delete [$tree children {}]
    foreach row [::GX::datasetPublicationV2DictDefault $report diagnostics {}] {$tree insert {} end -values [list [dict get $row file] [dict get $row line] [dict get $row column] [dict get $row message]]}
    if {$operation eq {export}&&[dict exists $result package]} {set s(status) "Candidate exported for review: [dict get $result package]"}
}
proc ::GX::ViewerDevelopmentWorkspace::controls {} {
    variable s
    if {![winfo exists .gxViewerDevelopment]} return
    foreach id {validate build demo test export} {.gxViewerDevelopment.toolbar.$id state [expr {$s(busy) eq {}?{!disabled}:{disabled}}]}
    .gxViewerDevelopment.toolbar.cancel state [expr {$s(busy) eq {}?{disabled}:{!disabled}}]
}
proc ::GX::ViewerDevelopmentWorkspace::cancel {} {variable s;if {$s(busy) ne {}} {::GX::scriptJobRequestCancel $s(busy)}}
proc ::GX::ViewerDevelopmentWorkspace::demo {} {
    variable s;if {$s(project) eq {}} {error {Open a project first}}
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
    variable s;set tree .gxViewerDevelopment.body.right.apis.list.tree;$tree delete [$tree children {}]
    dict for {api row} $s(catalog) {$tree insert {} end -id $api -text $api -values [list [dict get $row version] [expr {[dict get $row sdk_exposed]?{SDK subset}:{Not exposed}}]]}
    if {[$tree exists VIEWER_GUI_HOST_API_v1]} {$tree selection set VIEWER_GUI_HOST_API_v1;$tree see VIEWER_GUI_HOST_API_v1;apiSelect}
}
proc ::GX::ViewerDevelopmentWorkspace::apiSelect {} {
    variable s;set id [lindex [.gxViewerDevelopment.body.right.apis.list.tree selection] 0]
    if {$id eq {}||![dict exists $s(catalog) $id]} return
    set t .gxViewerDevelopment.body.right.apis.details.text;$t configure -state normal;$t delete 1.0 end
    dict for {key value} [dict get $s(catalog) $id] {$t insert end "$key: $value\n\n"}
    $t configure -state disabled
}
proc ::GX::ViewerDevelopmentWorkspace::apiGuide {} {set id [lindex [.gxViewerDevelopment.body.right.apis.list.tree selection] 0];if {$id ne {}} {::GX::documentationBrowserOpenApi $id}}
proc ::GX::ViewerDevelopmentWorkspace::manual {} {::GX::documentationBrowserOpenModuleWindow viewer.development_workspace .gxViewerDevelopment}
proc ::GX::ViewerDevelopmentWorkspace::find {direction} {variable s;::GX::sourceSurfaceFind [text] $s(find) $direction}
proc ::GX::ViewerDevelopmentWorkspace::importSource {} {
    variable s;if {$s(project) eq {}} {error {Open a project first}};if {![prepare]} return
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
    if {[winfo exists $w]} {raise $w;return $w}
    toplevel $w;wm title $w {Viewer Development Workspace · restricted C++};wm geometry $w 1320x860+40+60;wm minsize $w 980 650
    menu $w.menus -tearoff 0;$w configure -menu $w.menus
    foreach {id label} {file File edit Edit develop Develop help Help} {menu $w.menus.$id -tearoff 0;$w.menus add cascade -label $label -menu $w.menus.$id}
    foreach {label command} {{New project…} new {Open project…} openProject {Save source} save {Import C++ source…} importSource {Export candidate} {request export} Close close} {$w.menus.file add command -label $label -command [list ::GX::ViewerDevelopmentWorkspace::safe {*}$command]}
    foreach {label operation} {Undo undo Redo redo {Select all} select_all Copy copy Cut cut Paste paste} {$w.menus.edit add command -label $label -command [list ::GX::uiTextEdit $w $operation]}
    foreach {label command} {Validate {request validate} Build {request build} {Demo / Preview} demo Test {request test} {Cancel request} cancel} {$w.menus.develop add command -label $label -command [list ::GX::ViewerDevelopmentWorkspace::safe {*}$command]}
    $w.menus.help add command -label {Developer manual} -command ::GX::ViewerDevelopmentWorkspace::manual
    ttk::frame $w.toolbar;pack $w.toolbar -fill x -padx 5 -pady 5
    foreach {id label command} {new {New project…} new open {Open…} openProject save Save save validate Validate {request validate} build Build {request build} demo {Demo / Preview} demo test Test {request test} export {Export candidate} {request export} cancel Cancel cancel} {ttk::button $w.toolbar.$id -text $label -command [list ::GX::ViewerDevelopmentWorkspace::safe {*}$command];pack $w.toolbar.$id -side left -padx 2}
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
    set source [::GX::sourceSurfaceCreate $w.body.center.source {mode read_only language c}]
    set s(baseline) "// Open or create a restricted C++ Viewer project.\n// The trusted SDK is supplied automatically; no scientific Session is needed.\n"
    ::GX::sourceSurfaceSet $source $s(baseline)
    pack $w.body.center.source -fill both -expand 1
    bind $source <<Modified>> +::GX::ViewerDevelopmentWorkspace::modified
    ttk::frame $w.body.center.find
    ttk::label $w.body.center.find.label -text Find:
    ttk::entry $w.body.center.find.entry -textvariable ::GX::ViewerDevelopmentWorkspace::s(find)
    ttk::button $w.body.center.find.previous -text Previous -command {::GX::ViewerDevelopmentWorkspace::find backward}
    ttk::button $w.body.center.find.next -text Next -command {::GX::ViewerDevelopmentWorkspace::find forward}
    pack $w.body.center.find.label $w.body.center.find.entry $w.body.center.find.previous $w.body.center.find.next -side left -padx 3 -pady 3
    pack $w.body.center.find -side bottom -fill x -before $w.body.center.source
    ttk::frame $w.body.right.apis;ttk::frame $w.body.right.sdk;ttk::frame $w.body.right.profile
    $w.body.right add $w.body.right.apis -text {Public APIs};$w.body.right add $w.body.right.sdk -text SDK;$w.body.right add $w.body.right.profile -text Profile
    ttk::frame $w.body.right.apis.list;ttk::frame $w.body.right.apis.details
    ttk::treeview $w.body.right.apis.list.tree -columns {version exposed} -show {tree headings} -height 10 -selectmode browse
    $w.body.right.apis.list.tree heading #0 -text {Installed API};$w.body.right.apis.list.tree column #0 -width 185 -minwidth 100 -stretch 1
    foreach {id title width} {version Version 55 exposed Profile 105} {$w.body.right.apis.list.tree heading $id -text $title;$w.body.right.apis.list.tree column $id -width $width -minwidth $width -stretch 0}
    ::text $w.body.right.apis.details.text -wrap word -width 36 -height 12 -state disabled
    ttk::button $w.body.right.apis.guide -text {Open public API guide} -command ::GX::ViewerDevelopmentWorkspace::apiGuide
    pack $w.body.right.apis.guide -side bottom -fill x
    foreach panel {list details} {pack $w.body.right.apis.$panel -fill both -expand 1}
    ttk::scrollbar $w.body.right.apis.list.vertical -command [list $w.body.right.apis.list.tree yview]
    ttk::scrollbar $w.body.right.apis.list.horizontal -orient horizontal -command [list $w.body.right.apis.list.tree xview]
    $w.body.right.apis.list.tree configure -yscrollcommand [list $w.body.right.apis.list.vertical set] -xscrollcommand [list $w.body.right.apis.list.horizontal set]
    pack $w.body.right.apis.list.horizontal -side bottom -fill x;pack $w.body.right.apis.list.vertical -side right -fill y;pack $w.body.right.apis.list.tree -fill both -expand 1
    ttk::scrollbar $w.body.right.apis.details.vertical -command [list $w.body.right.apis.details.text yview]
    $w.body.right.apis.details.text configure -yscrollcommand [list $w.body.right.apis.details.vertical set]
    pack $w.body.right.apis.details.vertical -side right -fill y;pack $w.body.right.apis.details.text -fill both -expand 1
    bind $w.body.right.apis.list.tree <<TreeviewSelect>> ::GX::ViewerDevelopmentWorkspace::apiSelect
    set sdk [::GX::sourceSurfaceCreate $w.body.right.sdk.source {mode read_only language c}]
    pack $w.body.right.sdk.source -fill both -expand 1
    set f [::open [file join $::GX::scriptDir core development sdk gxtxt_viewer_sdk_v1.hpp] rb];try {::GX::sourceSurfaceSet $sdk [encoding convertfrom utf-8 [::read $f]]} finally {::close $f}
    ::text $w.body.right.profile.text -wrap word -width 36 -height 12
    $w.body.right.profile.text insert end {C++17 restricted SDK v1

Permitted: scalar locals, if/switch/loops, scalar helper functions, fixed event/state and enumerated Host methods. State indices are literal 0..15.

No authored includes, preprocessors, imports, external declarations, pointers/casts, raw libraries, I/O, processes or generic Tcl. Actual Clang lexer/AST policy runs before object generation.

The same GUI/CLI backend enforces the Linux project-write tool grant and separate bounded build/native worker. Candidate export never installs.

Python authoring is disabled. Public APIs outside the SDK remain unavailable; request an explicit CORE capability extension.

This cooperative architecture/quality workflow does not promise absolute hostile-native-code or account-wide isolation.}
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
    wm protocol $w WM_DELETE_WINDOW {::GX::ViewerDevelopmentWorkspace::safe close}
    controls
    if {[dict exists $context project]} {project [dict get $context project]}
    return $w
}
proc ::GX::ViewerDevelopmentWorkspace::initialLayout {w} {
    if {![winfo exists $w]} return
    set width [winfo width $w.body]
    if {$width<640} {after 100 [list ::GX::ViewerDevelopmentWorkspace::initialLayout $w];return}
    $w.body sashpos 0 205
    $w.body sashpos 1 [expr {$width-365}]
}
proc ::GX::ViewerDevelopmentWorkspace::dispatch {operation scene} {return [open [::GX::datasetPublicationV2DictDefault $scene open_context {}]]}
::GX::viewerBackendRegister viewer_development_workspace_tk ::GX::ViewerDevelopmentWorkspace::dispatch
