# SPDX-License-Identifier: GPL-3.0-or-later
# Additive UI Field shell primitive. No Viewer/scientific state is stored here.
proc ::GX::uiFieldViewerShellCreate {window title {geometry 1100x720} {inspectorWidth 320}} {
    if {[winfo exists $window]} {error {Viewer window already exists}}
    toplevel $window;wm title $window $title;wm geometry $window $geometry;wm minsize $window 640 400
    menu $window.menus -tearoff 0;$window configure -menu $window.menus
    ttk::frame $window.toolbar -padding 4;pack $window.toolbar -fill x
    _uiFieldToolbarAttach $window.toolbar
    ttk::frame $window.footer;pack $window.footer -side bottom -fill x
    ttk::label $window.footer.status -anchor w;pack $window.footer.status -fill x
    ttk::panedwindow $window.body -orient horizontal;pack $window.body -fill both -expand 1
    ttk::frame $window.body.inspector -width $inspectorWidth;ttk::frame $window.body.canvas
    $window.body add $window.body.inspector -weight 0;$window.body add $window.body.canvas -weight 1
    canvas $window.body.inspector.scroll -highlightthickness 0 -width $inspectorWidth -yscrollincrement 24 -xscrollincrement 24
    ttk::scrollbar $window.body.inspector.bar -command [list $window.body.inspector.scroll yview]
    ttk::scrollbar $window.body.inspector.xbar -orient horizontal -command [list $window.body.inspector.scroll xview]
    $window.body.inspector.scroll configure -yscrollcommand [list $window.body.inspector.bar set] -xscrollcommand [list $window.body.inspector.xbar set]
    ttk::frame $window.body.inspector.scroll.content -padding 6
    $window.body.inspector.scroll create window 0 0 -anchor nw -window $window.body.inspector.scroll.content -tags content
    bind $window <Configure> +[list ::GX::_uiFieldViewerInspectorSchedule $window %W]
    bind $window <FocusIn> +[list ::GX::_uiFieldViewerInspectorSchedule $window %W]
    bind $window.body.inspector.scroll <Destroy> [list after cancel [list ::GX::_uiFieldViewerInspectorLayout $window]]
    foreach {sequence delta} {<Button-4> -3 <Button-5> 3} {bind $window.body.inspector.scroll $sequence [list $window.body.inspector.scroll yview scroll $delta units]}
    bind $window <FocusIn> +[list ::GX::_uiFieldViewerInspectorFocus $window %W]
    bind $window.body <Map> +[list ::GX::_uiFieldViewerInitialSplit $window $inspectorWidth %W]
    bind $window.body <Configure> +[list ::GX::_uiFieldViewerInspectorFit $window $inspectorWidth %W %w]
    bind $window <MouseWheel> +[list ::GX::_uiFieldViewerWheel $window %W %D]
    foreach {event delta} {<Button-4> 1 <Button-5> -1} {bind $window $event +[list ::GX::_uiFieldViewerWheel $window %W $delta]}
    pack $window.body.inspector.bar -side right -fill y;pack $window.body.inspector.scroll -fill both -expand 1
    return [dict create window $window toolbar $window.toolbar inspector $window.body.inspector.scroll.content canvas $window.body.canvas footer $window.footer status $window.footer.status]
}

proc ::GX::_uiFieldViewerInspectorSchedule {window actual} {
    set canvas $window.body.inspector.scroll
    if {![winfo exists $canvas] || ($actual ne $canvas && [string first "$canvas.content" $actual]!=0)} return
    set callback [list ::GX::_uiFieldViewerInspectorLayout $window]
    after cancel $callback
    after idle $callback
}
proc ::GX::_uiFieldViewerInspectorLayout {window} {
    set canvas $window.body.inspector.scroll;set content $canvas.content
    if {![winfo exists $content] || ![winfo ismapped $canvas]} return
    set room [winfo width $canvas]
    set width [expr {max($room,[winfo reqwidth $content])}]
    # Nested scrolling pages can have a small request even when their native
    # actions are squeezed. Preserve each mapped caption's request plus its
    # existing surrounding allocation, without changing any child grid policy.
    set pending [winfo children $content]
    for {set i 0} {$i<[llength $pending]} {incr i} {
        set child [lindex $pending $i]
        if {![winfo ismapped $child]} continue
        lappend pending {*}[winfo children $child]
        if {[winfo class $child] in {Button TButton Checkbutton TCheckbutton Radiobutton TRadiobutton Menubutton TMenubutton}} {
            set width [expr {max($width,[winfo width $content]+[winfo reqwidth $child]-[winfo width $child])}]
        }
    }
    if {[$canvas itemcget content -width]!=$width} {$canvas itemconfigure content -width $width}
    $canvas configure -scrollregion [list 0 0 $width [winfo reqheight $content]]
    if {$width>$room} {
        if {[winfo manager $window.body.inspector.xbar] eq {}} {
            pack $window.body.inspector.xbar -side bottom -fill x -before $canvas
        }
    } else {
        pack forget $window.body.inspector.xbar
        $canvas xview moveto 0
    }
    # A fully offscreen keyboard target needs horizontal reveal. Leave partly
    # visible pointer targets still between their native press and release.
    set widget [focus -displayof $window]
    if {[string first "$content." $widget]==0 && [winfo exists $widget]} {
        set left [$canvas canvasx 0];set right [$canvas canvasx $room]
        set x [expr {[winfo rootx $widget]-[winfo rootx $content]}]
        set end [expr {$x+[winfo width $widget]}]
        if {$end<=$left || $x>=$right} {$canvas xview moveto [expr {max(0,($x-4)/double(max(1,$width)))}]}
    }
}

proc ::GX::_uiFieldViewerInitialSplit {window width mapped} {
    if {$mapped ne "$window.body" || ![winfo exists $mapped]} return
    # The public width remains its font10 nominal size. Preserve its character
    # capacity at larger actual fonts, within the mapped window's room.
    set normal [dict replace [font actual TkDefaultFont] -size 10]
    set scale [expr {max(1.0,double([font measure TkDefaultFont 0])/max(1,[font measure $normal 0]))}]
    set desired [expr {int(ceil($width*$scale))}]
    set limit [expr {max($width,int([winfo width $mapped]*2/3))}]
    if {[llength [$mapped panes]]>1} {$mapped sashpos 0 [expr {min($desired,$limit)}]}
    bind $mapped <Map> {}
}
proc ::GX::_uiFieldViewerInspectorFit {window nominal actual width} {
    if {$actual ne "$window.body" || ![winfo exists $actual] || $width<2 || [llength [$actual panes]]<2} return
    # Narrowing may reclaim room for the canvas. Growing or moving the sash
    # remains the native panedwindow/user's decision; never reset their split.
    set limit [expr {min($width,max($nominal,int($width*2/3)))}]
    if {[$actual sashpos 0]>$limit} {$actual sashpos 0 $limit}
}
proc ::GX::_uiFieldViewerWheel {window widget delta} {
    if {[string first "$window.body.inspector." $widget]!=0} return
    if {[_uiFieldTabViewportFor $widget] ne {}} return
    $window.body.inspector.scroll yview scroll [expr {$delta>0?-3:3}] units
}

