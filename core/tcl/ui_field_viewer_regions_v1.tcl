# SPDX-License-Identifier: GPL-3.0-or-later
# Additive UI Field shell primitive. No Viewer/scientific state is stored here.
proc ::GX::uiFieldViewerShellCreate {window title {geometry 1100x720} {inspectorWidth 320}} {
    if {[winfo exists $window]} {error {Viewer window already exists}}
    toplevel $window;wm title $window $title;wm geometry $window $geometry;wm minsize $window 640 400
    menu $window.menus -tearoff 0;$window configure -menu $window.menus
    ttk::frame $window.toolbar -padding 4;pack $window.toolbar -fill x
    ttk::frame $window.footer;pack $window.footer -side bottom -fill x
    ttk::label $window.footer.status -anchor w;pack $window.footer.status -fill x
    ttk::panedwindow $window.body -orient horizontal;pack $window.body -fill both -expand 1
    ttk::frame $window.body.inspector -width $inspectorWidth;ttk::frame $window.body.canvas
    $window.body add $window.body.inspector -weight 0;$window.body add $window.body.canvas -weight 1
    canvas $window.body.inspector.scroll -highlightthickness 0 -width $inspectorWidth -yscrollincrement 24
    ttk::scrollbar $window.body.inspector.bar -command [list $window.body.inspector.scroll yview]
    $window.body.inspector.scroll configure -yscrollcommand [list $window.body.inspector.bar set]
    ttk::frame $window.body.inspector.scroll.content -padding 6
    $window.body.inspector.scroll create window 0 0 -anchor nw -window $window.body.inspector.scroll.content -tags content
    bind $window.body.inspector.scroll <Configure> [list $window.body.inspector.scroll itemconfigure content -width %w]
    bind $window.body.inspector.scroll.content <Configure> [list $window.body.inspector.scroll configure -scrollregion [list 0 0 %w %h]]
    foreach {sequence delta} {<Button-4> -3 <Button-5> 3} {bind $window.body.inspector.scroll $sequence [list $window.body.inspector.scroll yview scroll $delta units]}
    bind $window <FocusIn> +[list ::GX::_uiFieldViewerInspectorFocus $window %W]
    bind $window.body <Map> +[list ::GX::_uiFieldViewerInitialSplit $window $inspectorWidth %W]
    bind $window <MouseWheel> +[list ::GX::_uiFieldViewerWheel $window %W %D]
    foreach {event delta} {<Button-4> 1 <Button-5> -1} {bind $window $event +[list ::GX::_uiFieldViewerWheel $window %W $delta]}
    pack $window.body.inspector.bar -side right -fill y;pack $window.body.inspector.scroll -fill both -expand 1
    return [dict create window $window toolbar $window.toolbar inspector $window.body.inspector.scroll.content canvas $window.body.canvas footer $window.footer status $window.footer.status]
}

proc ::GX::_uiFieldViewerInitialSplit {window width mapped} {
    if {$mapped ne "$window.body" || ![winfo exists $mapped]} return
    if {[llength [$mapped panes]]>1} {$mapped sashpos 0 $width}
    bind $mapped <Map> {}
}
proc ::GX::_uiFieldViewerWheel {window widget delta} {
    if {[string first "$window.body.inspector." $widget]!=0} return
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
    set content $window.body.inspector.scroll.content
    if {[string first "$content." $widget]==0} {uiFieldScrollSee $window.body.inspector.scroll $content $widget}
}

