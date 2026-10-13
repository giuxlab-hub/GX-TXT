# GX-TXT Series Editor Extension API v1
# SPDX-License-Identifier: GPL-3.0-or-later
# Provider-owned controls inside the authoritative CORE Graph Series Editor.

namespace eval ::GX {
    variable seriesEditorExtensionApiVersion 1
    variable seriesEditorExtensionRegistry
    variable seriesEditorExtensionInstance
    array set seriesEditorExtensionRegistry {}
    array set seriesEditorExtensionInstance {}
}

proc ::GX::seriesEditorExtensionIdValid {value} {
    return [regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} $value]
}

proc ::GX::seriesEditorExtensionRegister {providerId fields} {
    variable seriesEditorExtensionRegistry
    set providerId [string trim $providerId]
    if {![seriesEditorExtensionIdValid $providerId]} { error "Invalid Series Editor extension provider ID '$providerId'." }
    if {[catch {dict size $fields}]} { error "Series Editor extension registration must be a dict." }
    set allowed {module_id graph_ids build_proc load_proc validate_proc save_proc close_proc table_columns table_values_proc table_values_batch_proc}
    foreach key [dict keys $fields] {
        if {$key ni $allowed} { error "Unknown Series Editor extension registration field '$key'." }
    }
    foreach key {module_id graph_ids build_proc load_proc validate_proc save_proc} {
        if {![dict exists $fields $key] || [string trim [dict get $fields $key]] eq ""} {
            error "Series Editor extension requires '$key'."
        }
    }
    set moduleId [string trim [dict get $fields module_id]]
    if {![seriesEditorExtensionIdValid $moduleId]} { error "Invalid Series Editor extension module ID '$moduleId'." }
    set graphs [splitList [dict get $fields graph_ids]]
    if {![llength $graphs]} { error "Series Editor extension requires at least one graph ID." }
    foreach graphId $graphs {
        if {![seriesEditorExtensionIdValid $graphId]} { error "Invalid Series Editor extension graph ID '$graphId'." }
    }
    dict set fields module_id $moduleId
    dict set fields graph_ids $graphs
    foreach callback {build_proc load_proc validate_proc save_proc close_proc table_values_proc table_values_batch_proc} {
        if {![dict exists $fields $callback]} { dict set fields $callback "" }
        set prefix [dict get $fields $callback]
        if {$prefix eq ""} continue
        if {[catch {llength $prefix}] || ![llength $prefix] || ![llength [info commands [lindex $prefix 0]]]} {
            error "Series Editor extension callback '$callback' is not callable."
        }
    }
    # plot.dataset multi-panel: optional read-only columns expose provider state in the shared Series table without moving ownership into CORE.
    if {![dict exists $fields table_columns]} { dict set fields table_columns {} }
    set normalizedColumns {}
    foreach spec [dict get $fields table_columns] {
        if {[catch {dict size $spec}]} { error "Series Editor extension table_columns entries must be dicts." }
        foreach key {id heading width} {
            if {![dict exists $spec $key]} { error "Series Editor extension table column requires '$key'." }
        }
        set cid [string trim [dict get $spec id]]
        if {![seriesEditorExtensionIdValid $cid]} { error "Invalid Series Editor extension table column ID '$cid'." }
        set width [dict get $spec width]
        if {![string is integer -strict $width] || $width < 20} { error "Series Editor extension table column '$cid' width must be an integer >= 20." }
        lappend normalizedColumns [dict create id $cid heading [dict get $spec heading] width $width]
    }
    if {[llength $normalizedColumns] && [dict get $fields table_values_proc] eq "" && [dict get $fields table_values_batch_proc] eq ""} {
        error "Series Editor extension table_columns requires a table values callback."
    }
    dict set fields table_columns $normalizedColumns
    foreach existing [array names seriesEditorExtensionRegistry] {
        if {$existing eq $providerId} continue
        set other $seriesEditorExtensionRegistry($existing)
        if {[dict get $other module_id] ne $moduleId} continue
        foreach graphId $graphs {
            if {$graphId in [dict get $other graph_ids]} {
                error "Series Editor extension already registered for $moduleId/$graphId."
            }
        }
    }
    dict set fields provider_id $providerId
    dict set fields api_version 1
    set seriesEditorExtensionRegistry($providerId) $fields
    return $providerId
}

proc ::GX::seriesEditorExtensionUnregister {providerId} {
    variable seriesEditorExtensionRegistry
    catch {unset seriesEditorExtensionRegistry($providerId)}
}

proc ::GX::seriesEditorExtensionDefinition {providerId} {
    variable seriesEditorExtensionRegistry
    if {![info exists seriesEditorExtensionRegistry($providerId)]} {
        error "Unknown Series Editor extension provider '$providerId'."
    }
    return $seriesEditorExtensionRegistry($providerId)
}