# Host-only mapping and dialog lifecycle. No scientific or Workspace state.
proc ::GX::uiFieldFocusWhenMapped {container target {modal 0}} {
    if {![winfo exists $container] || ![winfo exists $target]} return
    bind $container <Map> +[list ::GX::_uiFieldFocusSchedule $container $target $modal %W]
    bind $container <Unmap> +[list ::GX::_uiFieldMappedRelease $container %W]
    after idle [list ::GX::_uiFieldMappedFocus $container $target $modal $container]
}
proc ::GX::_uiFieldFocusSchedule {container target modal changed} {
    if {$changed eq $container} {after idle [list ::GX::_uiFieldMappedFocus $container $target $modal $container]}
}
proc ::GX::_uiFieldMappedRelease {container changed} {
    if {$changed eq $container && [grab current] eq $container} {grab release $container}
}
proc ::GX::_uiFieldMappedFocus {container target modal changed} {
    if {$changed ne $container || ![winfo exists $container] || ![winfo exists $target] || ![winfo viewable $container] || ![winfo viewable $target]} return
    focus $target
    if {$modal} {grab $container}
}
proc ::GX::uiFieldDialogCreate {dialogWindow parent title {geometry {}}} {
    variable ::GX::UiField::dialogGeometry
    if {![winfo exists $parent]} {error {The dialogWindow owner has closed}}
    if {[winfo exists $dialogWindow]} {raise $dialogWindow;return $dialogWindow}
    toplevel $dialogWindow;wm withdraw $dialogWindow;wm title $dialogWindow $title;wm transient $dialogWindow [winfo toplevel $parent]
    set dialogGeometry($dialogWindow) $geometry
    bind $dialogWindow <Destroy> +[list ::GX::_uiFieldDialogDestroyed $dialogWindow %W]
    if {$geometry ne {}} {wm geometry $dialogWindow $geometry}
    wm protocol $dialogWindow WM_DELETE_WINDOW [list ::GX::uiFieldDialogClose $dialogWindow]
    bind $dialogWindow <Escape> [list ::GX::uiFieldDialogClose $dialogWindow]
    return $dialogWindow
}
proc ::GX::uiFieldDialogPresent {dialogWindow {target {}} {modal 0}} {
    if {![winfo exists $dialogWindow]} {error {Dialog has closed}}
    if {$target eq {}} {set target $dialogWindow}
    # Never drain the whole idle queue here: native viewport hosts can keep
    # scheduling paints. Placement and focus must follow mapping asynchronously.
    uiFieldFocusWhenMapped $dialogWindow $target $modal
    wm deiconify $dialogWindow;raise $dialogWindow
    after idle [list ::GX::_uiFieldDialogPlace $dialogWindow]
    return $dialogWindow
}
proc ::GX::_uiFieldDialogDestroyed {dialogWindow actual} {
    if {$dialogWindow eq $actual} {unset -nocomplain ::GX::UiField::dialogGeometry($dialogWindow)}
}
proc ::GX::_uiFieldDialogPlace {dialogWindow} {
    variable ::GX::UiField::dialogGeometry
    if {![winfo exists $dialogWindow] || ![winfo viewable $dialogWindow]} return
    # The global work-area mapper can freeze Tk's initial 200x200 size before
    # children negotiate their request. Shared dialogs without explicit size
    # use the completed request, rather than preserving that provisional size.
    if {[info exists dialogGeometry($dialogWindow)] && $dialogGeometry($dialogWindow) eq {}} {
        set width [expr {min([winfo reqwidth $dialogWindow],[winfo screenwidth $dialogWindow]-40)}]
        set height [expr {min([winfo reqheight $dialogWindow],[winfo screenheight $dialogWindow]-100)}]
        wm geometry $dialogWindow ${width}x${height}
    }
    set parent [wm transient $dialogWindow]
    if {$parent ne {} && [winfo exists $parent]} {
        set x [expr {[winfo rootx $parent]+max(0,([winfo width $parent]-[winfo reqwidth $dialogWindow])/2)}]
        set y [expr {[winfo rooty $parent]+max(0,([winfo height $parent]-[winfo reqheight $dialogWindow])/2)}]
        set x [expr {max(0,min($x,[winfo screenwidth $dialogWindow]-[winfo reqwidth $dialogWindow]))}]
        set y [expr {max(25,min($y,[winfo screenheight $dialogWindow]-[winfo reqheight $dialogWindow]-35))}]
        wm geometry $dialogWindow +$x+$y
    }
}
proc ::GX::uiFieldDialogClose {dialogWindow} {
    if {![winfo exists $dialogWindow]} return
    set parent [wm transient $dialogWindow]
    if {[grab current] eq $dialogWindow} {grab release $dialogWindow}
    destroy $dialogWindow
    if {$parent ne {} && [winfo exists $parent] && [winfo viewable $parent]} {focus $parent}
}
proc ::GX::uiFieldViewerSection {parent id title} {
    ttk::labelframe $parent.$id -text $title -padding 8
    pack $parent.$id -fill x -pady 5
    return $parent.$id
}

proc ::GX::_uiFieldViewerInspectorFocus {window widget} {
    # Tk also reports FocusIn for every ancestor of the receiving control.
    # Revealing those containers can scroll an already visible pointer target
    # between its button press and release. Reveal only the actual focus leaf.
    if {![winfo exists $window] || $widget ne [focus -displayof $window]} return
    set content $window.body.inspector.scroll.content
    if {[string first "$content." $widget]==0} {
        if {[_uiFieldTabViewportFor $widget] ne {}} {
            # Let the inner page scroll and finish native child geometry first.
            after idle [list after idle [list ::GX::_uiFieldTabOuterFocus $window.body.inspector.scroll $content $widget]]
        } else {uiFieldScrollSee $window.body.inspector.scroll $content $widget}
    }
}

