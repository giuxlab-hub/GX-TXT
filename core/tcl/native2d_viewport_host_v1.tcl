# SPDX-License-Identifier: GPL-3.0-or-later
# Tk chrome is a sibling of the geometry canvas. Placement never touches Native
# view state; semantic anchors are resolved only in device/widget coordinates.
namespace eval ::GX::ViewportHost {variable hosts {};variable tips {};variable serial 0;variable toggles}
proc ::GX::native2DViewportHostCreate {container canvas scene changed} {
    variable ::GX::ViewportHost::hosts
    # Chrome must share the canvas's actual geometry owner. Sibling overlays
    # across pack -in ancestry can obscure their children until hover on X11.
    set toplevel [winfo toplevel $canvas]
    set manager [winfo manager $canvas]
    if {$manager in {pack grid place}} {
        set information [$manager info $canvas]
        if {[dict exists $information -in]&&[dict get $information -in] ne {}} {
            set container [dict get $information -in]
        }
    }
    if {[winfo toplevel $container] ne $toplevel} {error {Viewport canvas belongs to another window}}
    dict set hosts $canvas [dict create container $container scene $scene changed $changed panels {}]
    bind $canvas <Configure> +[list ::GX::native2DViewportInvalidate $canvas]
    bind $container <Configure> +[list ::GX::native2DViewportConfigure $canvas $container %W]
    bind $canvas <Destroy> +[list ::GX::native2DViewportDispose $canvas %W]
    bind $toplevel <<ThemeChanged>> +[list ::GX::native2DViewportInvalidate $canvas]
    bind $toplevel <FocusIn> +[list ::GX::native2DViewportSeeWidget $canvas %W]
    bind $toplevel <Button-4> +[list ::GX::native2DViewportScrollWheel $canvas %W -1]
    bind $toplevel <Button-5> +[list ::GX::native2DViewportScrollWheel $canvas %W 1]
    return $canvas
}
proc ::GX::native2DViewportPanelWidget {host id} {
    variable ::GX::ViewportHost::hosts
    if {![dict exists $hosts $host]} {error {Unknown viewport host}}
    if {[dict exists $hosts $host panels $id]} {return [dict get $hosts $host panels $id widget]}
    return [dict get $hosts $host container].$id
}
proc ::GX::native2DViewportDispose {host widget} {
    variable ::GX::ViewportHost::hosts
    if {$widget ne $host} return
    if {[dict exists $hosts $host layout_pending]} {after cancel [dict get $hosts $host layout_pending]}
    if {[dict exists $hosts $host curve]} {_native2DViewportCurveDispose $host}
    native2DRasterCanvasDispose $host
    if {[dict exists $hosts $host]} {native2DRasterSceneDispose [dict get $hosts $host scene];dict unset hosts $host}
}
proc ::GX::native2DViewportPanelCreate {host id title anchor {options {}}} {
    variable ::GX::ViewportHost::hosts
    if {$anchor ni {top-left top-center top-right center-left center center-right bottom-left bottom-center bottom-right}} {error {Unknown semantic viewport anchor}}
    set container [dict get $hosts $host container];set panel $container.$id
    ttk::frame $panel -padding 3 -relief raised -borderwidth 1
    ttk::frame $panel.header;pack $panel.header -fill x
    ttk::button $panel.header.toggle -text $title -command [list ::GX::native2DViewportPanelToggle $host $id]
    native2DViewportTooltip $panel.header.toggle "Collapse / reopen $title"
    pack $panel.header.toggle -side left -fill x -expand 1
    if {[datasetPublicationV2DictDefault $options close 0]} {
        ttk::button $panel.header.close -text x -width 2 -command [list ::GX::native2DViewportPanelShow $host $id 0]
        native2DViewportTooltip $panel.header.close "Hide $title"
        pack $panel.header.close -side right
    }
    ttk::frame $panel.body;pack $panel.body -fill both -expand 1
    if {[datasetPublicationV2DictDefault $options scroll 0]} {
        canvas $panel.body.scroll -highlightthickness 0 -width 320 -height 340
        ttk::scrollbar $panel.body.bar -command [list $panel.body.scroll yview]
        $panel.body.scroll configure -yscrollcommand [list $panel.body.bar set]
        ttk::frame $panel.body.scroll.content
        $panel.body.scroll create window 0 0 -window $panel.body.scroll.content -anchor nw -tags content
        pack $panel.body.bar -side right -fill y;pack $panel.body.scroll -fill both -expand 1
        bind $panel.body.scroll <Configure> [list ::GX::native2DViewportScroll $panel.body.scroll]
        bind $panel.body.scroll.content <Configure> [list ::GX::native2DViewportScroll $panel.body.scroll]
    }
    dict set hosts $host panels $id [dict create widget $panel anchor $anchor visible 1 collapsed 0 margin [datasetPublicationV2DictDefault $options margin 8] orientation [datasetPublicationV2DictDefault $options orientation vertical] priority [datasetPublicationV2DictDefault $options priority 10] max_width [datasetPublicationV2DictDefault $options max_width 360] max_height [datasetPublicationV2DictDefault $options max_height 480] min_width [datasetPublicationV2DictDefault $options min_width 32] auto_collapsed 0 force_open 0 title $title]
    native2DViewportInvalidate $host
    if {[winfo exists $panel.body.scroll.content]} {return $panel.body.scroll.content}
    return $panel.body
}
proc ::GX::native2DViewportPanelShow {host id visible} {
    variable ::GX::ViewportHost::hosts
    dict set hosts $host panels $id visible $visible
    native2DViewportInvalidate $host
}
proc ::GX::native2DViewportPanelCollapse {host id collapsed} {
    variable ::GX::ViewportHost::hosts
    dict set hosts $host panels $id collapsed $collapsed
    dict set hosts $host panels $id force_open [expr {!$collapsed}]
    native2DViewportInvalidate $host
}
proc ::GX::native2DViewportPanelToggle {host id} {
    variable ::GX::ViewportHost::hosts
    set collapsed [expr {[dict get $hosts $host panels $id collapsed]||[dict get $hosts $host panels $id auto_collapsed]}]
    native2DViewportPanelCollapse $host $id [expr {!$collapsed}]
}
# Layout is invalidated by widget/configuration changes, never by camera motion.
# One idle callback absorbs the Configure events produced by panel reflow.
proc ::GX::native2DViewportInvalidate {host} {
    variable ::GX::ViewportHost::hosts
    if {![dict exists $hosts $host]} return
    if {[dict exists $hosts $host layout_pending]} return
    dict set hosts $host layout_pending [after idle [list ::GX::native2DViewportLayout $host]]
}
proc ::GX::native2DViewportSyncControls {host} {
    variable ::GX::ViewportHost::hosts
    if {![dict exists $hosts $host]||![winfo exists $host]} return
    set state [dict get $hosts $host]
    set signature [list [ttk::style theme use] [font actual TkDefaultFont] [tk scaling]]
    if {![dict exists $state layout_signature]||[dict get $state layout_signature] ne $signature} {native2DViewportInvalidate $host}
    set scene [dict get $state scene]
    set hasGeometry [expr {[llength [::GX::Native2D::core ids $scene]]>0}]
    foreach {action key} {grid visible grid_snap snap_enabled} {
        set ::GX::ViewportHost::toggles($host,$action) [dict get [::GX::Native2D::core grid $scene] $key]
    }
    set ::GX::ViewportHost::toggles($host,aspect) [expr {[::GX::Native2D::core aspect $scene] ne "auto"}]
    foreach action {fit_all fit_selected reset} {
        set widget [dict get $state container].controls.body.$action
        if {[winfo exists $widget]} {$widget state [expr {$hasGeometry?"!disabled":"disabled"}]}
    }
}
proc ::GX::native2DViewportLayout {host} {
    variable ::GX::ViewportHost::hosts
    if {![dict exists $hosts $host]||![winfo exists $host]} return
    if {[dict exists $hosts $host layout_pending]} {after cancel [dict get $hosts $host layout_pending];dict unset hosts $host layout_pending}
    dict set hosts $host layout_signature [list [ttk::style theme use] [font actual TkDefaultFont] [tk scaling]]
    set state [dict get $hosts $host]
    native2DViewportSyncControls $host
    set container [dict get $state container]
    set width [winfo width $host];set height [winfo height $host]
    if {$width<2||$height<2} return
    set x0 [expr {[winfo rootx $host]-[winfo rootx $container]}]
    set y0 [expr {[winfo rooty $host]-[winfo rooty $container]}]
    set scale [expr {max(1.0,[font metrics TkDefaultFont -linespace]/17.0)}]
    set occupied {};set ordered {}
    dict for {id panel} [dict get $state panels] {lappend ordered [list [dict get $panel priority] $id]}
    foreach pair [lsort -integer -index 0 $ordered] {
        set id [lindex $pair 1];set panel [dict get $state panels $id];set widget [dict get $panel widget]
        if {![winfo exists $widget]} continue
        if {![dict get $panel visible]} {place forget $widget;continue}
        set margin [expr {round([dict get $panel margin]*$scale)}]
        set limitWidth [expr {max(32,$width-2*$margin)}];set limitHeight [expr {max(24,$height-2*$margin)}]
        if {$id eq "controls"} {
            # Reflow instead of clipping rightmost actions on a narrow canvas.
            set buttons [lsearch -all -inline -not -exact [winfo children $widget.body] $widget.body.more];set cell 36;set rowHeight 32
            set themeBackground [ttk::style lookup TFrame -background]
            if {[catch {set glyphColor [uiFieldColorReadableText $themeBackground]}]} {set glyphColor #23344a}
            foreach button $buttons {$button configure -image [native2DViewportGlyph [winfo name $button] [expr {int(min(48,round(22*$scale)))}] $glyphColor]}
            foreach button $buttons {set cell [expr {max($cell,[winfo reqwidth $button]+2)}];set rowHeight [expr {max($rowHeight,[winfo reqheight $button]+2)}]}
            set columns [expr {max(1,min([llength $buttons],int($limitWidth/$cell)))}]
            set maxRows [expr {max(1,int(($limitHeight-8)/$rowHeight))}]
            set displayed $buttons;set overflow {}
            if {$maxRows*$columns<[llength $buttons]} {
                set cell [expr {max($cell,[winfo reqwidth $widget.body.more]+2)}]
                set columns [expr {max(1,int($limitWidth/$cell))}]
                set capacity [expr {max(1,$maxRows*$columns-1)}]
                set ordered {};foreach action {select transform fit_all fit_selected grid grid_snap zoom_in zoom_out pan zoom_box reset object_snap aspect} {if {"${widget}.body.$action" in $buttons} {lappend ordered $widget.body.$action}}
                set displayed [lrange $ordered 0 [expr {$capacity-1}]];set overflow [lrange $ordered $capacity end]
                if {$maxRows*$columns==1} {set displayed {};set overflow $ordered}
            }
            foreach button $buttons {grid forget $button}
            grid forget $widget.body.more
            set index 0
            foreach button $displayed {grid $button -row [expr {$index/$columns}] -column [expr {$index%$columns}] -padx 1 -pady 1;incr index}
            if {$overflow ne {}} {
                set menu $widget.body.more.menu;$menu delete 0 end
                foreach button $overflow {
                    set action [winfo name $button]
                    $menu add command -label [string totitle [string map {_ { }} $action]] -image [$button cget -image] -compound left -state [expr {[$button instate disabled]?"disabled":"normal"}] -command [$button cget -command]
                }
                grid $widget.body.more -row [expr {$index/$columns}] -column [expr {$index%$columns}] -padx 1 -pady 1;incr index
            }
            set displayedCount $index
        }
        set collapsed [dict get $panel collapsed]
        set auto [expr {$width<560*$scale&&[dict get $panel priority]>0&&![dict get $panel force_open]}]
        dict set hosts $host panels $id auto_collapsed $auto
        if {$auto} {set collapsed 1}
        if {$id ne "controls"} {
            if {$collapsed} {$widget.header.toggle configure -text {} -image [native2DViewportGlyph panel]} else {$widget.header.toggle configure -text [dict get $panel title] -image {}}
        }
        if {$collapsed} {pack forget $widget.body} else {pack $widget.body -fill both -expand 1}
        # Requested parent size can still describe the previously collapsed
        # pack state. Measure the existing header/body directly when reopening.
        set requestedWidth [expr {max([winfo reqwidth $widget.header],[winfo reqwidth $widget.body])+8}]
        set requestedHeight [expr {[winfo reqheight $widget.header]+[winfo reqheight $widget.body]+8}]
        set pw [expr {min($limitWidth,[dict get $panel max_width]*$scale,max([dict get $panel min_width],$requestedWidth))}]
        set ph [expr {min($limitHeight,[dict get $panel max_height]*$scale,$requestedHeight)}]
        if {$collapsed&&$id ne "controls"} {
            # pack forget updates requested geometry asynchronously. Reading the
            # old body size here would leave a large empty intercepting panel.
            set pw [expr {min($limitWidth,max([dict get $panel min_width],[winfo reqwidth $widget.header.toggle]+8))}]
            set ph [expr {min($limitHeight,[winfo reqheight $widget.header.toggle]+8)}]
        }
        if {$id eq "controls"} {
            set pw [expr {min($limitWidth,$columns*$cell+8)}]
            set ph [expr {min($limitHeight,int(ceil($displayedCount/double($columns)))*$rowHeight+8)}]
        }
        set anchor [dict get $panel anchor]
        if {[string match *left $anchor]} {set x $margin} elseif {[string match *right $anchor]} {set x [expr {$width-$pw-$margin}]} else {set x [expr {($width-$pw)/2}]}
        if {[string match top-* $anchor]} {set y $margin} elseif {[string match bottom-* $anchor]} {set y [expr {$height-$ph-$margin}]} else {set y [expr {($height-$ph)/2}]}
        # Deterministic stacking uses font-scaled lanes. If a lane cannot fit,
        # reduce to its header rather than obscure every scientific pixel.
        foreach rect $occupied {
            lassign $rect a b c d
            if {$x<$c&&$x+$pw>$a&&$y<$d&&$y+$ph>$b} {
                if {$y<$b&&$b-$margin-$y>50} {set ph [expr {$b-$margin-$y}]} else {set y [expr {$d+$margin}];set ph [expr {min($ph,$height-$y-$margin)}]}
                if {$ph<40||$y+$ph>$height-$margin} {pack forget $widget.body;set ph [winfo reqheight $widget.header];set y [expr {max($margin,$height-$ph-$margin)}];set x $margin}
            }
        }
        place $widget -x [expr {round($x0+$x)}] -y [expr {round($y0+$y)}] -width [expr {round($pw)}] -height [expr {round($ph)}]
        raise $widget
        if {[winfo exists $widget.body.scroll]} {
            set content [$widget.body.scroll itemcget content -window]
            # Sibling content supported by Tk window items must stay above the
            # panel surface; the canvas window item provides geometry/clipping.
            if {$content ne {}} {raise $content}
        }
        lappend occupied [list $x $y [expr {$x+$pw}] [expr {$y+$ph}]]
    }
}
proc ::GX::native2DViewportTooltip {widget text} {
    bind $widget <Enter> +[list ::GX::native2DViewportTooltipShow $widget $text]
    bind $widget <Leave> +[list catch {destroy .gxViewportTip}]
    bind $widget <ButtonPress> +[list catch {destroy .gxViewportTip}]
}
proc ::GX::native2DViewportTooltipShow {widget text} {
    catch {destroy .gxViewportTip}
    toplevel .gxViewportTip;wm overrideredirect .gxViewportTip 1
    ttk::label .gxViewportTip.text -text $text -padding 5;pack .gxViewportTip.text
    update idletasks
    set x [expr {min([winfo screenwidth $widget]-[winfo reqwidth .gxViewportTip],[winfo rootx $widget])}]
    set y [expr {min([winfo screenheight $widget]-[winfo reqheight .gxViewportTip],[winfo rooty $widget]+[winfo height $widget]+3)}]
    wm geometry .gxViewportTip +$x+$y
}
proc ::GX::native2DViewportGlyph {name {size 22} {color #23344a}} {
    package require Tk
    set key "gxViewport_${name}_${size}_[string map {# {}} $color]"
    if {$key in [image names]} {return $key}
    # Framework-owned raster vocabulary, generated from integer line patterns.
    # No icon font, emoji, vendor assets or geometry scene identities.
    image create photo $key -width $size -height $size
    set strokes [dict get {
        copy {{7 3 19 3} {19 3 19 16} {19 16 7 16} {7 16 7 3} {3 7 3 20} {3 20 15 20}}
        table {{3 3 19 3} {3 3 3 19} {3 19 19 19} {19 3 19 19} {3 8 19 8} {3 13 19 13} {8 3 8 19} {13 3 13 19}}
        close {{5 5 17 17} {5 17 17 5}}
        edit {{3 19 7 18} {7 18 19 6} {19 6 16 3} {16 3 4 15} {4 15 3 19}}
        save {{3 3 17 3} {17 3 20 6} {20 6 20 20} {20 20 3 20} {3 20 3 3} {7 3 7 9} {7 9 16 9} {16 9 16 3} {7 20 7 13} {7 13 16 13} {16 13 16 20}}
        print {{6 3 16 3} {6 3 6 8} {16 3 16 8} {3 8 19 8} {3 8 3 16} {19 8 19 16} {3 16 6 16} {16 16 19 16} {6 13 16 13} {6 13 6 20} {6 20 16 20} {16 13 16 20} {15 10 17 10}}
        refresh {{17 6 13 3} {13 3 7 3} {7 3 3 8} {3 8 3 14} {3 14 8 19} {8 19 15 19} {15 19 19 14} {17 2 17 7} {17 7 12 7}}
        open {{3 8 10 8} {3 8 3 20} {3 20 16 20} {16 20 16 13} {9 13 20 2} {13 2 20 2} {20 2 20 9}}
        select {{4 2 4 19} {4 2 17 13} {4 19 9 14} {9 14 13 21} {13 21 16 19} {16 19 12 13} {12 13 17 13}}
        namespace {{3 4 7 4} {7 4 7 8} {7 8 18 8} {13 8 13 13} {5 13 5 17} {13 13 13 17} {18 13 18 17} {3 17 7 17} {11 17 15 17} {16 17 20 17}}
        transform {{3 11 19 11} {11 3 11 19} {3 11 6 8} {3 11 6 14} {19 11 16 8} {19 11 16 14} {11 3 8 6} {11 3 14 6} {11 19 8 16} {11 19 14 16}}
        panel {{3 3 19 3} {3 3 3 19} {19 3 19 19} {3 19 19 19} {6 7 16 7} {6 11 16 11} {6 15 16 15}}
        fit_all {{3 3 8 3} {3 3 3 8} {14 3 19 3} {19 3 19 8} {3 14 3 19} {3 19 8 19} {14 19 19 19} {19 14 19 19}}
        fit_selected {{5 5 17 5} {5 5 5 17} {17 5 17 17} {5 17 17 17} {9 9 13 9} {9 13 13 13}}
        zoom_in {{4 10 16 10} {10 4 10 16} {15 15 20 20}}
        zoom_out {{4 10 16 10} {15 15 20 20}}
        zoom_box {{4 4 18 4} {4 4 4 18} {4 18 18 18} {18 4 18 18}}
        pan {{3 11 19 11} {11 3 11 19} {3 11 6 8} {3 11 6 14} {19 11 16 8} {19 11 16 14}}
        reset {{4 5 18 5} {18 5 18 17} {4 17 18 17} {4 5 4 9}}
        grid {{4 4 18 4} {4 11 18 11} {4 18 18 18} {4 4 4 18} {11 4 11 18} {18 4 18 18}}
        grid_snap {{4 4 18 4} {4 11 18 11} {11 4 11 18} {7 15 11 19} {11 19 19 11}}
        object_snap {{5 5 17 5} {5 5 5 17} {17 5 17 17} {5 17 17 17} {8 11 11 14} {11 14 20 5}}
        aspect {{4 4 18 4} {4 4 4 18} {4 18 18 18} {18 4 18 18} {8 9 14 9} {8 13 14 13}}
    } $name]
    foreach stroke $strokes {
        lassign $stroke x0 y0 x1 y1
        set steps [expr {max(abs($x1-$x0),abs($y1-$y0))}]
        for {set i 0} {$i<=$steps} {incr i} {
            set x [expr {round(($x0+($x1-$x0)*$i/double(max(1,$steps)))*$size/22.0)}]
            set y [expr {round(($y0+($y1-$y0)*$i/double(max(1,$steps)))*$size/22.0)}]
            $key put $color -to $x $y [expr {min($size,$x+2)}] [expr {min($size,$y+2)}]
        }
    }
    return $key
}
proc ::GX::native2DViewportControls {host actions {providerActions {}}} {
    variable ::GX::ViewportHost::hosts
    set body [native2DViewportPanelCreate $host controls View top-left {orientation horizontal priority 0 max_width 440 max_height 240}]
    pack forget [winfo parent $body].header
    foreach action $actions {
        # Coordinate aspect overrides belong to host APIs, not toolbar input.
        if {$action eq "aspect"} continue
        set command ttk::button;set arguments {}
        if {$action in {grid grid_snap aspect object_snap}} {set command ttk::checkbutton;set arguments [list -style Toolbutton -variable ::GX::ViewportHost::toggles($host,$action)]}
        $command $body.$action {*}$arguments -image [native2DViewportGlyph $action] -takefocus 1 -command [list ::GX::native2DViewportAction $host $action $providerActions]
        grid $body.$action -row 0 -column [expr {[llength [winfo children $body]]-1}] -padx 1
        native2DViewportTooltip $body.$action [string totitle [string map {_ { }} $action]]
    }
    ttk::menubutton $body.more -text More -width 4 -takefocus 1 -menu $body.more.menu
    menu $body.more.menu -tearoff 0
    native2DViewportTooltip $body.more {Additional viewport actions in a short or narrow view}
    return $body
}
proc ::GX::native2DViewportAction {host action providerActions} {
    variable ::GX::ViewportHost::hosts
    set scene [dict get $hosts $host scene]
    if {[dict exists $providerActions $action]} {uplevel #0 [dict get $providerActions $action]} else {
        lassign [::GX::Native2D::core view $scene] width height
        switch $action {
            fit_all - reset {::GX::Native2D::core fit $scene}
            fit_selected {::GX::Native2D::core fit_selected $scene}
            zoom_in - zoom_out {::GX::Native2D::core zoom $scene [expr {$action eq "zoom_in"?1/1.3:1.3}] [list [expr {$width/2}] [expr {$height/2}]]}
            grid - grid_snap {set key [expr {$action eq "grid"?"visible":"snap_enabled"}];set grid [::GX::Native2D::core grid $scene];dict set grid $key [expr {![dict get $grid $key]}];dict set grid enabled 1;::GX::Native2D::core grid $scene $grid}
            aspect {::GX::Native2D::core aspect $scene [expr {[::GX::Native2D::core aspect $scene] eq "auto"?"xy_equal":"auto"}]}
            default {error "Viewer must route the host gesture '$action'"}
        }
    }
    uplevel #0 [dict get $hosts $host changed]
}
proc ::GX::native2DViewportContextMenu {host target shared domain {allowed {select fit hide lock measure dimension constraints delete}}} {
    set menu ${host}_context;catch {destroy $menu};menu $menu -tearoff 0
    # Providers choose policy/order; the semantic target comes from Native pick.
    foreach action $allowed {
        if {![dict exists $shared $action]} continue
        if {$action eq "dimension"&&[dict get $target entity] eq "object"} continue
        lassign [dict get $shared $action] label command
        if {[lindex [dict get $shared $action] 2] eq "cascade"} {
            menu $menu.$action -tearoff 0
            foreach item $command {lassign $item title callback;$menu.$action add command -label $title -command $callback}
            $menu add cascade -label $label -menu $menu.$action
        } else {$menu add command -label $label -command $command}
    }
    if {[llength $domain]} {$menu add separator}
    foreach item $domain {lassign $item label command;$menu add command -label $label -command $command}
    return $menu
}

proc ::GX::native2DViewportConfigure {host container widget} {
    # A toplevel bindtag also receives child Configure events. Filtering prevents
    # panel placement from recursively scheduling its own layout forever.
    if {$widget eq $container} {native2DViewportInvalidate $host}
}

proc ::GX::native2DViewportScroll {canvas} {
    if {![winfo exists $canvas]} return
    $canvas itemconfigure content -width [winfo width $canvas]
    $canvas configure -scrollregion [$canvas bbox all]
}

proc ::GX::native2DViewportSeeWidget {host widget} {
    if {![dict exists $::GX::ViewportHost::hosts $host]||![winfo exists $widget]} return
    dict for {id panel} [dict get $::GX::ViewportHost::hosts $host panels] {
        set canvas [dict get $panel widget].body.scroll
        if {![winfo exists $canvas]||![winfo ismapped $canvas]} continue
        set content [$canvas itemcget content -window]
        if {$widget ne $content&&![string match "$content.*" $widget]&&![string match "$content.*" [winfo parent $widget]]} {
            # Tk permits a sibling widget to be packed -in the scroll content.
            if {[catch {pack info $widget} info]||![dict exists $info -in]||![string match "$content*" [dict get $info -in]]} {
                set parent [winfo parent $widget];set found 0
                while {$parent ne "."} {if {![catch {pack info $parent} info]&&[dict exists $info -in]&&[string match "$content*" [dict get $info -in]]} {set found 1;break};set parent [winfo parent $parent]}
                if {!$found} continue
            }
        }
        set top [winfo rooty $widget];set bottom [expr {$top+[winfo height $widget]}];set y [winfo rooty $canvas];set height [winfo height $canvas]
        set region [$canvas cget -scrollregion];if {[llength $region]!=4} return
        set total [lindex $region 3];if {$total<=0} return
        set first [lindex [$canvas yview] 0]
        if {$top<$y} {$canvas yview moveto [expr {$first+($top-$y-4)/double($total)}]} elseif {$bottom>$y+$height} {$canvas yview moveto [expr {$first+($bottom-$y-$height+4)/double($total)}]}
        update idletasks
        return
    }
}
proc ::GX::native2DViewportScrollWheel {host widget units} {
    if {![dict exists $::GX::ViewportHost::hosts $host]||![winfo exists $widget]} return
    dict for {id panel} [dict get $::GX::ViewportHost::hosts $host panels] {
        set canvas [dict get $panel widget].body.scroll
        if {![winfo exists $canvas]||![winfo ismapped $canvas]} continue
        set box [dict get $panel widget]
        set x [winfo pointerx $widget];set y [winfo pointery $widget]
        if {$x>=[winfo rootx $box]&&$x<[winfo rootx $box]+[winfo width $box]&&$y>=[winfo rooty $box]&&$y<[winfo rooty $box]+[winfo height $box]} {$canvas yview scroll [expr {3*$units}] units;return}
    }
}

proc ::GX::native2DViewportPanelContent {host id widget} {
    set panel [dict get $::GX::ViewportHost::hosts $host panels $id widget]
    set canvas $panel.body.scroll
    if {![winfo exists $canvas]} {error {Panel needs scroll mode for managed content}}
    pack forget $widget;place forget $widget
    $canvas itemconfigure content -window $widget
    bind $widget <Configure> +[list ::GX::native2DViewportScroll $canvas]
    native2DViewportScroll $canvas
}

proc ::GX::native2DViewportHostApiInfo {} {
    return [dict create api_id NATIVE2D_VIEWPORT_HOST_v1 api_version 1 host_only 1 operations {create panel_create panel_widget panel_content panel_show panel_collapse layout controls context_menu glyph tooltip tool_state see_widget scroll_wheel dispose curve_create curve_describe curve_navigate curve_hit curve_destroy}]
}

# Public state-managed existing ttk controls; caller supplies controller truth.
proc ::GX::native2DViewportToolState {widget active} {
    if {![winfo exists $widget]} return
    set base [expr {[winfo class $widget] eq "TMenubutton"?"TMenubutton":"TButton"}]
    set style GXSelected.$base
    if {[ttk::style configure $style -padding] ne "3"} {
        ttk::style configure $style -padding 3
        ttk::style map $style -background {selected #aecbea} -relief {selected sunken !selected raised}
    }
    if {[$widget cget -style] ne $style} {$widget configure -style $style}
    $widget state [expr {$active?"selected":"!selected"}]
}

source [file join [file dirname [info script]] native2d_viewport_curve_source.tcl]
