# Private real Debian GUI interactions. No implementation procedures replaced.
set ::p0serial 0
proc p0assert {condition name} {
    set pass [uplevel 1 [list expr $condition]]
    record $name [dict create pass $pass]
    if {!$pass} {error "FAIL: $name"}
}
proc p0pause {{ms 160}} {set v ::p0wait[incr ::p0serial];after $ms [list set $v 1];vwait $v;unset $v}
proc p0click {w {x 20} {y 10}} {
    raise [winfo toplevel $w];p0pause 80
    exec xdotool mousemove [expr {[winfo rootx $w]+$x}] [expr {[winfo rooty $w]+$y}] click 1
    p0pause
}
proc p0capture {w name} {
    raise $w;p0pause 350
    # Include native Tk menubar above the content window on X11.
    set x [winfo rootx $w];set y [expr {max(0,[winfo rooty $w]-26)}]
    exec import -window root -crop [winfo width $w]x[expr {[winfo height $w]+26}]+$x+$y [file join $::out $name.png]
}
proc p0state {w choice} {
    if {[winfo class $choice] eq {TCombobox}} {set value [$choice get]} else {set value [set [$choice cget -textvariable]]}
    set result [dict create choice $value focus [focus] grab [grab current] mapped [winfo ismapped $choice] geometry [winfo geometry $w] menu [$w cget -menu]]
    if {[dict exists $::GX::ScientificHistory::viewers $w]} {
        set a [dict get $::GX::ScientificHistory::viewers $w]
        set c [dict get $a strip].timeline
        dict set result settings [dict get $a strip_settings]
        dict set result steps [llength [dict get $a record steps]]
        dict set result canvas [list mapped [winfo ismapped $c] geometry [winfo geometry $c] items [$c find all]]
        set labels {};foreach item [$c find withtag all] {if {[$c type $item] eq {text}} {lappend labels [$c itemcget $item -text]}}
        dict set result labels $labels
    }
    return $result
}
proc p0select {w choice value method name} {
    wm deiconify $w;raise $w;p0pause
    exec xdotool windowfocus [winfo id $w];focus -force $choice;p0pause
    if {$method eq {pointer}} {p0click $choice} else {exec xdotool key [expr {[winfo class $choice] eq {TCombobox}?{Down}:{space}}];p0pause}
    set panel [::GX::_uiFieldSelectorPanel $choice $w]
    if {[winfo exists $panel]} {
        set list $panel.options
        set index [lsearch -exact [$list get 0 end] $value]
        if {$method eq {pointer}} {
            lassign [$list bbox $index] x y width height
            p0click $list [expr {$x+20}] [expr {$y+$height/2}]
        } else {
            focus -force $list
            exec xdotool key [expr {$value eq {Description}?{ctrl+Home}:{ctrl+End}}]
            exec xdotool key Return;p0pause
        }
    } elseif {[winfo class $choice] eq {TCombobox}} {
        set list [ttk::combobox::PopdownWindow $choice].f.l
        if {$method eq {pointer}} {
            set index [lsearch -exact [$list get 0 end] $value]
            lassign [$list bbox $index] x y width height
            p0click $list [expr {$x+20}] [expr {$y+$height/2}]
        } else {
            focus -force $list
            exec xdotool key [expr {$value eq {Description}?{ctrl+Home}:{ctrl+End}}]
            exec xdotool key Return;p0pause
        }
    } else {
        # Inspector's established native Menu selector.
        set menu [$choice cget -menu];set index [expr {$value eq {Description}?0:1}]
        if {$method eq {pointer}} {
            p0click $menu 30 [expr {[$menu yposition $index]+10}]
        } else {
            focus -force $menu
            set active [$menu index active]
            if {$active eq {none}} {set active -1}
            for {set i 0} {$i<3 && $active!=$index} {incr i} {exec xdotool key Down;p0pause 40;set active [$menu index active]}
            exec xdotool key Return;p0pause
        }
    }
    p0pause
    set state [p0state $w $choice]
    dict set state requested $value
    dict set state transition_pass [expr {[dict get $state choice] eq $value && [grab current] eq {}}]
    record $name $state
    p0capture $w $name
}
proc p0shared {module provider workspace label} {
    set w [::GX::viewerOpen $module $provider [dict create workspace_id $workspace]]
    wm geometry $w 1120x740+80+100;p0pause 500
    set a [dict get $::GX::ScientificHistory::viewers $w];set choice [dict get $a strip].choice
    foreach size {1120x740 850x480 1120x850} {
        wm geometry $w $size;p0pause
        foreach method {pointer keyboard} {
            foreach value {Description History Description} {
                p0select $w $choice $value $method ${label}_${size}_${method}_${value}_[incr ::p0serial]
            }
        }
    }
    return $w
}