# Declarative construction under the existing UI Field authority. The Builder
# and installed generated Viewers consume this same public constructor.
proc ::GX::uiFieldComponentCapabilities {} {
    set result {}
    foreach {type description properties} {
        panel {Responsive grid container} {title string}
        section {Labelled inspector section} {title string padding number}
        splitter {Resizable container} {orientation choice}
        tabs {Tabbed container} {tab_position choice}
        tab {Page inside a tab container} {title string}
        label {Plain descriptive text} {text string wraplength number}
        entry {Plain value entry; domain owner validates} {default string width number}
        combobox {Native bounded choice without a field wrapper} {default string choices list width number}
        checkbutton {Native boolean control without a field wrapper} {label string default boolean}
        list {Native read-only item list and selection} {items list height number selectmode choice}
        field {Validated typed value} {label string datatype choice default string choices list min number max number alpha boolean}
        action {ViewerCommands action button} {label string action identifier tooltip string shortcut string event_value number}
        toggle {Boolean value} {label string default boolean}
        choice {Bounded choice selector} {label string default string choices list}
        dataset_selector {Live canonical Dataset selector} {label string content_kind choice allow_empty boolean}
        status {Read-only status text} {text string}
        progress {Determinate progress display} {maximum number}
        log {Read-only diagnostic text} {text string height number width number}
        table {Read-only table; no Worksheet editing} {columns list scrollbars choice}
    } {
        dict set result $type [dict create label $description api_id UI_FIELD_API_v1 api_version 1 owner core/tcl/ui_field_viewer_regions_v1.tcl properties $properties events [expr {$type in {field toggle choice dataset_selector entry combobox checkbutton list} ? {changed} : ($type eq {action} ? {invoke} : {})}] status AVAILABLE]
    }
    foreach type {action label status checkbutton toggle} {
        foreach {key datatype} {icon string icon_disabled string icon_hover string icon_selected string presentation choice icon_position choice icon_size number icon_spacing number} {dict set result $type properties $key $datatype}
    }
    return $result
}
proc ::GX::uiFieldComponentCreate {widget type properties variableName callback {context {}}} {
    if {![dict exists [uiFieldComponentCapabilities] $type]} {error {Unsupported public UI Field component.}}
    set label [datasetPublicationV2DictDefault $properties label {}]
    switch $type {
        panel {
            ttk::frame $widget -padding 4
            _uiFieldToolbarAttach $widget
        }
        tab {
            ttk::frame $widget -padding 4
            _uiFieldTabAttach $widget
        }
        section {ttk::labelframe $widget -text [datasetPublicationV2DictDefault $properties title Section] -padding [datasetPublicationV2DictDefault $properties padding 6]}
        splitter {ttk::panedwindow $widget -orient [datasetPublicationV2DictDefault $properties orientation horizontal]}
        tabs {
            set position [datasetPublicationV2DictDefault $properties tab_position north]
            if {$position ni {north west}} {error {Tab position must be north or west}}
            if {$position eq {west}} {
                # Use the native notebook's own layout and hit testing. A
                # vertical stack keeps long page names reachable in sidebars.
                ttk::style configure GXViewerWest.TNotebook -tabposition wn
                ttk::notebook $widget -style GXViewerWest.TNotebook
            } else {
                ttk::notebook $widget
                _uiFieldNotebookAttach $widget
            }
        }
        label - status {
            set maximum [datasetPublicationV2DictDefault $properties wraplength 400]
            ttk::label $widget -text [datasetPublicationV2DictDefault $properties text {}] -anchor w -justify left -wraplength $maximum
            if {$maximum>0} {bind $widget <Configure> +[list ::GX::_uiFieldComponentTextWrap $widget $maximum %W %w]}
        }
        entry {ttk::entry $widget -textvariable $variableName -width [datasetPublicationV2DictDefault $properties width 20];if {$callback ne {}} {bind $widget <Return> $callback;bind $widget <FocusOut> $callback}}
        combobox {ttk::combobox $widget -state readonly -textvariable $variableName -values [datasetPublicationV2DictDefault $properties choices {}] -width [datasetPublicationV2DictDefault $properties width 20];uiFieldSelectorWithinViewer $widget [winfo toplevel $widget];if {$callback ne {}} {bind $widget <<ComboboxSelected>> $callback}}
        checkbutton {ttk::checkbutton $widget -text $label -variable $variableName -command $callback}
        list {listbox $widget -height [datasetPublicationV2DictDefault $properties height 6] -exportselection 0 -selectmode [datasetPublicationV2DictDefault $properties selectmode browse];foreach item [datasetPublicationV2DictDefault $properties items {}] {$widget insert end $item};if {$callback ne {}} {bind $widget <<ListboxSelect>> $callback}}
        field - toggle - choice {
            set datatype [dict get {field string toggle boolean choice choice} $type]
            set datatype [datasetPublicationV2DictDefault $properties datatype $datatype]
            set descriptor [dict create type $datatype label $label default [datasetPublicationV2DictDefault $properties default [expr {$datatype eq {boolean} ? 0 : {}}]] compact 1]
            foreach name {min max alpha} {if {[dict exists $properties $name]} {dict set descriptor $name [dict get $properties $name]}}
            if {$datatype eq {choice}} {dict set descriptor values [datasetPublicationV2DictDefault $properties choices {}]}
            uiFieldCreate $widget $descriptor $variableName $callback
            if {$label ne {}} {
                ttk::label $widget.caption -text $label -anchor w -justify left -wraplength 400
                bind $widget.caption <Configure> +[list ::GX::_uiFieldComponentTextWrap $widget.caption 400 %W %w]
                grid $widget.caption -row 0 -column 0 -columnspan [expr {$datatype eq {color} ? 1 : 4}] -sticky ew
                grid configure $widget.entry -row 1
                if {[winfo exists $widget.reset]} {grid configure $widget.reset -row 1}
            }
            if {$datatype eq {choice}} {uiFieldSelectorWithinViewer $widget.entry [winfo toplevel $widget]}
        }
        action {ttk::button $widget -text $label -command $callback;set tip [datasetPublicationV2DictDefault $properties tooltip {}];if {$tip ne {}} {bind $widget <Enter> [list ::GX::plotsToolbarTipSchedule $widget $tip];bind $widget <Leave> ::GX::plotsToolbarTipHide}}
        dataset_selector {
            set allowEmpty [datasetPublicationV2DictDefault $properties allow_empty 0]
            if {![string is boolean -strict $allowEmpty]} {error {Dataset selector allow_empty must be boolean}}
            ttk::frame $widget
            ttk::label $widget.caption -text $label -anchor w -justify left -wraplength 400
            bind $widget.caption <Configure> +[list ::GX::_uiFieldComponentTextWrap $widget.caption 400 %W %w]
            ttk::combobox $widget.entry -state readonly -textvariable $variableName
            pack $widget.caption $widget.entry -fill x
            if {[dict exists $context demo_choices]} {
                if {[dict keys $context] ne {demo_choices}||[llength [dict get $context demo_choices]]>32||[string bytelength $context]>8192} {error {Invalid bounded display-only selector context}}
                set choices [dict get $context demo_choices]
                if {$allowEmpty && {} ni $choices} {set choices [linsert $choices 0 {}]}
                $widget.entry configure -values $choices
            } else {datasetSelectorAttach $widget.entry [list ::GX::uiFieldDatasetChoices [datasetPublicationV2DictDefault $properties content_kind {}] $allowEmpty]}
            bind $widget.entry <<ComboboxSelected>> $callback
            if {$allowEmpty} {
                ttk::button $widget.clear -text {Clear selection} -command [list ::GX::_uiFieldDatasetClear $widget.entry]
                pack $widget.clear -anchor w -pady 2
            }
            uiFieldSelectorWithinViewer $widget.entry [winfo toplevel $widget]
        }
        progress {ttk::progressbar $widget -mode determinate -maximum [datasetPublicationV2DictDefault $properties maximum 100] -variable $variableName}
        log {text $widget -height [datasetPublicationV2DictDefault $properties height 6] -width [datasetPublicationV2DictDefault $properties width 32] -wrap word;$widget insert 1.0 [datasetPublicationV2DictDefault $properties text {}];$widget configure -state disabled}
        table {
            set columns [datasetPublicationV2DictDefault $properties columns {Column}]
            set bars [datasetPublicationV2DictDefault $properties scrollbars none]
            if {$bars ni {none vertical horizontal both}} {error {Table scrollbars must be none, vertical, horizontal or both.}}
            set tree $widget
            if {$bars ne {none}} {ttk::frame $widget;set tree $widget.table}
            ttk::treeview $tree -columns $columns -show headings -height 5
            foreach column $columns {$tree heading $column -text $column;$tree column $column -width 100 -minwidth 40}
            bind $tree <Control-c> {::GX::uiFieldComponentTableCopy %W; break}
            bind $tree <Control-C> {::GX::uiFieldComponentTableCopy %W; break}
            if {$bars ne {none}} {
                grid $tree -row 0 -column 0 -sticky nsew
                grid rowconfigure $widget 0 -weight 1;grid columnconfigure $widget 0 -weight 1
                if {$bars in {vertical both}} {ttk::scrollbar $widget.vertical -orient vertical -command [list $tree yview];$tree configure -yscrollcommand [list $widget.vertical set];grid $widget.vertical -row 0 -column 1 -sticky ns}
                if {$bars in {horizontal both}} {ttk::scrollbar $widget.horizontal -orient horizontal -command [list $tree xview];$tree configure -xscrollcommand [list $widget.horizontal set];grid $widget.horizontal -row 1 -column 0 -sticky ew}
            }
        }
    }
    return $widget
}
# Keep the declared notebook and its page identities when native tab labels
# cannot fit. The native readonly selector changes only notebook selection;
# the original tabs return when room is available again.
namespace eval ::GX::UiField {variable notebookOverflow {};variable toolbarOverflow {}}
proc ::GX::_uiFieldNotebookAttach {widget} {
    dict set ::GX::UiField::notebookOverflow $widget [dict create after {} compact 0 style [$widget cget -style] padding [$widget cget -padding]]
    foreach event {<Configure> <Map> <<NotebookTabChanged>>} {
        bind $widget $event +[list ::GX::_uiFieldNotebookSchedule $widget %W]
    }
    bind $widget <Destroy> +[list ::GX::_uiFieldNotebookDispose $widget %W]
}
proc ::GX::_uiFieldNotebookSchedule {widget actual} {
    if {$actual ne $widget || ![dict exists $::GX::UiField::notebookOverflow $widget]} return
    if {[dict get $::GX::UiField::notebookOverflow $widget after] eq {}} {
        dict set ::GX::UiField::notebookOverflow $widget after [after idle [list ::GX::_uiFieldNotebookLayout $widget]]
    }
}
proc ::GX::_uiFieldNotebookDispose {widget actual} {
    if {$actual ne $widget || ![dict exists $::GX::UiField::notebookOverflow $widget]} return
    after cancel [dict get $::GX::UiField::notebookOverflow $widget after]
    dict unset ::GX::UiField::notebookOverflow $widget
}
proc ::GX::_uiFieldNotebookLayout {widget} {
    if {![dict exists $::GX::UiField::notebookOverflow $widget]} return
    dict set ::GX::UiField::notebookOverflow $widget after {}
    if {![winfo exists $widget] || ![winfo ismapped $widget] || [winfo width $widget]<2} return
    set saved [dict get $::GX::UiField::notebookOverflow $widget]
    set style [dict get $saved style]
    if {$style eq {}} {set style TNotebook}
    set font [ttk::style lookup $style.Tab -font]
    if {$font eq {}} {set font TkDefaultFont}
    set padding [ttk::style lookup $style.Tab -padding]
    set horizontal 0
    if {[llength $padding]} {
        set horizontal [winfo pixels $widget [lindex $padding 0]]
        if {[llength $padding]>2} {incr horizontal [winfo pixels $widget [lindex $padding 2]]} else {incr horizontal $horizontal}
    }
    set needed 8;set pages {};set labels {}
    foreach page [$widget tabs] {
        set state [$widget tab $page -state]
        if {$state eq {hidden}} continue
        set title [$widget tab $page -text]
        incr needed [expr {[font measure $font $title]+$horizontal+4}]
        lappend pages $page
        lappend labels [expr {$state eq {disabled} ? "$title (unavailable)" : $title}]
    }
    set compact [expr {[llength $pages]>1 && $needed>[winfo width $widget]}]
    set selector $widget.__pageSelector
    if {$compact} {
        if {![winfo exists $selector]} {
            ttk::combobox $selector -state readonly -width 1 -font $font
            bind $selector <<ComboboxSelected>> [list ::GX::_uiFieldNotebookChoose $widget]
        }
        dict set ::GX::UiField::notebookOverflow $widget pages $pages
        $selector configure -values $labels -font $font
        set index [lsearch -exact $pages [$widget select]]
        if {$index>=0} {$selector current $index}
        $selector configure -state [expr {[$widget instate disabled] ? {disabled} : {readonly}}]
        ttk::style layout GXViewerCompact.TNotebook.Tab {null}
        set pad [dict get $saved padding]
        if {$pad eq {}} {set pad {0}}
        lassign $pad left top right bottom
        if {$top eq {}} {set top $left}
        if {$right eq {}} {set right $left}
        if {$bottom eq {}} {set bottom $top}
        set padding [list $left [expr {$top+[winfo reqheight $selector]+4}] $right $bottom]
        if {[$widget cget -style] ne {GXViewerCompact.TNotebook} || [$widget cget -padding] ne $padding} {
            $widget configure -style GXViewerCompact.TNotebook -padding $padding
        }
        place $selector -x 4 -y 2 -relwidth 1 -width -8 -height [winfo reqheight $selector]
        raise $selector
    } elseif {[dict get $saved compact]} {
        place forget $selector
        $widget configure -style [dict get $saved style] -padding [dict get $saved padding]
    }
    dict set ::GX::UiField::notebookOverflow $widget compact $compact
}
proc ::GX::_uiFieldNotebookChoose {widget} {
    if {![winfo exists $widget] || ![dict exists $::GX::UiField::notebookOverflow $widget pages]} return
    set selector $widget.__pageSelector
    set index [$selector current]
    set page [lindex [dict get $::GX::UiField::notebookOverflow $widget pages] $index]
    if {$index>=0 && $page ne {} && [$widget tab $page -state] eq {normal} && ![$widget instate disabled]} {$widget select $page}
    _uiFieldNotebookSchedule $widget $widget
}

