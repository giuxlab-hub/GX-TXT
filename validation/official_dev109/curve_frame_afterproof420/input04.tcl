# PREPARATION04 ordinary native input, adapted from literal164/common and consultation44/input.
# Owned display124 only; standalone transport, not a GUI execution release.
# No product setter, widget invoke, event_generate, direct focus/selection/scroll setter.
namespace eval ::qa420 {variable inputs {};variable sequence 0}
proc ::qa420::pause {{ms 200}} {after $ms {set ::qa420::awake 1};vwait ::qa420::awake;update}
proc ::qa420::input {args} {variable inputs;lappend inputs [dict create ms [clock milliseconds] argv $args];exec /usr/bin/xdotool {*}$args;pause}
proc ::qa420::widgets {{w .}} {set r {};foreach c [winfo children $w] {set t {};catch {set t [$c cget -text]};lappend r [list $c [winfo class $c] $t];lappend r {*}[widgets $c]};return $r}
# Read-only owned-client lookup adapted from registered native_window_helpers.
# Local activation deliberately calls only the public X11 desktop tool.
proc ::qa420::client {top} {
    if {$::env(DISPLAY) ne {:124} || ![winfo exists $top] || [winfo toplevel $top] ne $top} {error {Actual owned toplevel on separately leased124 required}}
    set content [winfo id $top];set candidate $content;set hierarchy {}
    for {set depth 0} {$depth<4} {incr depth} {
        set tree [exec /usr/bin/xwininfo -id $candidate -tree]
        set properties [exec /usr/bin/xprop -id $candidate WM_STATE WM_NORMAL_HINTS]
        set parent {};regexp {Parent window id: (0x[0-9a-fA-F]+)} $tree ignored parent
        lappend hierarchy [dict create window $candidate parent $parent properties $properties]
        if {[regexp {WM_STATE\(WM_STATE\):} $properties] && [regexp {WM_NORMAL_HINTS\(WM_SIZE_HINTS\):} $properties]} {return [dict create top $top content $content client $candidate frame [wm frame $top] hierarchy $hierarchy]}
        if {$parent eq {} || $parent eq {0x0} || $parent==$candidate} break
        set candidate $parent
    }
    error "No managed owned client in four ancestors: $hierarchy"
}
proc ::qa420::activate {w} {
    variable inputs
    set top [winfo toplevel $w]
    if {[wm state $top] ne {normal} || ![winfo ismapped $top]} {error {Owned activation target must be mapped and normal}}
    set ownership [client $top]
    input windowactivate --sync [dict get $ownership client]
    set active [exec /usr/bin/xdotool getactivewindow]
    lappend inputs [dict create ms [clock milliseconds] kind activation_observation pid [pid] ownership $ownership actual_active $active]
    if {$active!=[dict get $ownership client]} {error {Actual active WM client differs from owned toplevel}}
    return $ownership
}
proc ::qa420::click {w} {
    if {![winfo exists $w] || ![winfo ismapped $w]} {error "Unmapped native target: $w"}
    activate $w
    set x [expr {[winfo rootx $w]+[winfo width $w]/2}];set y [expr {[winfo rooty $w]+[winfo height $w]/2}]
    if {[winfo containing $x $y] ne $w} {error "Occluded native target: $w"}
    input mousemove $x $y click 1
}
proc ::qa420::key {w args} {activate $w;input key --clearmodifiers {*}$args}
proc ::qa420::button {root text} {set found {};foreach row [widgets $root] {lassign $row w cls label;if {$cls in {TButton TMenubutton Button} && $label eq $text && [winfo ismapped $w]} {lappend found $w}};if {[llength $found]!=1} {error "Unique actual button required: $text ($found)"};return [lindex $found 0]}
proc ::qa420::tab {n target} {
    activate $n;set wanted [$n index $target]
    for {set x 4} {$x<[winfo width $n]-4} {incr x 3} {if {[$n identify tab $x 8] eq $wanted} {input mousemove [expr {[winfo rootx $n]+$x}] [expr {[winfo rooty $n]+8}] click 1;if {[$n select] ne $target} {error {Native tab missed}};return}}
    error "Actual notebook tab unavailable: $target"
}
proc ::qa420::choose {w value} {
    set values [$w cget -values];set index [lsearch -exact $values $value]
    if {$index<0} {error "Actual choice missing: $value"}
    click $w;input key --clearmodifiers Home
    if {$index} {input key --clearmodifiers --repeat $index Down}
    input key --clearmodifiers Return
    if {[$w get] ne $value} {error {Native combobox chose another value}}
}
proc ::qa420::field {form name} {
    set target [dict get $::GX::UiField::forms $form widgets $name].entry
    activate $form
    for {set n 0} {$n<60} {incr n} {
        if {[focus] eq $target && [winfo ismapped $target]} {
            set x [expr {[winfo rootx $target]+[winfo width $target]/2}];set y [expr {[winfo rooty $target]+[winfo height $target]/2}]
            if {[winfo containing $x $y] eq $target} {return $target}
        }
        input key --clearmodifiers Tab
    }
    error "Native Tab could not reveal field $name"
}
proc ::qa420::type {form name value} {set e [field $form $name];click $e;key $e End shift+Home BackSpace;if {$value ne {}} {input type --clearmodifiers --delay 1 -- $value};if {[$e get] ne $value} {error {Typed form value differs}}}
proc ::qa420::menu {button label} {
    click $button;set found {}
    foreach row [widgets .] {lassign $row m cls;if {$cls ne {Menu} || ![winfo ismapped $m] || [$m index end] eq {none}} continue
        for {set i 0} {$i<=[$m index end]} {incr i} {if {![catch {$m entrycget $i -label} t] && $t eq $label} {lappend found [list $m $i]}}
    }
    if {[llength $found]!=1} {error "Unique mapped menu row required: $label"}
    lassign [lindex $found 0] m i
    set y [$m yposition $i];set next [expr {$i<[$m index end]?[$m yposition [expr {$i+1}]]:[winfo height $m]-2}]
    record native_menu [dict create menu $m index $i label $label command_readonly [$m entrycget $i -command]]
    input mousemove [expr {[winfo rootx $m]+min(60,[winfo width $m]/2)}] [expr {[winfo rooty $m]+($y+$next)/2}] click 1
}
proc ::qa420::treeSelect {tree node} {
    click $tree;key $tree ctrl+Home
    for {set n 0} {$n<180} {incr n} {
        if {[$tree selection] eq [list $node]} {set box [$tree bbox $node];if {[llength $box]!=4} {error {Native selected row clipped}};return $box}
        input key --clearmodifiers Down
    }
    error "Native tree cannot reach actual node $node"
}
proc ::qa420::capture {name {top .curve_workbench}} {variable gui;update;exec timeout 10s import -screen -window [wm frame $top] [file join $gui $name.png];record ${name}_pixels [dict create pid [pid] display $::env(DISPLAY) native_frame [wm frame $top] geometry [winfo geometry $top]]}