# Empty drafts, saved baseline-only Workspaces, and a normal reopen after Close
# have different lifecycles. Keep their exact state separate from stale Sessions.
proc p0emptyClosePrompt {window {attempt 0}} {
    if {[winfo exists $window.__tk__messagebox.no]} {
        record empty_close_prompt [list window $window text [$window.__tk__messagebox.msg cget -text] decision {Discard only private empty draft}]
        p0click $window.__tk__messagebox.no
    } elseif {$attempt<60} {after 100 [list p0emptyClosePrompt $window [expr {$attempt+1}]]}
}
proc p0emptyLifecycle {} {
    foreach {module provider window choice menu current} {
        viewer.scientific_worksheet scientific_worksheet .scientific_worksheet .scientific_worksheet.description.historyStrip.choice .scientific_worksheet.menu.workspace {::GX::ScientificWorksheet::UI::current .scientific_worksheet}
        viewer.dataset_curve_fit dataset_curve_fit .dataset_curve_fit .dataset_curve_fit.footer.historyStrip.choice .dataset_curve_fit.menus.workspace.menu {set ::GX::DatasetCurveFit::state(.dataset_curve_fit,documentId)}
    } {
        set label $provider
        foreach stage {draft saved_empty reopened_draft} {
            set w [::GX::viewerOpen $module $provider]
            if {$stage eq {saved_empty}} {$menu invoke 2;p0pause 400}
            record ${label}_${stage}_identity [dict create workspace [uplevel #0 $current] steps [llength [dict get [::GX::scientificHistoryViewerRecord $w] steps]] session $::GX::currentSession]
            foreach method {pointer keyboard} {
                foreach value {Description History Description} {p0select $w $choice $value $method ${label}_${stage}_${method}_$value}
            }
            # Existing native Workspace menu action; selector gestures above use
            # actual pointer/keyboard input. Do not claim menu-opening coverage.
            after 100 [list p0emptyClosePrompt $window]
            $menu invoke 6;p0pause 300
            p0assert {![winfo exists $window]} ${label}_${stage}_closed
        }
    }
    record empty_lifecycle_complete [dict create status PASS unexpected_errors [file exists [file join $::out tk_background_errors.log]]]
}

proc p0InspectorControl {label} {
    if {[winfo exists .scientific_image_inspector]} {::GX::SII::guiClose;p0pause}
    set w [::GX::viewerOpen viewer.scientific_image_inspector scientific_image_inspector]
    p0pause 500
    set ids [$w.head.ds cget -values]
    if {$ids eq {}} {error {Control needs a canonical image Dataset}}
    p0click $w.head.ds
    set list [ttk::combobox::PopdownWindow $w.head.ds].f.l
    focus -force $list;exec xdotool key ctrl+Home Return
    p0pause 800
    if {![info exists ::GX::SII::ui(workingInfo)]} {error {Image did not load}}
    ::GX::SII::annotationChooseTool Arrow
    p0pause
    set scene $::GX::SII::ui(native-original)
    set info $::GX::SII::ui(workingInfo)
    set width [dict get $info width];set height [dict get $info height]
    lassign [::GX::Native2D::core device $scene [list [expr {.3*$width}] [expr {.3*$height}]]] x0 y0
    lassign [::GX::Native2D::core device $scene [list [expr {.6*$width}] [expr {.6*$height}]]] x1 y1
    set c $w.layout.main.panes.original.canvas
    exec xdotool mousemove [expr {int([winfo rootx $c]+$x0)}] [expr {int([winfo rooty $c]+$y0)}] mousedown 1 mousemove [expr {int([winfo rootx $c]+$x1)}] [expr {int([winfo rooty $c]+$y1)}] mouseup 1
    p0pause 600
    record ${label}_image_control [list source $::GX::SII::ui(sourceId) history_count [llength $::GX::SII::ui(historyTimeline)] annotations $::GX::SII::ui(annotations)]
    foreach method {pointer keyboard} {foreach value {Description History Description} {p0select $w $w.strip.choice $value $method ${label}_${method}_$value}}
    return $w
}