# Reuse the shared controls layout for an overflowing single-row action bar.
# A declared multirow bar with full-width status headers uses a native command
# menu when narrow: stacking more rows there would consume its scientific view.
# Other declared layouts and the caller's original grid policy stay intact.
proc ::GX::_uiFieldToolbarAttach {widget} {
    dict set ::GX::UiField::toolbarOverflow $widget [dict create after {} policies {} headers {} columns {} multirow 0 wrapped 0]
    bind $widget <Configure> +[list ::GX::_uiFieldToolbarSchedule $widget %W]
    bind $widget <Destroy> +[list ::GX::_uiFieldToolbarDispose $widget %W]
}
proc ::GX::_uiFieldToolbarSchedule {widget actual} {
    if {$actual ne $widget || ![dict exists $::GX::UiField::toolbarOverflow $widget]} return
    if {[dict get $::GX::UiField::toolbarOverflow $widget after] eq {}} {
        dict set ::GX::UiField::toolbarOverflow $widget after [after idle [list ::GX::_uiFieldToolbarLayout $widget]]
    }
}
proc ::GX::_uiFieldToolbarDispose {widget actual} {
    if {$actual ne $widget || ![dict exists $::GX::UiField::toolbarOverflow $widget]} return
    after cancel [dict get $::GX::UiField::toolbarOverflow $widget after]
    dict unset ::GX::UiField::toolbarOverflow $widget
}
proc ::GX::_uiFieldToolbarLayout {widget} {
    if {![dict exists $::GX::UiField::toolbarOverflow $widget]} return
    dict set ::GX::UiField::toolbarOverflow $widget after {}
    if {![winfo exists $widget] || ![winfo ismapped $widget] || [winfo width $widget]<2} return
    set saved [dict get $::GX::UiField::toolbarOverflow $widget]
    set policies [dict get $saved policies]
    if {$policies eq {}} {
        set ordered {};set headers {};set firstRow {};set rows {};set maxColumn 0
        foreach child [winfo children $widget] {
            if {[winfo manager $child] eq {}} continue
            if {[winfo manager $child] ne {grid}} return
            set info [grid info $child]
            if {[dict get $info -rowspan]!=1} return
            set row [dict get $info -row];set column [dict get $info -column]
            if {[winfo class $child] in {TLabel Label}} {
                dict set headers $child [dict create grid $info wraplength [$child cget -wraplength]]
            } elseif {[winfo class $child] in {TButton TCheckbutton Button Checkbutton}} {
                lappend ordered [list $row $column $child $info]
                dict set rows $row 1
                if {$firstRow eq {} || $row<$firstRow} {set firstRow $row}
                set maxColumn [expr {max($maxColumn,$column+[dict get $info -columnspan])}]
            } else {return}
        }
        if {![llength $ordered]} return
        # Admit only complete prefix headers, never a mixed form or input grid.
        dict for {child header} $headers {
            set info [dict get $header grid]
            if {[dict get $info -row]>=$firstRow || [dict get $info -column]!=0 || [dict get $info -columnspan]<$maxColumn} return
        }
        set multirow [expr {[dict size $rows]>1}]
        if {$multirow && $headers eq {}} return
        if {!$multirow && ($headers ne {} || $firstRow!=0)} return
        foreach row [lsort -integer -index 0 [lsort -integer -index 1 $ordered]] {
            set info [lindex $row 3]
            if {$multirow && [dict get $info -columnspan]!=1} return
            dict set policies [lindex $row 2] $info
        }
        set columns {}
        for {set index 0} {$index<max($maxColumn,2*[dict size $policies])} {incr index} {dict set columns $index [grid columnconfigure $widget $index]}
        dict set ::GX::UiField::toolbarOverflow $widget policies $policies
        dict set ::GX::UiField::toolbarOverflow $widget headers $headers
        dict set ::GX::UiField::toolbarOverflow $widget multirow $multirow
        dict set ::GX::UiField::toolbarOverflow $widget columns $columns
        set saved [dict get $::GX::UiField::toolbarOverflow $widget]
    }
    set needed 8;set widths {}
    dict for {child info} $policies {
        if {![winfo exists $child]} return
        set pixels [expr {[winfo reqwidth $child]+2*[lindex [dict get $info -padx] 0]}]
        if {[dict get $saved multirow]} {
            set column [dict get $info -column]
            dict set widths $column [expr {max($pixels,[datasetPublicationV2DictDefault $widths $column 0])}]
        } else {incr needed $pixels}
    }
    dict for {column pixels} $widths {incr needed $pixels}
    if {$needed>[winfo width $widget]} {
        dict set ::GX::UiField::toolbarOverflow $widget wrapped 1
        if {[dict get $saved multirow]} {
            set button $widget.__overflowActions
            if {![winfo exists $button]} {
                ttk::menubutton $button -text {Actions…} -menu $button.menu
                menu $button.menu -tearoff 0 -postcommand [list ::GX::_uiFieldToolbarActionsPost $widget]
            }
            dict for {child policy} $policies {grid remove $child}
            set row 0;set span 1
            dict for {child header} [dict get $saved headers] {
                set policy [dict get $header grid]
                set row [expr {max($row,[dict get $policy -row]+1)}]
                set span [expr {max($span,[dict get $policy -columnspan])}]
                _uiFieldComponentTextWrap $child [dict get $header wraplength] $child [winfo width $child]
            }
            grid $button -row $row -column 0 -columnspan $span -sticky w -padx 3 -pady 2
        } else {uiFieldControlsLayout $widget [expr {[winfo width $widget]-8}] [dict keys $policies]}
    } elseif {[dict get $saved wrapped]} {
        dict set ::GX::UiField::toolbarOverflow $widget wrapped 0
        if {[winfo exists $widget.__overflowActions]} {grid remove $widget.__overflowActions}
        dict for {index policy} [dict get $saved columns] {grid columnconfigure $widget $index {*}$policy}
        dict for {child policy} $policies {grid $child {*}$policy}
        dict for {child header} [dict get $saved headers] {
            _uiFieldComponentTextWrap $child [dict get $header wraplength] $child [winfo width $child]
        }
    }
}
proc ::GX::_uiFieldToolbarActionsPost {widget} {
    if {![dict exists $::GX::UiField::toolbarOverflow $widget] || ![winfo exists $widget.__overflowActions.menu]} return
    set menu $widget.__overflowActions.menu
    $menu delete 0 end
    dict for {child policy} [dict get $::GX::UiField::toolbarOverflow $widget policies] {
        if {![winfo exists $child]} continue
        set state normal;set text [$child cget -text]
        if {[winfo class $child] in {TButton TCheckbutton}} {
            if {[$child instate disabled]} {set state disabled}
            if {[winfo class $child] eq {TCheckbutton} && [$child instate selected]} {set text "✓ $text"}
        } elseif {[$child cget -state] eq {disabled}} {set state disabled}
        $menu add command -label $text -state $state -command [list ::GX::_uiFieldToolbarActionInvoke $child]
        set image [lindex [$child cget -image] 0]
        if {$image ne {}} {$menu entryconfigure end -image $image -compound left}
    }
}
proc ::GX::_uiFieldToolbarActionInvoke {child} {
    if {[winfo exists $child]} {$child invoke}
}

