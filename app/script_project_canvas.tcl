# SPDX-License-Identifier: GPL-3.0-or-later
# Temporary presentation of the authoritative Script Registry Project owner.
# Source widgets/Notes/Undo remain alive; no source or Registry store lives here.
namespace eval ::GX::ScriptProjectCanvas {variable state {};variable values;variable treeLayouts {}}
proc ::GX::scriptProjectCanvasActive {window} {
    return [expr {[dict exists $::GX::ScriptProjectCanvas::state $window snapshot]}]
}
proc ::GX::scriptProjectCanvasMenus {editor language} {
    upvar #0 ${editor}::ui ui
    set menu $ui(window).toolbar.project.menu
    bind $ui(window) <FocusIn> +[list ::GX::_scriptProjectCanvasRememberFocus $ui(window) %W]
    bind $ui(window) <Destroy> +[list ::GX::_scriptProjectCanvasGone $ui(window) %W]
    set at 0
    foreach {label mode} {{New Project…} new {Open Project…} open {Import Project…} import {Manage Project…} open} {
        $menu insert $at command -label $label -command [list ::GX::scriptProjectCanvasShow $editor $language $mode]
        incr at
    }
    set submenu $menu.provided
    menu $submenu -tearoff 0 -postcommand [list ::GX::_scriptProjectCanvasApiMenu $ui(window)]
    foreach {label mode} {{Saved Public APIs} saved {Preview draft APIs} draft} {$submenu add command -label $label -command [list ::GX::scriptProjectCanvasApis $editor $language $mode]}
    $submenu add command -label {Open implementation} -command [list ::GX::_scriptProjectCanvasApiNavigate $ui(window)]
    $submenu add separator
    $submenu add command -label {Cancel API inventory} -command [list ::GX::_scriptProjectCanvasApiCancel $ui(window) user]
    $menu insert $at cascade -label {Public APIs} -menu $submenu;incr at
    $menu insert $at separator
    $menu add separator
    $menu add command -label {Return to code} -state disabled -command [list ::GX::scriptProjectCanvasReturn $ui(window)]
}
proc ::GX::_scriptProjectCanvasRememberFocus {window actual} {
    if {![scriptProjectCanvasActive $window] && [string match $window.p.* $actual] && $actual eq [focus]} {
        dict set ::GX::ScriptProjectCanvas::state $window last_focus $actual
    }
}
proc ::GX::_scriptProjectCanvasGone {window actual} {
    if {$window ne $actual} return
    _scriptProjectCanvasApiCancel $window
    dict unset ::GX::ScriptProjectCanvas::state $window
    array unset ::GX::ScriptProjectCanvas::values "$window,*"
    dict unset ::GX::ScriptProjectCanvas::treeLayouts $window.projectCanvas.book.open.rows
    dict unset ::GX::ScriptProjectCanvas::treeLayouts $window.projectCanvas.book.apis.panes.list.rows
}
proc ::GX::_scriptProjectCanvasTreeLayout {tree {mapped 0}} {
    # Hidden notebook pages can retain an old bbox indefinitely. Refreshing its
    # stale row metric can generate ThemeChanged again before it ever maps.
    # Map is the existing owner for applying the current theme once visible.
    if {![winfo exists $tree] || ![winfo ismapped $tree]} return
    variable ::GX::ScriptProjectCanvas::treeLayouts
    set headingFont [ttk::style lookup GXScriptProject.Treeview.Heading -font]
    if {$headingFont eq {}} {set headingFont [ttk::style lookup Treeview.Heading -font]}
    if {$headingFont eq {}} {set headingFont TkHeadingFont}
    set signature [list [winfo id $tree] [ttk::style theme use] [font actual TkDefaultFont] [font actual $headingFont]]
    set height [expr {[font metrics TkDefaultFont -linespace]+8}]
    if {!$mapped && [dict exists $treeLayouts $tree] && [dict get $treeLayouts $tree] eq $signature &&
        [$tree cget -style] eq {GXScriptProject.Treeview} &&
        [ttk::style lookup GXScriptProject.Treeview -rowheight] eq $height &&
        [ttk::style lookup GXScriptProject.Treeview -font] eq {TkDefaultFont}} return
    # Record before touching styles: repeated style-generated notifications
    # must not run the shared stale-bbox repair again for the same geometry.
    dict set treeLayouts $tree $signature
    _uiFieldTreeFontRows $tree GXScriptProject.Treeview
    # Only raise the existing Revision minimum; never shrink a user's column.
    set headingFont [ttk::style lookup GXScriptProject.Treeview.Heading -font]
    if {$headingFont eq {}} {set headingFont [ttk::style lookup Treeview.Heading -font]}
    if {$headingFont eq {}} {set headingFont TkHeadingFont}
    set minimum [expr {[font measure $headingFont [$tree heading revision -text]]+22}]
    $tree column revision -minwidth $minimum
    if {[$tree column revision -width]<$minimum} {$tree column revision -width $minimum}
}
proc ::GX::scriptProjectCanvasShow {editor language mode {options {}}} {
    variable ::GX::ScriptProjectCanvas::state
    variable ::GX::ScriptProjectCanvas::values
    upvar #0 ${editor}::ui ui
    set w $ui(window);set c $w.projectCanvas
    if {$mode ni {new open import apis} || $language ni {Python Octave}} {error {Unknown Script Project presentation}}
    if {[catch {dict size $options}] || [lsearch -all -inline -not -exact [dict keys $options] scope] ne {}} {error {Project presentation options admit only scope}}
    set requestedScope [datasetPublicationV2DictDefault $options scope {}]
    if {[dict exists $options scope]} {
        if {$requestedScope ni {user session} || $mode ni {new import}} {error {Explicit Project scope must be user or session for New/Import}}
        if {$requestedScope eq {session} && [scriptWorkspaceSessionToken] eq {}} {error {Session scope requires an actual current Session}}
        if {[scriptProjectCanvasActive $w]} {
            set prior [dict get $state $w snapshot]
            if {($requestedScope eq {session} && [dict get $prior session] ne [scriptWorkspaceSessionToken]) || ($requestedScope eq {user} && [dict get $prior user_root] ne [scriptRegistryRoot user])} {error {Project owner context changed; Return to code and reopen the canvas before selecting another scope}}
        }
    }
    if {![winfo exists $c]} {
        ttk::frame $c -padding 8
        ttk::label $c.title -text "$language Script Projects" -font TkHeadingFont
        ttk::label $c.about -text {New Script works independently. Projects use the same Registry, source tabs and Runner.} -wraplength 700 -justify left
        bind $c.about <Configure> [list ::GX::_uiFieldComponentTextWrap $c.about 32767 %W %w]
        ttk::label $c.status -textvariable ::GX::ScriptProjectCanvas::values($w,status) -wraplength 700 -justify left
        bind $c.status <Configure> [list ::GX::_uiFieldComponentTextWrap $c.status 32767 %W %w]
        ttk::button $c.return -text {Return to code} -command [list ::GX::scriptProjectCanvasReturn $w]
        pack $c.title $c.about -side top -fill x -pady {0 6}
        pack $c.return -side bottom -anchor e -pady {6 0}
        pack $c.status -side bottom -fill x
        ttk::notebook $c.book;pack $c.book -fill both -expand 1
        bind $c.book <<NotebookTabChanged>> [list ::GX::_scriptProjectCanvasApiSchedule $w]
        foreach {page title} {new {New project} open {Open / Manage projects} import {Import project} apis {Public APIs}} {
            ttk::frame $c.book.$page;$c.book add $c.book.$page -text $title
        }
        set values($w,name) {Untitled project};set values($w,id) {};set values($w,scope) [scriptWorkspaceDefaultScope]
        set values($w,entrypoint) [expr {$language eq {Python}?{main.py}:{main.m}}]
        set values($w,description) {};set values($w,archive) {};set values($w,status) {}
        foreach page {new import} {
            set body [uiFieldScrollableCreate $c.book.$page.form 600];pack $c.book.$page.form -fill both -expand 1
            ttk::label $body.language -text "Language: $language (fixed to this Workspace)";grid $body.language -row 0 -column 0 -columnspan 2 -sticky w -pady 8
            set row 1
            foreach {key label} {name Name id {Stable ID} scope Scope} {
                ttk::label $body.l$key -text $label
                if {$key eq {scope}} {ttk::combobox $body.e$key -state readonly -values [expr {$::GX::currentSession eq {}?{user}:{user session}}] -textvariable ::GX::ScriptProjectCanvas::values($w,$key)} else {ttk::entry $body.e$key -textvariable ::GX::ScriptProjectCanvas::values($w,$key)}
                grid $body.l$key -row $row -column 0 -sticky w -padx {0 8} -pady 5
                grid $body.e$key -row $row -column 1 -sticky ew -pady 5;incr row
            }
            if {$page eq {new}} {
                ttk::label $body.lentrypoint -text Entrypoint;ttk::entry $body.eentrypoint -textvariable ::GX::ScriptProjectCanvas::values($w,entrypoint)
                grid $body.lentrypoint -row $row -column 0 -sticky w;grid $body.eentrypoint -row $row -column 1 -sticky ew;incr row
                set label {Create project}
            } else {
                ttk::label $body.larchive -text {Project ZIP};ttk::entry $body.earchive -textvariable ::GX::ScriptProjectCanvas::values($w,archive) -state readonly
                ttk::button $body.browse -text {Choose project ZIP…} -command [list ::GX::_scriptProjectCanvasChoose $w]
                grid $body.larchive -row $row -column 0 -sticky w;grid $body.earchive -row $row -column 1 -sticky ew;incr row
                grid $body.browse -row $row -column 1 -sticky e;incr row
                set label {Import project}
            }
            ttk::label $body.ldescription -text Description
            ttk::entry $body.edescription -textvariable ::GX::ScriptProjectCanvas::values($w,description)
            grid $body.ldescription -row $row -column 0 -sticky w -pady 5
            grid $body.edescription -row $row -column 1 -sticky ew -pady 5
            ttk::button $c.book.$page.commit -text $label -command [list ::GX::scriptProjectCanvasCommit $w $page]
            pack $c.book.$page.commit -side bottom -anchor e -padx 8 -pady 8 -before $c.book.$page.form
            grid columnconfigure $body 1 -weight 1
        }
        set page $c.book.open
        ttk::treeview $page.rows -columns {name identity entrypoint revision} -show headings -selectmode browse
        foreach {key title width} {name Name 220 identity Identity 220 entrypoint Entrypoint 180 revision Revision 90} {$page.rows heading $key -text $title;$page.rows column $key -width $width -stretch [expr {$key eq {name}}]}
        _scriptProjectCanvasTreeLayout $page.rows
        bind $page.rows <<ThemeChanged>> [list ::GX::_scriptProjectCanvasTreeLayout $page.rows]
        bind $page.rows <Map> [list ::GX::_scriptProjectCanvasTreeLayout $page.rows 1]
        ttk::scrollbar $page.v -command [list $page.rows yview];ttk::scrollbar $page.h -orient horizontal -command [list $page.rows xview]
        $page.rows configure -yscrollcommand [list $page.v set] -xscrollcommand [list $page.h set]
        ttk::frame $page.actions
        ttk::button $page.actions.refresh -text Refresh -command [list ::GX::_scriptProjectCanvasRefresh $w]
        ttk::button $page.actions.open -text {Open entrypoint} -command [list ::GX::scriptProjectCanvasCommit $w open]
        pack $page.actions.refresh $page.actions.open -side left -padx 4
        grid $page.rows -row 0 -column 0 -sticky nsew;grid $page.v -row 0 -column 1 -sticky ns
        grid $page.h -row 1 -column 0 -sticky ew;grid $page.actions -row 2 -column 0 -sticky e -pady 8
        grid rowconfigure $page 0 -weight 1;grid columnconfigure $page 0 -weight 1
        bind $page.rows <Double-1> [list ::GX::scriptProjectCanvasCommit $w open]
        bind $page.rows <Return> "[list ::GX::scriptProjectCanvasCommit $w open];break"
        _scriptProjectCanvasApiCreate $w
        dict set state $w editor $editor;dict set state $w language $language
    }
    if {![scriptProjectCanvasActive $w]} {
        foreach page {new import} {
            $c.book.$page.form.scroll.content.escope configure -values [expr {$::GX::currentSession eq {}?{user}:{user session}}]
        }
        set pack [pack info $w.p];set siblings [pack slaves $w]
        set after [lrange $siblings [expr {[lsearch -exact $siblings $w.p]+1}] end]
        set previousFocus [focus]
        if {[string match $w.toolbar* $previousFocus] && [dict exists $state $w last_focus] && [winfo exists [dict get $state $w last_focus]]} {set previousFocus [dict get $state $w last_focus]}
        set snapshot [dict create user_root [scriptRegistryRoot user] pack $pack following $after focus $previousFocus session [scriptWorkspaceSessionToken] session_path $::GX::currentSession width [winfo width $w.p] sashes {} bindings {} menus {}]
        for {set i 0} {$i<[llength [$w.p panes]]-1} {incr i} {dict lappend snapshot sashes [$w.p sashpos $i]}
        foreach event {<Control-s> <Control-Shift-S> <Control-w> <Control-Tab> <Control-Shift-Tab> <Control-ISO_Left_Tab> <Control-f> <Control-h> <Control-g> <F3> <Shift-F3> <Escape>} {
            dict set snapshot bindings $event [bind $w $event]
            bind $w $event [expr {$event eq {<Escape>}?"[list ::GX::scriptProjectCanvasReturn $w];break":{break}}]
        }
        foreach group {file edit project view run} {
            set menu $w.toolbar.$group.menu;set entries {}
            for {set i 0} {$i<=[$menu index end]} {incr i} {if {[$menu type $i] ni {separator tearoff}} {dict set entries $i [$menu entrycget $i -state]}}
            dict set snapshot menus $group [dict create post [$menu cget -postcommand] entries $entries]
            $menu configure -postcommand [list ::GX::_scriptProjectCanvasMenuPost $w $group]
        }
        dict set state $w snapshot $snapshot
        pack forget $w.p;pack $c {*}$pack
    }
    if {$requestedScope ne {}} {set values($w,scope) $requestedScope}
    $c.about configure -text [expr {$mode eq {apis}?{Provided APIs: static source declarations; no execution or grants.}:{New Script works independently. Projects use the same Registry, source tabs and Runner.}}]
    $c.book select $c.book.$mode
    set values($w,status) {Source and Notes are retained. Session scope uses the Session active when this canvas opened.}
    if {$mode eq {open}} {_scriptProjectCanvasRefresh $w}
    focus $c.book
    return $c
}
proc ::GX::_scriptProjectCanvasMenuPost {w group} {
    set menu $w.toolbar.$group.menu
    set allowed [expr {$group eq {project}?{{New Project…} {Open Project…} {Import Project…} {Manage Project…} {Public APIs} {Return to code}}:($group eq {file}?{{New Script} Close}:{})}]
    for {set i 0} {$i<=[$menu index end]} {incr i} {
        if {[$menu type $i] in {separator tearoff}} continue
        $menu entryconfigure $i -state [expr {[$menu entrycget $i -label] in $allowed?{normal}:{disabled}}]
    }
}
proc ::GX::scriptProjectCanvasReturn {w} {
    variable ::GX::ScriptProjectCanvas::state
    if {![scriptProjectCanvasActive $w]} return
    _scriptProjectCanvasApiCancel $w
    set saved [dict get $state $w snapshot];dict unset state $w snapshot
    pack forget $w.projectCanvas
    set options [dict get $saved pack];set placed 0
    foreach next [dict get $saved following] {if {[winfo exists $next] && [winfo manager $next] eq {pack}} {pack $w.p {*}$options -before $next;set placed 1;break}}
    if {!$placed} {pack $w.p {*}$options}
    dict for {event value} [dict get $saved bindings] {bind $w $event $value}
    dict for {group data} [dict get $saved menus] {
        set menu $w.toolbar.$group.menu;$menu configure -postcommand [dict get $data post]
        dict for {index value} [dict get $data entries] {$menu entryconfigure $index -state $value}
    }
    update idletasks
    set i 0;foreach position [dict get $saved sashes] {$w.p sashpos $i [expr {int($position*[winfo width $w.p]/double(max(1,[dict get $saved width])))}];incr i}
    set previous [dict get $saved focus]
    if {$previous ne {} && [winfo exists $previous]} {focus $previous}
}
proc ::GX::_scriptProjectCanvasRefresh {w} {
    variable ::GX::ScriptProjectCanvas::state
    variable ::GX::ScriptProjectCanvas::values
    set tree $w.projectCanvas.book.open.rows;$tree delete [$tree children {}]
    set rows {};set count 0
    foreach item [scriptRegistryList all] {
        if {[dict get $item kind] ne {project} || [dict get $item language] ne [dict get $state $w language]} continue
        if {[incr count]>500} {set values($w,status) {Showing500 projects; refine the Registry outside this bounded view.};break}
        set ref "[dict get $item scope]:[dict get $item id]";dict set item reference $ref;dict set rows $ref $item
        $tree insert {} end -id $ref -values [list [dict get $item name] $ref [dict get $item entrypoint] [dict get $item revision]]
    }
    dict set state $w rows $rows
}
proc ::GX::_scriptProjectCanvasChoose {w} {
    variable ::GX::ScriptProjectCanvas::state
    variable ::GX::ScriptProjectCanvas::values
    set path [tk_getOpenFile -parent $w -filetypes {{{Script Project ZIP} {.zip}}}]
    if {$path eq {}} return
    set values($w,archive) $path;dict set state $w archive_sha [scriptRegistryHash $path]
}
proc ::GX::scriptProjectCanvasCommit {w mode} {
    variable ::GX::ScriptProjectCanvas::state
    variable ::GX::ScriptProjectCanvas::values
    if {![scriptProjectCanvasActive $w]} {return 0}
    set editor [dict get $state $w editor];set language [dict get $state $w language]
    try {
        if {$mode eq {open}} {
            set selected [$w.projectCanvas.book.open.rows selection]
            if {[llength $selected]!=1} {error {Select a saved project}}
            set old [dict get $state $w rows [lindex $selected 0]]
            set scope [dict get $old scope]
        } else {set scope $values($w,scope)}
        if {$scope eq {user} && [scriptRegistryRoot user] ne [dict get $state $w snapshot user_root]} {error {User Registry changed; return to code and reopen this canvas before continuing}}
        if {$scope eq {session} && ([dict get $state $w snapshot session] eq {} || [scriptWorkspaceSessionToken] ne [dict get $state $w snapshot session])} {error {Session changed or is absent; return to code and reopen the project canvas in the intended Session}}
        if {$mode eq {new}} {
            set code [expr {$language eq {Python}?"# Project entrypoint\n":"% Project entrypoint\n"}]
            set result [scriptRegistryProjectSave $scope $values($w,id) $values($w,name) $language $values($w,entrypoint) [dict create $values($w,entrypoint) $code] [dict create description $values($w,description)]]
        } elseif {$mode eq {import}} {
            set path $values($w,archive)
            if {![dict exists $state $w archive_sha] || [scriptRegistryHash $path] ne [dict get $state $w archive_sha]} {error {Project ZIP changed; choose it again}}
            set result [scriptRegistryProjectImport $scope $values($w,id) $values($w,name) $path [dict create expected_language $language description $values($w,description)]]
        } elseif {$mode eq {open}} {
            set result [scriptRegistryDescribe [dict get $old reference]]
            if {[dict get $result sha256] ne [dict get $old sha256] || [dict get $result revision] ne [dict get $old revision]} {error {Project changed; refresh the saved project list before opening}}
            if {[dict get $result language] ne $language || [dict get $result kind] ne {project}} {error {Project language or identity changed}}
        } else {error {Unknown project action}}
    } on error {reason options} {
        set values($w,status) "Project action refused: $reason. Existing source/Notes remain unchanged; Return to code restores them."
        return 0
    }
    set reference "$scope:[dict get $result id]"
    upvar #0 ${editor}::ui ui
    # Capture the old source BEFORE reading/opening the independently admitted
    # current-scope record. Never assign the old source's ui(sessionToken).
    scriptSourceTabsCapture $ui(tabs)
    set opened [::GX::${language}ScriptEditor::workspaceRead $reference]
    set opened [scriptSourceTabsAdmitDocument $reference $opened]
    scriptProjectCanvasReturn $w
    ${editor}::_refreshDocuments
    scriptSourceTabsOpen $ui(tabs) $reference $opened
    ${editor}::_selectTreeId $reference
    return 1
}

