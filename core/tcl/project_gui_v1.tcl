# GX-TXT Projects GUI v1
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This is a GUI projection of Project API v1, not a second Project backend.

namespace eval ::GX {
    variable projectGuiSelectedId ""
}

proc ::GX::projectGuiSelectedId {} {
    set tree .top.nb.projects.body.left.tree
    if {![winfo exists $tree]} { return "" }
    set sel [$tree selection]
    if {[llength $sel] != 1} { return "" }
    set node [lindex $sel 0]
    if {[projectExists $node]} {return $node}
    if {[regexp {^sn:([^:]+):} $node -> project]} {return $project}
    if {[string match ex:* $node]} {return [projectMembershipField [string range $node 3 end] project_id {}]}
    return {}
}

proc ::GX::projectGuiRefresh {} {
    set f .top.nb.projects
    if {![winfo exists $f]} return
    if {$::GX::projectTransactionDepth || [file exists [_projectJournal]]} {
        projectOrganizationGuiStatus {Organization transaction pending; retaining the displayed snapshot.}
        if {![info exists ::GX::ui(projectOrganizationCommitRefresh)]} {set ::GX::ui(projectOrganizationCommitRefresh) [after 150 {unset -nocomplain ::GX::ui(projectOrganizationCommitRefresh);::GX::projectGuiRefresh}]}
        return
    }
    set tree $f.body.left.tree
    projectOrganizationGuiRefresh
    projectGuiShowSelected
}