proc ::GX::uiFieldComponentLayout {widget parent layout} {
    if {[datasetPublicationV2DictDefault $layout manager grid] eq {pack}} {
        set args [list -in $parent]
        foreach key {side fill expand anchor padx pady} {if {[dict exists $layout $key]} {lappend args -$key [dict get $layout $key]}}
        pack $widget {*}$args
        if {[dict exists $layout minimum_width] || [dict exists $layout minimum_height]} {
            set width [datasetPublicationV2DictDefault $layout minimum_width 0];set height [datasetPublicationV2DictDefault $layout minimum_height 0]
            set tag GXPackMinimum$widget
            if {$tag ni [bindtags $widget]} {bindtags $widget [linsert [bindtags $widget] 0 $tag]}
            bind $tag <Configure> [list ::GX::_uiFieldPackedMinimum $widget $width $height]
            bind $tag <Destroy> [list ::GX::_uiFieldPackedMinimumDispose $tag]
            after idle [list ::GX::_uiFieldPackedMinimum $widget $width $height]
        }
    } else {
        grid $widget -in $parent -row [datasetPublicationV2DictDefault $layout row 0] -column [datasetPublicationV2DictDefault $layout column 0] -rowspan [datasetPublicationV2DictDefault $layout rowspan 1] -columnspan [datasetPublicationV2DictDefault $layout columnspan 1] -sticky [datasetPublicationV2DictDefault $layout sticky ew] -padx [datasetPublicationV2DictDefault $layout padding 3] -pady [datasetPublicationV2DictDefault $layout padding 3]
    }
}
proc ::GX::uiFieldComponentItemsSet {widget type items} {
    if {![winfo exists $widget] || $type ne {list} || [llength $items]>1000 || [string bytelength $items]>1048576} {error {Read-only list items require a live list and at most1000 rows/1MiB}}
    if {[winfo class $widget] ne {Listbox}} {error {Expected the shared native list component}}
    $widget delete 0 end;foreach item $items {$widget insert end $item}
    return [dict create count [llength $items] read_only 1]
}
proc ::GX::uiFieldComponentTableWidget {widget} {
    if {![winfo exists $widget]} {error {The declared read-only table has closed.}}
    if {[winfo class $widget] eq {Treeview}} {return $widget}
    if {[winfo class $widget] eq {TFrame} && [winfo exists $widget.table] && [winfo class $widget.table] eq {Treeview}} {return $widget.table}
    error {Expected a shared read-only table component.}
}
proc ::GX::uiFieldComponentTableRead {widget {selectedOnly 0}} {
    if {![string is boolean -strict $selectedOnly]} {error {Table selection flag must be boolean.}}
    set tree [uiFieldComponentTableWidget $widget]
    set ids [expr {$selectedOnly ? [$tree selection] : [$tree children {}]}]
    if {[llength $ids]>1000} {error {Read-only table comparison is bounded to 1000 rows / 4 MiB.}}
    set rows {};foreach id $ids {lappend rows [$tree item $id -values]}
    if {[string bytelength $rows]>4194304} {error {Read-only table comparison is bounded to 1000 rows / 4 MiB.}}
    return [dict create columns [$tree cget -columns] rows $rows selection [$tree selection] read_only 1]
}
proc ::GX::uiFieldComponentTableCopy {widget} {
    set table [uiFieldComponentTableRead $widget 1]
    if {![llength [dict get $table rows]]} {return 0}
    set lines {};foreach row [dict get $table rows] {
        set cells {};foreach cell $row {lappend cells [string map [list \t { } \r { } \n { }] $cell]}
        lappend lines [join $cells \t]
    }
    clipboard clear -displayof $widget;clipboard append -displayof $widget [join $lines \n]
    return [llength $lines]
}
proc ::GX::_uiFieldPackedMinimum {widget width height} {
    if {![winfo exists $widget] || [winfo manager $widget] ne {pack}} return
    set x [expr {max(0,int(ceil(($width-[winfo reqwidth $widget])/2.0)))}]
    set y [expr {max(0,int(ceil(($height-[winfo reqheight $widget])/2.0)))}]
    set current [pack info $widget]
    if {[dict get $current -ipadx]!=$x || [dict get $current -ipady]!=$y} {pack configure $widget -ipadx $x -ipady $y}
}
proc ::GX::_uiFieldPackedMinimumDispose {tag} {foreach event [bind $tag] {bind $tag $event {}}}
proc ::GX::uiFieldComponentRead {widget type} {
    if {![winfo exists $widget]} {error {The declared UI Field component has closed.}}
    if {$type eq {field} && [dict exists $::GX::UiField::widgets $widget] && [dict get $::GX::UiField::widgets $widget descriptor type] eq {color}} {
        # RGB and alpha have ordinary separate controls in the existing field.
        # Read their canonical value, not just the text of its RGB sub-entry.
        if {![uiFieldCommit $widget]} {error $::GX::UiField::errors($widget)}
        upvar #0 [dict get $::GX::UiField::widgets $widget variable] value
        return $value
    }
    if {$type eq {table}} {return [uiFieldComponentTableRead $widget]}
    if {$type in {field toggle choice dataset_selector}} {set widget $widget.entry}
    if {$type eq {list}} {
        if {[$widget size]>1000} {error {Read-only list comparison is bounded to 1000 items.}}
        return [dict create items [$widget get 0 end] selection [$widget curselection]]
    }
    if {$type eq {log}} {
        if {[$widget count -chars 1.0 end]>65536} {error {Read-only log comparison is bounded to 64 KiB.}}
        return [$widget get 1.0 end-1c]
    }
    set class [winfo class $widget]
    if {$class in {TCheckbutton Checkbutton TProgressbar}} {
        set name [$widget cget -variable]
        if {$name eq {}} {return [$widget cget -value]}
        upvar #0 $name value
        if {![info exists value]} {error {The declared UI value is unavailable.}}
        return $value
    }
    if {$class in {Entry TEntry TCombobox Spinbox TSpinbox}} {return [$widget get]}
    error {This component has no public scalar/list/log value.}
}
proc ::GX::_uiFieldComponentTextWrap {widget maximum actual width} {
    if {$actual ne $widget || ![winfo exists $widget] || $width<2} return
    set parent [winfo parent $widget]
    if {[dict exists $::GX::UiField::toolbarOverflow $parent headers $widget] &&
        [dict get $::GX::UiField::toolbarOverflow $parent multirow] &&
        [dict get $::GX::UiField::toolbarOverflow $parent wrapped]} {set maximum $width}
    # Auto-wrap may change height, but must not drive its own allocated width
    # through nested grid/notebook request negotiation. A stretched label gets
    # a constant one-character horizontal request; natural-size labels keep
    # their declared maximum and normal text-dependent request.
    set stretched 0
    switch -- [winfo manager $widget] {
        grid {
            set layout [grid info $widget];set sticky [dict get $layout -sticky]
            if {[string first e $sticky]>=0 && [string first w $sticky]>=0} {
                set parent [dict get $layout -in];set start [dict get $layout -column]
                for {set col $start} {$col<$start+[dict get $layout -columnspan]} {incr col} {
                    if {[grid columnconfigure $parent $col -weight]>0} {set stretched 1;break}
                }
            }
        }
        pack {set stretched [expr {[dict get [pack info $widget] -fill] in {x both}}]}
        default {return}
    }
    set wanted [expr {$stretched?1:0}]
    if {[$widget cget -width]!=$wanted} {$widget configure -width $wanted}
    set available [expr {[winfo width $widget]-2}]
    set padding [$widget cget -padding]
    if {$padding eq {}} {set padding [ttk::style lookup [$widget cget -style] -padding]}
    if {[llength $padding]} {
        set left [lindex $padding 0];set right [lindex $padding [expr {[llength $padding]>2?2:0}]]
        incr available [expr {-[winfo pixels $widget $left]-[winfo pixels $widget $right]}]
    }
    if {[$widget cget -compound] in {left right} && [llength [$widget cget -image]]} {
        set photo [lindex [$widget cget -image] 0]
        if {[lsearch -exact [image names] $photo]>=0} {
            set gap [ttk::style lookup [$widget cget -style] -space];if {![string is integer -strict $gap]} {set gap 4}
            incr available [expr {-[image width $photo]-$gap}]
        }
    }
    set wrap [expr {$stretched?max(1,min($maximum,$available)):$maximum}]
    if {[$widget cget -wraplength]!=$wrap} {$widget configure -wraplength $wrap}
}

