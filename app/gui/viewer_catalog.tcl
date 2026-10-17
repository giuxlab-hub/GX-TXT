# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::ViewerCatalog {variable images {};variable signature {};variable refreshing 0}
proc ::GX::viewerCatalogIcon {provider} {
    variable ::GX::ViewerCatalog::images
    set path [dict get $provider icon_path]
    if {$path eq {}} {set path [file join $::GX::scriptDir app icons viewer_fallback.png]}
    set desired [expr {max(64,min(192,int([tk scaling]*48)))}]
    set factor [expr {max(1,int(192/$desired))}];set key [list $path $factor]
    if {![dict exists $images $key]} {
        set master [image create photo -file $path];set photo [image create photo]
        $photo copy $master -subsample $factor $factor;image delete $master
        dict set images $key $photo
    }
    return [dict get $images $key]
}
proc ::GX::viewerGuiBuild {notebook} {
    variable ui
    set frame $notebook.viewers;ttk::frame $frame -padding 12
    $notebook add $frame -text Viewers
    ttk::frame $frame.tools;pack $frame.tools -fill x -pady {0 10}
    ttk::label $frame.tools.title -text {Scientific Viewers} -font TkHeadingFont
    ttk::label $frame.tools.searchLabel -text Search
    set ui(viewerQuery) {};ttk::entry $frame.tools.search -textvariable ::GX::ui(viewerQuery) -width 28
    ttk::button $frame.tools.refresh -text Refresh -command ::GX::viewerGuiRefresh
    pack $frame.tools.title -side left -padx {0 24}
    pack $frame.tools.refresh $frame.tools.search $frame.tools.searchLabel -side right -padx 5
    canvas $frame.viewport -highlightthickness 0 -background #f5f7fa -yscrollincrement 30
    ttk::scrollbar $frame.scroll -command [list $frame.viewport yview]
    $frame.viewport configure -yscrollcommand [list $frame.scroll set]
    ttk::frame $frame.viewport.content -padding 10
    $frame.viewport create window 0 0 -anchor nw -window $frame.viewport.content -tags content
    pack $frame.scroll -side right -fill y;pack $frame.viewport -fill both -expand 1
    bind $frame.viewport <Configure> [list ::GX::viewerCatalogLayout $frame %w]
    bind $frame.viewport.content <Configure> [list $frame.viewport configure -scrollregion [list 0 0 %w %h]]
    foreach {sequence delta} {<Button-4> -3 <Button-5> 3} {bind $frame.viewport $sequence [list $frame.viewport yview scroll $delta units]}
    bind $frame.tools.search <KeyRelease> ::GX::viewerGuiRefresh
    bind $notebook <<NotebookTabChanged>> +::GX::viewerGuiRefresh
    set ::GX::ViewerCatalog::signature {}
    viewerGuiRefresh
}
proc ::GX::viewerCatalogLayout {frame width} {
    if {![winfo exists $frame.viewport.content]} return
    $frame.viewport itemconfigure content -width $width
    set tileWidth 182
    foreach group [winfo children $frame.viewport.content] {foreach tile [winfo children $group] {set tileWidth [expr {max($tileWidth,[winfo reqwidth $tile]+14)}]}}
    set columns [expr {max(1,int(($width-38)/$tileWidth))}]
    foreach group [winfo children $frame.viewport.content] {
        set index 0
        foreach tile [winfo children $group] {
            grid $tile -row [expr {$index/$columns}] -column [expr {$index%$columns}] -sticky nsew -padx 7 -pady 8
            incr index
        }
    }
}
proc ::GX::viewerGuiRefresh {} {
    variable ui;variable ::GX::ViewerCatalog::signature;variable ::GX::ViewerCatalog::refreshing
    set f .top.nb.viewers
    if {$refreshing || ![winfo exists $f.viewport]} return
    set refreshing 1
    try {
        set providers [viewerProviderCatalog]
        set wanted [list $providers $ui(viewerQuery)]
        if {$wanted eq $signature} return
        set signature $wanted
        foreach child [winfo children $f.viewport.content] {destroy $child}
        set groups {};set ordinal 0
        foreach provider $providers {
            if {![dict get $provider enabled]} continue
            set query [string tolower [string trim $ui(viewerQuery)]]
            if {$query ne {} && [string first $query [string tolower "[dict get $provider short_title] [dict get $provider name] [dict get $provider group_title]"]]<0} continue
            set group [dict get $provider semantic_group]
            if {![dict exists $groups $group]} {
                set panel $f.viewport.content.g[dict size $groups]
                ttk::labelframe $panel -text [dict get $provider group_title] -padding 6
                pack $panel -fill x -pady {0 14};dict set groups $group $panel
            }
            set tile [dict get $groups $group].tile[incr ordinal]
            set module [dict get $provider module_id];set viewer [dict get $provider viewer_id]
            ttk::button $tile -text [dict get $provider short_title] -image [viewerCatalogIcon $provider] -compound top -padding {10 10} -width 18 -command [list ::GX::viewerGuiDispatch open $module $viewer]
            bind $tile <Return> [list ::GX::viewerGuiDispatch open $module $viewer]
            bind $tile <FocusIn> [list ::GX::uiFieldScrollSee $f.viewport $f.viewport.content $tile]
            bind $tile <Enter> [list ::GX::native2DViewportTooltipShow $tile "[dict get $provider name]\n[dict get $provider group_title]\n$module / $viewer"]
            bind $tile <Leave> {catch {destroy .gxViewportTip}}
            foreach {sequence delta} {<Button-4> -3 <Button-5> 3} {bind $tile $sequence [list $f.viewport yview scroll $delta units]}
        }
        viewerCatalogLayout $f [winfo width $f.viewport]
    } finally {set refreshing 0}
}
proc ::GX::viewerGuiDispatch {action {module {}} {viewer {}}} {
    if {$module eq {} || $viewer eq {}} {return}
    if {[catch {if {$action eq "open"} {viewerOpen $module $viewer} else {viewerRerender $module $viewer}} message]} {setStatus $message 0}
}
proc ::GX::viewerManagerBuild {parent} {
    ttk::frame $parent.tools
    ttk::label $parent.tools.note -text {Enable or disable Viewer presentation. Changes apply on next open; active Workspaces and required scientific services remain available.} -wraplength 950
    pack $parent.tools.note -fill x -pady 5
    foreach {name label value} {enable Enable 1 disable Disable 0} {ttk::button $parent.tools.$name -text $label -command [list ::GX::viewerManagerSet $parent $value];pack $parent.tools.$name -side left -padx 5}
    ttk::button $parent.tools.refresh -text Refresh -command [list ::GX::viewerManagerRefresh $parent];pack $parent.tools.refresh -side left -padx 5
    pack $parent.tools -side top -fill x -padx 8 -pady 8
    ttk::style configure GXViewerManager.Treeview -rowheight 74
    ttk::treeview $parent.tree -style GXViewerManager.Treeview -columns {group module state} -show {tree headings} -selectmode browse
    $parent.tree heading #0 -text Viewer;$parent.tree column #0 -width 280
    foreach {id label width} {group Category 210 module Module 260 state Presentation 150} {$parent.tree heading $id -text $label;$parent.tree column $id -width $width}
    ttk::scrollbar $parent.scroll -command [list $parent.tree yview];$parent.tree configure -yscrollcommand [list $parent.scroll set]
    pack $parent.scroll -side right -fill y;pack $parent.tree -fill both -expand 1 -padx 8 -pady 8
    viewerManagerRefresh $parent
}
proc ::GX::viewerManagerRefresh {parent} {
    $parent.tree delete [$parent.tree children {}]
    set rowHeight 74
    foreach provider [viewerProviderCatalog] {
        set rowHeight [expr {max($rowHeight,[image height [viewerCatalogIcon $provider]]+10)}]
        set module [dict get $provider module_id];set viewer [dict get $provider viewer_id]
        $parent.tree insert {} end -id $module/$viewer -text [dict get $provider short_title] -image [viewerCatalogIcon $provider] -values [list [dict get $provider group_title] $module [expr {[dict get $provider enabled]?"Enabled":"Disabled"}]]
    }
    ttk::style configure GXViewerManager.Treeview -rowheight $rowHeight
}
proc ::GX::viewerManagerSet {parent value} {
    set selected [$parent.tree selection]
    if {$selected eq {}} return
    lassign [split [lindex $selected 0] /] module viewer
    if {[catch {viewerProviderSetEnabled $module $viewer $value} message]} {$parent.tools.note configure -text $message;return}
    viewerManagerRefresh $parent
    $parent.tree selection set $selected;$parent.tree see $selected
}
