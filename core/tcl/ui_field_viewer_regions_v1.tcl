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
    $mapped sashpos 0 $width
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
