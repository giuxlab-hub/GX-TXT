# Typed request transport for provider-owned scientific APIs.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::ScientificTransportv1 {}
proc ::GX::ScientificTransportv1::_error {message} {return -code error -errorcode {GXTXT SCIENTIFIC TRANSPORT} $message}
# The three typed scientific providers share a data-only call shape. Publish
# its argument contract with each operation so generic clients can build a
# guided editor without parsing module implementation code.
proc ::GX::ScientificTransportv1::operationHelp {worksheetPrefix id familyContract} {
    set names [split [dict get $familyContract operands] ,]
    set shapes [split [dict get $familyContract input_shapes] {;}]
    set descriptors {}
    set index 0
    foreach name $names {
        set name [string trim $name]
        if {$name eq ""} continue
        set shape [expr {$index < [llength $shapes] ? [lindex $shapes $index] : "action-specific"}]
        lappend descriptors [dict create name $name shape $shape source {cell,range,column,scalar,option}]
        incr index
    }
    set callNames [lrange $names 0 2]
    return [dict create \
        arguments $names argument_descriptors $descriptors \
        signature "${worksheetPrefix}.${id}([join $callNames {, }], options)" \
        worksheet_example "Apply ${worksheetPrefix}.${id} using Worksheet ranges A1:A20 and B1:B20; set action-specific operands in the guided dialog." \
        result_fields [split [dict get $familyContract result_shapes] {;}] \
        unit_behavior [dict get $familyContract units]]
}
proc ::GX::ScientificTransportv1::_escape {s} {
    if {[regexp {[\x00-\x08\x0b\x0c\x0e-\x1f]} $s]} {_error "text contains unsupported control characters"}
    set s [string map [list \\ \\\\ \" \\" \n \\n \r \\r \t \\t] $s]
    return \"$s\"
}
proc ::GX::ScientificTransportv1::_number {value} {
    if {![string is double -strict $value]} {_error "numeric array contains a non-number"}
    set x [expr {double($value)}]
    if {![expr {abs($x) < Inf}]} {_error "nonfinite input is not accepted"}
    return [format %.17g $x]
}
proc ::GX::ScientificTransportv1::_jsonArray {values numeric} {
    set parts {}
    foreach value $values {if {$numeric} {lappend parts [_number $value]} else {lappend parts [_json $value]}}
    return \[[join $parts ,]\]
}
proc ::GX::ScientificTransportv1::_json {node} {
    if {[catch {dict get $node kind} kind]} {_error "typed node requires kind"}
    switch -- $kind {
        empty {return {{"kind":"empty"}}}
        text {return "{\"kind\":\"text\",\"value\":[_escape [dict get $node value]]}"}
        array {
            foreach key {shape real} {if {![dict exists $node $key]} {_error "array requires $key"}}
            set shape [dict get $node shape]; set real [dict get $node real]
            set count 1;foreach d $shape {if {![string is integer -strict $d] || $d < 1} {_error "array shape must contain positive integers"};set count [expr {$count*$d}]}
            if {$count != [llength $real]} {_error "array shape and real-value count differ"}
            set imag [lrepeat $count 0];if {[dict exists $node imaginary]} {set imag [dict get $node imaginary]}
            if {[llength $imag] != $count} {_error "real and imaginary counts differ"}
            return "{\"kind\":\"array\",\"shape\":[_jsonArray $shape 1],\"real\":[_jsonArray $real 1],\"imaginary\":[_jsonArray $imag 1]}"
        }
        uniform {
            foreach key {start step count} {if {![dict exists $node $key]} {_error "uniform grid requires $key"}}
            set count [dict get $node count]
            if {![string is integer -strict $count] || $count < 1 || $count > 67108864} {_error "uniform grid count exceeds limits"}
            set start [_number [dict get $node start]]; set step [_number [dict get $node step]]
            if {$step <= 0} {_error "uniform grid step must be positive"}
            return "{\"kind\":\"uniform\",\"start\":$start,\"step\":$step,\"count\":$count}"
        }
        cell {return "{\"kind\":\"cell\",\"items\":[_jsonArray [dict get $node items] 0]}"}
        struct {
            set parts {};dict for {key value} [dict get $node fields] {
                if {![regexp {^[A-Za-z][A-Za-z0-9_]*$} $key]} {_error "struct field name is invalid: $key"}
                lappend parts "[_escape $key]:[_json $value]"
            }
            return "{\"kind\":\"struct\",\"fields\":{[join $parts ,]}}"
        }
        default {_error "unsupported typed node kind $kind"}
    }
}
proc ::GX::ScientificTransportv1::array {shape real {imaginary {}}} {
    set out [dict create kind array shape $shape real $real]
    if {$imaginary ne {}} {dict set out imaginary $imaginary}
    return $out
}
proc ::GX::ScientificTransportv1::text {value} {dict create kind text value $value}
proc ::GX::ScientificTransportv1::struct {fields} {dict create kind struct fields $fields}
proc ::GX::ScientificTransportv1::empty {} {dict create kind empty}
proc ::GX::ScientificTransportv1::call {moduleId function family action a b c options} {
    set descriptor [::GX::moduleField $moduleId descriptor ""]
    if {$descriptor eq "" || ![file isfile $descriptor]} {_error "scientific provider $moduleId is unavailable"}
    set moduleDir [file dirname $descriptor]
    set root [file normalize [file join $moduleDir .. .. ..]]
    set worker [file join $root core octave gxtxt_scientific_provider_worker_v1.m]
    set octave "";foreach q {octave-cli octave} {if {[auto_execok $q] ne ""} {set octave [auto_execok $q];break}}
    if {$octave eq ""} {_error "GNU Octave executable is unavailable"}
    set request [dict create kind struct fields [dict create]]
    set json "{\"family\":[_escape $family],\"action\":[_escape $action],\"a\":[_json $a],\"b\":[_json $b],\"c\":[_json $c],\"options\":[_json $options]}"
    set requestChannel [file tempfile requestPath];fconfigure $requestChannel -encoding utf-8 -translation lf;puts -nonewline $requestChannel $json;close $requestChannel
    set responseChannel [file tempfile responsePath];close $responseChannel;file delete -force $responsePath
    set failed [catch {exec $octave --quiet --no-gui $worker $function $moduleDir $requestPath $responsePath 2>@1} workerOutput]
    set parsed [catch {set result [_parse $responsePath]} parseError parseOptions]
    file delete -force $requestPath $responsePath
    if {$parsed} {return -options $parseOptions $parseError}
    if {$failed} {_error "scientific worker failed: $workerOutput"}
    return $result
}
proc ::GX::ScientificTransportv1::_parse {path} {
    if {![file isfile $path]} {_error "scientific worker produced no response"}
    set d [::GX::parseIni $path]
    if {[::GX::descriptorValue $d result ok 0] ne "1"} {
        set id [::GX::descriptorValue $d error identifier GXTXT:ScientificTransport:Remote]
        set message [::GX::descriptorValue $d error message "scientific operation failed"]
        return -code error -errorcode [list GXTXT SCIENTIFIC $id] $message
    }
    set result [dict create];set types [dict create]
    foreach field [::GX::splitList [::GX::descriptorValue $d result fields ""]] {
        set section "result.$field";set kind [::GX::descriptorValue $d $section type string]
        _resultNodeTypes $d $section $field 0 types
        dict set result $field [_parseNode $d $section 0]
    }
    return [dict create values $result types $types]
}
proc ::GX::ScientificTransportv1::_resultNodeTypes {descriptor section path depth typesName} {
    upvar 1 $typesName types
    if {$depth>16||[dict size $types]>1000000} {_error "result type nesting exceeds bounded transport limits"}
    set kind [::GX::descriptorValue $descriptor $section type string];dict set types $path $kind
    if {$kind eq "struct"} {
        foreach name [::GX::splitList [::GX::descriptorValue $descriptor $section fields ""]] {_resultNodeTypes $descriptor "$section.$name" "$path.$name" [expr {$depth+1}] types}
    } elseif {$kind eq "cell"} {
        set count [::GX::descriptorValue $descriptor $section count -1]
        if {![string is integer -strict $count]||$count<0||$count>1000000} {_error "invalid cell result count"}
        for {set i 1} {$i<=$count} {incr i} {_resultNodeTypes $descriptor "$section.item$i" "$path.item$i" [expr {$depth+1}] types}
    }
}
proc ::GX::ScientificTransportv1::_parseRows {raw nr nc} {
    if {![string is integer -strict $nr] || ![string is integer -strict $nc] || $nr < 0 || $nc < 0} {
        _error "invalid matrix result shape"
    }
    set flat [expr {$raw eq "" ? {} : [split $raw {;}]}]
    if {[llength $flat] != $nr * $nc} {_error "matrix result value count does not match shape"}
    set value {}
    for {set i 0} {$i < $nr} {incr i} {
        lappend value [lrange $flat [expr {$i*$nc}] [expr {($i+1)*$nc-1}]]
    }
    return $value
}
proc ::GX::ScientificTransportv1::_parseNode {descriptor section depth} {
    if {$depth > 16} {_error "result nesting exceeds 16 levels"}
    set kind [::GX::descriptorValue $descriptor $section type string]
    set raw [::GX::descriptorValue $descriptor $section value ""]
    switch -- $kind {
        struct {
            set value [dict create]
            foreach name [::GX::splitList [::GX::descriptorValue $descriptor $section fields ""]] {
                dict set value $name [_parseNode $descriptor "$section.$name" [expr {$depth+1}]]
            }
            return $value
        }
        cell {
            set count [::GX::descriptorValue $descriptor $section count -1]
            if {![string is integer -strict $count] || $count < 0 || $count > 1000000} {_error "invalid cell result count"}
            set value {}
            for {set i 1} {$i <= $count} {incr i} {
                lappend value [_parseNode $descriptor "$section.item$i" [expr {$depth+1}]]
            }
            return $value
        }
        vector {return [expr {$raw eq "" ? {} : [split $raw {;}]}]}
        matrix {
            return [_parseRows $raw [::GX::descriptorValue $descriptor $section rows 0] [::GX::descriptorValue $descriptor $section cols 0]]
        }
        tensor {
            return [dict create shape [split [::GX::descriptorValue $descriptor $section dimensions ""] {;}] values [expr {$raw eq "" ? {} : [split $raw {;}]}]]
        }
        complex_number {
            return [dict create real [::GX::descriptorValue $descriptor $section real ""] imaginary [::GX::descriptorValue $descriptor $section imaginary ""]]
        }
        complex_vector {
            return [dict create real [split [::GX::descriptorValue $descriptor $section real ""] {;}] imaginary [split [::GX::descriptorValue $descriptor $section imaginary ""] {;}]]
        }
        complex_matrix {
            set nr [::GX::descriptorValue $descriptor $section rows 0]
            set nc [::GX::descriptorValue $descriptor $section cols 0]
            return [dict create real [_parseRows [::GX::descriptorValue $descriptor $section real ""] $nr $nc] imaginary [_parseRows [::GX::descriptorValue $descriptor $section imaginary ""] $nr $nc]]
        }
        complex_tensor {
            return [dict create shape [split [::GX::descriptorValue $descriptor $section dimensions ""] {;}] real [split [::GX::descriptorValue $descriptor $section real ""] {;}] imaginary [split [::GX::descriptorValue $descriptor $section imaginary ""] {;}]]
        }
        boolean {return [expr {$raw in {1 true yes on}}]}
        default {return $raw}
    }
}
