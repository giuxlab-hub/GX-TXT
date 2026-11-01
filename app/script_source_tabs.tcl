# SPDX-License-Identifier: GPL-3.0-or-later
# One file-aware controller for Python/Octave; source editing stays in Source Surface.
namespace eval ::GX::ScriptSourceTabs {variable state;variable serial 0}
proc ::GX::scriptSourceTabsCreate {p editor language} {
    variable ::GX::ScriptSourceTabs::state
    ttk::frame $p
    ttk::panedwindow $p.body -orient horizontal
    ttk::frame $p.body.tree -width 135
    pack propagate $p.body.tree 0
    ttk::treeview $p.body.tree.files -show tree -selectmode browse -height 6
    $p.body.tree.files column #0 -width 135 -minwidth 70 -stretch 0
    ttk::scrollbar $p.body.tree.scroll -command [list $p.body.tree.files yview]
    ttk::scrollbar $p.body.tree.horizontal -orient horizontal -command [list $p.body.tree.files xview]
    $p.body.tree.files configure -yscrollcommand [list $p.body.tree.scroll set] -xscrollcommand [list $p.body.tree.horizontal set]
    pack $p.body.tree.horizontal -side bottom -fill x
    pack $p.body.tree.scroll -side right -fill y
    pack $p.body.tree.files -side left -fill both -expand 1
    ttk::frame $p.body.source
    $p.body add $p.body.source -weight 4
    scriptSourceTabsStyle
    ttk::notebook $p.book -height 280 -style GXSource.TNotebook
    ttk::menubutton $p.overflow -text {…} -width 0 -menu $p.overflow.menu -takefocus 1
    menu $p.overflow.menu -tearoff 0 -postcommand [list ::GX::scriptSourceTabsOverflowMenu $p]
    pack $p.book -in $p.body.source -side top -fill both -expand 1
    pack $p.body -side top -fill both -expand 1
    set state($p,editor) $editor;set state($p,language) $language;set state($p,active) {};set state($p,switching) 0
    bind $p.book <<NotebookTabChanged>> [list ::GX::scriptSourceTabsSelected $p]
    bind $p.book <ButtonPress-1> "if {\[[list ::GX::scriptSourceTabsPress $p %x %y]\]} {break}"
    bind $p.book <ButtonRelease-1> "if {\[[list ::GX::scriptSourceTabsRelease $p %x %y]\]} {break}"
    bind $p.book <Motion> [list ::GX::scriptSourceTabsHover $p %x %y]
    bind $p.book <Leave> [list $p.book configure -cursor {}]
    bind $p.book <Configure> [list ::GX::scriptSourceTabsLayoutSchedule $p]
    bind $p.book <Alt-Down> "[list ::GX::scriptSourceTabsOverflowPopup $p];break"
    bind $p.body.tree.files <<TreeviewSelect>> [list ::GX::scriptSourceTabsTreeSelected $p]
    bind $p.body <Configure> [list ::GX::scriptSourceTabsTreeWidth $p]
    bind $p <Destroy> [list ::GX::scriptSourceTabsDestroy $p %W]
    bind [winfo toplevel $p] <Control-Tab> "[list ::GX::scriptSourceTabsCycle $p 1];break"
    bind [winfo toplevel $p] <Control-Shift-Tab> "[list ::GX::scriptSourceTabsCycle $p -1];break"
    bind [winfo toplevel $p] <Control-ISO_Left_Tab> "[list ::GX::scriptSourceTabsCycle $p -1];break"
    bind [winfo toplevel $p] <Control-w> "[list ::GX::scriptSourceTabsClose $p];break"
    bind [winfo toplevel $p] <Control-Shift-S> "[list ::GX::scriptSourceTabsAction $p save];break"
    return $p
}
proc ::GX::scriptSourceTabsStyle {} {
    # A native ttk tab element supplies a separate hit target, independent of
    # the tab label and its qualified source identity. Rebuild for font/theme.
    set size [expr {max(18,[font metrics TkDefaultFont -linespace])}]
    set theme [ttk::style theme use]
    variable ::GX::ScriptSourceTabs::styleKey
    if {[info exists styleKey] && $styleKey eq [list $theme $size]} {return $size}
    set styleKey [list $theme $size]
    set element GXSourceClose${size}
    set image gxSourceClose${size}
    if {$image ni [image names]} {
        image create photo $image -width $size -height $size
        set lo [expr {int($size*.32)}];set hi [expr {$size-$lo-1}]
        for {set i $lo} {$i<=$hi} {incr i} {
            foreach x [list $i [expr {$size-1-$i}]] {
                $image put #555555 -to $x $i [expr {$x+2}] [expr {$i+2}]
            }
        }
    }
    if {$element ni [ttk::style element names]} {ttk::style element create $element image $image -sticky {}}
    ttk::style layout GXSource.TNotebook.Tab [list Notebook.tab -sticky nswe -children [list Notebook.padding -side top -sticky nswe -children [list Notebook.focus -side top -sticky nswe -children [list Notebook.label -side left -sticky {} $element -side right -sticky {}]]]]
    ttk::style configure GXSource.TNotebook.Tab -padding {8 4}
    ttk::style configure GXSource.TNotebook.Tab -font TkDefaultFont
    return $size
}
proc ::GX::scriptSourceTabsHit {p x y} {
    if {![string match GXSourceClose* [$p.book identify $x $y]]} {return {}}
    if {[catch {$p.book index @$x,$y} index]} {return {}}
    return [lindex [$p.book tabs] $index]
}
proc ::GX::scriptSourceTabsPress {p x y} {
    variable ::GX::ScriptSourceTabs::state
    set state($p,pressed) [scriptSourceTabsHit $p $x $y]
    return [expr {$state($p,pressed) ne {}}]
}
proc ::GX::scriptSourceTabsRelease {p x y} {
    variable ::GX::ScriptSourceTabs::state
    if {![info exists state($p,pressed)] || $state($p,pressed) eq {}} {return 0}
    set tab $state($p,pressed);set state($p,pressed) {}
    if {$tab eq [scriptSourceTabsHit $p $x $y]} {scriptSourceTabsClose $p 0 $tab}
    return 1
}
proc ::GX::scriptSourceTabsHover {p x y} {
    $p.book configure -cursor [expr {[scriptSourceTabsHit $p $x $y] eq {} ? {} : {hand2}}]
}
proc ::GX::scriptSourceTabsLayoutSchedule {p} {
    variable ::GX::ScriptSourceTabs::state
    if {![info exists state($p,layoutPending)]} {
        set state($p,layoutPending) [after idle [list ::GX::scriptSourceTabsLayout $p]]
    }
}
proc ::GX::scriptSourceTabsLayout {p} {
    variable ::GX::ScriptSourceTabs::state
    unset -nocomplain state($p,layoutPending)
    if {![winfo exists $p.book]} return
    set icon [scriptSourceTabsStyle]
    set tabs [$p.book tabs];set total 0;set widths {}
    set available [expr {max(1,[winfo width $p.book]-8)}]
    foreach tab $tabs {
        set label $state($p,$tab,label)
        # Keep the close target reachable even for exceptionally long paths.
        # The overflow menu retains the full qualified identity.
        set limit [expr {max(25,$available-$icon-48-[winfo reqwidth $p.overflow])}]
        set short $label
        while {[string length $short]>1 && [font measure TkDefaultFont $short]>$limit} {set short [string range $short 0 end-1]}
        if {$short ne $label} {set short "[string trimright [string range $short 0 end-1]]…"}
        if {[$p.book tab $tab -text] ne $short} {$p.book tab $tab -text $short}
        set width [expr {[font measure TkDefaultFont $short]+$icon+40}]
        dict set widths $tab $width;incr total $width
    }
    set visible $tabs
    if {$total>$available && [llength $tabs]>1} {
        set available [expr {max(1,$available-[winfo reqwidth $p.overflow]-8)}]
        set active [$p.book select]
        # Closing the last visible overflow tab can briefly leave no selection.
        # Navigation owns the replacement; geometry must not index an empty key.
        if {![dict exists $widths $active]} {place forget $p.overflow;return}
        set at [lsearch -exact $tabs $active]
        set visible [list $active];set used [dict get $widths $active]
        for {set i [expr {$at-1}]} {$i>=0} {incr i -1} {
            set tab [lindex $tabs $i]
            if {$used+[dict get $widths $tab]>$available} break
            incr used [dict get $widths $tab]
            set visible [linsert $visible 0 $tab]
        }
        for {set i [expr {$at+1}]} {$i<[llength $tabs]} {incr i} {
            set tab [lindex $tabs $i]
            if {$used+[dict get $widths $tab]>$available} break
            incr used [dict get $widths $tab]
            lappend visible $tab
        }
        place $p.overflow -in $p.body.source -relx 1 -x -3 -y 2 -anchor ne
        raise $p.overflow
    } else {place forget $p.overflow}
    foreach tab $tabs {
        set desired [expr {$tab in $visible ? {normal} : {hidden}}]
        if {[$p.book tab $tab -state] ne $desired} {$p.book tab $tab -state $desired}
    }
}
proc ::GX::scriptSourceTabsOverflowMenu {p} {
    variable ::GX::ScriptSourceTabs::state
    $p.overflow.menu delete 0 end
    foreach tab [$p.book tabs] {
        $p.overflow.menu add command -label "$state($p,$tab,reference) / $state($p,$tab,label)" -command [list ::GX::scriptSourceTabsNavigate $p $tab]
    }
}
proc ::GX::scriptSourceTabsOverflowPopup {p} {
    scriptSourceTabsOverflowMenu $p
    tk_popup $p.overflow.menu [winfo rootx $p.book] [winfo rooty $p.book]
}
proc ::GX::scriptSourceTabsNavigate {p tab} {
    $p.book tab $tab -state normal
    $p.book select $tab
    scriptSourceTabsSelected $p
}
proc ::GX::scriptSourceTabsProjectMenu {menu editor} {
    foreach {label action} {{Open project file…} files {New file…} new {Rename/move file…} rename {Remove file} remove {Set entrypoint} entry} {
        $menu add command -label $label -command [list ::GX::scriptSourceTabsEditorAction $editor $action]
    }
}
proc ::GX::scriptSourceTabsMenusAttach {w} {
    # Tk's legacy F10 discovery omits themed menubuttons on X11. Keep the
    # existing primary row keyboard-accessible without a second menu system.
    set groups {file edit project view run help}
    bind $w <F10> "focus $w.toolbar.file;break"
    foreach key $groups {
        set button $w.toolbar.$key
        set index [lsearch -exact $groups $key]
        foreach {event delta} {Left -1 Right 1} {
            set next [lindex $groups [expr {($index+$delta+6)%6}]]
            bind $button <$event> "focus $w.toolbar.$next;break"
            bind $button.menu <$event> "if {\[[list ::GX::scriptSourceTabsMenuMove $w $key $delta]\]} {break}"
        }
        foreach event {Down Return} {bind $button <$event> "event generate $button <<Invoke>>;break"}
        bind $button <Escape> "[list ::GX::scriptSourceTabsFocusActive $w.p.center.edit];break"
        set letter [string index $key 0]
        bind $w <Alt-$letter> "focus $button;event generate $button <<Invoke>>;break"
    }
}
proc ::GX::scriptSourceTabsFocusActive {p} {
    set note [scriptSourceNotesMenuHandle $p]
    if {$note ne {}} {
        focus [dict get [_documentEditorRecord $note] source]
    } else {
        focus [dict get [scriptSourceTabsIdentity $p] source_widget]
    }
}
proc ::GX::scriptSourceTabsMenuMove {w group delta} {
    set menu $w.toolbar.$group.menu
    if {$delta>0 && [$menu index active] ne {none} && [$menu type active] eq {cascade}} {
        # The physical binding masks Tk's virtual class binding even without
        # break. Delegate explicitly so Tk posts AND focuses the native child.
        event generate $menu <<NextChar>>
        return 1
    }
    set groups {file edit project view run help}
    set next [lindex $groups [expr {([lsearch -exact $groups $group]+$delta+6)%6}]]
    # Let the native Menu class restore its own grab/focus before posting the
    # adjacent themed button through its ordinary native Invoke binding.
    event generate $menu <Escape>
    focus $w.toolbar.$next
    event generate $w.toolbar.$next <<Invoke>>
    return 1
}
proc ::GX::scriptSourceTabsEditorAction {editor action} {
    upvar #0 ${editor}::ui ui
    return [scriptSourceTabsAction $ui(tabs) $action]
}
proc ::GX::scriptSourceTabsMenuState {p group menu} {
    set project [expr {[dict get [scriptSourceTabsCurrent $p] kind] eq {project}}]
    set writable [scriptSourceTabsWritable $p]
    if {$group eq {project}} {
        $menu entryconfigure {Open project file…} -state [expr {$project ? {normal} : {disabled}}]
        foreach label {{New file…} {Rename/move file…} {Remove file} {Set entrypoint}} {$menu entryconfigure $label -state [expr {$project && $writable ? {normal} : {disabled}}]}
    } elseif {$group eq {file}} {
        $menu entryconfigure Save -state [expr {$writable ? {normal} : {disabled}}]
        set any 0
        variable ::GX::ScriptSourceTabs::state
        foreach tab [scriptSourceTabsPages $p] {if {[datasetPublicationV2DictDefault $state($p,$tab,document) mode editable] eq {editable}} {set any 1}}
        $menu entryconfigure {Save All} -state [expr {$any ? {normal} : {disabled}}]
    }
}
proc ::GX::scriptSourceTabsDestroy {p actual} {
    if {$p ne $actual} return
    variable ::GX::ScriptSourceTabs::state
    if {[info exists state($p,layoutPending)]} {after cancel $state($p,layoutPending)}
    foreach key [array names state "$p,*"] {unset state($key)}
}
proc ::GX::scriptSourceTabsCapture {p} {
    variable ::GX::ScriptSourceTabs::state
    if {$state($p,switching) || $state($p,active) eq {}} return
    set tab $state($p,active)
    upvar #0 $state($p,editor)::ui ui
    set fields {}
    foreach key {currentId currentSha revision scope scriptId name version requiredApis description arguments parameterDefinitions sessionToken baseline modified importDraft find} {
        if {[info exists ui($key)]} {dict set fields $key $ui($key)}
    }
    dict set fields parameterText [$ui(parameters) get 1.0 end-1c]
    set state($p,$tab,fields) $fields
    scriptSourceTabsLabels $p
}
# These are transient editor projections, not new Registry metadata. Untagged
# public reads are rechecked before capturing the actual current owner; tagged
# Tree/Debug documents retain their admitted originating context.
proc ::GX::scriptSourceTabsAdmitDocument {reference document} {
    if {![regexp {^(user|session):(.+)$} $reference -> scope id]} {return $document}
    if {[dict exists $document _editor_origin]} {
        if {[dict get $document _editor_origin] eq {} || ($scope eq {session} && ![dict exists $document _editor_session_token])} {error {Source document has incomplete originating context}}
        return $document
    }
    set token [scriptWorkspaceSessionToken]
    set owner [file normalize [scriptRegistryPath $scope $id]]
    set actual [scriptRegistryDescribe $reference]
    set fields {scope id language kind sha256 revision source_path}
    if {[dict get $actual kind] eq {project}} {lappend fields project_manifest project_root project_sha256 entrypoint}
    foreach key $fields {
        if {![dict exists $document $key] || [dict get $document $key] ne [dict get $actual $key]} {error {Source owner or revision changed while opening; review and reopen the intended source}}
    }
    if {$owner ne [file normalize [scriptRegistryPath $scope $id]] || ($scope eq {session} && $token ne [scriptWorkspaceSessionToken])} {error {Source authority changed while opening; review and reopen}}
    dict set document _editor_origin $owner
    if {$scope eq {session}} {dict set document _editor_session_token $token}
    return $document
}
proc ::GX::scriptSourceTabsDocumentKey {reference document} {
    if {![regexp {^(user|session):} $reference -> scope]} {return [list $reference {} {}]}
    set token [expr {$scope eq {session}?[dict get $document _editor_session_token]:{}}]
    return [list $reference [dict get $document _editor_origin] $token]
}
proc ::GX::scriptSourceTabsGroupKey {p {tab {}}} {
    variable ::GX::ScriptSourceTabs::state
    if {$tab eq {}} {set tab $state($p,active)}
    if {[info exists state($p,$tab,note_source)]} {set tab $state($p,$tab,note_source)}
    return [scriptSourceTabsDocumentKey $state($p,$tab,reference) $state($p,$tab,document)]
}
proc ::GX::scriptSourceTabsOwnerCurrent {p {tab {}}} {
    variable ::GX::ScriptSourceTabs::state
    if {$tab eq {}} {set tab $state($p,active)}
    if {[info exists state($p,$tab,note_source)]} {set tab $state($p,$tab,note_source)}
    set reference $state($p,$tab,reference)
    if {![regexp {^(user|session):(.+)$} $reference -> scope id]} {return 1}
    set doc $state($p,$tab,document)
    if {![dict exists $doc _editor_origin] || [catch {set current [file normalize [scriptRegistryPath $scope $id]]}]} {return 0}
    if {$current ne [dict get $doc _editor_origin]} {return 0}
    if {$scope eq {session} && ([dict get $doc _editor_session_token] ne [scriptWorkspaceSessionToken])} {return 0}
    return 1
}
proc ::GX::scriptSourceTabsRequireOwner {p {tab {}}} {
    if {[scriptSourceTabsOwnerCurrent $p $tab]} {return 1}
    tk_messageBox -parent [winfo toplevel $p] -icon error -title {Source owner changed} -message {This source belongs to a different Session or User Registry. Its local source and Notes drafts are retained. Return to its intended owner context and reopen before saving, copying, deleting or running. Visible code can still be copied or exported.}
    return 0
}
proc ::GX::scriptSourceTabsOpen {p reference document {relative {}}} {
    variable ::GX::ScriptSourceTabs::state
    variable ::GX::ScriptSourceTabs::serial
    scriptSourceTabsCapture $p
    set document [scriptSourceTabsAdmitDocument $reference $document]
    set incomingKey [scriptSourceTabsDocumentKey $reference $document]
    upvar #0 $state($p,editor)::ui ui
    if {$reference ne {} && [info exists ui(initialDraftTab)] && $state($p,active) eq $ui(initialDraftTab)} {
        $state($p,editor)::_recomputeDirty
        if {!$ui(modified)} {
            set old $state($p,active);set state($p,active) {};destroy $old
            foreach key [array names state "$p,$old,*"] {unset state($key)}
        }
        unset ui(initialDraftTab)
    }
    set kind [dict get $document kind]
    if {$relative eq {}} {set relative [expr {$kind eq {project} ? [dict get $document entrypoint] : [file tail [dict get $document source_path]]}]}
    foreach tab [scriptSourceTabsPages $p] {
        if {$reference ne {} && [scriptSourceTabsGroupKey $p $tab] eq $incomingKey && $state($p,$tab,path) eq $relative} {
            $p.book select $tab;scriptSourceTabsSelected $p;return $state($p,$tab,text)
        }
    }
    set tab $p.book.f[incr serial]
    ttk::frame $tab
    set mode [datasetPublicationV2DictDefault $document mode editable]
    set text [sourceSurfaceCreate $tab.surface [dict create mode $mode language [string tolower $state($p,language)] change_command [list ::GX::scriptSourceTabsChanged $p $tab]]]
    # On X11 the native Text class binds Ctrl+W to cut the selection. Handle
    # the editor's close shortcut before that class can mutate a source buffer.
    bind $text <Control-w> "[list ::GX::scriptSourceTabsClose $p];break"
    pack $tab.surface -fill both -expand 1
    if {$kind eq {project}} {
        if {![dict exists $document project_files $relative]} {error {File is absent from admitted project manifest}}
        set code [dict get [scriptRegistryProjectFiles $document] $relative]
    } else {set code [dict get $document code]}
    if {$mode eq {read_only}} {$text configure -state normal}
    $text insert 1.0 $code;$text edit reset;$text edit modified 0
    if {$mode eq {read_only}} {$text configure -state disabled}
    set state($p,$tab,text) $text;set state($p,$tab,reference) [expr {$reference eq {} ? "draft:$serial" : $reference}];set state($p,$tab,path) $relative
    set state($p,$tab,document) $document;set state($p,$tab,baseline) $code
    set fields [dict create currentId $reference currentSha [dict get $document sha256] revision [dict get $document revision] scope [dict get $document scope] scriptId [dict get $document id] name [dict get $document name] version [dict get $document version] requiredApis [dict get $document explicit_apis] description [dict get $document description] arguments [dict get $document default_arguments] parameterDefinitions [dict get $document parameters] parameterText [scriptParameterDefinitionsFormat [dict get $document parameters]] sessionToken [scriptWorkspaceSessionToken] modified 0 importDraft 0 find {}]
    if {[dict exists $document _editor_session_token]} {dict set fields sessionToken [dict get $document _editor_session_token]}
    set state($p,$tab,fields) $fields
    $p.book add $tab -text $relative
    $p.book select $tab
    scriptSourceTabsSelected $p
    return $text
}
proc ::GX::scriptSourceTabsSelected {p} {
    variable ::GX::ScriptSourceTabs::state
    if {![winfo exists $p] || $state($p,switching)} return
    set selected [$p.book select];set next $selected
    set notes [expr {[info exists state($p,$next,note_source)]}]
    if {$notes} {set next $state($p,$next,note_source)}
    scriptSourceNotesFocus $p $notes
    set state($p,show_notes) [expr {$next ne {} && [info exists state($p,$next,notes)] && $state($p,$next,notes) in [$p.book tabs]}]
    if {$next eq {} || $next eq $state($p,active)} {
        if {$notes} {focus [dict get [_documentEditorRecord $state($p,$selected,note_editor)] source]
        } elseif {$next ne {} && [winfo exists $state($p,$next,text)]} {focus $state($p,$next,text)}
        return
    }
    set previous $state($p,active)
    scriptSourceTabsCapture $p
    set fields $state($p,$next,fields)
    # A project's files share metadata, while keeping independent source buffers.
    if {$previous ne {} && $state($p,$previous,reference) ne {} && [scriptSourceTabsGroupKey $p $previous] eq [scriptSourceTabsGroupKey $p $next]} {
        foreach key {name version requiredApis description arguments parameterDefinitions parameterText scope scriptId sessionToken} {dict set fields $key [dict get $state($p,$previous,fields) $key]}
    }
    set state($p,switching) 1
    upvar #0 $state($p,editor)::ui ui
    dict for {key value} $fields {if {$key ne {parameterText}} {set ui($key) $value}}
    set ui(text) $state($p,$next,text)
    set ui(lines) [winfo parent $ui(text)].lines
    set ui(vscroll) [winfo parent $ui(text)].v
    set ui(activeFile) $state($p,$next,path)
    $ui(parameters) configure -state normal
    $ui(parameters) delete 1.0 end;$ui(parameters) insert 1.0 [dict get $fields parameterText]
    $ui(parameters) edit reset;$ui(parameters) edit modified 0
    set state($p,active) $next
    set state($p,switching) 0
    if {![dict exists $fields baseline]} {
        $state($p,editor)::_acceptBaseline
        scriptSourceTabsCapture $p
    }
    sourceSurfaceDocumentIdentity $ui(text) [list $ui(currentId) $ui(currentSha) $ui(activeFile)]
    set readonly [expr {[datasetPublicationV2DictDefault $state($p,$next,document) mode editable] eq {read_only}}]
    set queue {}
    foreach name {props version requiredApis desc params args} {set widget $ui(window).p.center.$name;if {[winfo exists $widget]} {lappend queue $widget}}
    while {[llength $queue]} {
        set widget [lindex $queue 0];set queue [lrange $queue 1 end]
        lappend queue {*}[winfo children $widget]
        if {[winfo class $widget] in {TEntry TCombobox TCheckbutton}} {$widget state [expr {$readonly ? {disabled} : {!disabled}}]}
        if {[winfo class $widget] eq {Text}} {$widget configure -state [expr {$readonly ? {disabled} : {normal}}]}
    }
    $state($p,editor)::_watchProperties
    $state($p,editor)::_recomputeDirty
    $state($p,editor)::_refreshEditor
    # Registry selection must follow tabs too. Otherwise _save's queued tree
    # selection can reopen an inactive source just closed with its close icon.
    if {$ui(currentId) eq {}} {
        if {[winfo exists $ui(tree)]} {$ui(tree) selection remove [$ui(tree) selection]}
    } elseif {[winfo exists $ui(tree)] && ![$ui(tree) exists $ui(currentId)]} {
        # A source opened through its exact API/association can be newer than
        # the optional Registry projection. Never retain an unrelated selection
        # whose queued Treeview event could silently reopen another source.
        $ui(tree) selection remove [$ui(tree) selection]
    } else {$state($p,editor)::_selectTreeId $ui(currentId)}
    scriptSourceTabsLabels $p
    scriptSourceTabsTree $p
    if {$notes} {focus [dict get [_documentEditorRecord $state($p,$selected,note_editor)] source]} else {focus $ui(text)}
}
proc ::GX::scriptSourceTabsTree {p} {
    variable ::GX::ScriptSourceTabs::state
    set doc [scriptSourceTabsCurrent $p]
    if {[dict get $doc kind] ne {project} || [scriptSourceNotesActive $p]} {
        if {"$p.body.tree" in [$p.body panes]} {$p.body forget $p.body.tree}
        return
    }
    if {"$p.body.tree" ni [$p.body panes]} {$p.body insert 0 $p.body.tree -weight 1;after idle [list ::GX::scriptSourceTabsTreeWidth $p]}
    set tree $p.body.tree.files
    $tree delete [$tree children {}]
    foreach path [lsort -dictionary [dict keys [dict get $doc project_files]]] {
        set parent {};set prefix {}
        foreach part [file split [file dirname $path]] {
            if {$part eq {.}} continue
            set prefix [expr {$prefix eq {} ? $part : "$prefix/$part"}]
            set id folder:$prefix
            if {![$tree exists $id]} {$tree insert $parent end -id $id -text $part -open 1}
            set parent $id
        }
        set label [file tail $path]
        if {$path eq [dict get $doc entrypoint]} {append label { (main)}}
        $tree insert $parent end -id file:$path -text $label -values [list $path]
    }
    set selected file:$state($p,$state($p,active),path)
    if {[$tree exists $selected]} {$tree selection set $selected;$tree see $selected}
    uiFieldInspectionColumnsSchedule $tree {recursive 1}
}
proc ::GX::scriptSourceTabsTreeWidth {p} {
    variable ::GX::ScriptSourceTabs::state
    if {[winfo exists $p.body] && [llength [$p.body panes]]==2 && [winfo width $p.body]>240 && [$p.body sashpos 0]<110} {$p.body sashpos 0 [expr {min(170,max(120,[winfo width $p.body]/3))}]}
    set tree $p.body.tree.files
    if {![winfo exists $tree]} return
    set key [list [font actual TkDefaultFont] [font actual TkHeadingFont] [ttk::style theme use] [winfo width $tree]]
    if {![info exists state($p,treeLayoutKey)] || $state($p,treeLayoutKey) ne $key} {
        set state($p,treeLayoutKey) $key
        uiFieldInspectionColumnsSchedule $tree {recursive 1}
    }
}
proc ::GX::scriptSourceTabsTreeSelected {p} {
    variable ::GX::ScriptSourceTabs::state
    if {![winfo exists $p] || $state($p,switching) || $state($p,active) eq {}} return
    # Treeview events are queued; an old project selection can arrive after
    # switching to an unrelated standalone source or historical tab.
    set doc [scriptSourceTabsCurrent $p]
    if {[dict get $doc kind] ne {project} || "$p.body.tree" ni [$p.body panes]} return
    set selection [$p.body.tree.files selection]
    if {[llength $selection]!=1 || ![string match file:* [lindex $selection 0]]} return
    set path [string range [lindex $selection 0] 5 end]
    if {![dict exists $doc project_files $path]} return
    if {$path eq $state($p,$state($p,active),path)} return
    scriptSourceTabsOpen $p $state($p,$state($p,active),reference) $doc $path
}
proc ::GX::scriptSourceTabsChanged {p tab} {
    variable ::GX::ScriptSourceTabs::state
    if {![info exists state($p,$tab,text)] || $state($p,switching)} return
    scriptSourceTabsLabels $p
    if {$state($p,active) eq $tab} {$state($p,editor)::_sourceChanged}
}
proc ::GX::scriptSourceTabsLabels {p} {
    variable ::GX::ScriptSourceTabs::state
    set counts {}
    foreach tab [scriptSourceTabsPages $p] {dict incr counts $state($p,$tab,path)}
    foreach tab [scriptSourceTabsPages $p] {
        set dirty [expr {[$state($p,$tab,text) get 1.0 end-1c] ne $state($p,$tab,baseline)}]
        if {[info exists state($p,$tab,fields)] && [dict exists $state($p,$tab,fields) modified] && [dict get $state($p,$tab,fields) modified]} {set dirty 1}
        set label $state($p,$tab,path)
        if {[dict get $counts $label]>1} {
            append label " — $state($p,$tab,reference)"
            if {[regexp {^(user|session):} $state($p,$tab,reference)]} {append label " · [format %08x [zlib crc32 [encoding convertto utf-8 [scriptSourceTabsGroupKey $p $tab]]]]"}
        }
        set state($p,$tab,label) "$label[expr {$dirty ? { *} : {}}]"
        $p.book tab $tab -text $state($p,$tab,label)
    }
    scriptSourceTabsLayoutSchedule $p
}
proc ::GX::scriptSourceTabsCurrent {p} {variable ::GX::ScriptSourceTabs::state;return $state($p,$state($p,active),document)}
proc ::GX::scriptSourceTabsIdentity {p} {
    variable ::GX::ScriptSourceTabs::state
    if {![winfo exists $p] || $state($p,active) eq {}} {error {No active source tab}}
    upvar #0 $state($p,editor)::ui ui
    return [dict create reference $ui(currentId) sha256 $ui(currentSha) revision $ui(revision) relative_file $state($p,$state($p,active),path) source_widget $ui(text) source_widget_id [winfo id $ui(text)] session_token $ui(sessionToken) scope $ui(scope)]
}
proc ::GX::scriptSourceTabsWritable {p} {return [expr {[datasetPublicationV2DictDefault [scriptSourceTabsCurrent $p] mode editable] eq {editable} && [scriptSourceTabsOwnerCurrent $p]}]}
proc ::GX::scriptSourceTabsOpenSnapshot {p inspected {relative {}}} {
    variable ::GX::ScriptSourceTabs::state
    if {[dict get $inspected snapshot_validation] ne {verified} || [dict get $inspected language] ne $state($p,language)} {error {Open sources requires a verified matching-language Job snapshot}}
    set doc [dict merge [scriptRegistryDefaults] [dict create scope snapshot id [dict get $inspected id] name [dict get $inspected script_name] language [dict get $inspected language] version [dict get $inspected script_version] revision [dict get $inspected script_revision] sha256 [dict get $inspected source_sha256] mode read_only]]
    if {[dict exists $inspected project_manifest]} {
        set verified [scriptProjectVerify [file dirname [dict get $inspected project_manifest]]]
        if {[dict get $verified project_sha256] ne [dict get $doc sha256]} {error {Historical project source changed}}
        set doc [dict merge $doc $verified [dict create kind project]]
    } else {
        set source [dict get $inspected snapshot]
        if {[scriptRegistryHash $source] ne [dict get $doc sha256]} {error {Historical source changed}}
        set ch [::open $source rb];try {set code [scriptWorkspaceDecodeUtf8 [read $ch]]} finally {close $ch}
        dict set doc source_path $source;dict set doc code $code
    }
    return [scriptSourceTabsOpen $p snapshot:[dict get $inspected id] $doc $relative]
}
proc ::GX::scriptSourceTabsDirty {p} {
    variable ::GX::ScriptSourceTabs::state
    if {$state($p,active) eq {}} {return 0}
    set group [scriptSourceTabsGroupKey $p]
    foreach tab [scriptSourceTabsPages $p] {
        if {[scriptSourceTabsGroupKey $p $tab] eq $group && [$state($p,$tab,text) get 1.0 end-1c] ne $state($p,$tab,baseline)} {return 1}
    }
    return 0
}
proc ::GX::scriptSourceTabsFiles {p} {
    variable ::GX::ScriptSourceTabs::state
    set doc [scriptSourceTabsCurrent $p]
    set files [scriptRegistryProjectFiles $doc]
    set group [scriptSourceTabsGroupKey $p]
    foreach tab [scriptSourceTabsPages $p] {if {[scriptSourceTabsGroupKey $p $tab] eq $group} {dict set files $state($p,$tab,path) [$state($p,$tab,text) get 1.0 end-1c]}}
    return $files
}
proc ::GX::scriptSourceTabsSaved {p result} {
    variable ::GX::ScriptSourceTabs::state
    upvar #0 $state($p,editor)::ui ui
    set group [scriptSourceTabsGroupKey $p]
    set newRef "[dict get $result scope]:[dict get $result id]"
    set result [scriptSourceTabsAdmitDocument $newRef $result]
    foreach tab [scriptSourceTabsPages $p] {
        if {[scriptSourceTabsGroupKey $p $tab] ne $group} continue
        set state($p,$tab,reference) $newRef;set state($p,$tab,document) $result
        if {[dict get $result kind] eq {script}} {set state($p,$tab,path) [scriptRegistrySourceName [dict get $result language]]}
        set state($p,$tab,baseline) [$state($p,$tab,text) get 1.0 end-1c]
        set f $state($p,$tab,fields)
        foreach {key value} [list currentId $newRef currentSha [dict get $result sha256] revision [dict get $result revision] scriptId [dict get $result id] name [dict get $result name] version [dict get $result version] description [dict get $result description] requiredApis [dict get $result explicit_apis] arguments [dict get $result default_arguments] parameterDefinitions [dict get $result parameters] parameterText [scriptParameterDefinitionsFormat [dict get $result parameters]] modified 0] {dict set f $key $value}
        dict unset f baseline
        set state($p,$tab,fields) $f
        sourceSurfaceDocumentIdentity $state($p,$tab,text) [list $newRef [dict get $result sha256] $state($p,$tab,path)]
        if {[info exists state($p,$tab,notes)]} {scriptSourceNotesSourceUpdated $p $tab $result}
    }
    set ui(activeFile) $state($p,$state($p,active),path)
    set ui(parameterDefinitions) [dict get $result parameters]
    foreach {key value} [list currentId $newRef currentSha [dict get $result sha256] revision [dict get $result revision] scriptId [dict get $result id] name [dict get $result name]] {set ui($key) $value}
    $ui(parameters) delete 1.0 end;$ui(parameters) insert 1.0 [scriptParameterDefinitionsFormat $ui(parameterDefinitions)]
    $ui(parameters) edit modified 0
    scriptSourceTabsLabels $p
    scriptSourceTabsTree $p
}
proc ::GX::scriptSourceTabsCycle {p delta} {
    set tabs [$p.book tabs];if {![llength $tabs]} return
    set i [lsearch -exact $tabs [$p.book select]]
    scriptSourceTabsNavigate $p [lindex $tabs [expr {($i+$delta+[llength $tabs])%[llength $tabs]}]]
}
proc ::GX::scriptSourceTabsClose {p {all 0} {target {}}} {
    variable ::GX::ScriptSourceTabs::state
    scriptSourceTabsCapture $p
    set original [$p.book select];set originalFocus [focus]
    set target [expr {$target eq {}?$original:$target}]
    if {!$all && [info exists state($p,$target,note_source)]} {
        set code $state($p,$target,note_source)
        if {![scriptSourceNotesReview $p $code]} {return 0}
        scriptSourceNotesDispose $p $code
        scriptSourceTabsNavigate $p $code
        return 1
    }
    set tabs [expr {$all ? [scriptSourceTabsPages $p] : [list $target]}]
    set reviewed {}
    foreach tab $tabs {
        if {![winfo exists $tab]} continue
        scriptSourceTabsNavigate $p $tab
        if {![scriptSourceNotesReview $p $tab]} {
            if {[winfo exists $original]} {scriptSourceTabsNavigate $p $original}
            return 0
        }
        upvar #0 $state($p,editor)::ui ui
        $state($p,editor)::_recomputeDirty
        set identity [scriptSourceTabsGroupKey $p $tab]
        if {$ui(modified) && $identity ni $reviewed} {
            set choice [tk_messageBox -parent [winfo toplevel $p] -type yesnocancel -default cancel -title {Unsaved source} -message "Save changes for $state($p,$tab,reference) / $state($p,$tab,path)?"]
            if {$choice eq {cancel} || ($choice eq {yes} && ![$state($p,editor)::_save])} {
                if {[winfo exists $original]} {scriptSourceTabsNavigate $p $original}
                if {[winfo exists $originalFocus]} {focus $originalFocus}
                return 0
            }
        }
        lappend reviewed $identity
    }
    foreach tab $tabs {
        if {![winfo exists $tab]} continue
        scriptSourceNotesDispose $p $tab
        set state($p,active) {};destroy $tab
        foreach key [array names state "$p,$tab,*"] {unset state($key)}
    }
    if {!$all} {
        if {[llength [$p.book tabs]]} {
            if {[winfo exists $original]} {scriptSourceTabsNavigate $p $original
            } elseif {[$p.book select] ne {}} {scriptSourceTabsNavigate $p [$p.book select]
            } else {
                set remaining [scriptSourceTabsPages $p]
                if {[llength $remaining]} {scriptSourceTabsNavigate $p [lindex $remaining 0]}
            }
            scriptSourceTabsLabels $p
        } else {$state($p,editor)::_new}
    }
    return 1
}
proc ::GX::scriptSourceTabsAction {p action} {
    variable ::GX::ScriptSourceTabs::state
    if {$action eq {close}} {scriptSourceTabsClose $p;return}
    if {$action eq {save}} {
        set original [$p.book select]
        set saved {}
        set success 1
        foreach tab [scriptSourceTabsPages $p] {
            scriptSourceTabsNavigate $p $tab
            if {[datasetPublicationV2DictDefault [scriptSourceTabsCurrent $p] mode editable] ne {editable}} continue
            upvar #0 $state($p,editor)::ui ui
            $state($p,editor)::_recomputeDirty
            set identity [scriptSourceTabsGroupKey $p $tab]
            if {$identity in $saved || !$ui(modified)} continue
            if {![$state($p,editor)::_save]} {set success 0;break}
            lappend saved $identity
        }
        if {$success} {set success [scriptSourceNotesSaveAll $p]}
        if {[winfo exists $original]} {scriptSourceTabsNavigate $p $original}
        return $success
    }
    set doc [scriptSourceTabsCurrent $p]
    if {[dict get $doc kind] ne {project}} {tk_messageBox -parent [winfo toplevel $p] -message {Project file operations require a registered Script Project. Create or import one in Script Library.};return}
    if {$action eq {files}} {
        set menu $p.filemenu;catch {destroy $menu};menu $menu -tearoff 0
        foreach path [dict keys [dict get $doc project_files]] {$menu add command -label $path -command [list ::GX::scriptSourceTabsOpen $p $state($p,$state($p,active),reference) $doc $path]}
        tk_popup $menu [winfo pointerx $p] [winfo pointery $p];return
    }
    if {![scriptSourceTabsWritable $p]} {error {Historical source tabs are read-only}}
    # Changes are committed in ONE Registry Save All transaction, including all
    # dirty source tabs; a stale revision never partially renames the tree.
    set tab $state($p,active);set path $state($p,$tab,path)
    if {$action in {new rename}} {
        set w [winfo toplevel $p].projectPath;catch {destroy $w};toplevel $w;wm transient $w [winfo toplevel $p]
        set state($p,pathInput) [expr {$action eq {rename} ? $path : {}}]
        ttk::label $w.hint -text {Normalized relative source path (subfolders allowed):}
        ttk::entry $w.value -textvariable ::GX::ScriptSourceTabs::state($p,pathInput) -width 45
        ttk::button $w.ok -text Apply -command [list ::GX::scriptSourceTabsFileCommit $p $action $w]
        ttk::button $w.cancel -text Cancel -command [list destroy $w]
        pack $w.hint $w.value $w.ok $w.cancel -fill x -padx 8 -pady 5
        bind $w.value <Return> [list ::GX::scriptSourceTabsFileCommit $p $action $w]
        bind $w <Escape> [list destroy $w];focus $w.value;return
    }
    scriptSourceTabsFileCommit $p $action {}
}
proc ::GX::scriptSourceTabsFileCommit {p action dialog} {
    variable ::GX::ScriptSourceTabs::state
    upvar #0 $state($p,editor)::ui ui
    if {![scriptSourceTabsRequireOwner $p]} return
    if {![scriptWorkspaceEditorSessionValid [winfo toplevel $p] $ui(sessionToken) $ui(scope)]} return
    if {[catch {
        set doc [scriptSourceTabsCurrent $p];set files [scriptSourceTabsFiles $p]
        set entry [dict get $doc entrypoint];set tab $state($p,active);set path $state($p,$tab,path)
        switch -- $action {
            new {set target $state($p,pathInput);if {[dict exists $files $target]} {error {File already exists}};dict set files $target {}}
            rename {set target $state($p,pathInput);if {[dict exists $files $target]} {error {File already exists}};dict set files $target [dict get $files $path];dict unset files $path;if {$entry eq $path} {set entry $target}}
            remove {if {$entry eq $path} {error {Select another entrypoint before removing this file}};if {[tk_messageBox -parent [winfo toplevel $p] -type okcancel -default cancel -message "Remove $path from the project and save all edited files?"] ne {ok}} return;dict unset files $path}
            entry {set entry $path}
        }
        if {$action eq {remove} && ![scriptSourceNotesReview $p $tab]} return
        set metadata [dict create parameters [$state($p,editor)::_parametersFromEditor] expected_revision $ui(revision)]
        if {$action eq {rename}} {dict set metadata source_authoring_renames [dict create $path $target]}
        set result [scriptRegistryProjectUpdate $ui(scope) $ui(scriptId) $ui(currentSha) $metadata $entry $files]
        if {$action eq {rename}} {set state($p,$tab,path) $target;set ui(activeFile) $target}
        scriptSourceTabsSaved $p $result
        set ui(currentSha) [dict get $result sha256];set ui(revision) [dict get $result revision]
        $state($p,editor)::_acceptBaseline
        if {$dialog ne {}} {destroy $dialog}
        if {$action eq {new}} {scriptSourceTabsOpen $p $ui(currentId) $result $target}
        if {$action eq {remove}} {scriptSourceNotesDispose $p $tab;set state($p,active) {};destroy $tab;scriptSourceTabsOpen $p $ui(currentId) $result $entry}
    } reason]} {tk_messageBox -parent [winfo toplevel $p] -icon error -title {Project change refused} -message $reason}
}
proc ::GX::scriptSourceTabsBreakpoints {p} {
    variable ::GX::ScriptSourceTabs::state
    set out {};set group [scriptSourceTabsGroupKey $p]
    foreach tab [scriptSourceTabsPages $p] {
        if {[scriptSourceTabsGroupKey $p $tab] ne $group} continue
        set lines [sourceSurfaceBreakpoints $state($p,$tab,text)]
        if {$lines ne {}} {dict set out $state($p,$tab,path) $lines}
    }
    return $out
}
proc ::GX::scriptSourceTabsDebugFile {p path sha} {
    variable ::GX::ScriptSourceTabs::state
    set doc [scriptSourceTabsCurrent $p]
    if {[dict get $doc kind] ne {project} || [dict get $doc sha256] ne $sha} {return {}}
    # Frozen file suffix is compared to the admitted manifest, never an arbitrary
    # filesystem path. Navigation opens the corresponding saved source buffer.
    foreach name [dict keys [dict get $doc project_files]] {
        if {[string match "*/project/files/$name" [string map {\\ /} $path]]} {
            return [scriptSourceTabsOpen $p $state($p,$state($p,active),reference) $doc $name]
        }
    }
    return {}
}

source [file join [file dirname [info script]] source_note_asset_provider.tcl]
source [file join [file dirname [info script]] source_note_editor.tcl]
source [file join [file dirname [info script]] script_source_notes.tcl]
