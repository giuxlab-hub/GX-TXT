# GX-TXT Scientific Plot Framework API v1
# SPDX-License-Identifier: GPL-3.0-or-later
# v0.9.3.3 additive framework capabilities for generic scientific 2D/3D plotters.
# v0.9.7.1: identity-preserved FS, dB and dBFS; v0.9.7.3 adds ppm and pH.

namespace eval ::GX {
    variable scientificPlotFrameworkApiVersion 1
}

# -----------------------------------------------------------------------------
# Unit selector API v1
# -----------------------------------------------------------------------------

proc ::GX::unitTclPrefixScale {p} {
    switch -- $p {
        "" {return 1.0}
        da {return 1e1}
        G {return 1e9}
        M {return 1e6}
        k {return 1e3}
        h {return 1e2}
        d {return 1e-1}
        c {return 1e-2}
        m {return 1e-3}
        u {return 1e-6}
        n {return 1e-9}
        p {return 1e-12}
        default {error "Unknown unit prefix '$p'"}
    }
}

proc ::GX::unitTclBaseDims {base} {
    switch -- $base {
        A {return [dict create A 1]}
        V {return [dict create V 1]}
        s {return [dict create s 1]}
        Hz {return [dict create s -1]}
        Ohm {return [dict create V 1 A -1]}
        W {return [dict create V 1 A 1]}
        J {return [dict create V 1 A 1 s 1]}
        K {return [dict create K 1]}
        mol {return [dict create mol 1]}
        m {return [dict create m 1]}
        g {return [dict create g 1]}
        default {error "Unknown base unit '$base'"}
    }
}

proc ::GX::unitTclSingle {sym} {
    set sym [string map [list "µ" u "μ" u "Ω" Ohm] $sym]
    if {$sym eq "min"} {return [list 60.0 s [unitTclBaseDims s]]}
    if {$sym eq "h"} {return [list 3600.0 s [unitTclBaseDims s]]}
    if {$sym eq "day"} {return [list 86400.0 s [unitTclBaseDims s]]}
    set bases {A V s Hz Ohm W J K mol m g}
    if {[lsearch -exact $bases $sym] >= 0} {return [list 1.0 $sym [unitTclBaseDims $sym]]}
    foreach p {da G M k h d c m u n p} {
        if {[string length $sym] <= [string length $p]} continue
        if {[string range $sym 0 [expr {[string length $p]-1}]] ne $p} continue
        set b [string range $sym [string length $p] end]
        if {[lsearch -exact $bases $b] >= 0} {return [list [unitTclPrefixScale $p] $b [unitTclBaseDims $b]]}
    }
    error "Unknown unit '$sym'"
}

proc ::GX::unitTclSemanticKey {unit} {
    set unit [string trim $unit]
    if {$unit in {dB dBFS FS ppm pH}} {return $unit}
    return ""
}

proc ::GX::unitTclDimensionKey {unit} {
    set unit [string trim [string map [list "µ" u "μ" u "Ω" Ohm "·" *] $unit]]
    if {$unit eq "" || $unit in {1 dimensionless}} {return "1"}
    set sem [unitTclSemanticKey $unit]
    if {$sem ne ""} {return "semantic:$sem"}
    set dims [dict create]
    set pos 0
    set sign 1
    set n [string length $unit]
    while {$pos < $n} {
        set ch [string index $unit $pos]
        if {$ch eq "*"} {set sign 1; incr pos; continue}
        if {$ch eq "/"} {set sign -1; incr pos; continue}
        set rest [string range $unit $pos end]
        if {![regexp {^([A-Za-z]+)(?:\^([+-]?[0-9]+))?} $rest whole sym pw]} {error "Unsupported unit expression '$unit'"}
        if {$pw eq ""} {set pw 1}
        set pw [expr {$pw * $sign}]
        lassign [unitTclSingle $sym] scale base bd
        dict for {k v} $bd {
            set cur [expr {[dict exists $dims $k] ? [dict get $dims $k] : 0}]
            set nv [expr {$cur + $v*$pw}]
            if {$nv == 0} {catch {dict unset dims $k}} else {dict set dims $k $nv}
        }
        incr pos [string length $whole]
        set sign 1
    }
    if {[dict size $dims] == 0} {return "1"}
    set parts {}
    foreach k [lsort [dict keys $dims]] {lappend parts "$k:[dict get $dims $k]"}
    return [join $parts ,]
}

proc ::GX::unitTclCompatible_before_unit_registry {a b} {
    if {[catch {set ka [unitTclDimensionKey $a]}] || [catch {set kb [unitTclDimensionKey $b]}]} {return 0}
    return [expr {$ka eq $kb}]
}

proc ::GX::unitSelectorCandidates_before_unit_registry {} {
    return {ns us ms s min h day pA nA uA mA A kA MA GA pV nV uV mV V kV MV GV pHz nHz uHz mHz Hz kHz MHz GHz pW nW uW mW W kW MW GW pJ nJ uJ mJ J kJ MJ GJ pm nm um mm cm m km pg ng ug mg g kg K mol Ohm kOhm MOhm FS dB dBFS ppm pH}
}

proc ::GX::unitDisplayChoicesForSource {sourceUnit {includeInherit 0}} {
    set out {}
    if {$includeInherit} {lappend out inherit}
    lappend out auto source
    set sourceUnit [string trim $sourceUnit]
    # Without authoritative source metadata there is no safe basis for an
    # explicit conversion. Keep only the non-converting/automatic choices.
    if {$sourceUnit eq ""} {return $out}
    foreach u [unitSelectorCandidates] {
        if {[unitTclCompatible $sourceUnit $u]} {lappend out $u}
    }
    if {[lsearch -exact $out $sourceUnit] < 0} {lappend out $sourceUnit}
    return $out
}

proc ::GX::unitSelectorSourceInfo {moduleId key} {
    variable moduleCfg
    variable currentSession
    set source [string trim [moduleConfigField $moduleId $key source [moduleConfigField $moduleId $key source_role primary]]]
    if {$source eq ""} {set source primary}
    set variable ""
    set binding [string trim [moduleConfigField $moduleId $key binding ""]]
    if {$binding ne ""} {
        set q ""
        catch {set q [resolveModuleBinding $moduleId $binding ""]}
        if {$q ne "" && $q ne "auto"} {
            set dot [string first . $q]
            if {$dot > 0} {set source [string range $q 0 [expr {$dot-1}]]; set variable [string range $q [expr {$dot+1}] end]} else {set variable $q}
        }
    }
    if {$variable eq ""} {
        set vc [string trim [moduleConfigField $moduleId $key variable_config ""]]
        if {$vc ne "" && [info exists moduleCfg($moduleId,$vc)]} {
            set q [string trim $moduleCfg($moduleId,$vc)]
            set dot [string first . $q]
            if {$dot > 0} {set source [string range $q 0 [expr {$dot-1}]]; set variable [string range $q [expr {$dot+1}] end]} else {set variable $q}
        }
    }
    if {$variable eq ""} {set variable [string trim [moduleConfigField $moduleId $key variable ""]]}
    set ds ""
    if {$currentSession ne "" && [file isdirectory $currentSession]} {
        catch {loadDatasetRegistry $currentSession}
        if {[llength [info commands ::GX::analysisSourceDatasetFor]] && [moduleSupportsAnalysisSources $moduleId]} {
            catch {set ds [analysisSourceDatasetFor $moduleId $source]}
        }
        if {$ds eq "" && [info exists moduleCfg($moduleId,dataset_id)]} {set ds [string trim $moduleCfg($moduleId,dataset_id)]}
    }
    set unit ""; set role ""
    if {$ds ne "" && $variable ne "" && [llength [info commands ::GX::analysisSourceDatasetVariables]]} {
        foreach m [analysisSourceDatasetVariables $ds] {
            if {[dict get $m name] eq $variable} {set unit [dict get $m unit]; set role [dict get $m semantic_role]; break}
        }
    }
    return [dict create source_role $source dataset_id $ds variable $variable unit $unit semantic_role $role]
}

proc ::GX::unitSelectorRefreshWidget {widget moduleId key} {
    if {![winfo exists $widget]} return
    set info [unitSelectorSourceInfo $moduleId $key]
    set values [unitDisplayChoicesForSource [dict get $info unit] 0]
    $widget configure -values $values
}