# Declarative construction under the existing UI Field authority. The Builder
# and installed generated Viewers consume this same public constructor.
proc ::GX::uiFieldComponentCapabilities {} {
    set result {}
    foreach {type description properties} {
        panel {Responsive grid container} {title string}
        section {Labelled inspector section} {title string padding number}
        splitter {Resizable container} {orientation choice}
        tabs {Tabbed container} {}
        tab {Page inside a tab container} {title string}
        label {Plain descriptive text} {text string wraplength number}
        entry {Plain value entry; domain owner validates} {default string width number}
        combobox {Native bounded choice without a field wrapper} {default string choices list width number}
        checkbutton {Native boolean control without a field wrapper} {label string default boolean}
        list {Native read-only item list and selection} {items list height number selectmode choice}
        field {Validated typed value} {label string datatype choice default string choices list min number max number}
        action {ViewerCommands action button} {label string action identifier tooltip string shortcut string}
        toggle {Boolean value} {label string default boolean}
        choice {Bounded choice selector} {label string default string choices list}
        dataset_selector {Live canonical Dataset selector} {label string}
        status {Read-only status text} {text string}
        progress {Determinate progress display} {maximum number}
        log {Read-only diagnostic text} {text string height number width number}
        table {Read-only table; no Worksheet editing} {columns list}
    } {
        dict set result $type [dict create label $description api_id UI_FIELD_API_v1 api_version 1 owner core/tcl/ui_field_viewer_regions_v1.tcl properties $properties events [expr {$type in {field toggle choice dataset_selector entry combobox checkbutton list} ? {changed} : ($type eq {action} ? {invoke} : {})}] status AVAILABLE]
    }
    return $result
}
proc ::GX::uiFieldComponentCreate {widget type properties variableName callback} {
    if {![dict exists [uiFieldComponentCapabilities] $type]} {error {Unsupported public UI Field component.}}
    set label [datasetPublicationV2DictDefault $properties label {}]
    switch $type {
        panel - tab {ttk::frame $widget -padding 4}
        section {ttk::labelframe $widget -text [datasetPublicationV2DictDefault $properties title Section] -padding [datasetPublicationV2DictDefault $properties padding 6]}
        splitter {ttk::panedwindow $widget -orient [datasetPublicationV2DictDefault $properties orientation horizontal]}
        tabs {ttk::notebook $widget}
        label - status {ttk::label $widget -text [datasetPublicationV2DictDefault $properties text {}] -anchor w -justify left -wraplength [datasetPublicationV2DictDefault $properties wraplength 400]}
        entry {ttk::entry $widget -textvariable $variableName -width [datasetPublicationV2DictDefault $properties width 20];if {$callback ne {}} {bind $widget <Return> $callback;bind $widget <FocusOut> $callback}}
        combobox {ttk::combobox $widget -state readonly -textvariable $variableName -values [datasetPublicationV2DictDefault $properties choices {}] -width [datasetPublicationV2DictDefault $properties width 20];uiFieldSelectorWithinViewer $widget [winfo toplevel $widget];if {$callback ne {}} {bind $widget <<ComboboxSelected>> $callback}}
        checkbutton {ttk::checkbutton $widget -text $label -variable $variableName -command $callback}
        list {listbox $widget -height [datasetPublicationV2DictDefault $properties height 6] -exportselection 0 -selectmode [datasetPublicationV2DictDefault $properties selectmode browse];foreach item [datasetPublicationV2DictDefault $properties items {}] {$widget insert end $item};if {$callback ne {}} {bind $widget <<ListboxSelect>> $callback}}
        field - toggle - choice {
            set datatype [dict get {field string toggle boolean choice choice} $type]
            set datatype [datasetPublicationV2DictDefault $properties datatype $datatype]
            set descriptor [dict create type $datatype label $label default [datasetPublicationV2DictDefault $properties default [expr {$datatype eq {boolean} ? 0 : {}}]] compact 1]
            foreach name {min max} {if {[dict exists $properties $name]} {dict set descriptor $name [dict get $properties $name]}}
            if {$datatype eq {choice}} {dict set descriptor values [datasetPublicationV2DictDefault $properties choices {}]}
            uiFieldCreate $widget $descriptor $variableName $callback
            if {$label ne {}} {
                ttk::label $widget.caption -text $label -anchor w
                grid $widget.caption -row 0 -column 0 -sticky ew
                grid configure $widget.entry -row 1
                if {[winfo exists $widget.reset]} {grid configure $widget.reset -row 1}
            }
            if {$datatype eq {choice}} {uiFieldSelectorWithinViewer $widget.entry [winfo toplevel $widget]}
        }
        action {ttk::button $widget -text $label -command $callback;set tip [datasetPublicationV2DictDefault $properties tooltip {}];if {$tip ne {}} {bind $widget <Enter> [list ::GX::plotsToolbarTipSchedule $widget $tip];bind $widget <Leave> ::GX::plotsToolbarTipHide}}
        dataset_selector {
            ttk::frame $widget
            ttk::label $widget.caption -text $label -anchor w
            ttk::combobox $widget.entry -state readonly -textvariable $variableName
            pack $widget.caption $widget.entry -fill x
            datasetSelectorAttach $widget.entry [list ::GX::uiFieldDatasetChoices]
            bind $widget.entry <<ComboboxSelected>> $callback
            uiFieldSelectorWithinViewer $widget.entry [winfo toplevel $widget]
        }
        progress {ttk::progressbar $widget -mode determinate -maximum [datasetPublicationV2DictDefault $properties maximum 100] -variable $variableName}
        log {text $widget -height [datasetPublicationV2DictDefault $properties height 6] -width [datasetPublicationV2DictDefault $properties width 32] -wrap word;$widget insert 1.0 [datasetPublicationV2DictDefault $properties text {}];$widget configure -state disabled}
        table {
            set columns [datasetPublicationV2DictDefault $properties columns {Column}]
            ttk::treeview $widget -columns $columns -show headings -height 5
            foreach column $columns {$widget heading $column -text $column;$widget column $column -width 100 -minwidth 40}
        }
    }
    return $widget
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
    set root [winfo toplevel $frame];set tag GXScrollFrame$frame
    bindtags $root [linsert [bindtags $root] 0 $tag]
    bind $tag <FocusIn> [list ::GX::_uiFieldScrollableFocus $frame %W]
    bind $tag <MouseWheel> [list ::GX::_uiFieldScrollableWheel $frame %W %D]
    foreach {event delta} {<Button-4> 1 <Button-5> -1} {bind $tag $event [list ::GX::_uiFieldScrollableWheel $frame %W $delta]}
    bind $frame <Destroy> [list ::GX::_uiFieldScrollableDispose $frame $root $tag %W]
    return $frame.scroll.content
}
proc ::GX::_uiFieldScrollableFocus {frame widget} {if {[winfo exists $frame] && [string match $frame.scroll.content.* $widget]} {uiFieldScrollSee $frame.scroll $frame.scroll.content $widget}}
proc ::GX::_uiFieldScrollableWheel {frame widget delta} {
    if {![winfo exists $frame] || ![string match $frame.* $widget]} return
    if {$widget ne $frame.scroll && [winfo class $widget] in {Treeview Listbox Text Canvas}} return
    $frame.scroll yview scroll [expr {$delta>0 ? -3 : 3}] units
}
proc ::GX::_uiFieldScrollableDispose {frame root tag actual} {
    if {$frame ne $actual} return
    foreach sequence [bind $tag] {bind $tag $sequence {}}
    if {[winfo exists $root]} {set tags [bindtags $root];set at [lsearch -exact $tags $tag];if {$at>=0} {bindtags $root [lreplace $tags $at $at]}}
}
proc ::GX::uiFieldDatasetChoices {} {return [dict get [datasetCatalogSnapshot] dataset_ids]}
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
