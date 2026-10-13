# GX-TXT Semantic Registry API v1
# SPDX-License-Identifier: GPL-3.0-or-later
# Public role definitions are independent of persisted dataset role strings.
namespace eval ::GX {
    variable semanticRegistryApiVersion 1
    variable semanticDefinitions
    array set semanticDefinitions {}
}

proc ::GX::semanticRegistryRegister {semanticId definition} {
    variable semanticDefinitions
    if {![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} $semanticId]} { error "Invalid semantic role ID: $semanticId" }
    set allowed {label description owner_plugin allowed_value_kinds suggested_units aliases}
    dict for {key value} $definition {
        if {$key ni $allowed} { error "Unknown semantic definition field: $key" }
        if {[regexp {[\r\n]} $value]} { error "Semantic definition fields must be single-line" }
    }
    if {![dict exists $definition label] || [string trim [dict get $definition label]] eq ""} { error "Semantic role requires a label" }
    foreach key {description owner_plugin allowed_value_kinds suggested_units aliases} {
        if {![dict exists $definition $key]} { dict set definition $key {} }
    }
    foreach kind [dict get $definition allowed_value_kinds] {
        if {$kind ni {number text elapsed_time absolute_time}} { error "Unsupported semantic value kind: $kind" }
    }
    set semanticDefinitions($semanticId) [dict merge [dict create semantic_id $semanticId] $definition]
    return $semanticDefinitions($semanticId)
}

proc ::GX::semanticRegistryRemoveProvider {provider} {
    variable semanticDefinitions
    foreach id [array names semanticDefinitions] {
        if {[dict get $semanticDefinitions($id) owner_plugin] eq $provider} { unset semanticDefinitions($id) }
    }
}

proc ::GX::semanticRegistryDefinition {semanticId} {
    variable semanticDefinitions
    if {![info exists semanticDefinitions($semanticId)]} { return {} }
    set def $semanticDefinitions($semanticId)
    set owner [dict get $def owner_plugin]
    if {$owner ne "" && (![info exists ::GX::moduleCatalog($owner,descriptor)] || ![moduleIsEnabled $owner])} { return {} }
    return $def
}

proc ::GX::semanticRegistryList {} {
    variable semanticDefinitions
    set out {}
    foreach id [lsort [array names semanticDefinitions]] {
        if {[semanticRegistryDefinition $id] ne {}} { lappend out $id }
    }
    return $out
}

proc ::GX::semanticRegistryByProvider {provider} {
    set out {}
    foreach id [semanticRegistryList] {
        if {[dict get [semanticRegistryDefinition $id] owner_plugin] eq $provider} { lappend out $id }
    }
    return $out
}

proc ::GX::semanticRegistryGuiValues {} {
    return [concat {Auto} [semanticRegistryList]]
}

proc ::GX::semanticRegistryInfer {variable} {
    set kind [dict get $variable value_kind]
    set unit [string trim [dict get $variable unit]]
    set name [string tolower [string trim [dict get $variable canonical]]]
    set raw [string tolower [string trim [dict get $variable original_header]]]
    if {$kind in {elapsed_time absolute_time}} {
        set temporalRole [expr {[dict get $variable time_reference] eq "absolute" ? "absolute_time" : "elapsed_time"}]
        return [dict create semantic_role $temporalRole semantic_source inferred semantic_reason "Value kind is $kind; time reference is [dict get $variable time_reference]"]
    }
    foreach id [semanticRegistryList] {
        set def [semanticRegistryDefinition $id]
        set kinds [dict get $def allowed_value_kinds]
        if {[llength $kinds] && $kind ni $kinds} continue
        # Temporal semantic roles are never inferred from a numeric variable's
        # name alone. A numeric representation may carry elapsed-time semantics,
        # but that semantic role must be explicit in Variable Schema metadata.
        if {$kind eq "number" && $id in {elapsed_time absolute_time}} continue
        foreach alias [concat [list $id] [dict get $def aliases]] {
            set hint [string tolower [string trim $alias]]
            if {$hint ne "" && ($name eq $hint || $raw eq $hint)} {
                return [dict create semantic_role $id semantic_source inferred semantic_reason "Variable name matches registered alias '$alias'"]
            }
        }
    }
    # A unit can be a hint, never a rigid semantic constraint.
    set matches {}
    foreach id [semanticRegistryList] {
        set def [semanticRegistryDefinition $id]
        set kinds [dict get $def allowed_value_kinds]
        if {[llength $kinds] && $kind ni $kinds} continue
        # A physical time unit is representation metadata, not enough evidence
        # to assign elapsed/absolute temporal meaning to an ordinary number.
        if {$kind eq "number" && $id in {elapsed_time absolute_time}} continue
        if {$unit ne "" && [lsearch -exact [dict get $def suggested_units] $unit] >= 0} { lappend matches $id }
    }
    if {[llength $matches] == 1} {
        set id [lindex $matches 0]
        return [dict create semantic_role $id semantic_source inferred semantic_reason "Source unit '$unit' suggests $id; user can override"]
    }
    return [dict create semantic_role generic semantic_source default semantic_reason "No unambiguous semantic hint"]
}