proc ::GX::standardConfigWidget_before_temporal_set_v1 {parent id key row} {
    variable moduleCfg
    set type [string tolower [moduleConfigField $id $key type string]]
    if {$type ne "unit"} {return [::GX::standardConfigWidget_v0933_before_unit_selector $parent $id $key $row]}
    set label [moduleConfigField $id $key label $key]
    if {![info exists moduleCfg($id,$key)] || [string trim $moduleCfg($id,$key)] eq ""} {set moduleCfg($id,$key) [moduleConfigField $id $key default auto]}
    ttk::label $parent.l$row -text $label
    set info [unitSelectorSourceInfo $id $key]
    ttk::combobox $parent.w$row -textvariable ::GX::moduleCfg($id,$key) -values [unitDisplayChoicesForSource [dict get $info unit] 0] -state readonly -width 24
    bind $parent.w$row <Button-1> [list ::GX::unitSelectorRefreshWidget $parent.w$row $id $key]
    grid $parent.l$row -row $row -column 0 -sticky e -padx 4 -pady 2
    grid $parent.w$row -row $row -column 1 -sticky w -padx 4 -pady 2
}

proc ::GX::writeStandardRuntimeConfig_v0941_before_computed_annotations {id} {
    variable moduleCfg
    set path [::GX::writeStandardRuntimeConfig_v0933_before_unit_selector $id]
    set found 0
    foreach key [moduleConfigKeys $id] {if {[string tolower [moduleConfigField $id $key type string]] eq "unit"} {set found 1; break}}
    if {!$found} {return $path}
    set fd [open $path a]; fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "\n\[unit_selector_api\]"; putKV $fd api_version 1
    foreach key [moduleConfigKeys $id] {
        if {[string tolower [moduleConfigField $id $key type string]] ne "unit"} continue
        set mode [expr {[info exists moduleCfg($id,$key)] ? [string trim $moduleCfg($id,$key)] : [moduleConfigField $id $key default auto]}]
        set required [expr {[moduleConfigField $id $key required 0] ? 1 : 0}]
        if {$mode eq ""} {if {$required} {close $fd; error "$id: unit selector '$key' is required."} else {set mode source}}
        set info [unitSelectorSourceInfo $id $key]
        set srcUnit [dict get $info unit]
        if {$mode ni {auto source inherit none} && $srcUnit ne "" && ![unitTclCompatible $srcUnit $mode]} {close $fd; error "$id: display unit '$mode' is incompatible with source unit '$srcUnit' for '$key'."}
        puts $fd "\n\[unit_selector.$key\]"
        putKV $fd api_version 1; putKV $fd mode $mode
        foreach f {source_role dataset_id variable unit semantic_role} {putKV $fd $f [dict get $info $f]}
    }
    close $fd
    return $path
}

# -----------------------------------------------------------------------------
# First-class Z/view/color axis state. Old axis sections remain untouched;
# new fields are additive and stored in plot.axis3d.* manifest sections.
# -----------------------------------------------------------------------------

proc ::GX::plot3dAxisFieldDefaults {} {
    return {x_scale inherit y_scale inherit y2_scale inherit xy_aspect_mode inherit z_unit inherit z_label "" z_min "" z_max "" z_step "" z_format inherit z_scale inherit zgrid inherit view_azimuth "" view_elevation "" projection inherit aspect_mode inherit aspect_ratio "" colormap inherit colorbar_visible inherit colorbar_label "" color_unit inherit color_min "" color_max "" background "" title "" x_label "" y_label "" y2_label ""}
}

proc ::GX::plot3dAspectValidate {mode ratio {allowInherit 1}} {
    set mode [string tolower [string trim $mode]]
    set choices {auto xy_equal data_equal manual}
    if {$allowInherit} {lappend choices inherit}
    if {$mode ni $choices} {error "3D aspect mode must be [join $choices {, }]."}
    set ratio [string trim $ratio]
    if {$mode eq "manual" && $ratio eq ""} {error "Manual 3D aspect requires X;Y;Z values."}
    if {$ratio ne ""} {
        set parts [regexp -all -inline {[^,;[:space:]]+} $ratio]
        if {[llength $parts] != 3} {error "Manual 3D aspect requires exactly three X;Y;Z values."}
        foreach value $parts {
            if {![string is double -strict $value] || [catch {expr {double($value) > 0 && double($value) < Inf}} valid] || !$valid} {
                error "3D aspect values must be finite and positive."
            }
        }
    }
}

proc ::GX::axisOverrideEnsure {gk panels} {
    variable axisOverride
    ::GX::axisOverrideEnsure_v0933_before_3d $gk $panels
    foreach {f d} [plot3dAxisFieldDefaults] {if {![info exists axisOverride($gk,$f)]} {set axisOverride($gk,$f) $d}}
}

proc ::GX::plotMetadataDictForPath {path} {
    if {$path eq ""} {return [dict create]}
    set fn [file join [file dirname $path] .gxtxt_plotmeta "[file rootname [file tail $path]].ini"]
    if {![file isfile $fn]} {return [dict create]}
    if {[catch {set d [parseIni $fn]}]} {return [dict create]}
    return $d
}

proc ::GX::plotMetadataAxisUnit {path which} {
    set d [plotMetadataDictForPath $path]
    switch -- $which {
        x - y - z - c {set key "axis.1.${which}_source_unit"}
        y2 {set key "overlay_axis.1.y_source_unit"}
        default {return ""}
    }
    return [expr {[dict exists $d $key] ? [dict get $d $key] : ""}]
}

# Global defaults for common 3D/color presentation. They are intentionally
# presentation-only and do not alter datasets.
proc ::GX::defaults_before_graph_series {} {
    variable cfg
    ::GX::defaults_v0933_before_plot3d
    foreach {k v} {plot_3d_azimuth -37.5 plot_3d_elevation 30 plot_3d_projection orthographic plot_3d_aspect_mode auto plot_3d_aspect_ratio "" plot_colormap viridis plot_colorbar_visible 0 plot_colorbar_label "" plot_color_unit auto plot_color_min "" plot_color_max ""} {
        if {![info exists cfg($k)]} {set cfg($k) $v}
    }
}

proc ::GX::plotEnv_before_unit_registry {{moduleId ""}} {
    variable cfg
    set out [::GX::plotEnv_v0933_before_plot3d $moduleId]
    foreach {key env} {
        plot_3d_azimuth GXTXT_PLOT3D_AZIMUTH
        plot_3d_elevation GXTXT_PLOT3D_ELEVATION
        plot_3d_projection GXTXT_PLOT3D_PROJECTION
        plot_3d_aspect_mode GXTXT_PLOT3D_ASPECT_MODE
        plot_3d_aspect_ratio GXTXT_PLOT3D_ASPECT_RATIO
        plot_colormap GXTXT_PLOT_COLORMAP
        plot_colorbar_visible GXTXT_PLOT_COLORBAR_VISIBLE
        plot_colorbar_label GXTXT_PLOT_COLORBAR_LABEL
        plot_color_unit GXTXT_PLOT_COLOR_UNIT
        plot_color_min GXTXT_PLOT_COLOR_MIN
        plot_color_max GXTXT_PLOT_COLOR_MAX
    } {if {[info exists cfg($key)]} {set out [envListReplace $out $env $cfg($key)]}}
    return $out
}

# Extend module-wide graphics inheritance with 3D/color fields.
proc ::GX::moduleGraphicsFields {} {
    set base [::GX::moduleGraphicsFields_v0933_before_3d]
    return [concat $base {view_azimuth view_elevation projection aspect_mode aspect_ratio colormap colorbar_visible colorbar_label color_unit color_min color_max}]
}
proc ::GX::moduleGraphicsEnvMap {} {
    set d [::GX::moduleGraphicsEnvMap_v0933_before_3d]
    dict set d view_azimuth GXTXT_PLOT3D_AZIMUTH; dict set d view_elevation GXTXT_PLOT3D_ELEVATION; dict set d projection GXTXT_PLOT3D_PROJECTION
    dict set d aspect_mode GXTXT_PLOT3D_ASPECT_MODE; dict set d aspect_ratio GXTXT_PLOT3D_ASPECT_RATIO
    dict set d colormap GXTXT_PLOT_COLORMAP; dict set d colorbar_visible GXTXT_PLOT_COLORBAR_VISIBLE; dict set d colorbar_label GXTXT_PLOT_COLORBAR_LABEL
    dict set d color_unit GXTXT_PLOT_COLOR_UNIT; dict set d color_min GXTXT_PLOT_COLOR_MIN; dict set d color_max GXTXT_PLOT_COLOR_MAX
    return $d
}

