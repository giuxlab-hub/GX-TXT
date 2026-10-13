# GX-TXT Graph Configuration Extension API v1
# SPDX-License-Identifier: GPL-3.0-or-later
# plot.dataset multi-panel: public hook for provider-owned controls in Graph configuration.

namespace eval ::GX {
    variable graphConfigExtensionApiVersion 1
    variable graphConfigExtensionRegistry
    variable graphConfigExtensionInstance
    array set graphConfigExtensionRegistry {}
    array set graphConfigExtensionInstance {}
}

proc ::GX::graphConfigExtensionIdValid {value} {
    expr {[regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} $value]}
}

proc ::GX::graphConfigExtensionRegister {providerId fields} {
    variable graphConfigExtensionRegistry
    if {![graphConfigExtensionIdValid $providerId]} { error "Invalid Graph Configuration extension provider ID '$providerId'." }
    if {[catch {dict size $fields}]} { error "Graph Configuration extension '$providerId' definition must be a dict." }
    foreach key {module_id graph_ids build_proc} {
        if {![dict exists $fields $key] || [string trim [dict get $fields $key]] eq ""} {
            error "Graph Configuration extension '$providerId' requires '$key'."
        }
    }
    set moduleId [dict get $fields module_id]
    if {![graphConfigExtensionIdValid $moduleId]} { error "Invalid Graph Configuration extension module ID '$moduleId'." }
    set graphIds [splitList [dict get $fields graph_ids]]
    if {![llength $graphIds]} { error "Graph Configuration extension '$providerId' requires at least one graph ID." }
    foreach graphId $graphIds {
        if {![graphConfigExtensionIdValid $graphId]} { error "Invalid Graph Configuration extension graph ID '$graphId'." }
    }
    dict set fields provider_id $providerId
    dict set fields module_id $moduleId
    dict set fields graph_ids $graphIds
    if {![dict exists $fields close_proc]} { dict set fields close_proc "" }
    foreach existing [array names graphConfigExtensionRegistry] {
        set other $graphConfigExtensionRegistry($existing)
        if {[dict get $other module_id] ne $moduleId} continue
        foreach graphId $graphIds {
            if {$graphId in [dict get $other graph_ids]} {
                error "Graph Configuration extension '$providerId' conflicts with '$existing' for $moduleId/$graphId."
            }
        }
    }
    set graphConfigExtensionRegistry($providerId) $fields
    return $providerId
}

proc ::GX::graphConfigExtensionUnregister {providerId} {
    variable graphConfigExtensionRegistry
    catch {unset graphConfigExtensionRegistry($providerId)}
}

proc ::GX::graphConfigExtensionDefinition {providerId} {
    variable graphConfigExtensionRegistry
    if {![info exists graphConfigExtensionRegistry($providerId)]} {
        error "Unknown Graph Configuration extension provider '$providerId'."
    }
    return $graphConfigExtensionRegistry($providerId)
}

proc ::GX::graphConfigExtensionFor_before_graph_workflow {moduleId graphId} {
    variable graphConfigExtensionRegistry
    set found {}
    foreach providerId [lsort [array names graphConfigExtensionRegistry]] {
        set d $graphConfigExtensionRegistry($providerId)
        if {[dict get $d module_id] eq $moduleId && $graphId in [dict get $d graph_ids]} {
            lappend found $d
        }
    }
    if {[llength $found] > 1} { error "Multiple Graph Configuration extensions registered for $moduleId/$graphId." }
    if {![llength $found]} { return {} }
    return [lindex $found 0]
}
proc ::GX::graphConfigExtensionFor {moduleId graphId} {
    tailcall ::GX::graphConfigExtensionFor_before_graph_workflow $moduleId $graphId
}

proc ::GX::graphConfigExtensionInvoke {prefix args} {
    if {$prefix eq ""} { return "" }
    return [uplevel #0 [list {*}$prefix {*}$args]]
}

proc ::GX::graphConfigExtensionBuild {parent moduleId graphId variantId row} {
    variable graphConfigExtensionInstance
    if {[catch {set definition [graphConfigExtensionFor $moduleId $graphId]} activationError]} {
        set box $parent.providerGraphConfigExtension
        catch {destroy $box}
        ttk::labelframe $box -text "Provider configuration"
        ttk::label $box.status -text "Provider extension unavailable: $activationError" -foreground #8B0000 -wraplength 620
        pack $box.status -fill x -padx 5 -pady 5
        grid $box -row $row -column 0 -columnspan 2 -sticky ew -padx 2 -pady 6
        return 1
    }
    if {$definition eq ""} { return 0 }
    set box $parent.providerGraphConfigExtension
    catch {destroy $box}
    ttk::labelframe $box -text "Provider configuration"
    ttk::label $box.status -text "" -foreground #8B0000 -wraplength 620
    ttk::frame $box.body
    pack $box.status -fill x -padx 5 -pady {3 0}
    pack $box.body -fill both -expand 1 -padx 5 -pady 5
    grid $box -row $row -column 0 -columnspan 2 -sticky ew -padx 2 -pady 6
    set context [dict create api_version 1 provider_id [dict get $definition provider_id] \
        module_id $moduleId graph_id $graphId variant_id $variantId parent $box.body]
    set graphConfigExtensionInstance($box) [dict create definition $definition context $context]
    bind $box <Destroy> +[list ::GX::graphConfigExtensionWidgetDestroyed $box %W]
    if {[catch {graphConfigExtensionInvoke [dict get $definition build_proc] $context} err]} {
        $box.status configure -text "Provider extension unavailable: $err"
    }
    return 1
}

proc ::GX::graphConfigExtensionClose {box} {
    variable graphConfigExtensionInstance
    if {![info exists graphConfigExtensionInstance($box)]} { return }
    set instance $graphConfigExtensionInstance($box)
    unset graphConfigExtensionInstance($box)
    set definition [dict get $instance definition]
    set callback [dict get $definition close_proc]
    if {$callback eq ""} { return }
    if {[catch {graphConfigExtensionInvoke $callback [dict get $instance context]} err]} {
        puts stderr "Graph Configuration extension cleanup failed: $err"
    }
}

proc ::GX::graphConfigExtensionWidgetDestroyed {box widget} {
    if {$widget eq $box} { graphConfigExtensionClose $box }
}