proc ::GX::projectOrganizationGuiStatus {text} {
    if {[winfo exists .top.nb.projects.body.left.organizationStatus]} {.top.nb.projects.body.left.organizationStatus configure -text $text}
}
proc ::GX::projectOrganizationGuiRefresh {} {
    set tree .top.nb.projects.body.left.tree
    if {![winfo exists $tree]} return
    if {!$::GX::projectTransactionDepth} {projectLoadRegistry}
    set query [expr {[info exists ::GX::ui(projectOrganizationQuery)] ? $::GX::ui(projectOrganizationQuery) : {}}]
    set catalog [projectOrganizationCatalog $query];set rows [dict get $catalog rows]
    set ::GX::ui(projectOrganizationRows) $rows
    set selected [$tree selection];set y [lindex [$tree yview] 0]
    set old {};set queue [$tree children {}]
    while {[llength $queue]} {set node [lindex $queue 0];set queue [lrange $queue 1 end];lappend old $node;lappend queue {*}[$tree children $node]}
    if {![info exists ::GX::ui(projectOrganizationRenderedQuery)] || $::GX::ui(projectOrganizationRenderedQuery) eq {}} {
        foreach node $old {dict set ::GX::ui(projectOrganizationExpanded) $node [$tree item $node -open]}
    }
    # Parent-first insertion regardless of filtered query dictionary order.
    dict for {node row} $rows {projectOrganizationGuiEnsureRow $tree $node $rows}
    foreach node [lreverse $old] {if {![dict exists $rows $node] && [$tree exists $node]} {$tree delete $node}}
    if {$query eq {} && [info exists ::GX::ui(projectOrganizationExpanded)]} {dict for {node open} $::GX::ui(projectOrganizationExpanded) {if {[$tree exists $node]} {$tree item $node -open $open}}}
    set ::GX::ui(projectOrganizationRenderedQuery) $query
    if {[llength $selected]==1 && [$tree exists $selected]} {$tree selection set $selected}
    $tree yview moveto $y
    projectOrganizationGuiStatus "[dict size $rows] entries • Drag to organize, or Cut / select destination / Paste."
}
proc ::GX::projectOrganizationGuiEnsureRow {tree node rows} {
    set row [dict get $rows $node];set parent [dict get $row parent]
    if {$parent ne {} && ![$tree exists $parent]} {projectOrganizationGuiEnsureRow $tree $parent $rows}
    set kind [dict get $row kind]
    set label [dict get {project_namespace {Project group} session_namespace {Session group} project Project experiment Session} $kind]
    set values [list $label [datasetPublicationV2DictDefault $row count 0]]
    if {![$tree exists $node]} {$tree insert $parent end -id $node -text [dict get $row name] -values $values -open [expr {$kind eq {project_namespace}}]} else {
        if {[$tree parent $node] ne $parent} {$tree move $node $parent end}
        $tree item $node -text [dict get $row name] -values $values
    }
    # Tree rows are virtualized by Tk; no per-Experiment widget is constructed.
    if {[info exists ::GX::ui(projectOrganizationQuery)] && $::GX::ui(projectOrganizationQuery) ne {}} {$tree item $node -open 1}
}
proc ::GX::projectOrganizationGuiSort {{reverse 0}} {
    set tree .top.nb.projects.body.left.tree;set parents [list {}]
    foreach node [dict keys $::GX::ui(projectOrganizationRows)] {lappend parents $node}
    foreach parent $parents {
        if {$parent ne {} && ![$tree exists $parent]} continue
        set names {};foreach child [$tree children $parent] {lappend names [list [$tree item $child -text] $child]}
        set args [list -dictionary -index 0];if {$reverse} {lappend args -decreasing}
        foreach pair [lsort {*}$args $names] {$tree move [lindex $pair 1] $parent end}
    }
}
proc ::GX::projectOrganizationGuiFilter {} {
    if {[info exists ::GX::ui(projectOrganizationFilterTimer)]} {after cancel $::GX::ui(projectOrganizationFilterTimer)}
    set ::GX::ui(projectOrganizationFilterTimer) [after 120 ::GX::projectGuiRefresh]
    projectOrganizationGuiRemember
}
proc ::GX::projectOrganizationGuiCut {{node {}}} {
    set tree .top.nb.projects.body.left.tree
    if {$node eq {}} {set node [lindex [$tree selection] 0]}
    if {[catch {set capture [projectOrganizationCapture $node]} err]} {projectOrganizationGuiStatus $err;return 0}
    set ::GX::ui(projectOrganizationClipboard) $capture
    projectOrganizationGuiStatus "Move ‘[$tree item $node -text]’: select a destination and Paste, or drag to it."
    return 1
}
proc ::GX::projectOrganizationGuiPaste {{target {}}} {
    if {![info exists ::GX::ui(projectOrganizationClipboard)]} {projectOrganizationGuiStatus {Cut a Project or Experiment first.};return 0}
    set tree .top.nb.projects.body.left.tree
    if {$target eq {}} {set target [lindex [$tree selection] 0]}
    set capture $::GX::ui(projectOrganizationClipboard)
    # Consume before commit; a duplicate release/paste cannot repeat a mutation.
    unset ::GX::ui(projectOrganizationClipboard)
    if {[catch {projectOrganizationMove $capture $target} err]} {projectLoadRegistry;projectOrganizationGuiRefresh;projectOrganizationGuiStatus "Move refused: $err";return 0}
    projectGuiRefresh
    set source [dict get $capture node]
    if {[$tree exists $source]} {$tree selection set $source;$tree focus $source;$tree see $source}
    projectOrganizationGuiStatus {Organization updated. Session directories and scientific data are preserved.}
    return 1
}
proc ::GX::projectOrganizationGuiPress {x y} {
    set tree .top.nb.projects.body.left.tree;set node [$tree identify row $x $y]
    set ::GX::ui(projectOrganizationPress) [list $x $y $node]
    set ::GX::ui(projectOrganizationDragging) 0
}
proc ::GX::projectOrganizationGuiMotion {x y} {
    if {![info exists ::GX::ui(projectOrganizationPress)]} return
    set tree .top.nb.projects.body.left.tree
    lassign $::GX::ui(projectOrganizationPress) px py source
    if {!$::GX::ui(projectOrganizationDragging)} {
        if {abs($x-$px)+abs($y-$py)<8} return
        if {![projectOrganizationGuiCut $source]} return
        set ::GX::ui(projectOrganizationDragging) 1
    }
    set target [$tree identify row $x $y];set valid 0
    if {$target ne {} && [dict exists $::GX::ui(projectOrganizationRows) $target]} {
        set kind [dict get $::GX::ui(projectOrganizationRows) $target kind]
        set sourceKind [dict get $::GX::ui(projectOrganizationClipboard) kind]
        set valid [expr {($sourceKind eq {project} && $kind eq {project_namespace}) || ($sourceKind eq {experiment} && $kind in {project session_namespace})}]
        if {[info exists ::GX::ui(projectOrganizationTarget)] && $::GX::ui(projectOrganizationTarget) ne $target} {catch {$tree item $::GX::ui(projectOrganizationTarget) -tags {}}}
        $tree item $target -tags [expr {$valid ? {drop_valid} : {drop_invalid}}]
        if {![info exists ::GX::ui(projectOrganizationTarget)] || $::GX::ui(projectOrganizationTarget) ne $target} {
            if {[info exists ::GX::ui(projectOrganizationHover)]} {after cancel $::GX::ui(projectOrganizationHover)}
            set ::GX::ui(projectOrganizationHover) [after 550 [list ::GX::projectOrganizationGuiExpand $target]]
        }
        set ::GX::ui(projectOrganizationTarget) $target
        projectOrganizationGuiStatus "[expr {$valid ? {Move to} : {Invalid destination:}}] [$tree item $target -text]"
    }
    if {$y<30} {$tree yview scroll -1 units} elseif {$y>[winfo height $tree]-30} {$tree yview scroll 1 units}
    # Pointer-stationary edge scrolling remains bounded to this live drag.
    if {[info exists ::GX::ui(projectOrganizationScroll)]} {after cancel $::GX::ui(projectOrganizationScroll)}
    if {$y<30 || $y>[winfo height $tree]-30} {set ::GX::ui(projectOrganizationScroll) [after 90 [list ::GX::projectOrganizationGuiMotion $x $y]]}
}
proc ::GX::projectOrganizationGuiExpand {node} {set t .top.nb.projects.body.left.tree;if {[winfo exists $t] && [$t exists $node]} {$t item $node -open 1}}
proc ::GX::projectOrganizationGuiRelease {x y} {
    if {![info exists ::GX::ui(projectOrganizationDragging)] || !$::GX::ui(projectOrganizationDragging)} return
    set tree .top.nb.projects.body.left.tree;set target [$tree identify row $x $y]
    projectOrganizationGuiCancel 0
    projectOrganizationGuiPaste $target
}
proc ::GX::projectOrganizationGuiCancel {{clipboard 1}} {
    set tree .top.nb.projects.body.left.tree
    foreach key {Hover Scroll} {if {[info exists ::GX::ui(projectOrganization$key)]} {after cancel $::GX::ui(projectOrganization$key);unset ::GX::ui(projectOrganization$key)}}
    if {[info exists ::GX::ui(projectOrganizationTarget)]} {catch {$tree item $::GX::ui(projectOrganizationTarget) -tags {}};unset ::GX::ui(projectOrganizationTarget)}
    set ::GX::ui(projectOrganizationDragging) 0
    unset -nocomplain ::GX::ui(projectOrganizationPress)
    if {$clipboard} {unset -nocomplain ::GX::ui(projectOrganizationClipboard);projectOrganizationGuiStatus {Move cancelled.}}
}
proc ::GX::projectOrganizationGuiEdit {action} {
    set t .top.nb.projects.body.left.tree;set node [lindex [$t selection] 0]
    set parent [projectGuiSelectedId];set kind $::GX::ui(projectOrganizationKind)
    set name $::GX::ui(projectOrganizationName);set generation [projectOrganizationGeneration]
    if {$action eq {create}} {
        set command [expr {$kind eq {Project namespace} ? [list ::GX::projectNamespaceCreate $name $generation] : [list ::GX::projectSessionNamespaceCreate $parent $name $generation]}]
    } elseif {[string match pn:* $node] && $node ne {pn:}} {
        set command [list ::GX::projectNamespace[string totitle $action] [string range $node 3 end]]
        if {$action eq {rename}} {lappend command $name};lappend command $generation
    } elseif {[regexp {^sn:([^:]+):(.+)$} $node -> parent id]} {
        set command [list ::GX::projectSessionNamespace[string totitle $action] $parent $id]
        if {$action eq {rename}} {lappend command $name};lappend command $generation
    } else {projectOrganizationGuiStatus {Select a named namespace to rename or remove.};return}
    if {$action eq {delete} && [tk_messageBox -parent . -type yesno -default no -icon question -title {Remove namespace} -message {Remove this logical group? All members will remain in Ungrouped; no Project, Session or scientific content will be deleted.}] ne {yes}} return
    if {[catch {uplevel #0 $command} err]} {projectOrganizationGuiStatus $err;return}
    set ::GX::ui(projectOrganizationName) {};projectGuiRefresh;projectOrganizationGuiSort
}
proc ::GX::projectOrganizationGuiBuild {} {
    set f .top.nb.projects.body.left;set tree $f.tree
    pack forget $tree $f.sy
    set ::GX::ui(projectOrganizationQuery) {};set ::GX::ui(projectOrganizationName) {};set ::GX::ui(projectOrganizationKind) {Project namespace}
    if {![dict exists [configurationFields] ui.projects.organization]} {
        configurationRegister ui.projects.organization [dict create group General label {Project navigator state} type string default {selected {} opened {} y 0 query {}} scope user scopes {user} application on_reopen validator ::GX::projectOrganizationGuiStateValidate]
    }
    set remembered [dict get [configurationResolve ui.projects.organization] effective]
    set ::GX::ui(projectOrganizationQuery) [dict get $remembered query]
    ttk::frame $f.find
    ttk::entry $f.find.query -textvariable ::GX::ui(projectOrganizationQuery)
    ttk::button $f.find.clear -text Reset -command {set ::GX::ui(projectOrganizationQuery) {};::GX::projectGuiRefresh}
    pack $f.find.clear -side right;pack $f.find.query -fill x -expand 1
    pack $f.find -side top -fill x
    ttk::frame $f.tools
    foreach {id label command} {cut Cut ::GX::projectOrganizationGuiCut paste Paste ::GX::projectOrganizationGuiPaste cancel Cancel ::GX::projectOrganizationGuiCancel sort {Sort A–Z} ::GX::projectOrganizationGuiSort collapse {Collapse all} ::GX::projectOrganizationGuiCollapse} {
        ttk::button $f.tools.$id -text $label -command $command;pack $f.tools.$id -side left
    }
    pack $f.tools -side top -fill x
    uiMenuRowAttach $f.tools [pack slaves $f.tools]
    ttk::labelframe $f.editor -text {Logical namespace}
    ttk::combobox $f.editor.kind -state readonly -values {{Project namespace} {Session namespace}} -textvariable ::GX::ui(projectOrganizationKind) -width 19
    ttk::entry $f.editor.name -textvariable ::GX::ui(projectOrganizationName)
    pack $f.editor.kind $f.editor.name -side top -fill x
    ttk::frame $f.editor.actions
    foreach {action label} {create Create rename Rename delete Remove} {ttk::button $f.editor.actions.$action -text $label -command [list ::GX::projectOrganizationGuiEdit $action];pack $f.editor.actions.$action -side left}
    pack $f.editor.actions -fill x;pack $f.editor -side bottom -fill x
    ttk::label $f.organizationStatus -text {} -wraplength 330 -justify left
    pack $f.organizationStatus -side bottom -fill x
    pack $f.sy -side right -fill y;pack $tree -fill both -expand 1
    $tree configure -show {tree headings}
    $tree heading #0 -text {Projects / Sessions};$tree column #0 -width 260 -minwidth 150
    $tree heading name -text Kind;$tree column name -width 105 -stretch 0
    $tree heading updated -text Count;$tree column updated -width 45 -minwidth 40 -stretch 0
    $tree tag configure drop_valid -background #b7e7c0;$tree tag configure drop_invalid -background #f2c7c7
    bind $f.find.query <KeyRelease> ::GX::projectOrganizationGuiFilter
    bind $tree <Control-x> {::GX::projectOrganizationGuiCut;break}
    bind $tree <Control-v> {::GX::projectOrganizationGuiPaste;break}
    bind $tree <Escape> {::GX::projectOrganizationGuiCancel;break}
    bind $tree <ButtonPress-1> {+::GX::projectOrganizationGuiPress %x %y}
    bind $tree <B1-Motion> {::GX::projectOrganizationGuiMotion %x %y;break}
    bind $tree <ButtonRelease-1> {+::GX::projectOrganizationGuiRelease %x %y}
    bind $tree <Double-1> {::GX::projectOrganizationGuiOpen;break}
    bind $tree <Return> {::GX::projectOrganizationGuiOpen;break}
    bind $tree <<TreeviewOpen>> ::GX::projectOrganizationGuiRemember
    bind $tree <<TreeviewClose>> ::GX::projectOrganizationGuiRemember
    $tree configure -yscrollcommand [list ::GX::projectOrganizationGuiScrolled $f.sy]
    menu $f.context -tearoff 0
    foreach {label command} {Cut ::GX::projectOrganizationGuiCut {Paste here} ::GX::projectOrganizationGuiPaste Open ::GX::projectOrganizationGuiOpen Cancel ::GX::projectOrganizationGuiCancel} {$f.context add command -label $label -command $command}
    bind $tree <Button-3> [list ::GX::uiMenuPopup $f.context %X %Y]
    $f.context add command -label {Identity / breadcrumb} -command ::GX::projectOrganizationGuiIdentity
    bind $f.organizationStatus <Configure> [list ::GX::projectOrganizationGuiStatusWidth %w]
    after idle [list ::GX::projectOrganizationGuiRestore $remembered]
}
proc ::GX::projectOrganizationGuiStateValidate {value} {
    if {[catch {dict size $value}] || [lsort [dict keys $value]] ne [lsort {selected opened y query}] || [llength [dict get $value opened]]>10000 || [string length [dict get $value query]]>500} {error {Invalid Project navigator preferences.}}
    set y [dict get $value y];if {![string is double -strict $y] || $y<0 || $y>1} {error {Invalid Project scroll preference.}}
    return $value
}
proc ::GX::projectOrganizationGuiRestore {state} {
    set tree .top.nb.projects.body.left.tree;if {![winfo exists $tree]} return
    dict for {node row} $::GX::ui(projectOrganizationRows) {$tree item $node -open 0}
    foreach node [dict get $state opened] {if {[$tree exists $node]} {$tree item $node -open 1}}
    set node [dict get $state selected]
    if {$node ne {} && [$tree exists $node]} {$tree selection set $node;$tree focus $node;projectGuiShowSelected}
    $tree yview moveto [dict get $state y]
}
proc ::GX::projectOrganizationGuiScrolled {scroll first last} {
    if {[winfo exists $scroll]} {$scroll set $first $last}
    projectOrganizationGuiRemember
}
proc ::GX::projectOrganizationGuiRemember {} {
    if {[info exists ::GX::ui(projectOrganizationRememberTimer)]} {after cancel $::GX::ui(projectOrganizationRememberTimer)}
    set ::GX::ui(projectOrganizationRememberTimer) [after 500 ::GX::projectOrganizationGuiSaveState]
}
proc ::GX::projectOrganizationGuiSaveState {} {
    set tree .top.nb.projects.body.left.tree
    if {![winfo exists $tree] || ![info exists ::GX::ui(projectOrganizationRows)]} return
    set opened {}
    if {$::GX::ui(projectOrganizationQuery) eq {}} {
        dict for {node row} $::GX::ui(projectOrganizationRows) {if {[$tree exists $node] && [$tree item $node -open]} {lappend opened $node}}
    } else {
        if {[info exists ::GX::ui(projectOrganizationExpanded)]} {dict for {node open} $::GX::ui(projectOrganizationExpanded) {if {$open} {lappend opened $node}}}
    }
    set value [dict create selected [lindex [$tree selection] 0] opened $opened y [lindex [$tree yview] 0] query $::GX::ui(projectOrganizationQuery)]
    if {$value ne [dict get [configurationResolve ui.projects.organization] effective]} {configurationCommit [list [dict create id ui.projects.organization scope user value $value]]}
}
proc ::GX::projectOrganizationGuiStatusWidth {width} {set w .top.nb.projects.body.left.organizationStatus;if {[winfo exists $w]} {$w configure -wraplength [expr {max(120,$width-8)}]}}
proc ::GX::projectOrganizationGuiIdentity {} {
    set t .top.nb.projects.body.left.tree;set node [lindex [$t selection] 0]
    if {$node ne {}} {projectOrganizationGuiStatus "[$t item $node -text]\nStable identity: $node"}
}
proc ::GX::projectOrganizationGuiSelection {} {
    set tree .top.nb.projects.body.left.tree;set node [lindex [$tree selection] 0]
    if {$node eq {} || ![info exists ::GX::ui(projectOrganizationRows)] || ![dict exists $::GX::ui(projectOrganizationRows) $node]} return
    set row [dict get $::GX::ui(projectOrganizationRows) $node];set path {};set p $node
    while {$p ne {}} {set item [dict get $::GX::ui(projectOrganizationRows) $p];set path [linsert $path 0 [dict get $item name]];set p [dict get $item parent]}
    if {[dict get $row kind] in {project_namespace session_namespace}} {set ::GX::ui(projectOrganizationName) [dict get $row name]}
    projectOrganizationGuiStatus [join $path { › }]
    if {[dict get $row kind] eq {experiment}} {
        set ::GX::projectGuiExperiment [dict get $row id]
        projectGuiOrganizationSummary [dict get $row id]
    }
    projectOrganizationGuiRemember
}
proc ::GX::projectOrganizationGuiMoveExperiment {eid} {
    set ::GX::ui(projectOrganizationQuery) {};projectOrganizationGuiRefresh
    if {[projectOrganizationGuiCut ex:$eid]} {focus .top.nb.projects.body.left.find.query}
}
proc ::GX::projectOrganizationGuiCollapse {} {set t .top.nb.projects.body.left.tree;foreach node [dict keys $::GX::ui(projectOrganizationRows)] {if {[$t exists $node]} {$t item $node -open 0}}}
proc ::GX::projectOrganizationGuiOpen {} {
    set t .top.nb.projects.body.left.tree;set node [lindex [$t selection] 0]
    if {[string match ex:* $node]} {projectGuiRowAction [string range $node 3 end] open} elseif {$node ne {}} {$t item $node -open [expr {![$t item $node -open]}]}
}

proc ::GX::projectGuiShowSelected {} {
    set f .top.nb.projects
    if {![winfo exists $f]} return
    set id [projectGuiSelectedId]
    foreach field {name id description tags created_at updated_at} {
        set w "$f.body.right.value_$field"
        if {[winfo exists $w]} { $w configure -text "" }
    }
    $f.body.right.experiments delete [$f.body.right.experiments children {}]
    if {$id eq "" || ![projectExists $id]} {
        $f.body.right.status configure -text "Select a Project to view its metadata and Experiments."
        return
    }
    set d [projectGet $id]
    foreach field {name id description tags created_at updated_at} {
        $f.body.right.value_$field configure -text [dict get $d $field]
    }
    set n 0
    foreach exp [projectListExperiments $id] {
        incr n
        $f.body.right.experiments insert {} end -id "exp:$n" -values [list [dict get $exp experiment_name] [dict get $exp session_path] [dict get $exp experiment_id]]
    }
    $f.body.right.status configure -text "$n Experiment(s) associated with this Project."
}

proc ::GX::projectGuiEditSelected {} {
    set id [projectGuiSelectedId]
    if {$id eq ""} return
    projectMetadataDialog edit $id
}

proc ::GX::projectGuiAssociateSelected {} {
    set id [projectGuiSelectedId]
    if {$id eq ""} return
    if {[catch {projectAssociateCurrentExperiment $id} err]} {
        tk_messageBox -icon error -title "Projects" -message $err
        return
    }
    projectGuiRefresh
}

proc ::GX::projectGuiNewSession {} {
    set id [projectGuiSelectedId]
    if {$id eq ""} {
        tk_messageBox -icon info -title "Projects" -message "Select a Project first."
        return
    }
    newSessionDialog $id
    catch {projectGuiRefresh}
}

proc ::GX::projectGuiOpenExperiment {} {
    set f .top.nb.projects
    set sel [$f.body.right.experiments selection]
    if {[llength $sel] != 1} return
    set values [$f.body.right.experiments item [lindex $sel 0] -values]
    set path [lindex $values 1]
    if {$path eq "" || ![file isdirectory $path]} {
        tk_messageBox -icon error -title "Projects" -message "The recorded Session path is not available:\n$path"
        return
    }
    if {[catch {openSessionPath $path} err]} { tk_messageBox -icon error -title "Projects" -message $err; return }
    projectGuiRefresh
}

proc ::GX::projectGuiDetachExperiment {} {
    set f .top.nb.projects
    set sel [$f.body.right.experiments selection]
    if {[llength $sel] != 1} return
    set values [$f.body.right.experiments item [lindex $sel 0] -values]
    set eid [lindex $values 2]
    if {[tk_messageBox -icon question -type yesno -title "Detach Experiment" -message "Detach this Experiment from the selected Project?\n\nNo Session or scientific data will be deleted."] ne "yes"} return
    if {[info exists ::GX::cfg(experiment_id)] && $::GX::cfg(experiment_id) eq $eid} {
        projectDetachCurrentExperiment
    } else {
        projectDetachExperiment $eid
    }
    projectGuiRefresh
}

proc ::GX::projectGuiBuild {} {
    set f .top.nb.projects
    if {![winfo exists $f]} return
    destroyChildren $f
    grid rowconfigure $f 1 -weight 1
    grid columnconfigure $f 0 -weight 1
    ttk::frame $f.toolbar
    ttk::button $f.toolbar.new -text "Create" -command {::GX::projectMetadataDialog new}
    ttk::button $f.toolbar.edit -text "Edit" -command ::GX::projectGuiEditSelected
    ttk::button $f.toolbar.delete -text "Delete Project..." -command ::GX::resourceLifecycleProjectDeleteSelected
    ttk::button $f.toolbar.select -text "Move open Session here" -command ::GX::projectGuiAssociateSelected
    ttk::button $f.toolbar.newSession -text "New Session in Project..." -command ::GX::projectGuiNewSession
    ttk::button $f.toolbar.refresh -text "Refresh" -command ::GX::projectGuiRefresh
    pack $f.toolbar.new $f.toolbar.edit $f.toolbar.delete $f.toolbar.select $f.toolbar.newSession $f.toolbar.refresh -side left -padx 3 -pady 4
    grid $f.toolbar -row 0 -column 0 -sticky ew -padx 5 -pady 4

    ttk::panedwindow $f.body -orient horizontal
    grid $f.body -row 1 -column 0 -sticky nsew -padx 5 -pady 5
    ttk::frame $f.body.left
    ttk::frame $f.body.right
    $f.body add $f.body.left -weight 1
    $f.body add $f.body.right -weight 2

    ttk::treeview $f.body.left.tree -columns {name updated} -show headings -selectmode browse
    $f.body.left.tree heading name -text "Project"
    $f.body.left.tree heading updated -text "Updated"
    $f.body.left.tree column name -width 260 -stretch 1
    $f.body.left.tree column updated -width 180 -stretch 0
    ttk::scrollbar $f.body.left.sy -orient vertical -command [list $f.body.left.tree yview]
    $f.body.left.tree configure -yscrollcommand [list $f.body.left.sy set]
    pack $f.body.left.sy -side right -fill y
    pack $f.body.left.tree -side left -fill both -expand 1
    bind $f.body.left.tree <<TreeviewSelect>> ::GX::projectGuiShowSelected

    grid columnconfigure $f.body.right 1 -weight 1
    set r 0
    foreach {field label} {name Name id {Project ID} description {Description / notes} notes Notes tags {Tags / keywords} author Author storage_path {Storage path} created_at Created updated_at Updated} {
        ttk::label $f.body.right.label_$field -text "$label:"
        ttk::label $f.body.right.value_$field -anchor w -justify left -wraplength 650
        grid $f.body.right.label_$field -row $r -column 0 -sticky ne -padx 5 -pady 3
        grid $f.body.right.value_$field -row $r -column 1 -sticky ew -padx 5 -pady 3
        incr r
    }
    ttk::label $f.body.right.expLabel -text "Experiments:"
    grid $f.body.right.expLabel -row $r -column 0 -sticky nw -padx 5 -pady 4
    ttk::treeview $f.body.right.experiments -columns {name path id} -show headings -height 10 -selectmode browse
    foreach {col label width stretch} {name Experiment 180 0 path {Session path} 360 1 id {Experiment ID} 240 0} {
        $f.body.right.experiments heading $col -text $label
        $f.body.right.experiments column $col -width $width -stretch $stretch
    }
    grid $f.body.right.experiments -row $r -column 1 -sticky nsew -padx 5 -pady 4
    grid rowconfigure $f.body.right $r -weight 1
    incr r
    ttk::frame $f.body.right.actions
    ttk::button $f.body.right.actions.open -text "Open Experiment Session" -command ::GX::projectGuiOpenExperiment
    ttk::button $f.body.right.actions.detach -text "Detach Experiment" -command ::GX::projectGuiDetachExperiment
    pack $f.body.right.actions.open $f.body.right.actions.detach -side left -padx 3
    grid $f.body.right.actions -row $r -column 1 -sticky w -padx 5 -pady 3
    incr r
    ttk::label $f.body.right.status -text "" -anchor w
    grid $f.body.right.status -row $r -column 0 -columnspan 2 -sticky ew -padx 5 -pady 3
    bind $f.body.right.experiments <Double-1> ::GX::projectGuiOpenExperiment
    projectGuiRefresh
}

# Project dialogs can also be opened from Experiment; refresh the Projects tab
# after a committed change so both views remain projections of one API state.
proc ::GX::projectMetadataDialogCommit {w mode id} {
    ::GX::projectMetadataDialogCommit_before_projects_gui_v1 $w $mode $id
    catch {projectGuiRefresh}
}

proc ::GX::projectRefreshExperimentUi {} {
    ::GX::projectRefreshExperimentUi_before_projects_gui_v1
    catch {projectGuiRefresh}
}

proc ::GX::launchGui_before_graph_selection {} {
    ::GX::launchGui_before_projects_gui_v1
    projectGuiBuild
}