# Persist global 3D/color presentation and plot-specific 3D additions in
# Manifest Format 2 without modifying existing sections.
proc ::GX::manifestStringV2_before_variable_ids {} {
    variable cfg
    variable axisOverride
    set out [::GX::manifestStringV2_v0933_before_plot3d]
    append out "\n\[scientific_plot_framework_api\]\n"; appendKV out version 1
    append out "\n\[unit_selector_api\]\n"; appendKV out version 1
    append out "\n\[graphics_3d\]\n"
    foreach k {plot_3d_azimuth plot_3d_elevation plot_3d_projection plot_3d_aspect_mode plot_3d_aspect_ratio plot_colormap plot_colorbar_visible plot_colorbar_label plot_color_unit plot_color_min plot_color_max} {appendKV out $k $cfg($k)}
    set keys {}
    foreach k [array names axisOverride "*,enabled"] {set gk [string range $k 0 end-8]; if {[lsearch -exact $keys $gk] < 0} {lappend keys $gk}}
    foreach gk [lsort $keys] {
        append out "\n\[plot.axis3d.$gk\]\n"
        foreach {f d} [plot3dAxisFieldDefaults] {appendKV out $f [expr {[info exists axisOverride($gk,$f)] ? $axisOverride($gk,$f) : $d}]}
    }
    return $out
}

proc ::GX::loadManifestV2_before_variable_ids {path} {
    variable cfg
    variable axisOverride
    ::GX::loadManifestV2_v0933_before_plot3d $path
    set d [parseIni $path]
    foreach k {plot_3d_azimuth plot_3d_elevation plot_3d_projection plot_3d_aspect_mode plot_3d_aspect_ratio plot_colormap plot_colorbar_visible plot_colorbar_label plot_color_unit plot_color_min plot_color_max} {
        set dk "graphics_3d.$k"; if {[dict exists $d $dk]} {set cfg($k) [dict get $d $dk]}
    }
    # Discover v0.9.3.3 sections independently of the historical 2D key list.
    # This also persists a 3D-only Graph Provider that had no legacy axis row.
    set graphKeys {}
    foreach dk [dict keys $d "plot.axis3d.*"] {
        foreach {f def} [plot3dAxisFieldDefaults] {
            set suffix ".$f"
            if {[string length $dk] > [expr {12+[string length $suffix]}] && [string equal [string range $dk end-[expr {[string length $suffix]-1}] end] $suffix]} {
                set gk [string range $dk 12 end-[string length $suffix]]
                if {$gk ne "" && [lsearch -exact $graphKeys $gk] < 0} {lappend graphKeys $gk}
            }
        }
    }
    if {[dict exists $d plot.axis.overrides.keys]} {
        foreach gk [splitList [dict get $d plot.axis.overrides.keys]] {if {[lsearch -exact $graphKeys $gk] < 0} {lappend graphKeys $gk}}
    }
    foreach gk $graphKeys {
        axisOverrideEnsure $gk {}
        foreach {f def} [plot3dAxisFieldDefaults] {set dk "plot.axis3d.$gk.$f"; if {[dict exists $d $dk]} {set axisOverride($gk,$f) [dict get $d $dk]}}
    }
}

# Runtime transport extends the existing [axis.<graph>] section additively.
proc ::GX::appendAxisRuntimeSections {fd id} {
    variable axisOverride
    # Reimplement rather than duplicate sections: preserve every historical
    # field and append the new Z/view/color keys in the same section.
    foreach graph [moduleGraphIds $id] {
        # Plot layout shares the per-graph store but is independent from the
        # Axes dialog enabled flag. Preserve its fields in this final 3D-aware
        # runtime writer; otherwise the later wrapper silently discards the
        # values emitted by the base writer and Apply and rerender has no effect.
        if {![info exists axisOverride($graph,enabled)] && ![info exists axisOverride($graph,layout_auto)]} continue
        axisOverrideEnsure $graph [expr {[info exists axisOverride($graph,panels)] ? $axisOverride($graph,panels) : {}}]
        puts $fd "\n\[axis.$graph\]"
        foreach {field def} {enabled 1 time_unit inherit x_unit inherit y_unit inherit y2_unit inherit align_ylabels inherit ylabel_x "" x_min "" x_max "" x_step "" x_format inherit y_min "" y_max "" y_step "" y2_min "" y2_max "" y2_step "" y2_format inherit xgrid inherit ygrid inherit ygrid_source inherit grid_color "" layout_auto 1 layout_margin_left "" layout_margin_right "" layout_margin_top "" layout_margin_bottom "" layout_gap "" layout_ylabel_dist "" layout_ylabel_allow_negative 0} {
            set v [expr {[info exists axisOverride($graph,$field)] ? $axisOverride($graph,$field) : $def}]; putKV $fd $field $v
        }
        foreach {field def} [plot3dAxisFieldDefaults] {set v [expr {[info exists axisOverride($graph,$field)] ? $axisOverride($graph,$field) : $def}]; putKV $fd $field $v}
        set panels [expr {[info exists axisOverride($graph,panels)] ? $axisOverride($graph,panels) : {}}]
        putKV $fd panel_count [llength $panels]
        set pi 0
        foreach pn $panels {
            incr pi; putKV $fd "panel${pi}_name" $pn
            foreach {field def} {y_min "" y_max "" y_step "" y_format inherit y2_min "" y2_max "" y2_step "" y2_format inherit xgrid inherit ygrid inherit ygrid_source inherit grid_color "" ylabel_x ""} {
                set ak "$graph,$pn,$field"; set v [expr {[info exists axisOverride($ak)] ? $axisOverride($ak) : $def}]; putKV $fd "panel${pi}_$field" $v
            }
        }
    }
}

