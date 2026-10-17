# SPDX-License-Identifier: GPL-3.0-or-later
# Fields are the provider validator's data contract, not a Viewer operation map.
namespace eval ::GX::SignalAPIv1 {variable formValues;variable forms {};variable formStatus}
proc ::GX::SignalAPIv1::operationSchema {operation} {
    if {$operation ni [listOperations]} {error "Unknown Signal operation '$operation'"}
    set path [file join [file dirname [::GX::moduleField math.signal descriptor {}]] api operation_fields_v1.tsv]
    set f [open $path];set fields {}
    try {
        while {[gets $f line]>=0} {
            if {$line eq {} || [string index $line 0] eq "#"} continue
            set parts [split $line |];if {[llength $parts]!=13} {error {Invalid Signal provider field contract}}
            lassign $parts id name label type required default unit min max choices shape conditions errorId
            if {$id ne $operation} continue
            set field [dict create name $name label $label type $type required $required unit $unit shape $shape error_id GXTXT:Signal:$errorId]
            set uiType [expr {$type in {array struct} ? "string" : $type}]
            set ui [dict create type $uiType label $label required $required]
            if {!$required} {dict set ui allow_inherit 1}
            if {$default ne {}} {
                if {$type in {integer number boolean} && [string is double -strict $default]} {dict set field default $default;dict set ui default $default} elseif {$type eq "choice" || $type eq "boolean"} {dict set field default $default;dict set ui default $default} else {dict set field default_expression $default}
            }
            foreach bound {min max} {set value [set $bound];if {$value ne {}} {dict set field $bound $value;if {[string is double -strict $value] && $uiType in {integer number}} {dict set ui $bound $value}}}
            if {$choices ne {}} {dict set field choices [split $choices {;}];dict set ui values [split $choices {;}]}
            if {$conditions ne {}} {dict set field conditions $conditions}
            dict set field ui_field $ui;dict set fields $name $field
        }
    } finally {close $f}
    set constraints [operationConstraints $operation]
    return [dict create api_id SIGNAL_API_v1 schema_version 1 operation $operation fields $fields constraints $constraints validation_owner gxtxt_signal_validate_v1 final_scientific_checks gxtxt_signal_v1]
}
proc ::GX::SignalAPIv1::operationConstraints {operation} {
    set path [file join [file dirname [::GX::moduleField math.signal descriptor {}]] api operation_constraints_v1.tsv]
    set f [open $path];set constraints {}
    try {
        while {[gets $f line]>=0} {
            if {$line eq {} || [string index $line 0] eq "#"} continue
            if {[llength [split $line |]]!=4} {error {Invalid Signal conditional contract}}
            lassign [split $line |] id name type value
            if {$id ne $operation} continue
            switch $type {
                map {set mapped {};foreach item [split $value {;}] {set colon [string first : $item];if {$colon<1} {error {Invalid Signal conditional map}};dict set mapped [string range $item 0 [expr {$colon-1}]] [string range $item [expr {$colon+1}] end]};set value $mapped}
                list {set value [split $value {;}]}
                scalar {}
                default {error {Unknown Signal conditional contract type}}
            }
            dict set constraints $name $value
        }
    } finally {close $f}
    return $constraints
}
proc ::GX::SignalAPIv1::validateOperation {operation a b c {options {kind struct fields {}}}} {
    operationSchema $operation
    return [dict get [::GX::ScientificTransportv1::call math.signal gxtxt_signal_v1 contract $operation $a $b $c $options] values]
}
proc ::GX::SignalAPIv1::operationFormCreate {parent operation} {
    variable forms;variable formValues;variable formStatus
    set schema [operationSchema $operation]
    ttk::frame $parent;grid columnconfigure $parent 1 -weight 1
    dict set forms $parent $schema;set row 0
    ttk::label $parent.title -text "Signal operation: $operation";grid $parent.title -row $row -column 0 -columnspan 2 -sticky w -pady 5;incr row
    dict for {name field} [dict get $schema fields] {
        if {[dict get $field type] eq "empty"} continue
        set value [::GX::datasetPublicationV2DictDefault $field default {}]
        set formValues($parent,$name) $value
        ttk::label $parent.label$row -text "[dict get $field label] ([dict get $field unit])"
        ::GX::uiFieldCreate $parent.field$row [dict get $field ui_field] ::GX::SignalAPIv1::formValues($parent,$name) [list ::GX::SignalAPIv1::operationFormChanged $parent]
        grid $parent.label$row -row $row -column 0 -sticky e -padx 5 -pady 3
        grid $parent.field$row -row $row -column 1 -sticky ew -padx 5 -pady 3
        dict set forms $parent widgets $name $parent.field$row
        incr row
    }
    ttk::label $parent.constraints -text {} -wraplength 650;grid $parent.constraints -row $row -column 0 -columnspan 2 -sticky w -padx 5;incr row
    set formStatus($parent) {Scientific data-dependent checks also run in the operation provider.}
    ttk::label $parent.status -textvariable ::GX::SignalAPIv1::formStatus($parent) -wraplength 650
    grid $parent.status -row $row -column 0 -columnspan 2 -sticky w -padx 5 -pady 5;incr row
    ttk::button $parent.validate -text {Validate inputs} -command [list ::GX::SignalAPIv1::operationFormCheck $parent]
    grid $parent.validate -row $row -column 1 -sticky e -padx 5 -pady 5
    bind $parent <Destroy> [list ::GX::SignalAPIv1::operationFormDestroy $parent %W]
    operationFormChanged $parent {}
    return $parent
}
proc ::GX::SignalAPIv1::operationFormChanged {parent value} {
    variable forms;variable formValues
    if {![dict exists $forms $parent]} return
    set schema [dict get $forms $parent];set text {}
    if {[dict exists $schema constraints cutoff_length_by_band]} {
        set band $formValues($parent,options.band);set domain $formValues($parent,options.domain)
        if {[dict exists $schema constraints cutoff_length_by_band $band] && [dict exists $schema constraints cutoff_unit_by_domain $domain]} {
            set text "Cutoff requires [dict get $schema constraints cutoff_length_by_band $band] edge(s), in [dict get $schema constraints cutoff_unit_by_domain $domain]."
        }
        if {[dict exists $schema constraints even_order_bands] && $band in [dict get $schema constraints even_order_bands]} {append text { Filter order must be even.}}
    }
    $parent.constraints configure -text $text
}
proc ::GX::SignalAPIv1::operationFormRequest {parent} {
    variable forms;variable formValues
    set schema [dict get $forms $parent];set operands [dict create a {kind empty} b {kind empty} c {kind empty}];set options {}
    dict for {name field} [dict get $schema fields] {
        if {[dict get $field type] eq "empty"} continue
        set value [string trim $formValues($parent,$name)]
        if {$value eq {}} {if {[dict get $field required]} {error "[dict get $field label] is required"};continue}
        set type [dict get $field type]
        switch -- $type {
            choice {set node [::GX::ScientificTransportv1::text $value]}
            struct {if {[dict get $value kind] ne "struct"} {error {Model requires a public typed struct node}};set node $value}
            default {
                if {$type eq "boolean"} {set value [expr {!!$value}]}
                foreach item $value {::GX::uiFieldNormalize {type number required 1} $item}
                set node [::GX::ScientificTransportv1::array [list [llength $value] 1] $value]
            }
        }
        if {[string match options.* $name]} {dict set options [string range $name 8 end] $node} else {dict set operands $name $node}
    }
    return [list [dict get $operands a] [dict get $operands b] [dict get $operands c] [::GX::ScientificTransportv1::struct $options]]
}
proc ::GX::SignalAPIv1::operationFormCheck {parent} {
    variable forms;variable formStatus
    if {[catch {set args [operationFormRequest $parent];set result [validateOperation [dict get $forms $parent operation] {*}$args]} message]} {
        set formStatus($parent) "Invalid inputs: $message";return 0
    }
    set formStatus($parent) {Typed inputs and conditional admission are valid. Final scientific checks run during calculation.}
    return 1
}
proc ::GX::SignalAPIv1::operationFormDestroy {parent actual} {
    if {$parent ne $actual} return
    variable forms;variable formValues;variable formStatus
    dict unset forms $parent;array unset formValues "$parent,*";unset -nocomplain formStatus($parent)
}
