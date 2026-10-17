# GX-TXT Unit Registry API v1
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX {
    variable unitRegistryApiVersion 1
    variable unitDefinitions
    array set unitDefinitions {}
}

proc ::GX::unitFormulaValidate {formula} {
    set compact [regsub -all {\s+} $formula ""]
    if {$compact eq ""} { error "Empty conversion formula" }
    set tokens [regexp -all -inline {(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?|[A-Za-z_][A-Za-z_0-9]*|[()+*/^-]} $compact]
    if {[join $tokens ""] ne $compact} { error "Unsafe conversion formula" }
    set i 0
    unitFormulaParseSum $tokens i
    if {$i != [llength $tokens]} { error "Invalid conversion formula" }
    if {[lsearch -exact $tokens x] < 0} { error "Conversion formula must use x" }
    return $compact
}
proc ::GX::unitFormulaParseSum {tokens indexVar} {
    upvar 1 $indexVar i
    set node [unitFormulaParseProduct $tokens i]
    while {$i < [llength $tokens] && [lindex $tokens $i] in {+ -}} {
        set op [lindex $tokens $i];incr i
        set node [list $op $node [unitFormulaParseProduct $tokens i]]
    }
    return $node
}
proc ::GX::unitFormulaParseProduct {tokens indexVar} {
    upvar 1 $indexVar i
    set node [unitFormulaParsePower $tokens i]
    while {$i < [llength $tokens] && [lindex $tokens $i] in {* /}} {
        set op [lindex $tokens $i];incr i
        set node [list $op $node [unitFormulaParsePower $tokens i]]
    }
    return $node
}
proc ::GX::unitFormulaParsePower {tokens indexVar} {
    upvar 1 $indexVar i
    set node [unitFormulaParseAtom $tokens i]
    if {$i < [llength $tokens] && [lindex $tokens $i] eq "^"} {
        incr i;set node [list ^ $node [unitFormulaParsePower $tokens i]]
    }
    return $node
}
proc ::GX::unitFormulaParseAtom {tokens indexVar} {
    upvar 1 $indexVar i
    if {$i >= [llength $tokens]} { error "Incomplete conversion formula" }
    set tok [lindex $tokens $i]; incr i
    if {$tok in {+ -}} {return [list unary$tok [unitFormulaParseAtom $tokens i]]}
    if {$tok eq "("} {
        set node [unitFormulaParseSum $tokens i]
        if {$i >= [llength $tokens] || [lindex $tokens $i] ne ")"} { error "Unclosed conversion formula" }
        incr i; return $node
    }
    if {$tok in {log log10 exp sqrt}} {
        if {$i >= [llength $tokens] || [lindex $tokens $i] ne "("} { error "Function requires parentheses" }
        incr i;set node [unitFormulaParseSum $tokens i]
        if {$i >= [llength $tokens] || [lindex $tokens $i] ne ")"} { error "Unclosed conversion function" }
        incr i; return [list $tok $node]
    }
    if {$tok eq "x"} {return [list x]}
    if {[string is double -strict $tok]} {return [list number $tok]}
    error "Unknown formula token: $tok"
}
proc ::GX::_unitFormulaTree {formula} {
    set compact [unitFormulaValidate $formula]
    set tokens [regexp -all -inline {(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?|[A-Za-z_][A-Za-z_0-9]*|[()+*/^-]} $compact]
    set index 0;return [unitFormulaParseSum $tokens index]
}
proc ::GX::_unitFiniteValue {value} {
    if {[catch {expr {double($value)}} result]||[catch {expr {abs($result)<Inf}} finite]||!$finite} {error {Unit conversion requires finite real binary64 values}}
    if {[string is entier -strict $value]&&[expr {entier($result)}]!=$value} {error {Integer coordinate cannot be represented exactly as binary64}}
    return $result
}
proc ::GX::_unitFormulaEvaluateTree {node x} {
    set op [lindex $node 0]
    if {$op eq "x"} {return $x}
    if {$op eq "number"} {return [_unitFiniteValue [lindex $node 1]]}
    set a [_unitFormulaEvaluateTree [lindex $node 1] $x]
    if {[llength $node]==3} {set b [_unitFormulaEvaluateTree [lindex $node 2] $x]}
    switch -- $op {
        + {set v [expr {$a+$b}]}
        - {set v [expr {$a-$b}]}
        * {set v [expr {$a*$b}]}
        / {set v [expr {$a/$b}]}
        ^ {set v [expr {pow($a,$b)}]}
        unary+ {set v $a}
        unary- {set v [expr {-$a}]}
        log {set v [expr {log($a)}]}
        log10 {set v [expr {log10($a)}]}
        exp {set v [expr {exp($a)}]}
        sqrt {set v [expr {sqrt($a)}]}
        default {error {Unknown Unit Registry formula node}}
    }
    return [_unitFiniteValue $v]
}
proc ::GX::unitFormulaEvaluate {formula value} {
    # Same parsed grammar as registration; no script evaluation/interpolation.
    return [_unitFormulaEvaluateTree [_unitFormulaTree $formula] [_unitFiniteValue $value]]
}
proc ::GX::_unitFormulaProgramNode {node depth counterName} {
    upvar 1 $counterName counter
    if {$depth>64||[incr counter]>4096} {error {Unit formula program exceeds bounded complexity}}
    set op [lindex $node 0]
    if {$op eq "x"} {return x}
    if {$op eq "number"} {return [list number [_unitFiniteValue [lindex $node 1]]]}
    set result [list $op]
    foreach child [lrange $node 1 end] {lappend result [_unitFormulaProgramNode $child [expr {$depth+1}] counter]}
    return $result
}
proc ::GX::unitFormulaProgram {formula} {
    set counter 0
    return [dict create program_version 1 tree [_unitFormulaProgramNode [_unitFormulaTree $formula] 0 counter]]
}
proc ::GX::unitRegistryConvertValues {source target values {sourceOverride {}}} {
    if {[llength $values]>4096} {error {Bounded Unit Registry conversion accepts at most 4096 values; use Dataset Transform for scientific arrays}}
    set plan [unitRegistryConversionPlan $source $target $sourceOverride]
    if {$source eq $target&&![dict size $sourceOverride]} {return [lmap value $values {_unitFiniteValue $value}]}
    set forward [_unitFormulaTree [dict get $plan source_to_canonical]]
    set inverse [_unitFormulaTree [dict get $plan target_from_canonical]]
    set ratio [_unitFiniteValue [dict get $plan base_scale_ratio]];set result {}
    foreach value $values {
        set canonical [_unitFormulaEvaluateTree $forward [_unitFiniteValue $value]]
        set scaled [_unitFiniteValue [expr {$canonical*$ratio}]]
        lappend result [_unitFormulaEvaluateTree $inverse $scaled]
    }
    return $result
}
proc ::GX::_unitFormulaAffineTree {node} {
    # Algebraic classification of the registered grammar, never sampled fitting.
    # Empty means no globally affine expression was established by these rules.
    set op [lindex $node 0]
    if {$op eq "x"} {return {1.0 0.0}}
    if {$op eq "number"} {return [list 0.0 [_unitFiniteValue [lindex $node 1]]]}
    set a [_unitFormulaAffineTree [lindex $node 1]]
    if {$a eq {}} {return {}}
    lassign $a af ao
    if {[llength $node]==3} {
        set b [_unitFormulaAffineTree [lindex $node 2]];if {$b eq {}} {return {}}
        lassign $b bf bo
    }
    switch -- $op {
        + {set factor [expr {$af+$bf}];set offset [expr {$ao+$bo}]}
        - {set factor [expr {$af-$bf}];set offset [expr {$ao-$bo}]}
        unary+ {return $a}
        unary- {set factor [expr {-$af}];set offset [expr {-$ao}]}
        * {
            if {$af!=0&&$bf!=0} {return {}}
            set factor [expr {$af*$bo+$bf*$ao}];set offset [expr {$ao*$bo}]
        }
        / {
            if {$bf!=0} {return {}}
            set factor [expr {$af/$bo}];set offset [expr {$ao/$bo}]
        }
        ^ {
            if {$bf!=0} {return {}}
            if {$bo==1} {return $a}
            if {$af!=0} {return {}}
            set factor 0.0;set offset [_unitFormulaEvaluateTree $node 0.0]
        }
        log - log10 - exp - sqrt {
            if {$af!=0} {return {}}
            set factor 0.0;set offset [_unitFormulaEvaluateTree $node 0.0]
        }
        default {error {Unknown Unit Registry formula node}}
    }
    return [list [_unitFiniteValue $factor] [_unitFiniteValue $offset]]
}
proc ::GX::unitRegistryAffinePlan {source target {sourceOverride {}} {direction forward}} {
    if {$direction ni {forward inverse}} {error {Affine plan direction must be forward or inverse}}
    set plan [unitRegistryConversionPlan $source $target $sourceOverride]
    dict set plan direction $direction
    dict set plan input_unit [expr {$direction eq "forward"?$source:$target}]
    dict set plan output_unit [expr {$direction eq "forward"?$target:$source}]
    if {$source eq $target&&![dict size $sourceOverride]} {return [dict merge $plan {affine 1 scale 1.0 offset 0.0 reason {}}]}
    set first [dict get $plan source_to_canonical];set last [dict get $plan target_from_canonical]
    set ratio [dict get $plan base_scale_ratio]
    if {$direction eq "inverse"} {
        set a [dict get $plan source_definition];set b [dict get $plan target_definition]
        set first [expr {[dict get $b canonical_unit] eq {}?"x":[dict get $b to_canonical]}]
        set last [expr {[dict get $a canonical_unit] eq {}?"x":[dict get $a from_canonical]}]
        set ratio [_unitFiniteValue [expr {1.0/$ratio}]]
    }
    set forward [_unitFormulaAffineTree [_unitFormulaTree $first]]
    set inverse [_unitFormulaAffineTree [_unitFormulaTree $last]]
    if {$forward eq {}||$inverse eq {}} {return [dict merge $plan {affine 0 reason {Registered formulas do not establish a global affine conversion; use pointwise Unit Registry conversion}}]}
    lassign $forward af ao;lassign $inverse bf bo
    set scale [_unitFiniteValue [expr {$af*$ratio*$bf}]]
    set offset [_unitFiniteValue [expr {$ao*$ratio*$bf+$bo}]]
    if {$scale==0} {error {Unit conversion collapses its coordinate dimension}}
    return [dict merge $plan [dict create affine 1 scale $scale offset $offset reason {}]]
}

proc ::GX::unitRegistryRegister {symbol definition} {
    variable unitDefinitions
    set symbol [string trim $symbol]
    if {$symbol eq "" || [regexp {[\r\n;=\[\]]} $symbol]} { error "Invalid unit symbol" }
    set allowed {label description owner_plugin canonical_unit conversion_kind scale offset to_canonical from_canonical}
    dict for {key value} $definition {
        if {$key ni $allowed} { error "Unknown unit definition field: $key" }
        if {[regexp {[\r\n]} $value]} { error "Unit definition fields must be single-line" }
    }
    foreach {key default} {label "" description "" owner_plugin "" canonical_unit "" conversion_kind opaque scale "" offset "" to_canonical "" from_canonical ""} {
        if {![dict exists $definition $key]} { dict set definition $key $default }
    }
    if {[dict get $definition label] eq ""} { dict set definition label $symbol }
    set kind [dict get $definition conversion_kind]
    if {$kind ni {opaque identity scale affine formula intrinsic}} { error "Invalid conversion kind" }
    set canonical [string trim [dict get $definition canonical_unit]]
    if {$kind in {scale affine formula} && ($canonical eq "" || $canonical eq $symbol)} { error "Conversion requires another canonical unit" }
    if {$kind in {scale affine}} {
        set factor [dict get $definition scale]
        set offset [dict get $definition offset]
        if {![string is double -strict $factor] || $factor == 0} { error "Scale must be nonzero numeric" }
        if {$offset eq ""} { set offset 0 }
        if {![string is double -strict $offset]} { error "Offset must be numeric" }
        dict set definition offset $offset
        dict set definition to_canonical "x * $factor + $offset"
        dict set definition from_canonical "(x - $offset) / $factor"
    }
    if {$kind eq "formula"} {
        if {[dict get $definition to_canonical] eq "" || [dict get $definition from_canonical] eq ""} { error "Formula conversion requires both directions" }
    }
    foreach field {to_canonical from_canonical} {
        set value [dict get $definition $field]
        if {$value ne ""} { dict set definition $field [unitFormulaValidate $value] }
    }
    set unitDefinitions($symbol) [dict merge [dict create symbol $symbol] $definition]
    return $unitDefinitions($symbol)
}

proc ::GX::unitRegistryDefinition {symbol} {
    variable unitDefinitions
    if {![info exists unitDefinitions($symbol)]} {
        return [dict create symbol $symbol label $symbol description "Unregistered opaque unit" owner_plugin "" canonical_unit "" conversion_kind opaque scale "" offset "" to_canonical "" from_canonical ""]
    }
    set def $unitDefinitions($symbol)
    set owner [dict get $def owner_plugin]
    if {$owner ne "" && (![info exists ::GX::moduleCatalog($owner,descriptor)] || ![moduleIsEnabled $owner])} {
        return [dict create symbol $symbol label $symbol description "Provider unavailable; opaque unit" owner_plugin "" canonical_unit "" conversion_kind opaque scale "" offset "" to_canonical "" from_canonical ""]
    }
    return $def
}

proc ::GX::unitRegistryList {} {
    variable unitDefinitions
    set out {}
    foreach symbol [array names unitDefinitions] {
        set owner [dict get $unitDefinitions($symbol) owner_plugin]
        if {$owner eq "" || ([info exists ::GX::moduleCatalog($owner,descriptor)] && [moduleIsEnabled $owner])} { lappend out $symbol }
    }
    return [lsort $out]
}
proc ::GX::unitRegistryByProvider {provider} {
    variable unitDefinitions
    set out {}
    foreach symbol [unitRegistryList] {
        if {[dict get $unitDefinitions($symbol) owner_plugin] eq $provider} { lappend out $symbol }
    }
    return $out
}
proc ::GX::datasetVariableUnitDefinition {datasetId variableId} {
    set v [datasetVariableById $datasetId $variableId]
    set unit [dict get $v unit]
    set base [unitRegistryDefinition $unit]
    if {[dict get $v canonical_unit] eq ""} { return $base }
    return [dict merge $base [dict create canonical_unit [dict get $v canonical_unit] conversion_kind formula to_canonical [dict get $v to_canonical] from_canonical [dict get $v from_canonical] owner_plugin ""]]
}

proc ::GX::unitRegistryLoadCore {} {
    # Core registration uses the fixed built-in list before registry choices exist.
    foreach symbol [unitSelectorCandidates_before_unit_registry] {
        set kind [expr {$symbol in {FS dB dBFS ppm pH} ? "opaque" : "intrinsic"}]
        unitRegistryRegister $symbol [dict create conversion_kind $kind description "CORE unit"]
    }
    unitRegistryRegister 1 [dict create label Dimensionless conversion_kind intrinsic description {Explicit dimensionless physical coordinate or ratio}]
    unitRegistryRegister mol/L [dict create conversion_kind opaque description "Molar concentration base for explicit relations"]
    unitRegistryRegister mmol/L [dict create conversion_kind scale canonical_unit mol/L scale 0.001 description "Millimolar concentration"]
    unitRegistryRegister °C [dict create label Celsius conversion_kind affine canonical_unit K scale 1 offset 273.15 description "Celsius temperature"]
    unitRegistryRegister % [dict create conversion_kind opaque description "Context-dependent percent"]
    # Long-duration units are explicit registry relations to seconds.  The
    # symbol `a` is defined here specifically as the Julian year so consumers
    # never have to guess a calendar-year convention.  ka and Ma are exact
    # decimal multiples of that same physical unit.
    unitRegistryRegister a [dict create label {Julian year} conversion_kind scale canonical_unit s scale 31557600 description {Julian year, exactly 365.25 days}]
    unitRegistryRegister ka [dict create label {kiloannum (Julian)} conversion_kind scale canonical_unit s scale 31557600000 description {1000 Julian years}]
    unitRegistryRegister Ma [dict create label {megaannum (Julian)} conversion_kind scale canonical_unit s scale 31557600000000 description {1000000 Julian years}]
}
proc ::GX::unitRegistryLoadDescriptors {} {
    variable unitDefinitions
    foreach symbol [array names unitDefinitions] {
        if {[dict get $unitDefinitions($symbol) owner_plugin] ne ""} { unset unitDefinitions($symbol) }
    }
    foreach module $::GX::moduleOrder {
        set d [moduleField $module dict {}]
        foreach id [splitList [descriptorValue $d units ids ""]] {
            set section "unit.$id"
            set symbol [descriptorValue $d $section symbol $id]
            set def [dict create label [descriptorValue $d $section label $symbol] description [descriptorValue $d $section description ""] owner_plugin $module canonical_unit [descriptorValue $d $section canonical_unit ""] conversion_kind [descriptorValue $d $section conversion_kind opaque] scale [descriptorValue $d $section scale ""] offset [descriptorValue $d $section offset ""] to_canonical [descriptorValue $d $section to_canonical ""] from_canonical [descriptorValue $d $section from_canonical ""]]
            unitRegistryRegister $symbol $def
        }
    }
}
::GX::unitRegistryLoadCore
proc ::GX::loadModuleCatalog_before_documentation_browser {} {
    ::GX::loadModuleCatalog_before_unit_registry
    ::GX::unitRegistryLoadDescriptors
}

proc ::GX::unitTclCompatible {a b} {
    if {$a eq $b} { return 1 }
    set A [unitRegistryDefinition $a]; set B [unitRegistryDefinition $b]
    if {[dict get $A canonical_unit] ne ""} { set a [dict get $A canonical_unit] }
    if {[dict get $B canonical_unit] ne ""} { set b [dict get $B canonical_unit] }
    return [unitTclCompatible_before_unit_registry $a $b]
}
proc ::GX::unitRegistryIntrinsicScale {unit} {
    set unit [string trim [string map [list "µ" u "μ" u "Ω" Ohm "·" *] $unit]]
    if {$unit eq "" || $unit in {1 dimensionless}} {return 1.0}
    unitTclDimensionKey $unit
    if {[unitTclSemanticKey $unit] ne ""} {error "Semantic units require an explicit conversion relation"}
    set scale 1.0;set sign 1;set pos 0
    while {$pos<[string length $unit]} {
        set ch [string index $unit $pos]
        if {$ch eq "*"} {set sign 1;incr pos;continue}
        if {$ch eq "/"} {set sign -1;incr pos;continue}
        if {[regexp {^1($|[*/])} [string range $unit $pos end]]} {incr pos;set sign 1;continue}
        regexp {^([A-Za-z]+)(?:\^([+-]?[0-9]+))?} [string range $unit $pos end] whole symbol power
        if {$power eq ""} {set power 1}
        set factor [lindex [unitTclSingle $symbol] 0]
        set scale [expr {$scale*pow($factor,$power*$sign)}]
        incr pos [string length $whole]
    }
    if {$scale<=0 || $scale==Inf} {error "Unit scale is outside the numeric range"}
    return $scale
}
proc ::GX::_unitDifferentialBasis {unit} {
    if {[string length $unit]>128||[string trim $unit] eq {}} {error {An explicit bounded unit is required; use 1 for dimensionless}}
    set definition [unitRegistryDefinition $unit]
    set canonical [dict get $definition canonical_unit]
    set affineScale 1.0
    set offset 0.0
    if {$canonical eq {}} {set canonical $unit} else {
        set plan [unitRegistryAffinePlan $unit $canonical]
        if {![dict get $plan affine]} {error {A nonlinear registered unit needs a point-dependent differential conversion}}
        set affineScale [dict get $plan scale];set offset [dict get $plan offset]
    }
    set key [unitTclDimensionKey $canonical]
    if {[string match semantic:* $key]} {error {Semantic level units have no declared linear differential ratio}}
    set scale [_unitFiniteValue [expr {$affineScale*[unitRegistryIntrinsicScale $canonical]}]]
    if {$scale==0} {error {Unit differential scale is not representable}}
    return [dict create unit $unit canonical_unit $canonical dimension_key $key scale $scale affine_offset $offset]
}
proc ::GX::unitRegistryDifferentialRatioPlan {numerator denominator {target {}}} {
    set result [dict create schema gxtxt.differential_unit_plan.v1 status unavailable numerator_unit $numerator denominator_unit $denominator requested_unit $target output_unit {} dimension_key {} reason {} offset_policy {Affine offsets cancel in differentials; this plan is not an absolute-value conversion}]
    try {
        set top [_unitDifferentialBasis $numerator];set bottom [_unitDifferentialBasis $denominator]
        set dimensions {}
        foreach basis [list $top $bottom] sign {1 -1} {
            set key [dict get $basis dimension_key]
            if {$key eq "1"} continue
            foreach term [split $key ,] {
                lassign [split $term :] base power
                dict incr dimensions $base [expr {$sign*$power}]
            }
        }
        set labels {};set keys {}
        foreach base [lsort [dict keys $dimensions]] {
            set power [dict get $dimensions $base]
            if {$power==0} continue
            lappend keys "$base:$power"
            lappend labels [expr {$power==1?$base:"$base^$power"}]
        }
        set key [join $keys ,];set canonical [join $labels *]
        if {$canonical eq {}} {set key 1;set canonical 1}
        if {$target eq {}} {set target $canonical}
        set output [_unitDifferentialBasis $target]
        if {[dict get $output dimension_key] ne $key} {error {Requested differential output unit has incompatible dimensions}}
        set scale [_unitFiniteValue [expr {[dict get $top scale]/[dict get $bottom scale]/[dict get $output scale]}]]
        if {$scale==0} {error {Differential ratio scale underflows}}
        return [dict merge $result [dict create status value output_unit $target dimension_key $key scale $scale numerator_basis $top denominator_basis $bottom output_basis $output]]
    } on error {message options} {
        dict set result reason $message
        return $result
    }
}
proc ::GX::unitRegistryConversionPlan {source target {sourceOverride {}}} {
    set a [unitRegistryDefinition $source];set b [unitRegistryDefinition $target]
    if {[dict size $sourceOverride]} {
        foreach field [dict keys $sourceOverride] {
            if {$field ni {canonical_unit to_canonical from_canonical}} {error "Unknown variable-specific unit override '$field'"}
        }
        foreach field {canonical_unit to_canonical from_canonical} {
            if {![dict exists $sourceOverride $field] || [string trim [dict get $sourceOverride $field]] eq ""} {error "Variable-specific conversion requires $field"}
        }
        if {[regexp {[\r\n;=\[\]]} [dict get $sourceOverride canonical_unit]]} {error "Invalid canonical unit override"}
        unitFormulaValidate [dict get $sourceOverride to_canonical]
        unitFormulaValidate [dict get $sourceOverride from_canonical]
        set a [dict merge $a $sourceOverride [dict create conversion_kind formula owner_plugin {}]]
    }
    set abase [expr {[dict get $a canonical_unit] ne "" ? [dict get $a canonical_unit] : $source}]
    set bbase [expr {[dict get $b canonical_unit] ne "" ? [dict get $b canonical_unit] : $target}]
    if {$abase eq $bbase} {set ratio 1.0} else {
        if {![unitTclCompatible_before_unit_registry $abase $bbase]} {error "Incompatible unit conversion '$source' -> '$target'"}
        set ratio [expr {[unitRegistryIntrinsicScale $abase]/[unitRegistryIntrinsicScale $bbase]}]
    }
    set forward [expr {[dict get $a canonical_unit] eq "" ? "x" : [dict get $a to_canonical]}]
    set inverse [expr {[dict get $b canonical_unit] eq "" ? "x" : [dict get $b from_canonical]}]
    unitFormulaValidate $forward;unitFormulaValidate $inverse
    return [dict create source_unit $source target_unit $target source_definition $a target_definition $b source_to_canonical $forward base_scale_ratio $ratio target_from_canonical $inverse]
}
proc ::GX::unitSelectorCandidates {} {
    return [lsort -unique [concat [unitSelectorCandidates_before_unit_registry] [unitRegistryList]]]
}
proc ::GX::unitRegistryConvertCoordinates {source target coordinates} {
    unitRegistryConversionPlan $source $target
    if {![unitTclCompatible $source m]||![unitTclCompatible $target m]} {error "Geometry coordinates require compatible length units"}
    if {[llength $coordinates]>4096} {error "Large coordinate conversions require typed Native geometry or a Dataset Transform"}
    set factor [expr {[unitRegistryIntrinsicScale $source]/[unitRegistryIntrinsicScale $target]}]
    set result {}
    foreach value $coordinates {
        if {![string is double -strict $value]||$value!=$value||abs($value)==Inf} {error "Coordinates must be finite"}
        set converted [expr {$value*$factor}]
        if {$converted!=$converted||abs($converted)==Inf} {error "Coordinate conversion exceeds the finite range"}
        lappend result $converted
    }
    return $result
}

# Runtime registry contains current provider definitions plus persisted
# variable-specific user definitions. It is derived, never RAW or canonical data.
proc ::GX::unitRegistryWriteRuntimeFile {} {
    variable currentSession
    variable unitDefinitions
    if {$currentSession eq "" || ![file isdirectory $currentSession]} { return "" }
    set defs [dict create]
    foreach symbol [unitRegistryList] {
        set def [unitRegistryDefinition $symbol]
        if {[dict get $def canonical_unit] ne ""} { dict set defs $symbol $def }
    }
    foreach id [datasetRegistryIds] {
        foreach v [datasetVariableSchema $id] {
            set canonical [dict get $v canonical_unit]
            if {$canonical eq ""} continue
            set symbol [dict get $v unit]
            set def [datasetVariableUnitDefinition $id [dict get $v variable_id]]
            if {[dict exists $defs $symbol]} {
                set old [dict get $defs $symbol]
                foreach field {canonical_unit to_canonical from_canonical} {
                    if {[dict get $old $field] ne [dict get $def $field]} { error "Conflicting conversion definition for unit $symbol" }
                }
            }
            dict set defs $symbol $def
        }
    }
    set path [file join $currentSession metadata unit_registry_runtime.ini]
    file mkdir [file dirname $path]
    set fd [open $path w]; fconfigure $fd -encoding utf-8 -translation lf
    puts $fd {[unit_registry]}; putKV $fd api_version 1; putKV $fd count [dict size $defs]
    set n 0
    dict for {symbol def} $defs {
        incr n; puts $fd "\n\[unit.$n\]"
        foreach field {symbol canonical_unit conversion_kind to_canonical from_canonical} { putKV $fd $field [dict get $def $field] }
    }
    close $fd
    return $path
}

proc ::GX::plotEnv {{moduleId ""}} {
    set out [::GX::plotEnv_before_unit_registry $moduleId]
    set path [unitRegistryWriteRuntimeFile]
    if {$path ne ""} { set out [envListReplace $out GXTXT_UNIT_REGISTRY_FILE $path] }
    return $out
}