# Add global common 3D/color controls without altering the historical dialog.
proc ::GX::globalGraphicsDialog {} {
    variable cfg
    ::GX::globalGraphicsDialog_v0933_before_3d
    set w .globalgfx
    if {![winfo exists $w]} return
    set r [expr {[lindex [grid size $w] 1] + 1}]
    ttk::labelframe $w.plot3d -text "3D view and color defaults"
    grid $w.plot3d -row $r -column 0 -columnspan 3 -sticky ew -padx 10 -pady 6
    foreach c {1 3 5} {grid columnconfigure $w.plot3d $c -weight 1}
    ttk::label $w.plot3d.azl -text "Azimuth"; ttk::entry $w.plot3d.az -textvariable ::GX::cfg(plot_3d_azimuth) -width 10
    ttk::label $w.plot3d.ell -text "Elevation"; ttk::entry $w.plot3d.el -textvariable ::GX::cfg(plot_3d_elevation) -width 10
    ttk::label $w.plot3d.prl -text "Projection"; ttk::combobox $w.plot3d.pr -textvariable ::GX::cfg(plot_3d_projection) -values {orthographic perspective} -state readonly -width 13
    grid $w.plot3d.azl -row 0 -column 0 -sticky e -padx 3; grid $w.plot3d.az -row 0 -column 1 -sticky w -padx 3
    grid $w.plot3d.ell -row 0 -column 2 -sticky e -padx 3; grid $w.plot3d.el -row 0 -column 3 -sticky w -padx 3
    grid $w.plot3d.prl -row 0 -column 4 -sticky e -padx 3; grid $w.plot3d.pr -row 0 -column 5 -sticky w -padx 3
    ttk::label $w.plot3d.cml -text "Colormap"; ttk::entry $w.plot3d.cm -textvariable ::GX::cfg(plot_colormap) -width 14
    ttk::label $w.plot3d.cbl -text "Colorbar"; ttk::combobox $w.plot3d.cb -textvariable ::GX::cfg(plot_colorbar_visible) -values {0 1} -state readonly -width 6
    ttk::label $w.plot3d.cul -text "Color unit"; ttk::combobox $w.plot3d.cu -textvariable ::GX::cfg(plot_color_unit) -values [unitDisplayChoicesForSource "" 0] -width 12
    grid $w.plot3d.cml -row 1 -column 0 -sticky e -padx 3 -pady 3; grid $w.plot3d.cm -row 1 -column 1 -sticky w -padx 3
    grid $w.plot3d.cbl -row 1 -column 2 -sticky e -padx 3; grid $w.plot3d.cb -row 1 -column 3 -sticky w -padx 3
    grid $w.plot3d.cul -row 1 -column 4 -sticky e -padx 3; grid $w.plot3d.cu -row 1 -column 5 -sticky w -padx 3
    ttk::label $w.plot3d.cl -text "Colorbar label"; ttk::entry $w.plot3d.ce -textvariable ::GX::cfg(plot_colorbar_label) -width 28
    ttk::label $w.plot3d.cminl -text "CLim min"; ttk::entry $w.plot3d.cmin -textvariable ::GX::cfg(plot_color_min) -width 10
    ttk::label $w.plot3d.cmaxl -text "CLim max"; ttk::entry $w.plot3d.cmax -textvariable ::GX::cfg(plot_color_max) -width 10
    grid $w.plot3d.cl -row 2 -column 0 -sticky e -padx 3; grid $w.plot3d.ce -row 2 -column 1 -columnspan 2 -sticky ew -padx 3
    grid $w.plot3d.cminl -row 2 -column 3 -sticky e -padx 3; grid $w.plot3d.cmin -row 2 -column 4 -sticky w -padx 3
    grid $w.plot3d.cmaxl -row 2 -column 5 -sticky e -padx 3; grid $w.plot3d.cmax -row 2 -column 6 -sticky w -padx 3
    ttk::label $w.plot3d.aml -text "3D aspect"
    ttk::combobox $w.plot3d.am -textvariable ::GX::cfg(plot_3d_aspect_mode) -values {auto xy_equal data_equal manual} -state readonly -width 13
    ttk::label $w.plot3d.arl -text "Manual X;Y;Z"
    ttk::entry $w.plot3d.ar -textvariable ::GX::cfg(plot_3d_aspect_ratio) -width 18
    grid $w.plot3d.aml -row 3 -column 0 -sticky e -padx 3; grid $w.plot3d.am -row 3 -column 1 -sticky w -padx 3
    grid $w.plot3d.arl -row 3 -column 2 -sticky e -padx 3; grid $w.plot3d.ar -row 3 -column 3 -columnspan 2 -sticky w -padx 3
}

# Extend global validation to the new framework-owned 3D/color defaults.
proc ::GX::globalGraphicsApply {{rerender 0}} {
    variable cfg
    if {[catch {plot3dAspectValidate $cfg(plot_3d_aspect_mode) $cfg(plot_3d_aspect_ratio) 0} err]} {
        tk_messageBox -parent .globalgfx -icon error -message $err; return
    }
    foreach f {plot_3d_azimuth plot_3d_elevation plot_color_min plot_color_max} {
        set v [string trim $cfg($f)]; if {$v eq ""} continue
        if {![string is double -strict $v]} {tk_messageBox -parent .globalgfx -icon error -message "$f must be numeric or blank."; return}
    }
    if {[string trim $cfg(plot_color_min)] ne "" && [string trim $cfg(plot_color_max)] ne "" && $cfg(plot_color_min) >= $cfg(plot_color_max)} {
        tk_messageBox -parent .globalgfx -icon error -message "Color limit min must be lower than max."; return
    }
    ::GX::globalGraphicsApply_v0933_before_3d_validation $rerender
}

# Extend module graphics UI with the same inherited 3D/color fields.
proc ::GX::moduleGraphicsDialog {id} {
    variable moduleGraphicsOverride
    moduleGraphicsEnsure $id
    set w .modulegfx; catch {destroy $w}; toplevel $w; wm title $w "Module graphics override - [moduleField $id name $id]"; wm transient $w .
    grid columnconfigure $w 1 -weight 1
    ttk::checkbutton $w.en -text "Override global graphics for this module" -variable ::GX::moduleGraphicsOverride($id,enabled); grid $w.en -row 0 -column 0 -columnspan 3 -sticky w -padx 8 -pady {8 5}
    ttk::label $w.note -text "Blank or inherit = use Global graphics. 3D view/color defaults are framework-owned and inherited like the existing common graphics fields." -wraplength 760 -justify left; grid $w.note -row 1 -column 0 -columnspan 3 -sticky ew -padx 8 -pady {0 6}
    set r 2
    foreach spec {
        {"Output width [px]" width_px entry} {"Output height [px]" height_px entry} {"Output DPI" dpi entry}
        {"Default font unit" font_unit {inherit px pt}} {"Axis tick font size" font_size entry} {"Axis-label font size" axis_label_font_size entry} {"Title font size" title_font_size entry}
        {"Line width" line_width entry} {"Grid mode" grid_mode {inherit both vertical horizontal none}} {"Grid color" grid_color entry} {"Background" background entry}
        {"Legend placement" legend_placement {inherit none inside below above right left manual}} {"Legend inside preset" legend_inside_preset {inherit north northeast east southeast south southwest west northwest}}
        {"Legend layout" legend_layout {inherit auto row stacked wrapped}} {"Legend alignment" legend_alignment {inherit start center end}} {"Legend columns" legend_columns entry}
        {"Legend font unit" legend_font_unit {inherit px pt}} {"Legend font size" legend_font_size entry} {"Legend background" legend_background entry} {"Legend border" legend_border {inherit 0 1}}
        {"Legend border color" legend_border_color entry} {"Legend/plot distance [px]" legend_margin_px entry}
        {"3D azimuth" view_azimuth entry} {"3D elevation" view_elevation entry} {"3D projection" projection {inherit orthographic perspective}}
        {"3D aspect" aspect_mode {inherit auto xy_equal data_equal manual}} {"Manual aspect X;Y;Z" aspect_ratio entry}
        {"Colormap" colormap entry} {"Colorbar visible" colorbar_visible {inherit 0 1}} {"Colorbar label" colorbar_label entry} {"Color display unit" color_unit entry} {"CLim min" color_min entry} {"CLim max" color_max entry}
    } {
        lassign $spec label field kind; ttk::label $w.l$r -text $label
        if {$kind eq "entry"} {ttk::entry $w.e$r -textvariable ::GX::moduleGraphicsOverride($id,$field) -width 18} else {ttk::combobox $w.e$r -textvariable ::GX::moduleGraphicsOverride($id,$field) -values $kind -state readonly -width 18}
        ttk::label $w.h$r -text "inherit global" -foreground #666666
        grid $w.l$r -row $r -column 0 -sticky e -padx 5 -pady 2; grid $w.e$r -row $r -column 1 -sticky w -padx 5 -pady 2; grid $w.h$r -row $r -column 2 -sticky w -padx 5 -pady 2; incr r
    }
    ttk::frame $w.b; ttk::button $w.b.save -text Save -command [list ::GX::moduleGraphicsSave $w $id]; ttk::button $w.b.cancel -text Cancel -command [list destroy $w]; pack $w.b.save $w.b.cancel -side left -padx 4; grid $w.b -row $r -column 0 -columnspan 3 -pady 8
    bind $w <Escape> [list destroy $w]; catch {wm geometry $w 700x850}
}

proc ::GX::moduleGraphicsSave {w id} {
    variable moduleGraphicsOverride
    if {[catch {plot3dAspectValidate $moduleGraphicsOverride($id,aspect_mode) $moduleGraphicsOverride($id,aspect_ratio)} err]} {
        tk_messageBox -parent $w -icon error -message $err; return
    }
    foreach f {view_azimuth view_elevation color_min color_max} {
        set v [string trim $moduleGraphicsOverride($id,$f)]; if {$v eq "" || $v eq "inherit"} continue
        if {![string is double -strict $v]} {tk_messageBox -parent $w -icon error -message "$f must be numeric or inherit/blank."; return}
    }
    set cmin [string trim $moduleGraphicsOverride($id,color_min)]; set cmax [string trim $moduleGraphicsOverride($id,color_max)]
    if {$cmin ni {"" inherit} && $cmax ni {"" inherit} && $cmin >= $cmax} {
        tk_messageBox -parent $w -icon error -message "color_min must be lower than color_max."; return
    }
    ::GX::moduleGraphicsSave_v0933_before_3d $w $id
}

