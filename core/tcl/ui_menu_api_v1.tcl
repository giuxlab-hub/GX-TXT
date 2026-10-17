# Native popup ownership, separate from Tk menubutton/cascade automatic posting.
proc ::GX::uiMenuWorkarea {widget x y} {
    set screen [list [winfo vrootx $widget] [winfo vrooty $widget] [winfo vrootwidth $widget] [winfo vrootheight $widget]]
    if {[lindex $screen 2]<2} {set screen [list 0 0 [winfo screenwidth $widget] [winfo screenheight $widget]]}
    set monitor $screen
    if {[tk windowingsystem] eq "x11"} {
        if {![catch {exec xrandr --listmonitors} data]} {
            foreach line [split $data \n] {
                if {[regexp {(\d+)/\d+x(\d+)/\d+([+-]\d+)([+-]\d+)} $line -> w h mx my] && $x>=$mx && $x<$mx+$w && $y>=$my && $y<$my+$h} {set monitor [list $mx $my $w $h];break}
            }
        }
        if {![catch {exec xprop -root _NET_CURRENT_DESKTOP _NET_WORKAREA} data]} {
            if {[regexp {_NET_CURRENT_DESKTOP[^=]*=\s*(\d+)} $data -> desktop] && [regexp {_NET_WORKAREA[^=]*=([^\n]+)} $data -> values]} {
                set numbers [regexp -all -inline -- {-?\d+} $values]
                set area [lrange $numbers [expr {4*$desktop}] [expr {4*$desktop+3}]]
                if {[llength $area]==4} {
                    lassign $monitor mx my mw mh;lassign $area ax ay aw ah
                    set left [expr {max($mx,$ax)}];set top [expr {max($my,$ay)}]
                    set right [expr {min($mx+$mw,$ax+$aw)}];set bottom [expr {min($my+$mh,$ay+$ah)}]
                    if {$right>$left&&$bottom>$top} {set monitor [list $left $top [expr {$right-$left}] [expr {$bottom-$top}]]}
                }
            }
        }
    }
    return $monitor
}
proc ::GX::_uiMenuCopyEntry {source index destination {submenu {}}} {
    set type [$source type $index];set args {}
    foreach descriptor [$source entryconfigure $index] {
        set option [lindex $descriptor 0]
        if {$submenu ne {}&&$option eq "-menu"} {set value $submenu} else {set value [lindex $descriptor end]}
        lappend args $option $value
    }
    $destination add $type {*}$args
}
proc ::GX::_uiMenuPaged {source destination height {depth 0} {populated 0}} {
    if {$depth>12} {error {Menu cascade depth exceeds twelve levels}}
    set post [$source cget -postcommand]
    if {!$populated&&$post ne {}} {uplevel #0 $post}
    update idletasks
    catch {destroy $destination};menu $destination -tearoff 0
    foreach option {-font -foreground -background -activeforeground -activebackground -disabledforeground -selectcolor} {$destination configure $option [$source cget $option]}
    set end [$source index end];if {$end eq "none"} {return $destination}
    set limit [expr {max(4,int(($height-25)/max(24,[font metrics [$source cget -font] -linespace]+10)))}]
    set pageable [expr {[winfo reqheight $source]>$height}]
    set page -1;set target $destination
    for {set i 0} {$i<=$end} {incr i} {
        if {$pageable&&$i%$limit==0} {
            incr page;set target $destination.page$page;menu $target -tearoff 0 -font [$source cget -font]
            $destination add cascade -label "Items [expr {$i+1}]–[expr {min($end+1,$i+$limit)}]" -menu $target
        }
        set submenu {}
        if {[$source type $i] eq "cascade"} {set submenu [_uiMenuPaged [$source entrycget $i -menu] $target.sub$i $height [expr {$depth+1}]]}
        _uiMenuCopyEntry $source $i $target $submenu
    }
    return $destination
}
proc ::GX::_uiMenuNeedsPaging {menu height {depth 0}} {
    if {$depth>12} {error {Menu cascade depth exceeds twelve levels}}
    if {[winfo reqheight $menu]>$height} {return 1}
    set end [$menu index end]
    if {$end ne "none"} {for {set i 0} {$i<=$end} {incr i} {
        if {[$menu type $i] eq "cascade"&&[_uiMenuNeedsPaging [$menu entrycget $i -menu] $height [expr {$depth+1}]]} {return 1}
    }}
    return 0
}
proc ::GX::uiMenuPopup {menu x y} {
    if {![winfo exists $menu]} return
    lassign [uiMenuWorkarea $menu $x $y] left top width height
    # A projection of native Menu entries preserves variables, commands and
    # keyboard/grab behavior. Long cascades are paged, never silently clipped.
    set post [$menu cget -postcommand]
    if {$post ne {}} {uplevel #0 $post}
    update idletasks
    set display $menu
    if {[_uiMenuNeedsPaging $menu [expr {$height-12}]]} {set display [_uiMenuPaged $menu ${menu}_visible [expr {$height-12}] 0 1]}
    update idletasks
    set mw [winfo reqwidth $display];set mh [winfo reqheight $display]
    set px [expr {$x+$mw>$left+$width-6?$x-$mw:$x}]
    set py [expr {$y+$mh>$top+$height-6?$y-$mh:$y}]
    set px [expr {max($left+6,min($px,$left+$width-$mw-6))}]
    set py [expr {max($top+6,min($py,$top+$height-$mh-6))}]
    set displayPost [$display cget -postcommand];$display configure -postcommand {}
    try {tk_popup $display $px $py} finally {if {[winfo exists $display]} {$display configure -postcommand $displayPost}}
    return $display
}

# A single native menu row with an overflow cascade, retaining its final group.
# This is transient UI layout; the original menus still own every command.
namespace eval ::GX::UiMenuRows {variable rows {}}
proc ::GX::uiMenuRowAppend {frame button} {
    if {![dict exists $::GX::UiMenuRows::rows $frame]} return
    if {![winfo exists $button] || [winfo parent $button] ne $frame || [winfo class $button] ni {Button TButton Menubutton TMenubutton}} {error {Appended action must belong to its native menu row}}
    set buttons [dict get $::GX::UiMenuRows::rows $frame buttons]
    set index [lsearch -exact $buttons $button]
    if {$index>=0} {set buttons [lreplace $buttons $index $index]}
    lappend buttons $button
    dict set ::GX::UiMenuRows::rows $frame buttons $buttons
    _uiMenuRowSchedule $frame
}
proc ::GX::uiMenuRowAttach {frame buttons {trailing 1}} {
    if {[llength $buttons]<2 || [llength [lsort -unique $buttons]]!=[llength $buttons]} {error {A menu row requires distinct ordered menubuttons}}
    if {![string is integer -strict $trailing] || $trailing<1 || $trailing>=[llength $buttons]} {error {Invalid retained trailing button count}}
    foreach button $buttons {
        if {[winfo parent $button] ne $frame || [winfo class $button] ni {Button TButton Menubutton TMenubutton}} {error {Action row requires native buttons or menubuttons belonging to its frame}}
        if {[winfo class $button] in {Menubutton TMenubutton} && [$button cget -menu] eq {}} {error {Menubutton requires its native menu}}
    }
    set more $frame.overflow
    ttk::menubutton $more -text More -menu $more.menu
    menu $more.menu -tearoff 0 -postcommand [list ::GX::_uiMenuRowStates $frame]
    dict set ::GX::UiMenuRows::rows $frame [dict create buttons $buttons more $more trailing $trailing hidden {} pending {} layout {}]
    bind $frame <Configure> +[list ::GX::_uiMenuRowSchedule $frame]
    foreach button [concat $buttons $more] {bind $button <Configure> +[list ::GX::_uiMenuRowSchedule $frame]}
    bind $frame <Destroy> +[list ::GX::_uiMenuRowDestroy $frame %W]
    _uiMenuRowSchedule $frame
    return $more
}
proc ::GX::_uiMenuRowStates {frame} {
    if {![dict exists $::GX::UiMenuRows::rows $frame]} return
    set row [dict get $::GX::UiMenuRows::rows $frame];set menu [dict get $row more].menu;set index 0
    foreach button [dict get $row hidden] {
        $menu entryconfigure $index -label [$button cget -text] -state [expr {[$button cget -state] eq "disabled" ? "disabled" : "normal"}]
        incr index
    }
}
proc ::GX::_uiMenuRowDestroy {frame destroyed} {
    if {$frame ne $destroyed || ![dict exists $::GX::UiMenuRows::rows $frame]} return
    set pending [dict get $::GX::UiMenuRows::rows $frame pending]
    if {$pending ne {}} {after cancel $pending}
    dict unset ::GX::UiMenuRows::rows $frame
}
proc ::GX::_uiMenuRowSchedule {frame} {
    if {![dict exists $::GX::UiMenuRows::rows $frame] || [dict get $::GX::UiMenuRows::rows $frame pending] ne {}} return
    dict set ::GX::UiMenuRows::rows $frame pending [after idle [list ::GX::_uiMenuRowLayout $frame]]
}
proc ::GX::_uiMenuRowLayout {frame} {
    if {![winfo exists $frame] || ![dict exists $::GX::UiMenuRows::rows $frame]} return
    dict set ::GX::UiMenuRows::rows $frame pending {}
    set row [dict get $::GX::UiMenuRows::rows $frame];set buttons [dict get $row buttons];set more [dict get $row more]
    set available [expr {max(0,[winfo width $frame]-12)}];set total 0
    foreach button $buttons {incr total [expr {[winfo reqwidth $button]+6}]}
    set shown $buttons;set hidden {}
    if {$total>$available} {
        set trailing [dict get $row trailing]
        set suffix [lrange $buttons end-[expr {$trailing-1}] end]
        set used [expr {[winfo reqwidth $more]+6}];set shown {}
        foreach button $suffix {incr used [expr {[winfo reqwidth $button]+6}]}
        foreach button [lrange $buttons 0 end-$trailing] {
            set width [expr {[winfo reqwidth $button]+6}]
            if {$used+$width<=$available && $hidden eq {}} {lappend shown $button;incr used $width} else {lappend hidden $button}
        }
        lappend shown $more {*}$suffix
    }
    if {$shown eq [dict get $row layout]} return
    foreach button [concat $buttons $more] {pack forget $button}
    $more.menu delete 0 end
    foreach button $hidden {
        if {[winfo class $button] in {Menubutton TMenubutton}} {
            $more.menu add cascade -label [$button cget -text] -menu [$button cget -menu]
        } else {
            # Invoke the original widget, which owns the current command and
            # disabled state; no copied callback or second action registry.
            $more.menu add command -label [$button cget -text] -command [list $button invoke]
        }
    }
    foreach button $shown {pack $button -side left -padx 3}
    dict set ::GX::UiMenuRows::rows $frame layout $shown
    dict set ::GX::UiMenuRows::rows $frame hidden $hidden
}
