# SPDX-License-Identifier: GPL-3.0-or-later
# Presentation-only, per-graph and per-axis Level Scale API v1.
namespace eval ::GX {
    variable levelScaleApiVersion 1
    variable levelScale
    array set levelScale {}
}

proc ::GX::levelScaleDefaults {} {
    return [dict create scale linear quantity_kind "" amplitude_basis "" reference_value "" reference_unit "" zero_policy missing]
}
proc ::GX::levelScaleValidate {fields} {
    set d [dict merge [levelScaleDefaults] $fields]
    foreach k [dict keys $d] {if {$k ni {scale quantity_kind amplitude_basis reference_value reference_unit zero_policy}} {error "Unknown level scale field: $k"}}
    set scale [dict get $d scale]
    if {$scale ni {linear dB dBFS FS}} {error "Invalid level scale: $scale"}
    if {$scale ne "linear"} {
        if {[dict get $d quantity_kind] ni {amplitude power}} {error "Level scale requires explicit amplitude or power quantity_kind"}
        if {[dict get $d quantity_kind] eq "amplitude" && [dict get $d amplitude_basis] ni {peak rms}} {error "Amplitude level scale requires explicit peak or rms basis"}
        if {![string is double -strict [dict get $d reference_value]]} {error "Level scale requires a numeric reference_value"}
        set ref [dict get $d reference_value]
        if {[catch {expr {double($ref) > 0 && double($ref) < Inf}} valid] || !$valid} {error "Level scale reference_value must be finite and positive"}
        if {[string trim [dict get $d reference_unit]] eq ""} {error "Level scale requires explicit reference_unit"}
        if {[dict get $d zero_policy] ni {missing negative_infinity}} {error "Invalid zero_policy"}
    }
    foreach v [dict values $d] {if {[regexp {[
]} $v]} {error "Level scale fields must be single-line"}}
    return $d
}
proc ::GX::levelScaleSet {graphId axis fields} {
    variable levelScale
    if {![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} $graphId]} {error "Invalid graph ID"}
    if {$axis ni {y y2 z}} {error "Level scale axis must be y, y2 or z"}
    set levelScale($graphId,$axis) [levelScaleValidate $fields]
    return $levelScale($graphId,$axis)
}
proc ::GX::levelScaleGet {graphId axis} {
    variable levelScale
    if {$axis ni {y y2 z}} {error "Level scale axis must be y, y2 or z"}
    if {[info exists levelScale($graphId,$axis)]} {return $levelScale($graphId,$axis)}
    return [levelScaleDefaults]
}

proc ::GX::manifestStringV2_before_viewer_provider {} {
    variable levelScale
    set out [::GX::manifestStringV2_before_level_scale]
    append out "\n\[level_scale_api\]\n"; appendKV out version 1
    foreach key [lsort [array names levelScale]] {
        lassign [split $key ,] graph axis
        append out "\n\[level_scale.$graph.$axis\]\n"
        dict for {field value} $levelScale($key) {appendKV out $field $value}
    }
    return $out
}
proc ::GX::loadManifestV2_before_viewer_provider {path} {
    variable levelScale
    array unset levelScale *
    ::GX::loadManifestV2_before_level_scale $path
    set ini [parseIni $path]
    foreach key [dict keys $ini "level_scale.*.scale"] {
        set tail [string range $key [string length "level_scale."] end-[string length ".scale"]]
        set dot [string last . $tail]
        if {$dot < 1} continue
        set graph [string range $tail 0 [expr {$dot-1}]]
        set axis [string range $tail [expr {$dot+1}] end]
        set fields [dict create]
        foreach field {scale quantity_kind amplitude_basis reference_value reference_unit zero_policy} {
            set name "level_scale.$graph.$axis.$field"
            if {[dict exists $ini $name]} {dict set fields $field [dict get $ini $name]}
        }
        levelScaleSet $graph $axis $fields
    }
}
proc ::GX::writeStandardRuntimeConfig_before_viewer_provider {moduleId} {
    set path [::GX::writeStandardRuntimeConfig_before_level_scale $moduleId]
    set fd [open $path a]; fconfigure $fd -encoding utf-8 -translation lf
    foreach graph [moduleGraphIds $moduleId] {
        foreach axis {y y2 z} {
            set d [levelScaleGet $graph $axis]
            puts $fd "\n\[level_scale.$graph.$axis\]"
            foreach field {scale quantity_kind amplitude_basis reference_value reference_unit zero_policy} {putKV $fd $field [dict get $d $field]}
        }
    }
    close $fd
    return $path
}
proc ::GX::defaults_before_viewer_provider {} {
    ::GX::defaults_before_level_scale
    array unset ::GX::levelScale *
}