proc ::GX::seriesEditorExtensionFor_before_graph_workflow {moduleId graphId} {
    variable seriesEditorExtensionRegistry
    set found {}
    foreach providerId [lsort [array names seriesEditorExtensionRegistry]] {
        set d $seriesEditorExtensionRegistry($providerId)
        if {[dict get $d module_id] eq $moduleId && $graphId in [dict get $d graph_ids]} {
            lappend found $d
        }
    }
    if {[llength $found] > 1} { error "Multiple Series Editor extensions registered for $moduleId/$graphId." }
    if {![llength $found]} { return {} }
    return [lindex $found 0]
}
proc ::GX::seriesEditorExtensionFor {moduleId graphId} {
    tailcall ::GX::seriesEditorExtensionFor_before_graph_workflow $moduleId $graphId
}

proc ::GX::seriesEditorExtensionInvoke {prefix args} {
    if {$prefix eq ""} { return "" }
    return [uplevel #0 [list {*}$prefix {*}$args]]
}

proc ::GX::seriesEditorExtensionContext {f seriesId genericSeries} {
    variable seriesEditorExtensionInstance
    if {![info exists seriesEditorExtensionInstance($f)]} { return {} }
    set instance $seriesEditorExtensionInstance($f)
    set definition [dict get $instance definition]
    return [dict create         api_version 1         provider_id [dict get $definition provider_id]         module_id [dict get $instance module_id]         graph_id [dict get $instance graph_id]         variant_id [dict get $instance variant_id]         series_id $seriesId         parent [dict get $instance parent]         generic_series $genericSeries]
}

proc ::GX::seriesEditorExtensionSetStatus {f message {failed 0}} {
    variable seriesEditorExtensionInstance
    if {![info exists seriesEditorExtensionInstance($f)]} { return }
    set instance $seriesEditorExtensionInstance($f)
    dict set instance error $message
    if {$failed} { dict set instance available 0 }
    set seriesEditorExtensionInstance($f) $instance
    set label [dict get $instance status]
    if {[llength [info commands winfo]] && [winfo exists $label]} {
        $label configure -text $message
    }
}

# Optional provider-owned read-only columns in the shared Series table.
# plot.dataset uses this to expose panel membership without teaching CORE
# any plot.dataset-specific presentation semantics.
proc ::GX::seriesEditorExtensionTableColumns {moduleId graphId} {
    set d [seriesEditorExtensionFor $moduleId $graphId]
    if {$d eq "" || ![dict exists $d table_columns]} { return {} }
    return [dict get $d table_columns]
}

proc ::GX::seriesEditorExtensionTableValues {moduleId graphId variantId seriesId genericSeries} {
    set d [seriesEditorExtensionFor $moduleId $graphId]
    if {$d eq "" || ![dict exists $d table_values_proc] || [dict get $d table_values_proc] eq ""} { return [dict create] }
    set context [dict create api_version 1 provider_id [dict get $d provider_id] module_id $moduleId graph_id $graphId variant_id $variantId series_id $seriesId generic_series $genericSeries]
    set values [seriesEditorExtensionInvoke [dict get $d table_values_proc] $context]
    if {[catch {dict size $values}]} { error "Series Editor extension table_values_proc must return a dict." }
    return $values
}

# A provider can compute all read-only table columns once per editor refresh.
# The result maps stable series IDs to their column dictionaries.
proc ::GX::seriesEditorExtensionTableValuesBatch {moduleId graphId variantId seriesIds} {
    set d [seriesEditorExtensionFor $moduleId $graphId]
    if {$d eq "" || [dict get $d table_values_batch_proc] eq ""} {return ""}
    set context [dict create api_version 1 provider_id [dict get $d provider_id] module_id $moduleId graph_id $graphId variant_id $variantId series_ids $seriesIds]
    set values [seriesEditorExtensionInvoke [dict get $d table_values_batch_proc] $context]
    if {[catch {dict size $values}]} {error "Series Editor batch table values must be a dictionary"}
    return $values
}

# Returns one when a provider area was added and zero for the unchanged legacy
# editor layout.
proc ::GX::seriesEditorExtensionBuild {f moduleId graphId variantId row} {
    variable seriesEditorExtensionInstance
    if {[catch {set definition [seriesEditorExtensionFor $moduleId $graphId]} activationError]} {
        set box $f.providerExtension
        ttk::labelframe $box -text "Provider details"
        ttk::label $box.status -text "Provider extension unavailable: $activationError" -foreground #8B0000 -wraplength 540
        pack $box.status -fill x -padx 5 -pady 5
        grid $box -row $row -column 0 -columnspan 6 -sticky ew -padx 2 -pady 6
        return 1
    }
    if {$definition eq ""} { return 0 }
    set box $f.providerExtension
    ttk::labelframe $box -text "Provider details"
    ttk::label $box.status -text "" -foreground #8B0000 -wraplength 540
    ttk::frame $box.body
    pack $box.status -fill x -padx 5 -pady {3 0}
    pack $box.body -fill both -expand 1 -padx 5 -pady 5
    grid $box -row $row -column 0 -columnspan 6 -sticky ew -padx 2 -pady 6
    set seriesEditorExtensionInstance($f) [dict create         definition $definition module_id $moduleId graph_id $graphId         variant_id $variantId parent $box.body status $box.status         available 1 error "" series_id ""]
    bind $f <Destroy> +[list ::GX::seriesEditorExtensionWidgetDestroyed $f %W]
    set context [seriesEditorExtensionContext $f "" {}]
    if {[catch {
        seriesEditorExtensionInvoke [dict get $definition build_proc] $context
    } err]} {
        seriesEditorExtensionSetStatus $f "Provider extension unavailable: $err" 1
    }
    return 1
}

proc ::GX::seriesEditorExtensionLoad {f seriesId genericSeries} {
    variable seriesEditorExtensionInstance
    if {![info exists seriesEditorExtensionInstance($f)]} { return 1 }
    set instance $seriesEditorExtensionInstance($f)
    if {![dict get $instance available]} { return 0 }
    dict set instance series_id $seriesId
    set seriesEditorExtensionInstance($f) $instance
    set definition [dict get $instance definition]
    set context [seriesEditorExtensionContext $f $seriesId $genericSeries]
    if {[catch {
        seriesEditorExtensionInvoke [dict get $definition load_proc] $context
    } err]} {
        seriesEditorExtensionSetStatus $f "Provider extension unavailable: $err" 1
        return 0
    }
    seriesEditorExtensionSetStatus $f ""
    return 1
}

proc ::GX::seriesEditorExtensionPrepareSave {f seriesId genericSeries} {
    variable seriesEditorExtensionInstance
    if {![info exists seriesEditorExtensionInstance($f)]} {
        return [dict create present 0]
    }
    set instance $seriesEditorExtensionInstance($f)
    if {![dict get $instance available]} {
        error "Provider extension is unavailable: [dict get $instance error]"
    }
    set definition [dict get $instance definition]
    set context [seriesEditorExtensionContext $f $seriesId $genericSeries]
    if {[catch {
        set validated [seriesEditorExtensionInvoke [dict get $definition validate_proc] $context]
    } err opts]} {
        seriesEditorExtensionSetStatus $f "Provider validation failed: $err"
        return -options $opts $err
    }
    return [dict create present 1 validated_state $validated]
}

proc ::GX::seriesEditorExtensionCommitSave {f seriesId genericSeries prepared} {
    variable seriesEditorExtensionInstance
    if {![dict get $prepared present]} { return }
    if {![info exists seriesEditorExtensionInstance($f)]} {
        error "Provider extension closed before save."
    }
    set instance $seriesEditorExtensionInstance($f)
    if {![dict get $instance available]} {
        error "Provider extension is unavailable: [dict get $instance error]"
    }
    set definition [dict get $instance definition]
    set context [seriesEditorExtensionContext $f $seriesId $genericSeries]
    if {[catch {
        seriesEditorExtensionInvoke [dict get $definition save_proc]             $context [dict get $prepared validated_state]
    } err opts]} {
        seriesEditorExtensionSetStatus $f "Provider save failed: $err"
        return -options $opts $err
    }
    dict set instance series_id $seriesId
    set seriesEditorExtensionInstance($f) $instance
    seriesEditorExtensionSetStatus $f ""
}

proc ::GX::seriesEditorExtensionClose {f} {
    variable seriesEditorExtensionInstance
    if {![info exists seriesEditorExtensionInstance($f)]} { return }
    set instance $seriesEditorExtensionInstance($f)
    unset seriesEditorExtensionInstance($f)
    set definition [dict get $instance definition]
    set callback [dict get $definition close_proc]
    if {$callback eq ""} { return }
    set sid [dict get $instance series_id]
    set generic {}
    if {$sid ne "" && ![catch {
        graphSeriesSnapshot [dict get $instance module_id] [dict get $instance graph_id]             $sid [dict get $instance variant_id]
    } snapshot]} {
        set generic $snapshot
    }
    set context [dict create         api_version 1 provider_id [dict get $definition provider_id]         module_id [dict get $instance module_id] graph_id [dict get $instance graph_id]         variant_id [dict get $instance variant_id] series_id $sid         parent [dict get $instance parent] generic_series $generic]
    if {[catch {seriesEditorExtensionInvoke $callback $context} err]} {
        puts stderr "Series Editor extension cleanup failed: $err"
    }
}

proc ::GX::seriesEditorExtensionWidgetDestroyed {f widget} {
    if {$widget eq $f} { seriesEditorExtensionClose $f }
}
