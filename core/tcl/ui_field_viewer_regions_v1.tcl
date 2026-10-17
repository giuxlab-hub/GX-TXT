# SPDX-License-Identifier: GPL-3.0-or-later
# Additive UI Field shell primitive. No Viewer/scientific state is stored here.
proc ::GX::uiFieldViewerShellCreate {window title {geometry 1100x720}} {
    if {[winfo exists $window]} {error {Viewer window already exists}}
    toplevel $window;wm title $window $title;wm geometry $window $geometry;wm minsize $window 640 400
    menu $window.menus -tearoff 0;$window configure -menu $window.menus
    ttk::frame $window.toolbar -padding 4;pack $window.toolbar -fill x
    ttk::frame $window.footer;pack $window.footer -side bottom -fill x
    ttk::label $window.footer.status -anchor w;pack $window.footer.status -fill x
    ttk::panedwindow $window.body -orient horizontal;pack $window.body -fill both -expand 1
    ttk::frame $window.body.inspector -width 280;ttk::frame $window.body.canvas
    $window.body add $window.body.inspector -weight 0;$window.body add $window.body.canvas -weight 1
    canvas $window.body.inspector.scroll -highlightthickness 0 -width 280
    ttk::scrollbar $window.body.inspector.bar -command [list $window.body.inspector.scroll yview]
    $window.body.inspector.scroll configure -yscrollcommand [list $window.body.inspector.bar set]
    ttk::frame $window.body.inspector.scroll.content -padding 6
    $window.body.inspector.scroll create window 0 0 -anchor nw -window $window.body.inspector.scroll.content -tags content
    bind $window.body.inspector.scroll <Configure> [list $window.body.inspector.scroll itemconfigure content -width %w]
    bind $window.body.inspector.scroll.content <Configure> [list $window.body.inspector.scroll configure -scrollregion [list 0 0 %w %h]]
    foreach {sequence delta} {<Button-4> -3 <Button-5> 3} {bind $window.body.inspector.scroll $sequence [list $window.body.inspector.scroll yview scroll $delta units]}
    bind $window <FocusIn> +[list ::GX::_uiFieldViewerInspectorFocus $window %W]
    pack $window.body.inspector.bar -side right -fill y;pack $window.body.inspector.scroll -fill both -expand 1
    return [dict create window $window toolbar $window.toolbar inspector $window.body.inspector.scroll.content canvas $window.body.canvas footer $window.footer status $window.footer.status]
}

proc ::GX::_uiFieldViewerInspectorFocus {window widget} {
    set content $window.body.inspector.scroll.content
    if {[string first "$content." $widget]==0} {uiFieldScrollSee $window.body.inspector.scroll $content $widget}
}