# Static PROVIDED inventory is a read-only view over the existing source owner.
proc ::GX::_scriptProjectCanvasApiCreate {w} {
    set p $w.projectCanvas.book.apis
    bind $p <Map> [list ::GX::_scriptProjectCanvasApiSchedule $w]
    ttk::label $p.notice -text {Select an operation for its details. Enter opens its implementation.} -wraplength 700 -justify left
    bind $p.notice <Configure> [list ::GX::_uiFieldComponentTextWrap $p.notice 32767 %W %w]
    pack $p.notice -side top -fill x -pady {0 5}
    ttk::notebook $p.panes;pack $p.panes -fill both -expand 1
    ttk::frame $p.panes.list;set f $p.panes.list
    ttk::treeview $f.rows -columns {implementation state} -show {tree headings} -selectmode browse
    $f.rows heading #0 -text {API / operation};$f.rows column #0 -width 360 -minwidth 220
    $f.rows heading implementation -text {Source / line};$f.rows column implementation -width 350 -minwidth 160
    $f.rows heading state -text Qualification;$f.rows column state -width 220 -minwidth 120
    ttk::scrollbar $f.sy -command [list $f.rows yview];ttk::scrollbar $f.sx -orient horizontal -command [list $f.rows xview]
    $f.rows configure -yscrollcommand [list $f.sy set] -xscrollcommand [list $f.sx set]
    grid $f.rows -row 0 -column 0 -sticky nsew;grid $f.sy -row 0 -column 1 -sticky ns;grid $f.sx -row 1 -column 0 -sticky ew
    grid columnconfigure $f 0 -weight 1;grid rowconfigure $f 0 -weight 1
    bind $f.rows <Map> [list ::GX::_scriptProjectCanvasApiRows $f.rows]
    bind $f.rows <<ThemeChanged>> [list ::GX::_scriptProjectCanvasApiRows $f.rows]
    bind $f.rows <Configure> [list ::GX::_scriptProjectCanvasApiRows $f.rows]
    bind $f.rows <<TreeviewSelect>> [list ::GX::_scriptProjectCanvasApiDetail $w]
    bind $f.rows <Double-1> [list ::GX::_scriptProjectCanvasApiNavigate $w]
    bind $f.rows <Return> "[list ::GX::_scriptProjectCanvasApiNavigate $w];break"
    ttk::frame $p.panes.detail
    set text [sourceSurfaceCreate $p.panes.detail.source {mode read_only language javascript find_bar 0}]
    pack $p.panes.detail.source -fill both -expand 1
    $p.panes add $f -text {Operations / requirements};$p.panes add $p.panes.detail -text {Operation details}
    dict set ::GX::ScriptProjectCanvas::state $w api_detail $text
    sourceSurfaceSet $text {Save first if this source is not registered. Saved inventory and unsaved draft preview are explicitly separate; neither executes the source.}
}
proc ::GX::_scriptProjectCanvasApiRows {tree} {
    if {![winfo exists $tree] || ![winfo ismapped $tree] || [winfo width $tree]<20 || [winfo height $tree]<[font metrics TkDefaultFont -linespace]} return
    variable ::GX::ScriptProjectCanvas::treeLayouts
    set signature [list [winfo id $tree] [ttk::style theme use] [font actual TkDefaultFont]]
    if {[dict exists $treeLayouts $tree] && [dict get $treeLayouts $tree] eq $signature && [$tree cget -style] eq {GXScriptProvided.Treeview}} return
    dict set treeLayouts $tree $signature
    _uiFieldTreeFontRows $tree GXScriptProvided.Treeview
}
proc ::GX::_scriptProjectCanvasApiMenu {w} {
    if {![winfo exists $w]} return
    set menu $w.toolbar.project.menu.provided
    set pending [expr {[dict exists $::GX::ScriptProjectCanvas::state $w api_request] && [dict get $::GX::ScriptProjectCanvas::state $w api_request] ne {}}]
    foreach label {{Saved Public APIs} {Preview draft APIs}} {$menu entryconfigure $label -state [expr {$pending?{disabled}:{normal}}]}
    $menu entryconfigure {Cancel API inventory} -state [expr {$pending?{normal}:{disabled}}]
    set selected 0
    if {[scriptProjectCanvasActive $w] && [dict exists $::GX::ScriptProjectCanvas::state $w api_rows]} {
        set rows $w.projectCanvas.book.apis.panes.list.rows
        if {[winfo exists $rows] && [llength [$rows selection]]==1 && [dict exists $::GX::ScriptProjectCanvas::state $w api_rows [lindex [$rows selection] 0]]} {
            set operation [dict get $::GX::ScriptProjectCanvas::state $w api_rows [lindex [$rows selection] 0]]
            set selected [expr {[dict exists $operation implementation sha256] && [dict exists $operation implementation line]}]
        }
    }
    $menu entryconfigure {Open implementation} -state [expr {$selected&&!$pending?{normal}:{disabled}}]
}
proc ::GX::_scriptProjectCanvasApiCancel {w {reason context_changed}} {
    variable ::GX::ScriptProjectCanvas::state
    if {![dict exists $state $w]} return
    if {[dict exists $state $w api_auto_timer]} {after cancel [dict get $state $w api_auto_timer];dict unset state $w api_auto_timer}
    set generation [datasetPublicationV2DictDefault [dict get $state $w] api_generation 0]
    if {$reason eq {user} && [dict exists $state $w api_request_generation]} {
        dict set state $w api_cancel_generation [dict get $state $w api_request_generation]
        set ::GX::ScriptProjectCanvas::values($w,status) {Cancelling API inventory; waiting for the owned worker to close.}
    }
    dict set state $w api_generation [incr generation]
    if {[dict exists $state $w api_request] && [dict get $state $w api_request] ne {}} {catch {scriptJobRequestCancel [dict get $state $w api_request] user_cancelled}}
}
proc ::GX::_scriptProjectCanvasApiSchedule {w} {
    variable ::GX::ScriptProjectCanvas::state
    if {![winfo exists $w] || ![dict exists $state $w]} return
    if {[dict exists $state $w api_auto_timer]} {after cancel [dict get $state $w api_auto_timer]}
    dict set state $w api_auto_timer [after idle [list ::GX::_scriptProjectCanvasApiAutomatic $w]]
}
proc ::GX::_scriptProjectCanvasApiAutomatic {w} {
    variable ::GX::ScriptProjectCanvas::state
    if {![winfo exists $w] || ![dict exists $state $w]} return
    dict unset state $w api_auto_timer
    if {![scriptProjectCanvasActive $w] || [$w.projectCanvas.book select] ne "$w.projectCanvas.book.apis"} return
    if {[dict exists $state $w api_request] && [dict get $state $w api_request] ne {}} return
    scriptProjectCanvasApis [dict get $state $w editor] [dict get $state $w language] saved
}
proc ::GX::_scriptProjectCanvasApiFingerprint {w} {
    variable ::GX::ScriptProjectCanvas::state
    set editor [dict get $state $w editor];upvar #0 ${editor}::ui ui
    set p $ui(tabs);set group [scriptSourceTabsGroupKey $p];set sources {}
    foreach tab [scriptSourceTabsPages $p] {
        if {[scriptSourceTabsGroupKey $p $tab] ne $group} continue
        set relative $::GX::ScriptSourceTabs::state($p,$tab,path)
        set text $::GX::ScriptSourceTabs::state($p,$tab,text)
        set body [$text get 1.0 end-1c]
        if {$body ne $::GX::ScriptSourceTabs::state($p,$tab,baseline)} {dict set sources $relative $body}
    }
    set sorted {};foreach relative [lsort [dict keys $sources]] {lappend sorted $relative [dict get $sources $relative]}
    return [scriptRegistryHashBytes [encoding convertto utf-8 [list $group $sorted]]]
}
proc ::GX::_scriptProjectCanvasApiContext {w mode {captureSources 1}} {
    variable ::GX::ScriptProjectCanvas::state
    set editor [dict get $state $w editor];upvar #0 ${editor}::ui ui
    set identity [scriptSourceTabsIdentity $ui(tabs)];set reference [dict get $identity reference]
    if {![regexp {^(user|session):} $reference]} {error {Save first: register this Script or Project through the existing File → Save owner before discovering its APIs. No draft identity has been invented.}}
    if {![scriptSourceTabsOwnerCurrent $ui(tabs)]} {error {Source owner changed; the source and Notes remain retained. Reopen the intended context before API discovery.}}
    # Registry operations require the captured directory; the opaque token is
    # a separate lifetime guard, including reopening the same Session path.
    set session {};set sessionToken {}
    if {[dict get $identity scope] eq {session}} {
        set sessionToken [dict get $state $w snapshot session]
        set session [dict get $state $w snapshot session_path]
        if {$sessionToken eq {} || $sessionToken ne [scriptWorkspaceSessionToken] || $session eq {} || $session ne $::GX::currentSession} {error {Session changed; return to code and reopen the canvas in the intended Session}}
    }
    set metadata [scriptRegistryDescribe $reference $session];set options {}
    foreach field {sha256 revision record_sha256 owner_context} {dict set options expected_$field [dict get $metadata $field]}
    set context [dict create reference $reference session $session session_token $sessionToken baseline $options mode $mode fingerprint [_scriptProjectCanvasApiFingerprint $w]]
    if {$mode eq {draft}} {
        if {[dict get $identity sha256] ne [dict get $metadata sha256] || [dict get $identity revision] ne [dict get $metadata revision]} {error {Saved source changed since this draft opened. Review/reopen without discarding your draft before previewing its API inventory.}}
        if {!$captureSources} {return [list $context $options]}
        if {[dict get $metadata kind] eq {project}} {
            dict set options draft_sources [scriptSourceTabsFiles $ui(tabs)]
            dict set options draft_entrypoint [dict get $metadata entrypoint]
        } else {dict set options draft_sources [dict create [scriptRegistrySourceName [dict get $metadata language]] [$ui(text) get 1.0 end-1c]]}
    }
    return [list $context $options]
}
proc ::GX::scriptProjectCanvasApis {editor language mode} {
    variable ::GX::ScriptProjectCanvas::state
    variable ::GX::ScriptProjectCanvas::values
    if {$mode ni {saved draft}} {error {Choose saved inventory or explicit draft preview}}
    upvar #0 ${editor}::ui ui;set w $ui(window)
    scriptProjectCanvasShow $editor $language apis
    if {[dict exists $state $w api_request] && [dict get $state $w api_request] ne {}} {set values($w,status) {API inventory is still running or cancelling; wait for owned worker cleanup.};return}
    if {[catch {
        lassign [_scriptProjectCanvasApiContext $w $mode] context options
        set pins {}
        foreach relative {app/script_provided_inventory_request.tcl core/tcl/script_provided_api_v1.tcl core/tcl/script_project_v1.tcl core/tcl/script_execution_api_v1.tcl core/python/script_project.py core/python/script_api_exports.py core/python/script_api_declarations.py} {dict set pins $relative [sha256File [file join $::GX::scriptDir $relative]]}
        set payload [dict create reference [dict get $context reference] session [dict get $context session] options $options code_pins $pins python [runtimeToolResolve python]]
        set generation [expr {[datasetPublicationV2DictDefault [dict get $state $w] api_generation 0]+1}]
        dict unset state $w api_cancel_generation
        dict set state $w api_generation $generation;dict set state $w api_request_generation $generation
        set command [list {*}[auto_execok setsid] {*}[auto_execok tclsh] [file join $::GX::scriptDir app script_provided_inventory_request.tcl] $::GX::scriptDir]
        set request [scriptJobAsync $command $payload [list ::GX::_scriptProjectCanvasApiDone $w $generation $context] {timeout_ms 30000 max_bytes 4194304 process_group 1 ui_lifetime 1 label {Source-provided API inventory}}]
        dict set state $w api_request $request
        set values($w,status) "Discovering $mode APIs for [dict get $context reference] asynchronously; no source execution."
    } reason]} {
        set values($w,status) [expr {[string first {Save first:} $reason]==0?{Save first: this source is not registered.}:[string range $reason 0 150]}]
        sourceSurfaceSet [dict get $state $w api_detail] $reason
    }
}
proc ::GX::_scriptProjectCanvasApiDone {w generation context response} {
    variable ::GX::ScriptProjectCanvas::state
    variable ::GX::ScriptProjectCanvas::values
    if {![winfo exists $w] || ![dict exists $state $w]} return
    if {[dict exists $state $w api_request_generation] && [dict get $state $w api_request_generation]==$generation} {dict set state $w api_request {};dict unset state $w api_request_generation}
    if {![scriptProjectCanvasActive $w] || ![dict exists $state $w api_generation]} return
    if {[dict get $state $w api_generation]!=$generation} {
        if {[dict exists $state $w api_cancel_generation] && [dict get $state $w api_cancel_generation]==$generation} {
            dict unset state $w api_cancel_generation
            set values($w,status) {API inventory cancelled; owned worker closed. Source and Notes are unchanged.}
        }
        return
    }
    if {[catch {
        if {![dict get $response ok]} {error [dict get $response error]}
        lassign [_scriptProjectCanvasApiContext $w [dict get $context mode] 0] current ignored
        foreach field {reference session session_token mode fingerprint} {if {[dict get $current $field] ne [dict get $context $field]} {error {Source context/draft changed during discovery; result discarded. Refresh the intended source.}}}
        foreach field {expected_sha256 expected_revision expected_record_sha256 expected_owner_context} {if {[dict get $current baseline $field] ne [dict get $context baseline $field]} {error {Registered source/owner changed during API discovery; result discarded.}}}
        set inventory [dict get $response result]
        if {[dict get $inventory schema] ne {gxtxt.script_provided_api_inventory.v1} || [dict get $inventory execution_authority] ne {none}} {error {Unexpected inventory owner receipt}}
        dict set state $w api_inventory $inventory
        dict set state $w api_context $context
        _scriptProjectCanvasApiPopulate $w $inventory
        set label [expr {[dict get $inventory source_scope] eq {registered_snapshot}?{Saved APIs}:{UNSAVED draft preview}}]
        set values($w,status) "$label · [dict get $inventory reference] · revision[dict get $inventory registry_baseline expected_revision] · [llength [dict get $inventory operations]] operations · valid=[dict get $inventory valid]"
    } reason]} {set values($w,status) "API inventory not current: $reason"}
}
proc ::GX::_scriptProjectCanvasApiPopulate {w inventory} {
    variable ::GX::ScriptProjectCanvas::state
    set tree $w.projectCanvas.book.apis.panes.list.rows;$tree delete [$tree children {}]
    $tree insert {} end -id provided -text PROVIDED -open 1
    $tree insert {} end -id consumed -text CONSUMED -open 1
    $tree insert {} end -id diagnostics -text Diagnostics -open 1
    $tree insert {} end -id files -text {Whole source closure} -open 0
    set details {};set serial 0
    foreach api [dict get $inventory provided] {
        set parent api#[incr serial];set title [dict get $api name];if {$title eq [dict get $api id]} {set title {}}
        $tree insert provided end -id $parent -text [dict get $api id] -values [list $title "version[dict get $api version] · static"] -open 1
        foreach operation [dict get $inventory operations] {
            if {[dict get $operation api_id] ne [dict get $api id]} continue
            set impl [dict get $operation implementation];set row operation#[incr serial]
            set line [datasetPublicationV2DictDefault $impl line 0]
            set status [expr {$line>0?"read_only=[dict get $operation read_only]":{UNBOUND; see diagnostics}}]
            $tree insert $parent end -id $row -text [dict get $operation id] -values [list "[dict get $impl file]:$line" $status]
            dict set details $row $operation
        }
    }
    foreach requirement [dict get $inventory consumed] {$tree insert consumed end -text $requirement -values {{} {requirement only; no grant}}}
    foreach diagnostic [dict get $inventory diagnostics] {$tree insert diagnostics end -text [dict get $diagnostic code] -values [list "[dict get $diagnostic file]:[dict get $diagnostic line]" [dict get $diagnostic message]]}
    foreach file [dict get $inventory files] {$tree insert files end -text [dict get $file path] -values [list "[dict get $file size] bytes" [dict get $file sha256]]}
    dict set state $w api_rows $details
    sourceSurfaceSet [dict get $state $w api_detail] "Select a PROVIDED operation for its exact source, signature and declared typed schema.\n\nDeclaration SHA: [dict get $inventory declaration_sha256]\n\nThis is static inventory; no function was imported or executed."
}
proc ::GX::_scriptProjectCanvasApiType {schema {indent {}}} {
    set text "$indent[dict get $schema kind]"
    foreach key {name required units default max_items max_length description} {if {[dict exists $schema $key]} {append text " · $key=[dict get $schema $key]"}}
    append text \n
    if {[dict exists $schema fields]} {foreach field [dict get $schema fields] {append text [_scriptProjectCanvasApiType $field "$indent  "]}}
    if {[dict exists $schema items]} {append text [_scriptProjectCanvasApiType [dict get $schema items] "$indent  "]}
    return $text
}
proc ::GX::_scriptProjectCanvasApiDetail {w} {
    variable ::GX::ScriptProjectCanvas::state
    if {![winfo exists $w] || ![dict exists $state $w api_rows]} return
    set tree $w.projectCanvas.book.apis.panes.list.rows;set selected [$tree selection]
    if {[llength $selected]!=1 || ![dict exists $state $w api_rows [lindex $selected 0]]} return
    set op [dict get $state $w api_rows [lindex $selected 0]];set impl [dict get $op implementation]
    set text "[dict get $op api_id] / [dict get $op id]\n[dict get $op summary]\n\nImplementation: [dict get $impl file]:[dict get $impl function], line[datasetPublicationV2DictDefault $impl line 0]\nSignature: [datasetPublicationV2DictDefault $impl signature UNBOUND]\nSource SHA: [datasetPublicationV2DictDefault $impl sha256 UNBOUND]\nDeclaration: [dict get $op declaration_file], line[dict get $op declaration_line]\n\nArguments:\n"
    foreach arg [dict get $op arguments] {append text [_scriptProjectCanvasApiType $arg {  }]}
    append text "\nResult:\n" [_scriptProjectCanvasApiType [dict get $op result] {  }]
    foreach key {result_contract unit_behavior read_only effects capabilities required_apis} {append text "\n${key}: [dict get $op $key]"}
    sourceSurfaceSet [dict get $state $w api_detail] $text
}
proc ::GX::_scriptProjectCanvasApiNavigate {w} {
    variable ::GX::ScriptProjectCanvas::state
    variable ::GX::ScriptProjectCanvas::values
    if {![scriptProjectCanvasActive $w] || ![dict exists $state $w api_context]} return
    set tree $w.projectCanvas.book.apis.panes.list.rows;set selected [$tree selection]
    if {[llength $selected]!=1 || ![dict exists $state $w api_rows [lindex $selected 0]]} return
    if {[catch {
        set context [dict get $state $w api_context]
        lassign [_scriptProjectCanvasApiContext $w [dict get $context mode] 0] current ignored
        foreach field {reference session session_token mode fingerprint} {if {[dict get $current $field] ne [dict get $context $field]} {error {Source draft/context changed; refresh the API inventory before navigation}}}
        foreach field {expected_sha256 expected_revision expected_record_sha256 expected_owner_context} {if {[dict get $current baseline $field] ne [dict get $context baseline $field]} {error {Saved source changed; refresh the API inventory before navigation}}}
        set op [dict get $state $w api_rows [lindex $selected 0]];set impl [dict get $op implementation]
        if {![dict exists $impl sha256] || ![dict exists $impl line]} {error {Implementation is not bound; inspect diagnostics and repair the source declaration first}}
        set editor [dict get $state $w editor];set language [dict get $state $w language];upvar #0 ${editor}::ui ui
        set document [scriptSourceTabsCurrent $ui(tabs)]
        if {[dict get $document kind] eq {project}} {set files [scriptSourceTabsFiles $ui(tabs)]} else {set files [dict create [scriptRegistrySourceName $language] [$ui(text) get 1.0 end-1c]]}
        set relative [dict get $impl file]
        if {![dict exists $files $relative] || [scriptRegistryHashBytes [encoding convertto utf-8 [dict get $files $relative]]] ne [dict get $impl sha256]} {error {The selected declaration differs from the current source buffer; preview the draft before navigation}}
        set reference [dict get $context reference]
        set admitted [scriptSourceTabsAdmitDocument $reference [::GX::${language}ScriptEditor::workspaceRead $reference]]
        scriptProjectCanvasReturn $w
        scriptSourceTabsOpen $ui(tabs) $reference $admitted $relative
        set line [dict get $impl line];$ui(text) mark set insert $line.0;$ui(text) see $line.0;focus $ui(text)
        ${editor}::_updateStatus
    } reason]} {set values($w,status) "Source navigation refused: $reason"}
}