proc ::GX::datasetVariableSemantic {datasetId variableId} {
    set v [datasetVariableById $datasetId $variableId]
    set role [dict get $v semantic_role]
    return [dict create dataset_id $datasetId variable_id $variableId semantic_role $role semantic_source [dict get $v semantic_source] semantic_reason [dict get $v semantic_reason] definition [semanticRegistryDefinition $role]]
}

proc ::GX::datasetVariablesBySemanticRole {semanticId {datasetId ""}} {
    set out {}
    set ids [expr {$datasetId eq "" ? [datasetRegistryIds] : [list $datasetId]}]
    foreach id $ids {
        foreach v [datasetVariableSchema $id] {
            if {[dict get $v semantic_role] eq $semanticId} {
                lappend out [dict merge [dict create dataset_id $id] $v]
            }
        }
    }
    return $out
}

proc ::GX::semanticRegistryLoadCore {} {
    foreach {id label kinds units aliases} {
        elapsed_time {Elapsed time} {number elapsed_time} {s min h} {time elapsed duration}
        absolute_time {Absolute time} {elapsed_time absolute_time} {} {timestamp datetime}
        voltage Voltage number {V mV uV} {voltage volt}
        current Current number {A mA uA} {current ampere}
        temperature Temperature number {K °C} {temperature temp}
        concentration Concentration number {mol/L mmol/L ppm mg/L} {concentration conc}
        pressure Pressure number {Pa kPa bar} {pressure}
        flow_rate {Flow rate} number {m3/s L/min} {flow flowrate}
        conversion Conversion number {%} {conversion conv}
        ph pH number {pH} {ph}
        activity Activity number {} {activity}
        generic Generic {number text elapsed_time absolute_time} {} {}
    } {
        semanticRegistryRegister $id [dict create label $label description "CORE semantic role $label" owner_plugin "" allowed_value_kinds $kinds suggested_units $units aliases $aliases]
    }
}

proc ::GX::semanticRegistryLoadDescriptors {} {
    variable semanticDefinitions
    foreach id [array names semanticDefinitions] {
        if {[dict get $semanticDefinitions($id) owner_plugin] ne ""} { unset semanticDefinitions($id) }
    }
    foreach module $::GX::moduleOrder {
        set d [moduleField $module dict {}]
        foreach id [splitList [descriptorValue $d semantic_roles ids ""]] {
            set section "semantic_role.$id"
            set def [dict create label [descriptorValue $d $section label $id] description [descriptorValue $d $section description ""] owner_plugin $module allowed_value_kinds [splitList [descriptorValue $d $section allowed_value_kinds ""]] suggested_units [splitList [descriptorValue $d $section suggested_units ""]] aliases [splitList [descriptorValue $d $section aliases ""]]]
            semanticRegistryRegister $id $def
        }
    }
}

::GX::semanticRegistryLoadCore
proc ::GX::loadModuleCatalog_before_unit_registry {} {
    ::GX::loadModuleCatalog_before_semantic_registry
    ::GX::semanticRegistryLoadDescriptors
}
