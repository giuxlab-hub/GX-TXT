# GX-TXT Axis Configuration Extension API v1
# SPDX-License-Identifier: GPL-3.0-or-later
# plot.dataset multi-panel: let artifact providers add panel presentation controls to the shared Axes dialog.

namespace eval ::GX {
    variable axisConfigExtensionApiVersion 1
    variable axisConfigExtensionRegistry
    variable axisConfigExtensionInstance
    array set axisConfigExtensionRegistry {}
    array set axisConfigExtensionInstance {}
}

proc ::GX::axisConfigExtensionIdValid {value} {
    expr {[regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} $value]}
}

proc ::GX::axisConfigExtensionRegister {providerId fields} {
    variable axisConfigExtensionRegistry
    if {![axisConfigExtensionIdValid $providerId]} {error "Invalid Axis Configuration extension provider ID '$providerId'."}
    if {[catch {dict size $fields}]} {error "Axis Configuration extension '$providerId' definition must be a dict."}
    foreach key {match_proc build_proc} {
        if {![dict exists $fields $key] || [string trim [dict get $fields $key]] eq ""} {
            error "Axis Configuration extension '$providerId' requires '$key'."
        }
    }
    if {![dict exists $fields close_proc]} {dict set fields close_proc ""}
    dict set fields provider_id $providerId
    set axisConfigExtensionRegistry($providerId) $fields
    return $providerId
}

proc ::GX::axisConfigExtensionUnregister {providerId} {
    variable axisConfigExtensionRegistry
    catch {unset axisConfigExtensionRegistry($providerId)}
}

proc ::GX::axisConfigExtensionDefinition {providerId} {
    variable axisConfigExtensionRegistry
    if {![info exists axisConfigExtensionRegistry($providerId)]} {error "Unknown Axis Configuration extension provider '$providerId'."}
    return $axisConfigExtensionRegistry($providerId)
}

proc ::GX::axisConfigExtensionInvoke {prefix args} {
    if {$prefix eq ""} {return ""}
    return [uplevel #0 [list {*}$prefix {*}$args]]
}

proc ::GX::axisConfigExtensionForArtifact {path} {
    variable axisConfigExtensionRegistry
    set found {}
    foreach providerId [lsort [array names axisConfigExtensionRegistry]] {
        set d $axisConfigExtensionRegistry($providerId)
        if {[axisConfigExtensionInvoke [dict get $d match_proc] $path]} {lappend found $d}
    }
    if {[llength $found] > 1} {error "Multiple Axis Configuration extensions recognize '[file tail $path]'."}
    if {![llength $found]} {return {}}
    return [lindex $found 0]
}

proc ::GX::axisConfigExtensionBuild {parent path graphKey panels row} {
    variable axisConfigExtensionInstance
    if {[catch {set definition [axisConfigExtensionForArtifact $path]} err]} {
        set box $parent.providerAxisConfigExtension
        catch {destroy $box}
        ttk::labelframe $box -text "Provider panel presentation"
        ttk::label $box.status -text "Provider extension unavailable: $err" -foreground #8B0000 -wraplength 900
        pack $box.status -fill x -padx 5 -pady 5
        grid $box -row $row -column 0 -sticky ew -padx 8 -pady 5
        return 1
    }
    if {$definition eq ""} {return 0}
    set box $parent.providerAxisConfigExtension
    catch {destroy $box}
    ttk::labelframe $box -text "Provider panel presentation"
    ttk::label $box.status -text "" -foreground #8B0000 -wraplength 900
    ttk::frame $box.body
    pack $box.status -fill x -padx 5 -pady {3 0}
    pack $box.body -fill both -expand 1 -padx 5 -pady 5
    grid $box -row $row -column 0 -sticky ew -padx 8 -pady 5
    set context [dict create api_version 1 provider_id [dict get $definition provider_id] artifact_path $path graph_key $graphKey panel_ids $panels parent $box.body]
    set axisConfigExtensionInstance($box) [dict create definition $definition context $context]
    bind $box <Destroy> +[list ::GX::axisConfigExtensionWidgetDestroyed $box %W]
    if {[catch {axisConfigExtensionInvoke [dict get $definition build_proc] $context} buildErr]} {
        $box.status configure -text "Provider extension unavailable: $buildErr"
    }
    return 1
}

proc ::GX::axisConfigExtensionClose {box} {
    variable axisConfigExtensionInstance
    if {![info exists axisConfigExtensionInstance($box)]} {return}
    set instance $axisConfigExtensionInstance($box)
    unset axisConfigExtensionInstance($box)
    set definition [dict get $instance definition]
    set callback [dict get $definition close_proc]
    if {$callback eq ""} {return}
    if {[catch {axisConfigExtensionInvoke $callback [dict get $instance context]} err]} {
        puts stderr "Axis Configuration extension cleanup failed: $err"
    }
}

proc ::GX::axisConfigExtensionWidgetDestroyed {box widget} {
    if {$widget eq $box} {axisConfigExtensionClose $box}
}