# A fixed explanatory row must not consume the natural height of a weighted
# content row. Keep ordinary pages unchanged; only overflowing mixed-row pages
# acquire a native scroll viewport. Declared children keep their paths/commands.
namespace eval ::GX::UiField {variable tabOverflow {}}
proc ::GX::_uiFieldTabAttach {tab} {
    dict set ::GX::UiField::tabOverflow $tab [dict create after {} viewport {} policies {}]
    set root [winfo toplevel $tab]
    bind $root <Configure> +[list ::GX::_uiFieldTabSchedule $tab %W]
    bind $root <FocusIn> +[list ::GX::_uiFieldTabFocus $tab %W]
    foreach {event delta} {<MouseWheel> %D <Button-4> 1 <Button-5> -1} {
        bind $root $event +[list ::GX::_uiFieldTabWheel $tab %W $delta]
    }
    bind $tab <Map> +[list ::GX::_uiFieldTabSchedule $tab %W]
    bind $tab <Destroy> +[list ::GX::_uiFieldTabDispose $tab $root %W]
}
proc ::GX::_uiFieldTabSchedule {tab actual} {
    if {![dict exists $::GX::UiField::tabOverflow $tab] ||
        ($actual ne $tab && [string first "$tab." $actual]!=0)} return
    if {[dict exists $::GX::UiField::tabOverflow $tab outerFocus]} {
        dict for {viewport request} [dict get $::GX::UiField::tabOverflow $tab outerFocus] {
            lassign $request content widget anchor
            if {$actual eq $anchor} {
                # Canvas window Configure precedes grid -in's maintained
                # sibling geometry. Reveal outside only after that child moves.
                after idle [list ::GX::_uiFieldTabOuterFocus $viewport $content $widget 1]
            }
        }
    }
    if {[dict get $::GX::UiField::tabOverflow $tab after] eq {}} {
        dict set ::GX::UiField::tabOverflow $tab after [after idle [list ::GX::_uiFieldTabLayout $tab]]
    }
}
proc ::GX::_uiFieldTabLayout {tab} {
    if {![dict exists $::GX::UiField::tabOverflow $tab]} return
    dict set ::GX::UiField::tabOverflow $tab after {}
    if {![winfo exists $tab] || ![winfo ismapped $tab] || [winfo height $tab]<2} return
    set state [dict get $::GX::UiField::tabOverflow $tab]
    set viewport [dict get $state viewport]
    set host [expr {$viewport eq {} ? $tab : "$viewport.content"}]
    set children [grid slaves $host]
    if {![llength $children]} return
    set natural [winfo reqheight $host]
    # The tab's frame padding remains outside its scroll viewport.
    set room [expr {$viewport eq {} ? [winfo height $tab] : [winfo height $viewport]}]
    if {$viewport eq {}} {
        set weighted 0;set fixed 0
        foreach child $children {
            set row [dict get [grid info $child] -row]
            if {[grid rowconfigure $tab $row -weight]>0} {set weighted 1} else {set fixed 1}
        }
        if {!$weighted || !$fixed || $natural<=$room} return
        set policies {}
        lassign [grid size $tab] columns rows
        foreach {axis count} [list column $columns row $rows] {
            for {set n 0} {$n<$count} {incr n} {
                dict set policies $axis $n [grid ${axis}configure $tab $n]
            }
        }
        set viewport $tab.__uiFieldViewport
        set background [ttk::style lookup TFrame -background]
        if {$background eq {}} {set background #d9d9d9}
        canvas $viewport -highlightthickness 0 -borderwidth 0 -width 1 -height 1 -yscrollincrement 24 -background $background
        ttk::frame $viewport.content
        ttk::scrollbar $tab.__uiFieldBar -command [list $viewport yview]
        $viewport configure -yscrollcommand [list $tab.__uiFieldBar set]
        $viewport create window 0 0 -anchor nw -window $viewport.content -tags content
        foreach child $children {grid configure $child -in $viewport.content}
        dict for {axis entries} $policies {
            dict for {n policy} $entries {
                grid ${axis}configure $viewport.content $n {*}$policy
                grid ${axis}configure $tab $n -weight 0 -minsize 0 -pad 0 -uniform {}
            }
        }
        grid $viewport -row 0 -column 0 -sticky nsew
        grid $tab.__uiFieldBar -row 0 -column 1 -sticky ns
        grid rowconfigure $tab 0 -weight 1
        grid columnconfigure $tab 0 -weight 1
        # Geometry -in preserves each declared child's native parent. Those
        # older siblings must remain above the new viewport's opaque window.
        foreach child [lreverse $children] {raise $child}
        dict set ::GX::UiField::tabOverflow $tab viewport $viewport
        dict set ::GX::UiField::tabOverflow $tab policies $policies
        _uiFieldTabSchedule $tab $tab
        return
    }
    if {$natural<=$room} {
        # Return to the original grid when resizing/font restoration makes room.
        foreach child $children {grid configure $child -in $tab}
        grid forget $viewport $tab.__uiFieldBar
        lassign [grid size $tab] columns rows
        foreach {axis count} [list column $columns row $rows] {
            for {set n 0} {$n<$count} {incr n} {grid ${axis}configure $tab $n -weight 0 -minsize 0 -pad 0 -uniform {}}
        }
        dict for {axis entries} [dict get $state policies] {
            dict for {n policy} $entries {grid ${axis}configure $tab $n {*}$policy}
        }
        dict set ::GX::UiField::tabOverflow $tab viewport {}
        dict set ::GX::UiField::tabOverflow $tab policies {}
        destroy $viewport $tab.__uiFieldBar
        return
    }
    set width [winfo width $viewport]
    set height [expr {max($natural,$room)}]
    if {[$viewport itemcget content -width]!=$width || [$viewport itemcget content -height]!=$height} {
        $viewport itemconfigure content -width $width -height $height
    }
    $viewport configure -scrollregion [list 0 0 $width $height]
}
proc ::GX::_uiFieldTabFocus {tab widget} {
    if {![dict exists $::GX::UiField::tabOverflow $tab] || ![winfo exists $widget] ||
        $widget ne [focus -displayof $widget] || [string first "$tab." $widget]!=0} return
    set viewport [dict get $::GX::UiField::tabOverflow $tab viewport]
    if {$viewport ne {}} {uiFieldScrollSee $viewport $viewport.content $widget}
}
proc ::GX::_uiFieldTabWheel {tab widget delta} {
    if {![dict exists $::GX::UiField::tabOverflow $tab] || ![winfo exists $widget] ||
        [string first "$tab." $widget]!=0} return
    set viewport [dict get $::GX::UiField::tabOverflow $tab viewport]
    if {$viewport eq {} || ($widget ne $viewport && [winfo class $widget] in {Treeview Listbox Text Canvas})} return
    # A nested scrolling page/editor keeps its native wheel ownership.
    if {[_uiFieldTabViewportFor $widget] ne $viewport} return
    $viewport yview scroll [expr {$delta>0?-3:3}] units
}
proc ::GX::_uiFieldTabViewportFor {widget} {
    while {$widget ne {} && [winfo exists $widget]} {
        if {[dict exists $::GX::UiField::tabOverflow $widget] &&
            [dict get $::GX::UiField::tabOverflow $widget viewport] ne {}} {
            return [dict get $::GX::UiField::tabOverflow $widget viewport]
        }
        set widget [winfo parent $widget]
    }
    return {}
}
proc ::GX::_uiFieldTabOuterFocus {viewport content widget {settled 0}} {
    if {![winfo exists $viewport] || ![winfo exists $content] || ![winfo exists $widget] ||
        $widget ne [focus -displayof $widget]} return
    set inner [_uiFieldTabViewportFor $widget]
    if {$inner ne {}} {
        set tab [winfo parent $inner]
        if {$settled} {
            if {[dict exists $::GX::UiField::tabOverflow $tab outerFocus $viewport]} {
                dict unset ::GX::UiField::tabOverflow $tab outerFocus $viewport
            }
        } else {
            set anchor $widget
            while {[winfo parent $anchor] ne $tab && [winfo parent $anchor] ne {}} {set anchor [winfo parent $anchor]}
            dict set ::GX::UiField::tabOverflow $tab outerFocus $viewport [list $content $widget $anchor]
        }
    }
    uiFieldScrollSee $viewport $content $widget
}
proc ::GX::_uiFieldTabDispose {tab root actual} {
    if {$actual ne $tab || ![dict exists $::GX::UiField::tabOverflow $tab]} return
    set pending [dict get $::GX::UiField::tabOverflow $tab after]
    if {$pending ne {}} {after cancel $pending}
    dict unset ::GX::UiField::tabOverflow $tab
    if {![winfo exists $root]} return
    foreach {event callback} [list <Configure> [list ::GX::_uiFieldTabSchedule $tab %W] <FocusIn> [list ::GX::_uiFieldTabFocus $tab %W] <MouseWheel> [list ::GX::_uiFieldTabWheel $tab %W %D] <Button-4> [list ::GX::_uiFieldTabWheel $tab %W 1] <Button-5> [list ::GX::_uiFieldTabWheel $tab %W -1]] {
        set keep {};foreach line [split [bind $root $event] \n] {if {$line ne $callback} {lappend keep $line}}
        bind $root $event [join $keep \n]
    }
}
proc ::GX::uiFieldScrollableCreate {frame {width 320}} {
    ttk::frame $frame
    set background [ttk::style lookup TFrame -background];if {$background eq {}} {set background #d9d9d9}
    canvas $frame.scroll -highlightthickness 0 -width $width -height 300 -yscrollincrement 24 -background $background
    ttk::scrollbar $frame.bar -command [list $frame.scroll yview]
    $frame.scroll configure -yscrollcommand [list $frame.bar set]
    ttk::frame $frame.scroll.content
    $frame.scroll create window 0 0 -anchor nw -window $frame.scroll.content -tags content
    bind $frame.scroll <Configure> [list $frame.scroll itemconfigure content -width %w]
    bind $frame.scroll.content <Configure> [list $frame.scroll configure -scrollregion [list 0 0 %w %h]]
    pack $frame.bar -side right -fill y;pack $frame.scroll -fill both -expand 1
    set root [winfo toplevel $frame]
    # Descendant bindtags contain the toplevel path, not the toplevel's own
    # extra tags. Bind that existing path so real child focus and wheels arrive.
    bind $root <FocusIn> +[list ::GX::_uiFieldScrollableFocus $frame %W]
    bind $root <MouseWheel> +[list ::GX::_uiFieldScrollableWheel $frame %W %D]
    foreach {event delta} {<Button-4> 1 <Button-5> -1} {bind $root $event +[list ::GX::_uiFieldScrollableWheel $frame %W $delta]}
    bind $frame <Destroy> [list ::GX::_uiFieldScrollableDispose $frame $root %W]
    return $frame.scroll.content
}
proc ::GX::_uiFieldScrollableFocus {frame widget} {
    if {[winfo exists $frame] && $widget eq [focus -displayof $frame] && [string match $frame.scroll.content.* $widget]} {
        if {[_uiFieldTabViewportFor $widget] ne {}} {
            after idle [list after idle [list ::GX::_uiFieldTabOuterFocus $frame.scroll $frame.scroll.content $widget]]
        } else {uiFieldScrollSee $frame.scroll $frame.scroll.content $widget}
    }
}
proc ::GX::_uiFieldScrollableWheel {frame widget delta} {
    if {![winfo exists $frame] || ![string match $frame.* $widget]} return
    if {[_uiFieldTabViewportFor $widget] ne {}} return
    if {$widget ne "${frame}.scroll" && [winfo class $widget] in {Treeview Listbox Text Canvas}} return
    $frame.scroll yview scroll [expr {$delta>0 ? -3 : 3}] units
}
proc ::GX::_uiFieldScrollableDispose {frame root actual} {
    if {$frame ne $actual} return
    if {![winfo exists $root]} return
    foreach {event callback} [list <FocusIn> [list ::GX::_uiFieldScrollableFocus $frame %W] <MouseWheel> [list ::GX::_uiFieldScrollableWheel $frame %W %D] <Button-4> [list ::GX::_uiFieldScrollableWheel $frame %W 1] <Button-5> [list ::GX::_uiFieldScrollableWheel $frame %W -1]] {
        set keep {};foreach line [split [bind $root $event] \n] {if {$line ne $callback} {lappend keep $line}}
        bind $root $event [join $keep \n]
    }
}
# Public maintained scrolling for an existing canvas/content pair. Descendant
# bindtags include the toplevel path; blank group areas receive the same routing
# as their controls. Embedded editors/trees retain their own native wheel input.
proc ::GX::uiFieldScrollAreaAttach {viewport content} {
    if {[winfo class $viewport] ne {Canvas} || ![string match $viewport.* $content]} {error {Scroll area requires its own Canvas content descendant}}
    set root [winfo toplevel $viewport]
    foreach {event delta} {<MouseWheel> %D <Button-4> 1 <Button-5> -1} {
        set callback [list ::GX::_uiFieldScrollAreaWheel $viewport $content %W $delta]
        if {[lsearch -exact [split [bind $root $event] \n] $callback]<0} {bind $root $event +$callback}
    }
    bind $viewport <Destroy> +[list ::GX::_uiFieldScrollAreaDispose $viewport $content $root %W]
}
proc ::GX::_uiFieldScrollAreaWheel {viewport content widget delta} {
    if {![winfo exists $viewport] || ($widget ne $viewport && $widget ne $content && ![string match $content.* $widget])} return
    if {[_uiFieldTabViewportFor $widget] ne {}} return
    if {$widget ne $viewport && [winfo class $widget] in {Treeview Listbox Text Canvas}} return
    $viewport yview scroll [expr {$delta>0?-3:3}] units
}
proc ::GX::_uiFieldScrollAreaDispose {viewport content root actual} {
    if {$actual ne $viewport || ![winfo exists $root]} return
    foreach {event delta} {<MouseWheel> %D <Button-4> 1 <Button-5> -1} {
        set callback [list ::GX::_uiFieldScrollAreaWheel $viewport $content %W $delta]
        set keep {};foreach line [split [bind $root $event] \n] {if {$line ne $callback} {lappend keep $line}}
        bind $root $event [join $keep \n]
    }
}
proc ::GX::_uiFieldDatasetClear {widget} {
    if {![winfo exists $widget] || [$widget instate disabled] || {} ni [$widget cget -values]} return
    $widget set {}
    # Use the same normal change notification as a finite native choice.
    event generate $widget <<ComboboxSelected>>
}
proc ::GX::uiFieldDatasetChoices {{contentKind {}} {allowEmpty 0}} {
    if {$contentKind ni {{} html pdf code table raster}} {error {Unsupported canonical Dataset content_kind}}
    if {![string is boolean -strict $allowEmpty]} {error {Dataset selector allow_empty must be boolean}}
    set ids [dict get [datasetCatalogSnapshot] dataset_ids]
    set result {}
    if {$allowEmpty} {lappend result {}}
    if {$contentKind eq {}} {return [concat $result $ids]}
    foreach id $ids {
        if {$contentKind eq {raster}} {
            if {[datasetField $id contract [datasetField $id kind {}]] eq {image.raster}} {lappend result $id}
            continue
        }
        if {![catch {viewerGuiDocumentCompatible $id $contentKind} compatible] && $compatible} {lappend result $id}
    }
    return $result
}
proc ::GX::uiFieldViewerRegionsSet {window regions} {
    foreach region $regions {if {$region ni {toolbar inspector canvas footer}} {error {Unknown Viewer region.}}}
    set inspector $window.body.inspector
    if {{inspector} in $regions} {
        if {$inspector ni [$window.body panes]} {$window.body insert 0 $inspector -weight 0}
    } elseif {$inspector in [$window.body panes]} {$window.body forget $inspector}
    foreach region {toolbar footer} {
        set widget $window.$region
        if {$region in $regions} {
            if {[winfo manager $widget] eq {}} {pack $widget -fill x -side [expr {$region eq {footer} ? {bottom} : {top}}] -before $window.body}
        } else {pack forget $widget}
    }
}

# Independent checkbox state is distinct from current-row focus/selection.
namespace eval ::GX::UiCheckTable {variable checked;variable callback}
proc ::GX::uiFieldCheckTableCreate {widget columns callback} {
    ttk::treeview $widget -columns $columns -show {tree headings} -selectmode browse
    $widget heading #0 -text {Show};$widget column #0 -width 52 -stretch 0
    set ::GX::UiCheckTable::checked($widget) {};set ::GX::UiCheckTable::callback($widget) $callback
    bind $widget <ButtonRelease-1> [list ::GX::_uiFieldCheckTableClick $widget %x %y]
    bind $widget <Key-space> "[list ::GX::uiFieldCheckTableToggle $widget];break"
    bind $widget <Destroy> [list ::GX::_uiFieldCheckTableDestroy $widget %W]
    return $widget
}
proc ::GX::_uiFieldCheckTableDestroy {widget actual} {if {$actual eq $widget} {unset -nocomplain ::GX::UiCheckTable::checked($widget) ::GX::UiCheckTable::callback($widget)}}
proc ::GX::_uiFieldCheckTableClick {widget x y} {if {[$widget identify column $x $y] eq {#0}} {set id [$widget identify row $x $y];if {$id ne {}} {uiFieldCheckTableToggle $widget $id}}}
proc ::GX::uiFieldCheckTableToggle {widget {id {}}} {
    if {$id eq {}} {set id [lindex [$widget selection] 0]}
    if {$id eq {} || ![$widget exists $id]} return
    set current $::GX::UiCheckTable::checked($widget);set i [lsearch -exact $current $id]
    if {$i<0} {lappend current $id} else {set current [lreplace $current $i $i]}
    uiFieldCheckTableSet $widget $current
    set command $::GX::UiCheckTable::callback($widget);if {$command ne {}} {uplevel #0 $command}
}
proc ::GX::uiFieldCheckTableSet {widget ids} {
    set ::GX::UiCheckTable::checked($widget) [lsort -unique $ids]
    foreach row [$widget children {}] {$widget item $row -text [expr {$row in $ids ? {☑}:{☐}}]}
}
proc ::GX::uiFieldCheckTableGet {widget} {return $::GX::UiCheckTable::checked($widget)}