# plot.dataset multi-panel/notebook usability: long shared dialogs need a reusable scrollable body instead of exceeding the screen.
proc ::GX::scrollableDialogCanvasSync {canvas body item} {
    if {![winfo exists $canvas] || ![winfo exists $body]} {return}
    update idletasks
    set vw [winfo width $canvas]
    set rw [winfo reqwidth $body]
    if {$vw < 1} {set vw $rw}
    set width [expr {$rw > $vw ? $rw : $vw}]
    catch {$canvas itemconfigure $item -width $width}
    catch {$canvas configure -scrollregion [$canvas bbox all]}
}
proc ::GX::scrollableDialogCanvasWheel {canvas delta} {
    if {![winfo exists $canvas]} {return}
    set step [expr {$delta > 0 ? -3 : 3}]
    catch {$canvas yview scroll $step units}
}
proc ::GX::scrollableDialogBody {w} {
    ttk::frame $w.viewport
    pack $w.viewport -fill both -expand 1
    canvas $w.viewport.canvas -highlightthickness 0 -borderwidth 0
    ttk::scrollbar $w.viewport.vscroll -orient vertical -command [list $w.viewport.canvas yview]
    ttk::scrollbar $w.viewport.hscroll -orient horizontal -command [list $w.viewport.canvas xview]
    $w.viewport.canvas configure -yscrollcommand [list $w.viewport.vscroll set] -xscrollcommand [list $w.viewport.hscroll set]
    grid $w.viewport.canvas -row 0 -column 0 -sticky nsew
    grid $w.viewport.vscroll -row 0 -column 1 -sticky ns
    grid $w.viewport.hscroll -row 1 -column 0 -sticky ew
    grid rowconfigure $w.viewport 0 -weight 1
    grid columnconfigure $w.viewport 0 -weight 1
    ttk::frame $w.viewport.canvas.body
    set item [$w.viewport.canvas create window 0 0 -anchor nw -window $w.viewport.canvas.body]
    bind $w.viewport.canvas.body <Configure> [list ::GX::scrollableDialogCanvasSync $w.viewport.canvas $w.viewport.canvas.body $item]
    bind $w.viewport.canvas <Configure> [list ::GX::scrollableDialogCanvasSync $w.viewport.canvas $w.viewport.canvas.body $item]
    bind $w.viewport.canvas <MouseWheel> [list ::GX::scrollableDialogCanvasWheel $w.viewport.canvas %D]
    bind $w.viewport.canvas.body <MouseWheel> [list ::GX::scrollableDialogCanvasWheel $w.viewport.canvas %D]
    bind $w.viewport.canvas <Button-4> [list $w.viewport.canvas yview scroll -3 units]
    bind $w.viewport.canvas <Button-5> [list $w.viewport.canvas yview scroll 3 units]
    return $w.viewport.canvas.body
}

# plot.dataset multi-panel: expose existing CORE per-panel Y overrides only for real stacked artifacts.
proc ::GX::axisConfigPanelBind {w} {
    variable ui
    if {![winfo exists $w.panel.select]} {return}
    set pn [string trim $ui(axisEditPanelSelected)]
    set idx 0
    for {set i 1} {$i <= $ui(axisEditPanelCount)} {incr i} {
        if {$ui(axisEditPanel,$i,name) eq $pn} {set idx $i; break}
    }
    if {$idx <= 0} {return}
    foreach {widget field} {
        ylmin y_min ylmax y_max ylstep y_step ylfmt y_format
        yrmin y2_min yrmax y2_max yrstep y2_step yrfmt y2_format
        gridmode grid_mode ygridsource ygrid_source gridcolor grid_color ylabelx ylabel_x
    } {
        catch {$w.panel.$widget configure -textvariable ::GX::ui(axisEditPanel,$idx,$field)}
    }
}

proc ::GX::axisConfigBuildPanelControls {w panels} {
    variable ui; variable axisOverride
    set gk $ui(axisEditGraphKey)
    set i 0
    foreach pn $panels {
        incr i
        set ui(axisEditPanel,$i,name) $pn
        foreach f {y_min y_max y_step y_format y2_min y2_max y2_step y2_format xgrid ygrid ygrid_source grid_color ylabel_x} {
            set ui(axisEditPanel,$i,$f) $axisOverride($gk,$pn,$f)
        }
        foreach f {y_format y2_format xgrid ygrid ygrid_source} {
            if {[string trim $ui(axisEditPanel,$i,$f)] eq ""} {set ui(axisEditPanel,$i,$f) inherit}
        }
        set ui(axisEditPanel,$i,grid_mode) [gridModeFromXY $ui(axisEditPanel,$i,xgrid) $ui(axisEditPanel,$i,ygrid)]
    }
    set ui(axisEditPanelCount) $i
    set ui(axisEditPanelSelected) [lindex $panels 0]

    ttk::labelframe $w.panel -text "Multi-panel axes"
    grid columnconfigure $w.panel 2 -weight 1; grid columnconfigure $w.panel 3 -weight 1; grid columnconfigure $w.panel 4 -weight 1
    ttk::label $w.panel.psl -text "Panel"
    ttk::combobox $w.panel.select -textvariable ::GX::ui(axisEditPanelSelected) -values $panels -state readonly -width 20
    bind $w.panel.select <<ComboboxSelected>> [list ::GX::axisConfigPanelBind $w]
    grid $w.panel.psl -row 0 -column 0 -sticky e -padx 3 -pady 3
    grid $w.panel.select -row 0 -column 1 -sticky w -padx 3 -pady 3

    foreach {c text} {0 Axis 1 Min 2 Max 3 Step 4 Format} {ttk::label $w.panel.h$c -text $text; grid $w.panel.h$c -row 1 -column $c -sticky w -padx 3}
    ttk::label $w.panel.yl -text "Y Left"; ttk::entry $w.panel.ylmin -width 10; ttk::entry $w.panel.ylmax -width 10; ttk::entry $w.panel.ylstep -width 10
    ttk::combobox $w.panel.ylfmt -values {inherit auto %g %.0f %.1f %.2f %.3f %.4f} -width 11
    ttk::label $w.panel.yr -text "Y Right"; ttk::entry $w.panel.yrmin -width 10; ttk::entry $w.panel.yrmax -width 10; ttk::entry $w.panel.yrstep -width 10
    ttk::combobox $w.panel.yrfmt -values {inherit auto %g %.0f %.1f %.2f %.3f %.4f} -width 11
    foreach {widget row col} {yl 2 0 ylmin 2 1 ylmax 2 2 ylstep 2 3 ylfmt 2 4 yr 3 0 yrmin 3 1 yrmax 3 2 yrstep 3 3 yrfmt 3 4} {grid $w.panel.$widget -row $row -column $col -sticky ew -padx 3 -pady 2}

    ttk::label $w.panel.gml -text "Grid mode"; ttk::combobox $w.panel.gridmode -values {inherit both vertical horizontal none} -state readonly -width 11
    ttk::label $w.panel.ysl -text "Y grid source"; ttk::combobox $w.panel.ygridsource -values {inherit left right none} -state readonly -width 10
    ttk::label $w.panel.gcl -text "Grid color"; ttk::entry $w.panel.gridcolor -width 11
    ttk::label $w.panel.yxl -text "Y-label X"; ttk::entry $w.panel.ylabelx -width 9
    grid $w.panel.gml -row 4 -column 0 -sticky e -padx 3 -pady 3; grid $w.panel.gridmode -row 4 -column 1 -sticky w -padx 3
    grid $w.panel.ysl -row 4 -column 2 -sticky e -padx 3; grid $w.panel.ygridsource -row 4 -column 3 -sticky w -padx 3
    grid $w.panel.gcl -row 5 -column 0 -sticky e -padx 3 -pady 3; grid $w.panel.gridcolor -row 5 -column 1 -sticky w -padx 3
    grid $w.panel.yxl -row 5 -column 2 -sticky e -padx 3; grid $w.panel.ylabelx -row 5 -column 3 -sticky w -padx 3
    ttk::label $w.panel.note -text "X remains graph-wide. Panel values override the graph-wide Y/Y2 defaults for the selected stacked panel." -foreground #555555 -wraplength 900 -justify left
    grid $w.panel.note -row 6 -column 0 -columnspan 5 -sticky ew -padx 3 -pady {3 4}
    axisConfigPanelBind $w
}

