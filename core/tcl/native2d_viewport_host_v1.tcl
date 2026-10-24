# SPDX-License-Identifier: GPL-3.0-or-later
# Tk chrome is a sibling of the geometry canvas. Placement never touches Native
# view state; semantic anchors are resolved only in device/widget coordinates.
namespace eval ::GX::ViewportHost {variable hosts {};variable tips {};variable serial 0;variable toggles}
source [file join [file dirname [info script]] native2d_diagram_viewport_v1.tcl]
proc ::GX::native2DViewportHostCreate {container canvas scene changed {options {}}} {
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
    foreach key [dict keys $options] {if {$key ne {presentation_bounds}} {error {Unknown viewport host option}}}
    dict set hosts $canvas [dict create container $container scene $scene changed $changed panels {} presentation_bounds [datasetPublicationV2DictDefault $options presentation_bounds {}]]
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
    if {[dict exists $hosts $host target_session_trace]} {trace remove variable ::GX::currentSession {write unset} [dict get $hosts $host target_session_trace]}
    if {[dict exists $hosts $host curve]} {_native2DViewportCurveDispose $host}
    native2DRasterCanvasDispose $host
    if {[dict exists $hosts $host]} {
        dict for {id panel} [dict get $hosts $host panels] {if {[winfo exists [dict get $panel widget]]} {destroy [dict get $panel widget]}}
        if {[dict get $hosts $host scene] ne {}} {native2DRasterSceneDispose [dict get $hosts $host scene]}
        dict unset hosts $host
    }
}
proc ::GX::native2DViewportPanelDestroy {host id} {
    variable ::GX::ViewportHost::hosts
    if {![dict exists $hosts $host panels $id]} return
    set widget [dict get $hosts $host panels $id widget]
    dict unset hosts $host panels $id
    if {[winfo exists $widget]} {destroy $widget}
    native2DViewportInvalidate $host
}
proc ::GX::_native2DViewportPresentationBounds {host} {
    set state [dict get $::GX::ViewportHost::hosts $host]
    if {[dict get $state scene] ne {}} {return [::GX::Native2D::core view [dict get $state scene]]}
    # A Plot surface already owns scientific axes and navigation. Reuse only
    # shared panel/chrome layout; do not allocate a synthetic geometry scene.
    set command [dict get $state presentation_bounds]
    if {$command ne {}} {return [uplevel #0 $command]}
    return [list [winfo width $host] [winfo height $host] 0 0 0 0]
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
proc ::GX::native2DViewportPanelTarget {host id target} {
    variable ::GX::ViewportHost::hosts
    if {![dict exists $hosts $host panels $id]} {error {Unknown viewport panel}}
    if {$target eq {}} {
        catch {dict unset hosts $host panels $id target}
    } else {
        foreach key [dict keys $target] {if {$key ni {scene_token kind object_token selection_set_token reference roi_id annotation_id annotation_generation offset}} {error "Unknown semantic panel target field: $key"}}
        set kind [dict get $target kind]
        if {$kind ni {object selection reference roi annotation}} {error {Panel target must be object, selection, reference, roi or annotation}}
        set offset [datasetPublicationV2DictDefault $target offset {12 12}]
        if {[llength $offset]!=2} {error {Panel target offset requires two device distances}}
        foreach value $offset {if {![string is double -strict $value] || ![expr {abs($value)<=1024}]} {error {Panel target offset must be finite and at most1024 pixels}}}
        dict set target offset $offset
        if {$kind eq {annotation}} {
            set annotations [native2DGeometryCall [dict get $target scene_token] raster_annotation_get [dict create object_token [dict get $target object_token]]]
            set generation [dict get $annotations generations [dict get $target annotation_id]]
            if {[dict exists $target annotation_generation] && [dict get $target annotation_generation]!=$generation} {error {Annotation panel target identity was replaced}}
            dict set target annotation_generation $generation
        }
        # Validate ownership and the original geometry identity before changing
        # presentation. A missing selection may legitimately resolve no point.
        _native2DViewportPanelTargetPoint $host $target
        dict set hosts $host panels $id target $target
        if {![dict exists $hosts $host target_session_trace]} {
            set callback [list ::GX::_native2DViewportPanelTargetSessionChanged $host]
            trace add variable ::GX::currentSession {write unset} $callback
            dict set hosts $host target_session_trace $callback
        }
    }
    native2DViewportInvalidate $host
    return $target
}
proc ::GX::_native2DViewportPanelTargetSessionChanged {host args} {
    # Resolve after all existing Session identity traces have completed. A write
    # of the same unchanged Session must not invalidate a legitimate editor.
    native2DViewportInvalidate $host
}
proc ::GX::_native2DViewportPanelTargetVisible {scene object} {
    _native2DRasterDatasetCheck $scene $object
    set native [dict get $scene native]
    set id [_native2DGeometryObject $scene $object]
    set style [::GX::Native2D::core object_style $native $id]
    set layer [_native2DRasterLayer $native $style]
    if {![dict get $style visible] || ![dict get $layer visible]} {return 0}
    set image [::GX::Native2D::core image_get $native $id]
    if {$image ne {} && ![dict get $image visible]} {return 0}
    return 1
}
proc ::GX::_native2DViewportPanelTargetPoint {host target} {
    set scene [dict get $target scene_token]
    set owned [_native2DGeometryRequire $scene]
    if {[dict get $owned native] ne [dict get $::GX::ViewportHost::hosts $host scene]} {error {Panel target belongs to another Native2D viewport}}
    if {[dict exists $target object_token] && ![_native2DViewportPanelTargetVisible $owned [dict get $target object_token]]} {return {}}
    switch -- [dict get $target kind] {
        annotation {
            set object [dict get $target object_token]
            set collection [native2DGeometryCall $scene raster_annotation_get [dict create object_token $object]]
            if {[dict get $target annotation_generation]!=[dict get $collection generations [dict get $target annotation_id]]} {error {Annotation panel target identity was replaced}}
            set definition [dict get $collection annotations [dict get $target annotation_id]]
            set world [dict get [native2DGeometryCall $scene image_map [dict create object_token $object point [dict get $definition point] inverse 0]] point]
            return [dict get [native2DGeometryCall $scene world_to_device [dict create point $world]] point]
        }
        object {
            set object [native2DGeometryCall $scene describe [dict create object_token [dict get $target object_token]]]
            if {![dict get $object style visible]} {return {}}
            set bounds [dict get $object bounds]
        }
        selection {
            # A raster host can anchor to its actual selected native image
            # without manufacturing a persistent selection-set resource.
            if {[dict exists $target object_token] && ![dict exists $target selection_set_token]} {
                set object [dict get $target object_token]
                set native [dict get $owned native]
                if {![dict get [::GX::Native2D::core selection_summary $native [_native2DGeometryObject $owned $object]] count]} {return {}}
                set bounds [dict get [native2DGeometryCall $scene describe [dict create object_token $object]] bounds]
            } else {
                set request [dict create selection_set_token [dict get $target selection_set_token]]
                foreach member [dict get [native2DGeometryCall $scene selection_set_get $request] members] {
                    if {[dict get $member kind] eq {fragment}} {
                        set parent [dict get [native2DGeometryCall $scene fragment_get [dict create fragment_token [dict get $member fragment_token]]] parent_token]
                    } else {set parent [dict get $member object_token]}
                    if {![_native2DViewportPanelTargetVisible $owned $parent]} {return {}}
                }
                set bounds [dict get [native2DGeometryCall $scene selection_set_bounds $request] bounds]
            }
        }
        reference {
            if {![_native2DViewportPanelTargetVisible $owned [dict get $target reference object_token]]} {return {}}
            set point [dict get [native2DGeometryCall $scene reference_resolve [dict create reference [dict get $target reference]]] point]
            return [dict get [native2DGeometryCall $scene world_to_device [dict create point $point]] point]
        }
        roi {
            set object [dict get $target object_token]
            set roi [dict get [native2DGeometryCall $scene raster_roi_get [dict create object_token $object]] rois [dict get $target roi_id]]
            if {![dict get $roi intersects_image]} {return {}}
            lassign [dict get $roi clipped_bounds] x0 y0 x1 y1
            set pixel [list [expr {$x0/2.0+$x1/2.0}] [expr {$y0/2.0+$y1/2.0}]]
            set point [dict get [native2DGeometryCall $scene image_map [dict create object_token $object point $pixel inverse 0]] point]
            return [dict get [native2DGeometryCall $scene world_to_device [dict create point $point]] point]
        }
    }
    if {[llength $bounds]!=4} {return {}}
    lassign $bounds x0 y0 x1 y1
    return [dict get [native2DGeometryCall $scene world_to_device [dict create point [list [expr {$x0/2.0+$x1/2.0}] [expr {$y0/2.0+$y1/2.0}]]]] point]
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
    set signature [list [ttk::style theme use] [font actual TkDefaultFont] [tk scaling] [lrange [_native2DViewportPresentationBounds $host] 2 5]]
    if {![dict exists $state layout_signature]||[dict get $state layout_signature] ne $signature} {native2DViewportInvalidate $host}
    set scene [dict get $state scene]
    if {$scene eq {}} return
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
proc ::GX::_native2DViewportPanelAvoidTarget {rect target occupied width height margin minWidth minHeight} {
    lassign $rect x y pw ph
    lassign $target a b c d
    if {$x+$pw<=$a || $x>=$c || $y+$ph<=$b || $y>=$d} {return $rect}
    # Keep the rendered target visible, including a long or rotated label.
    # Prefer a full-size adjacent panel; otherwise its existing scroll body
    # can use the largest available strip. The scientific camera is untouched.
    set best {};set bestScore {}
    foreach area [list [list $margin $margin [expr {$width-$margin}] [expr {$b-$margin}]] \
            [list $margin [expr {$d+$margin}] [expr {$width-$margin}] [expr {$height-$margin}]] \
            [list $margin $margin [expr {$a-$margin}] [expr {$height-$margin}]] \
            [list [expr {$c+$margin}] $margin [expr {$width-$margin}] [expr {$height-$margin}]]] {
        lassign $area left top right bottom
        set w [expr {min($pw,$right-$left)}];set h [expr {min($ph,$bottom-$top)}]
        if {$w<$minWidth || $h<$minHeight} continue
        set px [expr {max($left,min($right-$w,$x))}];set py [expr {max($top,min($bottom-$h,$y))}]
        set blocked 0
        foreach other $occupied {
            lassign $other oa ob oc od
            if {$px<$oc && $px+$w>$oa && $py<$od && $py+$h>$ob} {set blocked 1;break}
        }
        if {$blocked} continue
        # A scrollable properties form should retain its full readable width
        # before preferring a larger but unnecessarily narrow side strip.
        set score [expr {$w*$h+($w==$pw?$width*$height:0)}]
        if {$best eq {} || $score>$bestScore} {set best [list $px $py $w $h];set bestScore $score}
    }
    if {$best eq {}} {return $rect}
    return $best
}
proc ::GX::native2DViewportLayout {host} {
    variable ::GX::ViewportHost::hosts
    if {![dict exists $hosts $host]||![winfo exists $host]} return
    if {[dict exists $hosts $host layout_pending]} {after cancel [dict get $hosts $host layout_pending];dict unset hosts $host layout_pending}
    dict set hosts $host layout_signature [list [ttk::style theme use] [font actual TkDefaultFont] [tk scaling] [lrange [_native2DViewportPresentationBounds $host] 2 5]]
    set state [dict get $hosts $host]
    native2DViewportSyncControls $host
    set container [dict get $state container]
    set width [winfo width $host];set height [winfo height $host]
    if {$width<2||$height<2} return
    set x0 [expr {[winfo rootx $host]-[winfo rootx $container]}]
    set y0 [expr {[winfo rooty $host]-[winfo rooty $container]}]
    # Native view margins reserve the scientific graduation/title bands.
    # Semantic overlay anchors belong inside the plotting rectangle; they must
    # never cover those bands or change the native camera/coordinate mapping.
    lassign [_native2DViewportPresentationBounds $host] nativeWidth nativeHeight left top right bottom
    if {$left>=0 && $top>=0 && $right>=0 && $bottom>=0 && $width>$left+$right && $height>$top+$bottom} {
        set x0 [expr {$x0+$left}];set y0 [expr {$y0+$top}]
        set width [expr {$width-$left-$right}];set height [expr {$height-$top-$bottom}]
    }
    set scale [expr {max(1.0,[font metrics TkDefaultFont -linespace]/17.0)}]
    set occupied {};set ordered {}
    dict for {id panel} [dict get $state panels] {lappend ordered [list [dict get $panel priority] $id]}
    foreach pair [lsort -integer -index 0 $ordered] {
        set id [lindex $pair 1];set panel [dict get $state panels $id];set widget [dict get $panel widget]
        if {![winfo exists $widget]} continue
        if {![dict get $panel visible]} {place forget $widget;continue}
        set targetPoint {}
        if {[dict exists $panel target]} {
            if {[catch {set targetPoint [_native2DViewportPanelTargetPoint $host [dict get $panel target]]} reason]} {
                dict set hosts $host panels $id target_state [dict create status stale reason $reason]
                place forget $widget;continue
            }
            if {$targetPoint eq {}} {dict set hosts $host panels $id target_state {status no_selection};place forget $widget;continue}
            dict set hosts $host panels $id target_state [dict create status ready point $targetPoint]
        }
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
        if {$targetPoint ne {}} {
            lassign $targetPoint tx ty;lassign [dict get $panel target offset] dx dy
            set tx [expr {$tx+[winfo rootx $host]-[winfo rootx $container]-$x0}]
            set ty [expr {$ty+[winfo rooty $host]-[winfo rooty $container]-$y0}]
            set x [expr {$tx+$dx}];set y [expr {$ty+$dy}]
            if {$x+$pw>$width-$margin} {set x [expr {$tx-$pw-abs($dx)}]}
            if {$y+$ph>$height-$margin} {set y [expr {$ty-$ph-abs($dy)}]}
            set x [expr {max($margin,min($width-$pw-$margin,$x))}]
            set y [expr {max($margin,min($height-$ph-$margin,$y))}]
        }
        # Deterministic stacking uses font-scaled lanes. If a lane cannot fit,
        # reduce to its header rather than obscure every scientific pixel.
        foreach rect $occupied {
            lassign $rect a b c d
            if {$x<$c&&$x+$pw>$a&&$y<$d&&$y+$ph>$b} {
                if {$y<$b&&$b-$margin-$y>50} {set ph [expr {$b-$margin-$y}]} else {set y [expr {$d+$margin}];set ph [expr {min($ph,$height-$y-$margin)}]}
                if {$ph<40||$y+$ph>$height-$margin} {pack forget $widget.body;set ph [winfo reqheight $widget.header];set y [expr {max($margin,$height-$ph-$margin)}];set x $margin}
            }
        }
        if {$targetPoint ne {} && [dict get $panel target kind] eq {annotation}} {
            # Target resolution above has already checked scene ownership,
            # visibility and annotation generation. Use the actual painted
            # bounds, not an estimated text width or only its anchor point.
            set bounds [$host bbox native_annotation_[dict get $panel target annotation_id]]
            if {[llength $bounds]==4} {
                lassign $bounds a b c d
                set ox [expr {[winfo rootx $host]-[winfo rootx $container]-$x0}]
                set oy [expr {[winfo rooty $host]-[winfo rooty $container]-$y0}]
                set bounds [list [expr {$a+$ox}] [expr {$b+$oy}] [expr {$c+$ox}] [expr {$d+$oy}]]
                lassign [_native2DViewportPanelAvoidTarget [list $x $y $pw $ph] $bounds $occupied $width $height $margin \
                    [expr {min($pw,[dict get $panel min_width])}] [expr {[winfo reqheight $widget.header]+24}]] x y pw ph
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
    variable ::GX::ViewportHost::tips
    # One dispatcher per widget; repeat registration updates only its content.
    dict set tips texts $widget $text
    set script [list ::GX::_native2DViewportTooltipEnter $widget]
    if {$script ni [split [bind $widget <Enter>] \n]} {bind $widget <Enter> +$script}
    _native2DViewportTooltipTargetBind $widget
}
proc ::GX::_native2DViewportTooltipEnter {widget} {
    if {[dict exists $::GX::ViewportHost::tips texts $widget]} {
        native2DViewportTooltipShow $widget [dict get $::GX::ViewportHost::tips texts $widget]
    }
}
proc ::GX::_native2DViewportTooltipTargetBind {widget} {
    variable ::GX::ViewportHost::tips
    if {![dict exists $tips targets $widget]} {
        foreach event {Leave ButtonPress Unmap Destroy} {bind $widget <$event> +[list ::GX::_native2DViewportTooltipTargetEvent $widget $event %W]}
        dict set tips targets $widget 1
    }
}
proc ::GX::native2DViewportTooltipHide {{widget {}}} {
    variable ::GX::ViewportHost::tips
    if {$widget ne {} && (![dict exists $tips current target] || [dict get $tips current target] ne $widget)} return
    catch {dict unset tips current}
    catch {destroy .gxViewportTip}
}
proc ::GX::_native2DViewportTooltipTargetEvent {widget event actual} {
    if {$actual ne $widget} return
    # Native toolbar reflow can queue Leave/Unmap before restoring the same
    # control beneath an unchanged pointer. Consult current widget ownership.
    if {$event in {Leave Unmap} && [_native2DViewportTooltipHovered $widget]} return
    native2DViewportTooltipHide $widget
    if {$event eq {Destroy}} {catch {dict unset ::GX::ViewportHost::tips targets $widget};catch {dict unset ::GX::ViewportHost::tips texts $widget}}
}
proc ::GX::_native2DViewportTooltipHovered {widget} {
    if {![winfo exists $widget] || ![winfo ismapped $widget]} {return 0}
    set actual [winfo containing -displayof $widget [winfo pointerx $widget] [winfo pointery $widget]]
    expr {$actual eq $widget || [string match ${widget}.* $actual]}
}
proc ::GX::_native2DViewportTooltipOwnerEvent {owner event actual} {
    if {$actual ne $owner} return
    if {[dict exists $::GX::ViewportHost::tips current owner] && [dict get $::GX::ViewportHost::tips current owner] eq $owner} {
        # FocusOut/NotifyInferior is also sent when focus moves from the
        # toplevel to its own canvas. It is not a Viewer deactivation.
        if {$event eq {FocusOut}} {
            set focused [focus -displayof $owner]
            if {$focused ne {} && [winfo exists $focused] && [winfo toplevel $focused] eq $owner} return
        }
        # A real ConfigureNotify may describe stacking only (including raising
        # a transient tooltip), not a move away from the hovered control.
        if {$event eq {Configure} && [winfo ismapped $owner] && [_native2DViewportTooltipHovered [dict get $::GX::ViewportHost::tips current target]]} return
        native2DViewportTooltipHide
    }
    if {$event eq {Destroy}} {catch {dict unset ::GX::ViewportHost::tips owners $owner}}
}
proc ::GX::native2DViewportTooltipShow {widget text} {
    variable ::GX::ViewportHost::tips
    if {![winfo exists $widget] || ![winfo ismapped $widget] || $text eq {}} return
    set owner [winfo toplevel $widget]
    set focused [focus -displayof $widget]
    # A delayed legacy toolbar request must not reappear after a window switch.
    if {$focused eq {} || [winfo toplevel $focused] ne $owner} return
    if {[dict exists $tips current] && [dict get $tips current target] eq $widget && [dict get $tips current text] eq $text && [winfo exists .gxViewportTip]} return
    native2DViewportTooltipHide
    if {![dict exists $tips owners $owner]} {
        foreach event {FocusOut Deactivate Unmap Destroy Configure} {bind $owner <$event> +[list ::GX::_native2DViewportTooltipOwnerEvent $owner $event %W]}
        dict set tips owners $owner 1
    }
    _native2DViewportTooltipTargetBind $widget
    # Position while withdrawn: the first visible frame must already belong to
    # the hovered control's window, rather than briefly mapping at the root.
    # The override-redirect surface must own its opaque background, including
    # the server-cleared area before the child receives its first Expose.
    set background [ttk::style lookup TLabel -background]
    if {$background eq {} || [catch {winfo rgb $widget $background}]} {set background #ffffe0}
    set foreground [ttk::style lookup TLabel -foreground]
    if {$foreground eq {} || [catch {winfo rgb $widget $foreground}]} {set foreground [uiFieldColorReadableText $background]}
    set opaque [configurationGet ui.x11_tooltip_opaque]
    set premap [configurationGet ui.x11_tooltip_premap]
    toplevel .gxViewportTip -background $background
    if {$premap} {wm withdraw .gxViewportTip}
    wm overrideredirect .gxViewportTip 1;wm transient .gxViewportTip $owner
    set left [winfo vrootx $widget];set top [winfo vrooty $widget]
    set width [winfo vrootwidth $widget];set height [winfo vrootheight $widget]
    set pad [expr {max(4,int(5*max(1.0,[tk scaling]/1.333333)))}]
    # One ordinary Tk label paints background, border, padding and text into
    # the same drawable, independent of a theme's parent-background elements.
    if {$opaque} {
    label .gxViewportTip.text -text $text -background $background -foreground $foreground \
        -font TkDefaultFont -borderwidth 1 -relief solid -highlightthickness 0 \
        -padx $pad -pady $pad -justify left \
        -wraplength [expr {max(40,min(int(480*max(1.0,[tk scaling]/1.333333)),$width-2*$pad-2))}]
    } else {
        ttk::label .gxViewportTip.text -text $text -padding $pad -justify left \
            -wraplength [expr {max(40,min(int(480*max(1.0,[tk scaling]/1.333333)),$width-2*$pad-2))}]
    }
    pack .gxViewportTip.text -fill both -expand 1
    update idletasks
    if {![winfo exists $widget] || ![winfo ismapped $widget] || ![winfo exists .gxViewportTip]} {native2DViewportTooltipHide;return}
    set tw [winfo reqwidth .gxViewportTip];set th [winfo reqheight .gxViewportTip]
    set x [expr {max($left,min($left+$width-$tw,[winfo rootx $widget]))}]
    set y [expr {[winfo rooty $widget]+[winfo height $widget]+$pad}]
    if {$y+$th>$top+$height} {set y [expr {[winfo rooty $widget]-$th-$pad}]}
    set y [expr {max($top,min($top+$height-$th,$y))}]
    # Send the complete negotiated rectangle before mapping, not only position.
    if {$premap} {wm geometry .gxViewportTip [format {%dx%d%+d%+d} $tw $th $x $y]
    } else {wm geometry .gxViewportTip [format {%+d%+d} $x $y]}
    dict set tips current [dict create target $widget owner $owner text $text]
    wm deiconify .gxViewportTip
    raise .gxViewportTip
}
proc ::GX::native2DViewportGlyph {name {size 22} {color #23344a}} {
    package require Tk
    set key "gxViewport_${name}_${size}_[string map {# {}} $color]"
    if {$key in [image names]} {return $key}
    # Framework-owned raster vocabulary, generated from integer line patterns.
    # No icon font, emoji, vendor assets or geometry scene identities.
    image create photo $key -width $size -height $size
    set strokes [dict get {
        debug_start {{6 3 18 11} {18 11 6 19} {6 19 6 3}}
        debug_continue {{4 3 4 19} {8 3 19 11} {19 11 8 19} {8 19 8 3}}
        debug_pause {{7 3 7 19} {8 3 8 19} {14 3 14 19} {15 3 15 19}}
        debug_stop {{4 4 18 4} {18 4 18 18} {18 18 4 18} {4 18 4 4} {5 5 17 17} {5 17 17 5}}
        debug_into {{4 4 11 4} {11 4 11 15} {7 11 11 15} {11 15 15 11} {5 19 17 19}}
        debug_over {{3 10 5 5} {5 5 10 3} {10 3 16 5} {16 5 19 10} {15 7 19 10} {19 10 20 5} {8 18 14 18}}
        debug_out {{5 18 11 18} {11 18 11 5} {7 9 11 5} {11 5 15 9} {5 2 17 2}}
        debug_breakpoint {{5 4 16 4} {16 4 20 11} {20 11 16 18} {16 18 5 18} {5 18 1 11} {1 11 5 4}}
        debug_clear {{5 4 16 4} {16 4 20 11} {20 11 16 18} {16 18 5 18} {5 18 1 11} {1 11 5 4} {3 20 20 2}}
        copy {{7 3 19 3} {19 3 19 16} {19 16 7 16} {7 16 7 3} {3 7 3 20} {3 20 15 20}}
        table {{3 3 19 3} {3 3 3 19} {3 19 19 19} {19 3 19 19} {3 8 19 8} {3 13 19 13} {8 3 8 19} {13 3 13 19}}
        close {{5 5 17 17} {5 17 17 5}}
        edit {{3 19 7 18} {7 18 19 6} {19 6 16 3} {16 3 4 15} {4 15 3 19}}
        text {{3 4 19 4} {11 4 11 19} {7 19 15 19} {3 4 3 7} {19 4 19 7}}
        save {{3 3 17 3} {17 3 20 6} {20 6 20 20} {20 20 3 20} {3 20 3 3} {7 3 7 9} {7 9 16 9} {16 9 16 3} {7 20 7 13} {7 13 16 13} {16 13 16 20}}
        print {{6 3 16 3} {6 3 6 8} {16 3 16 8} {3 8 19 8} {3 8 3 16} {19 8 19 16} {3 16 6 16} {16 16 19 16} {6 13 16 13} {6 13 6 20} {6 20 16 20} {16 13 16 20} {15 10 17 10}}
        refresh {{17 6 13 3} {13 3 7 3} {7 3 3 8} {3 8 3 14} {3 14 8 19} {8 19 15 19} {15 19 19 14} {17 2 17 7} {17 7 12 7}}
        open {{3 8 10 8} {3 8 3 20} {3 20 16 20} {16 20 16 13} {9 13 20 2} {13 2 20 2} {20 2 20 9}}
        select {{4 2 4 19} {4 2 17 13} {4 19 9 14} {9 14 13 21} {13 21 16 19} {16 19 12 13} {12 13 17 13}}
        roi_rectangle {{3 5 19 5} {19 5 19 17} {19 17 3 17} {3 17 3 5} {2 4 5 4} {17 18 20 18}}
        roi_polygon {{3 16 6 4} {6 4 17 3} {17 3 20 13} {20 13 12 19} {12 19 3 16} {6 3 6 6} {2 15 5 15}}
        rotate {{4 12 4 8} {4 8 8 4} {8 4 14 4} {14 4 18 8} {18 8 18 15} {18 15 14 19} {14 19 8 19} {3 6 4 12} {4 12 9 10}}
        pivot {{11 2 11 20} {2 11 20 11} {7 7 15 7} {15 7 15 15} {15 15 7 15} {7 15 7 7}}
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
    return [dict create api_id NATIVE2D_VIEWPORT_HOST_v1 api_version 1 host_only 1 operations {create panel_create panel_widget panel_target panel_content panel_show panel_destroy panel_collapse layout controls context_menu glyph tooltip tool_state see_widget scroll_wheel dispose curve_create curve_describe curve_navigate curve_hit curve_destroy diagram_create diagram_command diagram_edit diagram_describe diagram_hit_test raster_attach raster_describe raster_tool raster_command} tooltip_commands {native2DViewportTooltip native2DViewportTooltipShow native2DViewportTooltipHide} tooltip_owner hovered_toplevel diagram_commands {native2DGeometryDiagramViewportCreate native2DGeometryDiagramViewportCommand native2DGeometryDiagramViewportEdit native2DGeometryDiagramViewportDescribe native2DGeometryDiagramViewportHitTest} diagram_events {before_edit committed tool_changed probe} diagram_hit_kinds {terminal wire} diagram_authority INTERACTIVE_DOCUMENT_API_v1 diagram_renderer NATIVE2D_API_v1]
}

# Public state-managed existing ttk controls; caller supplies controller truth.
proc ::GX::native2DViewportToolState {widget active} {
    if {![winfo exists $widget]} return
    set base [$widget cget -style]
    if {$base eq {}} {set base [expr {[winfo class $widget] eq "TMenubutton"?"TMenubutton":"TButton"}]}
    set spacing {}
    while {[regexp {^(GXSelected|GXIconSpace[0-9]+)\.(.+)$} $base -> wrapper original]} {
        if {$spacing eq {} && [string match GXIconSpace* $wrapper]} {set spacing $wrapper}
        set base $original
    }
    if {$spacing ne {}} {set base $spacing.$base}
    set style GXSelected.$base
    # Inherit the real icon-spacing/theme layout, font and outside padding.
    # Read the complete current map: preserve other option mappings and react
    # to real base/theme changes without rewriting global styles every frame.
    set current [ttk::style map $style]
    set desired [dict replace $current \
        -background [concat {selected #aecbea} [ttk::style map $base -background]] \
        -relief [concat {selected sunken} [ttk::style map $base -relief]]]
    if {$current ne $desired} {ttk::style map $style {*}$desired}
    if {[$widget cget -style] ne $style} {$widget configure -style $style}
    set state [expr {$active?"selected":"!selected"}]
    if {![$widget instate $state]} {$widget state $state}
}

source [file join [file dirname [info script]] native2d_viewport_curve_source.tcl]
source [file join [file dirname [info script]] native2d_viewport_raster_v1.tcl]