# The level editor is separate from display units; it is reachable from the
# existing graph axes dialog and uses the same selected graph ID.
proc ::GX::axisConfigDialog {} {
    ::GX::axisConfigDialog_before_level_scale
    if {![winfo exists .axiscfg]} return
    set p [currentGraphPath]; set graph [graphKeyForPath $p]
    # plot.dataset multi-panel/notebook usability: the shared Axes dialog body may be canvas-scrolled; attach this existing action to its real button frame.
    set bf [expr {[winfo exists .axiscfg.viewport.canvas.body.b] ? ".axiscfg.viewport.canvas.body.b" : ".axiscfg.b"}]
    ttk::button $bf.level -text "Level scales..." -command [list ::GX::levelScaleDialog $graph $p]
    pack $bf.level -side left -padx 4
}
proc ::GX::levelScaleAxesForGraph {graph path} {
    if {$path ne "" && [plotMetadataAxisUnit $path z] ne ""} { return {y y2 z} }
    foreach module $::GX::moduleOrder {
        foreach gid [moduleGraphIds $module] {
            if {$graph ne $gid && ![string match "$gid.p*" $graph]} continue
            if {[lsearch -exact [moduleGraphConfigKeys $module $gid] z_label] >= 0} { return {y y2 z} }
        }
    }
    return {y y2}
}
proc ::GX::levelScaleDialog {graph path} {
    variable ui
    set w .levelscale; catch {destroy $w}; toplevel $w
    wm title $w "Level scales - $graph"; wm transient $w .axiscfg
    ttk::label $w.note -text "References and peak/RMS basis are explicit. Values stay unchanged in the dataset. Each axis has its own scale." -wraplength 720 -justify left
    grid $w.note -row 0 -column 0 -columnspan 7 -sticky ew -padx 8 -pady 8
    foreach {col title} {0 Axis 1 Scale 2 Quantity 3 Basis 4 Reference 5 "Reference unit" 6 Zero} {
        ttk::label $w.h$col -text $title; grid $w.h$col -row 1 -column $col -padx 4 -sticky w
    }
    set row 2
    foreach axis [levelScaleAxesForGraph $graph $path] {
        set d [levelScaleGet $graph $axis]
        foreach f {scale quantity_kind amplitude_basis reference_value reference_unit zero_policy} {set ui(levelScale,$axis,$f) [dict get $d $f]}
        ttk::label $w.a$row -text [expr {$axis eq "y" ? "Y1" : ($axis eq "y2" ? "Y2" : "Z")}]
        ttk::combobox $w.s$row -textvariable ::GX::ui(levelScale,$axis,scale) -values {linear dB dBFS FS} -state readonly -width 9
        ttk::combobox $w.q$row -textvariable ::GX::ui(levelScale,$axis,quantity_kind) -values {amplitude power} -state readonly -width 12
        ttk::combobox $w.b$row -textvariable ::GX::ui(levelScale,$axis,amplitude_basis) -values {peak rms} -state readonly -width 8
        ttk::entry $w.r$row -textvariable ::GX::ui(levelScale,$axis,reference_value) -width 13
        ttk::entry $w.u$row -textvariable ::GX::ui(levelScale,$axis,reference_unit) -width 13
        ttk::combobox $w.z$row -textvariable ::GX::ui(levelScale,$axis,zero_policy) -values {missing negative_infinity} -state readonly -width 18
        foreach {col name} {0 a 1 s 2 q 3 b 4 r 5 u 6 z} {grid $w.$name$row -row $row -column $col -padx 4 -pady 3}
        incr row
    }
    ttk::label $w.hint -text "dB uses 20 log10(|x|/ref) for amplitude, 10 log10(x/ref) for power. dBFS/FS use the stated full-scale reference. Nonfinite samples become missing." -wraplength 720 -justify left
    grid $w.hint -row $row -column 0 -columnspan 7 -sticky ew -padx 8 -pady 8
    ttk::button $w.save -text Save -command [list ::GX::levelScaleDialogSave $w $graph $path 0]
    ttk::button $w.render -text "Save and rerender" -command [list ::GX::levelScaleDialogSave $w $graph $path 1]
    incr row
    grid $w.save -row $row -column 4 -padx 4 -pady 8; grid $w.render -row $row -column 5 -columnspan 2 -padx 4
}
proc ::GX::levelScaleDialogSave {w graph path rerender} {
    variable ui; variable levelScale
    set pending [dict create]
    foreach axis [levelScaleAxesForGraph $graph $path] {
        set d [dict create]
        foreach f {scale quantity_kind amplitude_basis reference_value reference_unit zero_policy} {dict set d $f [string trim $ui(levelScale,$axis,$f)]}
        if {[catch {set d [levelScaleValidate $d]} err]} {tk_messageBox -parent $w -icon error -message "$axis: $err"; return}
        if {[dict get $d scale] ne "linear"} {
            set sourceUnit [plotMetadataAxisUnit $path $axis]
            if {$sourceUnit ne "" && ![unitTclCompatible $sourceUnit [dict get $d reference_unit]]} {
                tk_messageBox -parent $w -icon error -message "$axis: reference unit is incompatible with source unit $sourceUnit"
                return
            }
        }
        dict set pending $axis $d
    }
    foreach axis [dict keys $pending] {set levelScale($graph,$axis) [dict get $pending $axis]}
    destroy $w
    refreshManifestPreview
    if {$rerender} {startRerenderPaths [list $path]}
}