# Replace the common Axes dialog with an additive version including Z/view/color.
proc ::GX::axisConfigDialog_before_level_scale {} {
    variable ui; variable axisOverride
    set p [currentGraphPath]; if {$p eq ""} {tk_messageBox -message "Select a plot."; return}
    set gk [graphKeyForPath $p]; set panels [stackedGraphPanels $p]
    if {$gk eq ""} {tk_messageBox -message "The selected plot does not expose a configurable axes/grid ID."; return}
    axisOverrideEnsure $gk $panels
    if {[string trim $axisOverride($gk,x_unit)] in {"" inherit} && [string trim $axisOverride($gk,time_unit)] ni {"" inherit}} {set axisOverride($gk,x_unit) $axisOverride($gk,time_unit)}
    set w .axiscfg; catch {destroy $w}; toplevel $w; wm title $w "Axes / grid / 3D / color - $gk"; wm transient $w .; set body [scrollableDialogBody $w]; grid columnconfigure $body 0 -weight 1
    set ui(axisEditEnabled) $axisOverride($gk,enabled)
    foreach f {time_unit x_unit y_unit y2_unit align_ylabels ylabel_x x_min x_max x_step x_format y_min y_max y_step y_format y2_min y2_max y2_step y2_format xgrid ygrid ygrid_source grid_color x_scale y_scale y2_scale xy_aspect_mode z_unit z_label z_min z_max z_step z_format z_scale zgrid view_azimuth view_elevation projection aspect_mode aspect_ratio colormap colorbar_visible colorbar_label color_unit color_min color_max background title x_label y_label y2_label} {set ui(axisEdit,$f) $axisOverride($gk,$f)}
    set ui(axisSharedXRef) ""
    set ui(axisEdit,x_minor_grid) Off
    if {![catch {
        modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
        set ref [::GX::PlotDatasetAPIv3::plotRefForArtifact $p]
        if {$ref ne "" && [dict get $ref graph_id] ne "plot.dataset.xyz"} {
            set shared [::GX::PlotDatasetAPIv3::sharedXAxisGet $ref]
            set ui(axisSharedXRef) $ref
            set ui(axisEdit,x_scale) [dict get $shared scale]
            set ui(axisEdit,x_step) [dict get $shared major_step]
            set ui(axisEdit,x_minor_grid) [string totitle [dict get $shared minor_grid]]
            # Preserve the effective rendering of old Sessions with CORE X
            # overrides until the next Save migrates them to PlotSpec.
            if {$axisOverride($gk,x_scale) in {linear log}} {set ui(axisEdit,x_scale) $axisOverride($gk,x_scale)}
            if {[string trim $axisOverride($gk,x_step)] ne ""} {set ui(axisEdit,x_step) $axisOverride($gk,x_step)}
        }
    }]} {}
    set ui(axisEdit,grid_mode) [gridModeFromXY $ui(axisEdit,xgrid) $ui(axisEdit,ygrid)]
    set ui(axisEditGraphKey) $gk
    set ui(axisEditPanelCount) 0
    foreach f {time_unit x_unit y_unit y2_unit align_ylabels x_format y_format y2_format xgrid ygrid ygrid_source x_scale y_scale y2_scale xy_aspect_mode z_unit z_format z_scale zgrid projection aspect_mode colormap colorbar_visible color_unit} {if {[string trim $ui(axisEdit,$f)] eq ""} {set ui(axisEdit,$f) inherit}}
    ttk::label $body.title -text "Axes/grid override for: [file tail $p]\nPlot ID: $gk\nDisplay-unit conversion changes only presentation; canonical dataset values are never modified." -justify left; grid $body.title -row 0 -column 0 -sticky ew -padx 8 -pady 7
    ttk::checkbutton $body.en -text "Use plot-specific configuration" -variable ::GX::ui(axisEditEnabled); grid $body.en -row 1 -column 0 -sticky w -padx 8 -pady 3
    set xu [plotMetadataAxisUnit $p x]; set yu [plotMetadataAxisUnit $p y]; set y2u [plotMetadataAxisUnit $p y2]; set zu [plotMetadataAxisUnit $p z]; set cu [plotMetadataAxisUnit $p c]
    ttk::labelframe $body.axes -text "Axes"
    grid $body.axes -row 2 -column 0 -sticky ew -padx 8 -pady 4
    foreach {c h} {0 Axis 1 "Display unit" 2 Min 3 Max 4 Step 5 Format 6 Scale 7 "Minor grid"} {ttk::label $body.axes.h$c -text $h; grid $body.axes.h$c -row 0 -column $c -sticky w -padx 3}
    foreach spec [list [list 1 X x x_unit $xu] [list 2 "Y Left" y y_unit $yu] [list 3 "Y Right" y2 y2_unit $y2u] [list 4 Z z z_unit $zu]] {
        lassign $spec r name pre uf srcu; ttk::label $body.axes.n$r -text $name
        ttk::combobox $body.axes.u$r -textvariable ::GX::ui(axisEdit,$uf) -values [unitDisplayChoicesForSource $srcu 1] -state readonly -width 12
        ttk::entry $body.axes.mn$r -textvariable ::GX::ui(axisEdit,${pre}_min) -width 10; ttk::entry $body.axes.mx$r -textvariable ::GX::ui(axisEdit,${pre}_max) -width 10; ttk::entry $body.axes.st$r -textvariable ::GX::ui(axisEdit,${pre}_step) -width 10
        ttk::combobox $body.axes.fm$r -textvariable ::GX::ui(axisEdit,${pre}_format) -values {inherit auto %g %.0f %.1f %.2f %.3f %.4f} -width 11
        ttk::combobox $body.axes.sc$r -textvariable ::GX::ui(axisEdit,${pre}_scale) -values {inherit linear log} -state readonly -width 10
        grid $body.axes.n$r -row $r -column 0 -sticky w -padx 3 -pady 2; grid $body.axes.u$r -row $r -column 1 -sticky ew -padx 3; grid $body.axes.mn$r -row $r -column 2 -sticky ew -padx 3; grid $body.axes.mx$r -row $r -column 3 -sticky ew -padx 3; grid $body.axes.st$r -row $r -column 4 -sticky ew -padx 3; grid $body.axes.fm$r -row $r -column 5 -sticky ew -padx 3; grid $body.axes.sc$r -row $r -column 6 -sticky ew -padx 3
    }
    ttk::combobox $body.axes.xminor -textvariable ::GX::ui(axisEdit,x_minor_grid) -values {Off Auto} -state readonly -width 10
    grid $body.axes.xminor -row 1 -column 7 -sticky ew -padx 3
    if {$ui(axisSharedXRef) eq ""} {$body.axes.xminor state disabled}
    ttk::label $body.axes.zll -text "Z label"; ttk::entry $body.axes.zl -textvariable ::GX::ui(axisEdit,z_label) -width 40; ttk::label $body.axes.zgl -text "Z grid"; ttk::combobox $body.axes.zg -textvariable ::GX::ui(axisEdit,zgrid) -values {inherit on off} -state readonly -width 10
    grid $body.axes.zll -row 5 -column 0 -sticky e -padx 3 -pady 2; grid $body.axes.zl -row 5 -column 1 -columnspan 3 -sticky ew -padx 3; grid $body.axes.zgl -row 5 -column 4 -sticky e -padx 3; grid $body.axes.zg -row 5 -column 5 -sticky w -padx 3
    ttk::label $body.axes.xyal -text "2D XY data aspect"
    ttk::combobox $body.axes.xya -textvariable ::GX::ui(axisEdit,xy_aspect_mode) -values {inherit auto xy_equal} -state readonly -width 12
    grid $body.axes.xyal -row 6 -column 0 -sticky e -padx 3 -pady 3; grid $body.axes.xya -row 6 -column 1 -sticky w -padx 3
    ttk::labelframe $body.view -text "3D view"
    grid $body.view -row 3 -column 0 -sticky ew -padx 8 -pady 4
    foreach c {1 3 5} {grid columnconfigure $body.view $c -weight 1}
    ttk::label $body.view.azl -text Azimuth; ttk::entry $body.view.az -textvariable ::GX::ui(axisEdit,view_azimuth) -width 10; ttk::label $body.view.ell -text Elevation; ttk::entry $body.view.el -textvariable ::GX::ui(axisEdit,view_elevation) -width 10; ttk::label $body.view.prl -text Projection; ttk::combobox $body.view.pr -textvariable ::GX::ui(axisEdit,projection) -values {inherit orthographic perspective} -state readonly -width 13
    grid $body.view.azl -row 0 -column 0 -sticky e -padx 3; grid $body.view.az -row 0 -column 1 -sticky w -padx 3; grid $body.view.ell -row 0 -column 2 -sticky e -padx 3; grid $body.view.el -row 0 -column 3 -sticky w -padx 3; grid $body.view.prl -row 0 -column 4 -sticky e -padx 3; grid $body.view.pr -row 0 -column 5 -sticky w -padx 3
    ttk::label $body.view.aml -text "Aspect"
    ttk::combobox $body.view.am -textvariable ::GX::ui(axisEdit,aspect_mode) -values {inherit auto xy_equal data_equal manual} -state readonly -width 13
    ttk::label $body.view.arl -text "Manual X;Y;Z"
    ttk::entry $body.view.ar -textvariable ::GX::ui(axisEdit,aspect_ratio) -width 18
    grid $body.view.aml -row 1 -column 0 -sticky e -padx 3; grid $body.view.am -row 1 -column 1 -sticky w -padx 3
    grid $body.view.arl -row 1 -column 2 -sticky e -padx 3; grid $body.view.ar -row 1 -column 3 -columnspan 2 -sticky w -padx 3
    ttk::labelframe $body.color -text "Colormap / colorbar"
    grid $body.color -row 4 -column 0 -sticky ew -padx 8 -pady 4
    ttk::label $body.color.cml -text Colormap; ttk::entry $body.color.cm -textvariable ::GX::ui(axisEdit,colormap) -width 14; ttk::label $body.color.cbl -text Colorbar; ttk::combobox $body.color.cb -textvariable ::GX::ui(axisEdit,colorbar_visible) -values {inherit 0 1} -state readonly -width 8; ttk::label $body.color.cul -text "Color unit"; ttk::combobox $body.color.cu -textvariable ::GX::ui(axisEdit,color_unit) -values [unitDisplayChoicesForSource $cu 1] -state readonly -width 12
    grid $body.color.cml -row 0 -column 0 -sticky e -padx 3; grid $body.color.cm -row 0 -column 1 -sticky w -padx 3; grid $body.color.cbl -row 0 -column 2 -sticky e -padx 3; grid $body.color.cb -row 0 -column 3 -sticky w -padx 3; grid $body.color.cul -row 0 -column 4 -sticky e -padx 3; grid $body.color.cu -row 0 -column 5 -sticky w -padx 3
    ttk::label $body.color.ll -text Label; ttk::entry $body.color.le -textvariable ::GX::ui(axisEdit,colorbar_label) -width 32; ttk::label $body.color.mnl -text "CLim min"; ttk::entry $body.color.mn -textvariable ::GX::ui(axisEdit,color_min) -width 10; ttk::label $body.color.mxl -text "CLim max"; ttk::entry $body.color.mx -textvariable ::GX::ui(axisEdit,color_max) -width 10
    grid $body.color.ll -row 1 -column 0 -sticky e -padx 3 -pady 2; grid $body.color.le -row 1 -column 1 -columnspan 2 -sticky ew -padx 3; grid $body.color.mnl -row 1 -column 3 -sticky e -padx 3; grid $body.color.mn -row 1 -column 4 -sticky w -padx 3; grid $body.color.mxl -row 1 -column 5 -sticky e -padx 3; grid $body.color.mx -row 1 -column 6 -sticky w -padx 3
    ttk::label $body.color.bgl -text "Plot background"
    ttk::entry $body.color.bg -textvariable ::GX::ui(axisEdit,background) -width 12
    ttk::button $body.color.bgc -text "Choose..." -command {set initial [expr {[regexp {^#[0-9A-Fa-f]{6}$} $::GX::ui(axisEdit,background)] ? $::GX::ui(axisEdit,background) : $::GX::cfg(plot_background)}]; set picked [tk_chooseColor -parent .axiscfg -title "Plot background" -initialcolor $initial]; if {$picked ne ""} {set ::GX::ui(axisEdit,background) $picked}}
    ttk::button $body.color.bgi -text Inherit -command {set ::GX::ui(axisEdit,background) ""}
    ttk::button $body.color.bgt -text Transparent -command {set ::GX::ui(axisEdit,background) transparent}
    grid $body.color.bgl -row 2 -column 0 -sticky e -padx 3 -pady 3
    grid $body.color.bg -row 2 -column 1 -sticky w -padx 3
    grid $body.color.bgc -row 2 -column 2 -sticky w -padx 3
    grid $body.color.bgi -row 2 -column 3 -sticky w -padx 3
    grid $body.color.bgt -row 2 -column 4 -sticky w -padx 3
    ttk::labelframe $body.common -text "Grid and labels"; grid $body.common -row 5 -column 0 -sticky ew -padx 8 -pady 4
    set ui(axisEdit,grid_mode) [gridModeFromXY $ui(axisEdit,xgrid) $ui(axisEdit,ygrid)]
    ttk::label $body.common.al -text "Align Y labels"; ttk::combobox $body.common.a -textvariable ::GX::ui(axisEdit,align_ylabels) -values {inherit 1 0} -state readonly -width 10; ttk::label $body.common.gml -text "XY grid"; ttk::combobox $body.common.gm -textvariable ::GX::ui(axisEdit,grid_mode) -values {both vertical horizontal none inherit} -state readonly -width 12; ttk::label $body.common.ysl -text "Y grid source"; ttk::combobox $body.common.ys -textvariable ::GX::ui(axisEdit,ygrid_source) -values {inherit left right none} -state readonly -width 10; ttk::label $body.common.gcl -text "Grid color"; ttk::entry $body.common.gc -textvariable ::GX::ui(axisEdit,grid_color) -width 12
    grid $body.common.al -row 0 -column 0 -sticky e -padx 3; grid $body.common.a -row 0 -column 1 -sticky w -padx 3; grid $body.common.gml -row 0 -column 2 -sticky e -padx 3; grid $body.common.gm -row 0 -column 3 -sticky w -padx 3; grid $body.common.ysl -row 0 -column 4 -sticky e -padx 3; grid $body.common.ys -row 0 -column 5 -sticky w -padx 3; grid $body.common.gcl -row 0 -column 6 -sticky e -padx 3; grid $body.common.gc -row 0 -column 7 -sticky w -padx 3
    set nextRow 6
    if {[llength $panels] > 1} {
        # plot.dataset multi-panel: reuse CORE panel override state for every stacked artifact discovered by stackedGraphPanels().
        axisConfigBuildPanelControls $body $panels
        grid $body.panel -row $nextRow -column 0 -sticky ew -padx 8 -pady 5
        incr nextRow
        if {[llength [info commands ::GX::axisConfigExtensionBuild]]} {
            if {[axisConfigExtensionBuild $body $p $gk $panels $nextRow]} {incr nextRow}
        }
    }
    ttk::label $body.note -text "Z/view/color fields are ignored by ordinary 2D plots. X is graph-wide for stacked plots; panel-local Y/Y2 overrides appear only when the selected artifact is multi-panel. Limits are expressed in displayed units." -wraplength 1000 -justify left; grid $body.note -row $nextRow -column 0 -sticky ew -padx 8 -pady 5; incr nextRow
    ttk::frame $body.b; ttk::button $body.b.save -text Save -command [list ::GX::axisConfigSave $w $gk $p 0]; ttk::button $body.b.render -text "Save and rerender plot" -command [list ::GX::axisConfigSave $w $gk $p 1]; ttk::button $body.b.auto -text "Restore automatic" -command [list ::GX::axisConfigResetUi $w]; ttk::button $body.b.cancel -text Cancel -command [list destroy $w]; pack $body.b.save $body.b.render $body.b.auto $body.b.cancel -side left -padx 4; grid $body.b -row $nextRow -column 0 -pady 8
    set sw [winfo screenwidth $w]; set sh [winfo screenheight $w]; set ww [expr {min([llength $panels] > 1 ? 1080 : 1050,max(720,$sw-80))}]; set hh [expr {min([llength $panels] > 1 ? 820 : 720,max(480,$sh-120))}]; catch {wm geometry $w ${ww}x${hh}}; catch {wm minsize $w 700 420}; catch {wm resizable $w 1 1}
}

proc ::GX::axisConfigDialog {} { ::GX::axisConfigDialog_before_level_scale }

proc ::GX::axisConfigResetUi {w} {
    variable ui
    ::GX::axisConfigResetUi_v0933_before_3d $w
    foreach {f v} [plot3dAxisFieldDefaults] {set ui(axisEdit,$f) $v}
    if {[info exists ui(axisSharedXRef)] && $ui(axisSharedXRef) ne ""} {
        set ui(axisEdit,x_scale) linear
        set ui(axisEdit,x_step) ""
        set ui(axisEdit,x_minor_grid) Off
    }
}

proc ::GX::axisConfigSave {w gk path rerender} {
    variable ui; variable axisOverride
    if {[string trim $ui(axisEdit,background)] ni {"" transparent} &&
        ![regexp {^#[0-9A-Fa-f]{6}$} [string trim $ui(axisEdit,background)]]} {
        tk_messageBox -parent $w -icon error -message "Plot background must be #RRGGBB, transparent, or blank to inherit."
        return
    }
    set sharedRef [expr {[info exists ui(axisSharedXRef)] ? $ui(axisSharedXRef) : ""}]
    if {$sharedRef ne ""} {
        set sharedFields [dict create scale [string tolower $ui(axisEdit,x_scale)] \
            major_step [string trim $ui(axisEdit,x_step)] minor_grid [string tolower $ui(axisEdit,x_minor_grid)]]
        if {[dict get $sharedFields scale] ni {linear log} ||
            [dict get $sharedFields minor_grid] ni {off auto} ||
            ([dict get $sharedFields major_step] ne "" &&
            (![string is double -strict [dict get $sharedFields major_step]] || [dict get $sharedFields major_step] <= 0))} {
            tk_messageBox -parent $w -icon error -message "X scale, step or minor grid is invalid."
            return
        }
    }
    if {$ui(axisEdit,xy_aspect_mode) ni {inherit auto xy_equal}} {tk_messageBox -parent $w -icon error -message "2D aspect must be inherit, auto, or xy_equal."; return}
    foreach pre {x y y2 z} {
        if {$ui(axisEdit,${pre}_scale) ni {inherit linear log}} {tk_messageBox -parent $w -icon error -message "$pre scale must be inherit, linear, or log."; return}
        if {$ui(axisEdit,${pre}_scale) eq "log"} {
            foreach bound {min max} {
                set value [string trim $ui(axisEdit,${pre}_$bound)]
                if {$value ne "" && (![string is double -strict $value] || $value <= 0)} {tk_messageBox -parent $w -icon error -message "$pre log $bound must be positive."; return}
            }
        }
    }
    if {[catch {plot3dAspectValidate $ui(axisEdit,aspect_mode) $ui(axisEdit,aspect_ratio)} err]} {
        tk_messageBox -parent $w -icon error -message $err; return
    }
    if {[string tolower [string trim $ui(axisEdit,ygrid_source)]] ni {inherit left right none}} {tk_messageBox -parent $w -icon error -message "Y grid source must be inherit, left, right, or none."; return}
    foreach f {z_min z_max z_step view_azimuth view_elevation color_min color_max} {
        set v [string trim $ui(axisEdit,$f)]; if {$v ne "" && ![string is double -strict $v]} {tk_messageBox -parent $w -icon error -message "$f must be numeric or blank."; return}
    }
    if {[string trim $ui(axisEdit,z_step)] ne "" && $ui(axisEdit,z_step) <= 0} {tk_messageBox -parent $w -icon error -message "Z step must be > 0."; return}
    if {[string trim $ui(axisEdit,z_min)] ne "" && [string trim $ui(axisEdit,z_max)] ne "" && $ui(axisEdit,z_min) >= $ui(axisEdit,z_max)} {tk_messageBox -parent $w -icon error -message "Z min must be lower than max."; return}
    if {[string trim $ui(axisEdit,color_min)] ne "" && [string trim $ui(axisEdit,color_max)] ne "" && $ui(axisEdit,color_min) >= $ui(axisEdit,color_max)} {tk_messageBox -parent $w -icon error -message "CLim min must be lower than max."; return}
    # Use historical validator/save first while temporarily preserving the 3D UI.
    set save3d [dict create]; foreach {f d} [plot3dAxisFieldDefaults] {dict set save3d $f $ui(axisEdit,$f)}
    if {$sharedRef ne ""} {
        set displayXScale $ui(axisEdit,x_scale); set displayXStep $ui(axisEdit,x_step)
        set ui(axisEdit,x_scale) inherit; set ui(axisEdit,x_step) ""
        dict set save3d x_scale inherit
    }
    ::GX::axisConfigSave_v0933_before_3d $w $gk $path 0
    # Historical save leaves the dialog open on validation failure.
    if {[winfo exists $w]} {
        if {$sharedRef ne ""} {set ui(axisEdit,x_scale) $displayXScale; set ui(axisEdit,x_step) $displayXStep}
        return
    }
    foreach {f d} [plot3dAxisFieldDefaults] {set v [string trim [dict get $save3d $f]]; if {$v eq "inherit"} {set v ""}; set axisOverride($gk,$f) $v}
    if {$sharedRef ne ""} {
        set axisOverride($gk,x_scale) ""
        set axisOverride($gk,x_step) ""
        ::GX::PlotDatasetAPIv3::sharedXAxisSet $sharedRef $sharedFields
    }
    refreshManifestPreview; writeAxisOverrideFile
    if {$rerender} {startRerenderPaths [list $path]}
}

# Extend TSV fallback transport with Z/view/color fields. Runtime.ini remains
# authoritative for modern modules.
proc ::GX::writeAxisOverrideFile {} {
    variable currentSession; variable axisOverride
    if {$currentSession eq ""} {return ""}
    set keys {}; foreach k [array names axisOverride "*,enabled"] {set gk [string range $k 0 end-8]; if {[lsearch -exact $keys $gk] < 0} {lappend keys $gk}}
    if {![llength $keys]} {return ""}
    set d [file join $currentSession analysis]; file mkdir $d; set path [file join $d .plot_axis_overrides.tsv]; set fd [open $path w]; fconfigure $fd -encoding utf-8 -translation lf
    set baseFields {enabled time_unit x_unit y_unit y2_unit align_ylabels ylabel_x x_min x_max x_step x_format y_min y_max y_step y_format y2_min y2_max y2_step y2_format xgrid ygrid ygrid_source grid_color}
    set extraFields {}; foreach {f def} [plot3dAxisFieldDefaults] {lappend extraFields $f}
    puts $fd [join [concat {key panel} $baseFields $extraFields] "\t"]
    foreach gk [lsort $keys] {
        set panels [expr {[info exists axisOverride($gk,panels)] ? $axisOverride($gk,panels) : {}}]
        axisOverrideEnsure $gk $panels
        set row [list $gk *]
        foreach f $baseFields {set v [expr {[info exists axisOverride($gk,$f)] ? $axisOverride($gk,$f) : ""}]; lappend row [string map [list "\t" " " "\n" " " "\r" " "] $v]}
        foreach f $extraFields {set v $axisOverride($gk,$f); lappend row [string map [list "\t" " " "\n" " " "\r" " "] $v]}
        puts $fd [join $row "\t"]
        # Preserve the historical per-panel rows. 3D/view/color fields are
        # graph-level in API v1, therefore those columns remain blank here.
        foreach pn $panels {
            set prow [list $gk $pn]
            foreach f $baseFields {
                set v ""
                if {$f eq "enabled"} {set v 1}
                if {$f in {y_min y_max y_step y_format y2_min y2_max y2_step y2_format xgrid ygrid ygrid_source grid_color ylabel_x}} {
                    set ak "$gk,$pn,$f"; if {[info exists axisOverride($ak)]} {set v $axisOverride($ak)}
                }
                lappend prow [string map [list "\t" " " "\n" " " "\r" " "] $v]
            }
            foreach f $extraFields {lappend prow ""}
            puts $fd [join $prow "\t"]
        }
    }
    close $fd; return $path
}
