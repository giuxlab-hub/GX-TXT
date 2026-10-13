# GX-TXT math.numeric protected CORE numerical service API v1
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Public, versioned API hosted by the bundled CORE math.numeric package.
# Consumers discover this entrypoint through math.numeric/module.ini and must
# not depend on runtime implementation files.

namespace eval ::GX::NumericAPIv1 {
    variable apiVersion 1
    variable moduleId math.numeric
    variable lastResultTypes [dict create]
    variable operationCatalogCache [dict create]
    variable foundationCatalogCache [dict create]
}
source [file normalize [file join [file dirname [info script]] .. .. .. .. core tcl scientific_provider_transport_v1.tcl]]

proc ::GX::NumericAPIv1::_error {message} {
    return -code error "math.numeric API v1: $message"
}

proc ::GX::NumericAPIv1::_requireFramework {} {
    foreach cmd {::GX::moduleField ::GX::parseIni ::GX::descriptorValue ::GX::splitList} {
        if {![llength [info commands $cmd]]} {_error "required GX-TXT public service is unavailable: $cmd"}
    }
    variable moduleId
    if {[::GX::moduleField $moduleId descriptor ""] eq ""} {_error "module $moduleId is not discovered"}
}

proc ::GX::NumericAPIv1::_descriptorPath {} {
    variable moduleId
    _requireFramework
    set p [::GX::moduleField $moduleId descriptor ""]
    if {$p eq "" || ![file isfile $p]} {_error "module descriptor is unavailable"}
    return $p
}
proc ::GX::NumericAPIv1::_descriptor {} {return [::GX::parseIni [_descriptorPath]]}
proc ::GX::NumericAPIv1::capabilities {} {
    set d [_descriptor]
    return [::GX::splitList [::GX::descriptorValue $d public_api.NUMERIC_API_v1 capabilities ""]]
}
proc ::GX::NumericAPIv1::supports {capability} {expr {[lsearch -exact [capabilities] $capability] >= 0}}
proc ::GX::NumericAPIv1::requireCapability {capability} {if {![supports $capability]} {_error "capability '$capability' is not supported"}; return 1}
proc ::GX::NumericAPIv1::apiInfo {} {
    variable apiVersion; variable moduleId; _requireFramework
    return [dict create api_name NUMERIC_API_v1 api_version $apiVersion module_id $moduleId \
        module_version [::GX::moduleField $moduleId version ""] octave_available [octaveAvailable] \
        capabilities [capabilities] \
        octave_callback_operations {nonlinear_fit dataset_nonlinear_fit root_find minimize_1d minimize}]
}
proc ::GX::NumericAPIv1::_operationCatalog {} {
    variable operationCatalogCache
    if {[dict size $operationCatalogCache]} {return $operationCatalogCache}
    set path [file join [file dirname [_descriptorPath]] api operations_v1.tsv]
    if {![file isfile $path]} {_error "operation catalog is unavailable"}
    set fd [open $path r]; fconfigure $fd -encoding utf-8
    set catalog [dict create]; set lineNumber 0
    try {
        while {[gets $fd line] >= 0} {
            incr lineNumber
            if {[string trim $line] eq "" || [string index $line 0] eq "#"} continue
            set fields [split $line |]
            if {[llength $fields] != 17} {_error "invalid operation catalog record at line $lineNumber"}
            lassign $fields ids expression category bindings arity arguments kinds shape broadcast options resultKind resultShape nonfinite unit summary capability flags
            if {![regexp {^([0-9]+)(?:\.\.([0-9]+))?$} $arity unused minArity maxArity]} {_error "invalid operation arity at line $lineNumber"}
            if {$maxArity eq ""} {set maxArity $minArity}
            set optionSpecs [dict create]
            if {$options ne "none"} {
                foreach spec [split $options {;}] {
                    if {![regexp {^([^=]+)=(.*)$} $spec unused key values]} {_error "invalid option metadata at line $lineNumber"}
                    dict set optionSpecs $key [split $values ,]
                }
            }
            foreach id [split $ids ,] {
                if {[dict exists $catalog $id]} {_error "duplicate operation ID '$id'"}
                set name $expression
                if {$name eq "auto"} {set name [lindex [split $id .] end]}
                if {$name eq "none"} {set name ""}
                set flagList [split $flags ,]; set resultField values; set optionArgument ""
                foreach flag $flagList {
                    if {[string match {result=*} $flag]} {set resultField [string range $flag 7 end]}
                    if {[string match {option_arg=*} $flag]} {set optionArgument [string range $flag 11 end]}
                }
                dict set catalog $id [dict create \
                    id $id expression_name $name category $category \
                    bindings [split $bindings ,] arity_min $minArity arity_max $maxArity \
                    arguments [split $arguments ,] accepted_kinds [split $kinds ,] \
                    shape_semantics $shape broadcast_semantics $broadcast \
                    options $optionSpecs result_kind $resultKind result_shape $resultShape \
                    nonfinite_policies [split $nonfinite ,] unit_behavior $unit \
                    summary $summary capability $capability flags $flagList \
                    expression_result_field $resultField expression_option_argument $optionArgument \
                    api_id NUMERIC_API_v1 api_version 1]
            }
        }
    } finally {close $fd}
    set operationCatalogCache $catalog
    return $catalog
}
proc ::GX::NumericAPIv1::listOperations {} {return [lsort [dict keys [_operationCatalog]]]}
proc ::GX::NumericAPIv1::operationMetadata {id} {
    set catalog [_operationCatalog]
    if {![dict exists $catalog $id]} {_error "unknown numerical operation '$id'"}
    return [dict get $catalog $id]
}
proc ::GX::NumericAPIv1::operationByExpressionName {name} {
    set found {}
    dict for {id meta} [_operationCatalog] {
        if {[dict get $meta expression_name] eq $name && [lsearch -exact [dict get $meta flags] expression] >= 0} {lappend found $id}
    }
    if {[llength $found] != 1} {_error "unknown or ambiguous expression operation '$name'"}
    return [operationMetadata [lindex $found 0]]
}
# The public foundation dispatcher groups many distinct mathematical actions.
# This provider-owned catalog makes those actions individually discoverable by
# guided clients while retaining the stable foundation call contract.
proc ::GX::NumericAPIv1::_foundationCatalog {} {
    variable foundationCatalogCache
    if {[dict size $foundationCatalogCache]} {return $foundationCatalogCache}
    set path [file join [file dirname [_descriptorPath]] api foundation_operations_v1.tsv]
    if {![file isfile $path]} {_error "foundation operation catalog is unavailable"}
    set fd [open $path r]
    fconfigure $fd -encoding utf-8
    set catalog [dict create]
    set lineNumber 0
    try {
        while {[gets $fd line] >= 0} {
            incr lineNumber
            if {[string trim $line] eq "" || [string index $line 0] eq "#"} continue
            set fields [split $line |]
            if {[llength $fields] != 7} {_error "invalid foundation catalog record at line $lineNumber"}
            lassign $fields family action arguments inputShapes resultShape summary flags
            set id "$family.$action"
            if {[dict exists $catalog $id]} {_error "duplicate foundation action '$id'"}
            set names [split $arguments ,]
            set flagList [split $flags ,]
            set bindings {tcl octave bridge}
            if {[lsearch -exact $flagList callback] >= 0} {set bindings {octave bridge}}
            dict set catalog $id [dict create \
                id $id family $family action $action api_id NUMERIC_API_v1 api_version 1 \
                parent_operation foundation worksheet_name "numeric.foundation.$id" \
                arguments $names input_shapes $inputShapes result_shape $resultShape \
                result_kind structured unit_behavior caller_owned summary $summary \
                flags $flagList bindings $bindings \
                signature "numeric.foundation.${id}([join $names {, }], options)" \
                worksheet_example "Apply numeric.foundation.$id using Worksheet ranges A1:A20 and B1:B20; set action-specific operands in the guided dialog."]
        }
    } finally {close $fd}
    set foundationCatalogCache $catalog
    return $catalog
}
proc ::GX::NumericAPIv1::listFoundationOperations {} {return [lsort [dict keys [_foundationCatalog]]]}
proc ::GX::NumericAPIv1::foundationOperationMetadata {id} {
    set catalog [_foundationCatalog]
    if {![dict exists $catalog $id]} {_error "unknown foundation action '$id'"}
    return [dict get $catalog $id]
}
# Invoke a catalogued, data-only operation through the provider's public
# Octave binding. Operands and options use ScientificTransportv1 typed nodes;
# no caller-supplied command, expression, or callback is evaluated here.
proc ::GX::NumericAPIv1::callOperation {id operands {options {kind struct fields {}}}} {
    set meta [operationMetadata $id]
    if {[lsearch -exact [dict get $meta flags] callback] >= 0} {
        return -code error -errorcode {GXTXT NUMERIC CallbackRequired} "operation '$id' requires an execution-scoped callback"
    }
    if {[lsearch -exact [dict get $meta bindings] octave] < 0} {
        _error "operation '$id' has no Octave data binding"
    }
    set count [llength $operands]
    if {$count < [dict get $meta arity_min] || $count > [dict get $meta arity_max]} {
        _error "operation '$id' expects [dict get $meta arity_min]..[dict get $meta arity_max] data operands; received $count"
    }
    foreach item $operands {
        if {![dict exists $item kind]} {_error "operation '$id' operands must be typed nodes"}
    }
    if {![dict exists $options kind] || [dict get $options kind] ne "struct"} {
        _error "operation '$id' options must be a typed struct node"
    }
    set empty [::GX::ScientificTransportv1::empty]
    set result [::GX::ScientificTransportv1::call math.numeric gxtxt_numeric_catalog_call_v1 \
        $id invoke [dict create kind cell items $operands] $empty $empty $options]
    variable lastResultTypes
    set lastResultTypes [dict get $result types]
    return [dict get $result values]
}
proc ::GX::NumericAPIv1::modelKinds {id} {
    switch -- $id {
        nonlinear_fit - dataset_nonlinear_fit {return {polynomial_fit gaussian exponential}}
        root_find - minimize_1d {return {polynomial}}
        minimize - foundation.constrained.solve {return {quadratic_norm}}
        foundation.calculus.gradient - foundation.calculus.hessian - foundation.calculus.directional {return {polynomial quadratic_norm}}
        foundation.calculus.jacobian {return {polynomial quadratic_norm linear_system}}
        foundation.equations.solve - foundation.equations.multiple_start - foundation.equations.continuation {return {linear_system}}
        foundation.ode.solve {return {linear_ode}}
        foundation.variational.action - foundation.variational.functional -
        foundation.variational.legendre - foundation.variational.euler_lagrange_residual {return {quadratic_lagrangian}}
        foundation.variational.first_variation - foundation.variational.constrained {return {quadratic_norm}}
        default {_error "operation '$id' has no declarative model callback contract"}
    }
}
proc ::GX::NumericAPIv1::callModelOperation {id model operands {options {kind struct fields {}}}} {
    set allowed [modelKinds $id]
    if {![dict exists $model kind] || [dict get $model kind] ne "struct" || ![dict exists $model fields kind value]} {
        _error "model must be a typed struct containing a text kind"
    }
    set kind [dict get $model fields kind value]
    if {$kind ni $allowed} {_error "model '$kind' is not allowed for '$id'; choose [join $allowed {, }]"}
    if {![dict exists $options kind] || [dict get $options kind] ne "struct"} {_error "options must be a typed struct"}
    set expected [expr {[string match {foundation.*} $id] ? 2 : [dict get [dict create nonlinear_fit 3 dataset_nonlinear_fit 5 root_find 1 minimize_1d 1 minimize 1] $id]}]
    if {[llength $operands] != $expected} {_error "operation '$id' requires $expected data operands with its declarative model"}
    foreach item $operands {if {![dict exists $item kind]} {_error "model operation operands must be typed nodes"}}
    set empty [::GX::ScientificTransportv1::empty]
    set result [::GX::ScientificTransportv1::call math.numeric gxtxt_numeric_model_call_v1 \
        $id model [dict create kind cell items $operands] $model $empty $options]
    variable lastResultTypes
    set lastResultTypes [dict get $result types]
    return [dict get $result values]
}
proc ::GX::NumericAPIv1::octaveApiDir {} {
    set descriptor [_descriptorPath]; set d [::GX::parseIni $descriptor]
    set rel [::GX::descriptorValue $d public_api.NUMERIC_API_v1 octave_entrypoint ""]
    if {$rel eq ""} {_error "public Octave binding entrypoint is not declared"}
    set p [file normalize [file join [file dirname $descriptor] $rel]]
    if {![file isfile $p]} {_error "public Octave binding entrypoint is missing"}
    return [file dirname $p]
}
proc ::GX::NumericAPIv1::octaveFunction {} {
    set d [_descriptor]; set f [::GX::descriptorValue $d public_api.NUMERIC_API_v1 octave_function ""]
    if {$f eq ""} {_error "public Octave binding function is not declared"}; return $f
}
proc ::GX::NumericAPIv1::_octaveCommand {} {
    if {[info exists ::GX::cfg(octave_cmd)] && [string trim $::GX::cfg(octave_cmd)] ne ""} {
        set q $::GX::cfg(octave_cmd); if {[auto_execok $q] ne "" || [file executable $q]} {return $q}
    }
    foreach q {octave-cli octave} {set p [auto_execok $q]; if {$p ne ""} {return $p}}
    return ""
}
proc ::GX::NumericAPIv1::octaveAvailable {} {expr {[_octaveCommand] ne ""}}
proc ::GX::NumericAPIv1::_workerPath {} {
    set descriptor [_descriptorPath]; set p [file normalize [file join [file dirname $descriptor] runtime numeric_worker.m]]
    if {![file isfile $p]} {_error "numerical worker is missing"}; return $p
}
proc ::GX::NumericAPIv1::_safeLine {value what} {if {[regexp {[\r\n]} $value]} {_error "$what must be a single-line value"}; return $value}
proc ::GX::NumericAPIv1::_encodeNumber {value what} {
    if {![string is double -strict $value]} {_error "$what contains a non-numeric value '$value'"}
    set q [string tolower [string trim $value]]
    if {[string match {*nan*} $q]} {return NaN}; if {$q in {inf +inf infinity +infinity}} {return Inf}; if {$q in {-inf -infinity}} {return -Inf}
    return [format %.17g [expr {double($value)}]]
}
proc ::GX::NumericAPIv1::_encodeVector {values what} {
    set out {}; set i 0; foreach v $values {lappend out [_encodeNumber $v "$what element $i"]; incr i}; return [join $out {;}]
}
proc ::GX::NumericAPIv1::_matrixShapeAndValues {matrix what} {
    set rows [llength $matrix]; if {$rows < 1} {_error "$what must contain at least one row"}
    set cols [llength [lindex $matrix 0]]; if {$cols < 1} {_error "$what must contain at least one column"}
    set flat {}; set r 0
    foreach row $matrix {if {[llength $row] != $cols} {_error "$what row $r has a different column count"}; set c 0; foreach v $row {lappend flat [_encodeNumber $v "$what row $r column $c"]; incr c}; incr r}
    return [list $rows $cols [join $flat {;}]]
}
proc ::GX::NumericAPIv1::_validateOptions {options} {
    if {$options eq ""} {return [dict create]}; if {[catch {dict size $options}]} {_error "options must be a Tcl dict"}
    dict for {k v} $options {if {![regexp {^[A-Za-z][A-Za-z0-9_]*$} $k]} {_error "invalid option name '$k'"}; _safeLine $v "option '$k'"}; return $options
}
proc ::GX::NumericAPIv1::_writeRequest {path operation data options selection} {
    set f [open $path w]; fconfigure $f -encoding utf-8 -translation lf
    puts $f {[request]}; puts $f "operation=[_safeLine $operation operation]"; puts $f "api_version=1"; puts $f ""
    dict for {key item} $data {
        set kind [dict get $item kind]; set value [dict get $item value]; puts $f "\[data.$key\]"; puts $f "kind=$kind"
        switch -- $kind {
            string {puts $f "value=[_safeLine $value "data '$key'"]"}
            scalar {puts $f "value=[_encodeNumber $value "data '$key'"]"}
            vector {puts $f "value=[_encodeVector $value "data '$key'"]"}
            matrix {lassign [_matrixShapeAndValues $value "data '$key'"] rows cols flat; puts $f "rows=$rows"; puts $f "cols=$cols"; puts $f "value=$flat"}
            default {close $f; _error "unsupported internal data kind '$kind'"}
        }
        puts $f ""
    }
    puts $f {[options]}; dict for {k v} $options {puts $f "$k=[_safeLine $v "option '$k'"]"}; puts $f ""
    puts $f {[selection]}; if {$selection eq ""} {puts $f "enabled=0"} else {dict for {k v} $selection {puts $f "$k=[_safeLine $v "selection '$k'"]"}}
    close $f
}
proc ::GX::NumericAPIv1::_parseResult {path} {
    if {![file isfile $path]} {_error "numerical worker produced no response"}; set d [::GX::parseIni $path]; set ok [::GX::descriptorValue $d result ok 0]
    if {$ok ne "1"} {
        set identifier [::GX::descriptorValue $d error identifier GXTXT:Numeric:WorkerError]
        set message [::GX::descriptorValue $d error message "numerical worker failed"]
        return -code error -errorcode [list GXTXT NUMERIC $identifier] "math.numeric API v1: $message"
    }
    set fields [::GX::splitList [::GX::descriptorValue $d result fields ""]]; set out [dict create]
    variable lastResultTypes; set lastResultTypes [dict create]
    foreach field $fields {
        set sec "result.$field"; set typ [::GX::descriptorValue $d $sec type string]; set val [::GX::descriptorValue $d $sec value ""]
        dict set lastResultTypes $field $typ
        switch -- $typ {
            vector {dict set out $field [expr {$val eq "" ? {} : [split $val {;}]}]}
            matrix {set rows [::GX::descriptorValue $d $sec rows 0]; set cols [::GX::descriptorValue $d $sec cols 0]; set flat [expr {$val eq "" ? {} : [split $val {;}]}]; set m {}; set pos 0; for {set r 0} {$r < $rows} {incr r} {lappend m [lrange $flat $pos [expr {$pos+$cols-1}]]; incr pos $cols}; dict set out $field $m}
            boolean {dict set out $field [expr {$val in {1 true yes on} ? 1 : 0}]}
            default {dict set out $field $val}
        }
    }
    return $out
}
proc ::GX::NumericAPIv1::resultTypes {} {
    variable lastResultTypes
    return $lastResultTypes
}
proc ::GX::NumericAPIv1::_run {operation data {options {}} {selection {}}} {
    set options [_validateOptions $options]; set octave [_octaveCommand]; if {$octave eq ""} {_error "GNU Octave executable is unavailable"}
    variable lastResultTypes; set lastResultTypes [dict create]
    set reqChan [file tempfile reqPath]; close $reqChan; set rspChan [file tempfile rspPath]; close $rspChan; file delete -force $rspPath
    _writeRequest $reqPath $operation $data $options $selection; set cmd [list $octave --quiet --no-gui [_workerPath] --request $reqPath --response $rspPath]
    set failed [catch {exec {*}$cmd 2>@1} output opts]; set parseFailed [catch {set result [_parseResult $rspPath]} parseErr parseOpts]; file delete -force $reqPath $rspPath
    if {$parseFailed} {return -options $parseOpts $parseErr}
    if {$failed} {set msg [string trim $output]; if {$msg eq ""} {set msg "GNU Octave process failed"}; _error $msg}; return $result
}
proc ::GX::NumericAPIv1::_vectorData {args} {set out [dict create]; foreach {name values} $args {dict set out $name [dict create kind vector value $values]}; return $out}
proc ::GX::NumericAPIv1::_scalarData {name value} {dict create $name [dict create kind vector value [list $value]]}
proc ::GX::NumericAPIv1::_mergeData {a b} {dict for {k v} $b {dict set a $k $v}; return $a}

proc ::GX::NumericAPIv1::_arrayOperand {operand} {
    if {![dict exists $operand kind] || ![dict exists $operand value]} {_error "array operand requires kind and value"}
    set kind [dict get $operand kind]
    if {$kind ni {scalar vector matrix}} {_error "array operand kind must be scalar, vector or matrix"}
    return [dict create kind $kind value [dict get $operand value]]
}
proc ::GX::NumericAPIv1::arrayUnary {name operand {options {}}} {
    requireCapability elementwise_unary
    return [_run array_unary [dict create name [dict create kind string value $name] a [_arrayOperand $operand]] $options]
}
proc ::GX::NumericAPIv1::arrayBinary {name left right {options {}}} {
    requireCapability elementwise_binary
    return [_run array_binary [dict create name [dict create kind string value $name] a [_arrayOperand $left] b [_arrayOperand $right]] $options]
}
proc ::GX::NumericAPIv1::arrayCompare {name left right {options {}}} {
    requireCapability elementwise_comparison
    return [_run array_compare [dict create name [dict create kind string value $name] a [_arrayOperand $left] b [_arrayOperand $right]] $options]
}
proc ::GX::NumericAPIv1::arrayMask {name first {second {}}} {
    requireCapability logical_masks
    set data [dict create name [dict create kind string value $name] a [_arrayOperand $first]]
    if {$second ne {}} {dict set data b [_arrayOperand $second]}
    return [_run array_mask $data]
}
proc ::GX::NumericAPIv1::arraySelect {values mask} {
    requireCapability array_selection
    return [_run array_select [dict create a [_arrayOperand $values] mask [_arrayOperand $mask]]]
}
proc ::GX::NumericAPIv1::arrayWhere {mask trueValues falseValues} {
    requireCapability array_selection
    return [_run array_where [dict create mask [_arrayOperand $mask] a [_arrayOperand $trueValues] b [_arrayOperand $falseValues]]]
}
proc ::GX::NumericAPIv1::arrayReduce {name operand {options {}}} {
    requireCapability array_reduction
    return [_run array_reduce [dict create name [dict create kind string value $name] a [_arrayOperand $operand]] $options]
}
proc ::GX::NumericAPIv1::complexUnary {name realPart imaginaryPart {options {}}} {
    requireCapability complex_unary
    return [_run complex_unary [dict create name [dict create kind string value $name] real_part [_arrayOperand $realPart] imaginary_part [_arrayOperand $imaginaryPart]] $options]
}
proc ::GX::NumericAPIv1::complexBinary {name realA imaginaryA realB imaginaryB {options {}}} {
    requireCapability complex_binary
    return [_run complex_binary [dict create name [dict create kind string value $name] real_a [_arrayOperand $realA] imaginary_a [_arrayOperand $imaginaryA] real_b [_arrayOperand $realB] imaginary_b [_arrayOperand $imaginaryB]] $options]
}
proc ::GX::NumericAPIv1::unwrap {phase {options {}}} {
    requireCapability phase_unwrap
    return [_run unwrap [dict create phase [_arrayOperand $phase]] $options]
}

# Low-level vector/matrix operations.
proc ::GX::NumericAPIv1::interpolate {x y xq {options {}}} {requireCapability interpolation; return [_run interpolate [_vectorData x $x y $y xq $xq] $options]}
proc ::GX::NumericAPIv1::resample {x y targetX {options {}}} {requireCapability resampling; return [_run resample [_vectorData x $x y $y xq $targetX] $options]}
proc ::GX::NumericAPIv1::resampleUniform {x y step {options {}}} {requireCapability resampling; set d [_vectorData x $x y $y]; dict set d step [dict create kind vector value [list $step]]; return [_run resample_uniform $d $options]}
proc ::GX::NumericAPIv1::splineCreate {x y {options {}}} {requireCapability splines; return [_run spline_create [_vectorData x $x y $y] $options]}
proc ::GX::NumericAPIv1::_splineModelData {model} {
    foreach k {breaks coefficients pieces order dimension} {if {![dict exists $model $k]} {_error "spline model is missing '$k'"}}
    set d [dict create model_breaks [dict create kind vector value [dict get $model breaks]] model_coefficients [dict create kind matrix value [dict get $model coefficients]] model_pieces [dict create kind vector value [list [dict get $model pieces]]] model_order [dict create kind vector value [list [dict get $model order]]] model_dimension [dict create kind vector value [list [dict get $model dimension]]]]
    set method ""
    if {[dict exists $model method]} {set method [dict get $model method]}
    dict set d model_method [dict create kind string value $method]
    return $d
}
proc ::GX::NumericAPIv1::splineEvaluate {model xq {options {}}} {requireCapability splines; set d [_splineModelData $model]; dict set d xq [dict create kind vector value $xq]; return [_run spline_evaluate $d $options]}
proc ::GX::NumericAPIv1::splineIntegral {model a b {options {}}} {requireCapability splines; set d [_splineModelData $model]; dict set d a [dict create kind vector value [list $a]]; dict set d b [dict create kind vector value [list $b]]; return [_run spline_integral $d $options]}
proc ::GX::NumericAPIv1::integrate {x y {options {}}} {requireCapability integration; return [_run integrate [_vectorData x $x y $y] $options]}
proc ::GX::NumericAPIv1::cumulativeIntegrate {x y {options {}}} {requireCapability cumulative_integration; return [_run cumulative_integrate [_vectorData x $x y $y] $options]}
proc ::GX::NumericAPIv1::differentiate {x y {options {}}} {requireCapability differentiation; return [_run differentiate [_vectorData x $x y $y] $options]}
proc ::GX::NumericAPIv1::gridInfo {x {options {}}} {requireCapability grid_analysis; return [_run grid_info [_vectorData x $x] $options]}
proc ::GX::NumericAPIv1::validateMonotonic {x {options {}}} {requireCapability grid_analysis; return [_run validate_monotonic [_vectorData x $x] $options]}
proc ::GX::NumericAPIv1::uniformGrid {start stop spacing {options {}}} {requireCapability uniform_grid; set d [_vectorData start [list $start] stop [list $stop] spacing [list $spacing]]; return [_run uniform_grid $d $options]}
proc ::GX::NumericAPIv1::commonRange {x1 x2 {options {}}} {requireCapability common_range; return [_run common_range [_vectorData x1 $x1 x2 $x2] $options]}
proc ::GX::NumericAPIv1::statistics {values {options {}}} {requireCapability descriptive_statistics; return [_run statistics [_vectorData values $values] $options]}
proc ::GX::NumericAPIv1::rank {values {options {}}} {requireCapability ranking; return [_run rank [_vectorData values $values] $options]}
proc ::GX::NumericAPIv1::covariance {x y {options {}}} {requireCapability covariance; return [_run covariance [_vectorData x $x y $y] $options]}
proc ::GX::NumericAPIv1::correlation {x y {options {}}} {requireCapability correlation; return [_run correlation [_vectorData x $x y $y] $options]}
proc ::GX::NumericAPIv1::mad {values {options {}}} {requireCapability robust_mad; return [_run mad [_vectorData values $values] $options]}
proc ::GX::NumericAPIv1::histogram {values {edges {}} {options {}}} {
    requireCapability histogram
    set data [_vectorData values $values]
    if {[llength $edges]} {dict set data edges [dict create kind vector value $edges]}
    return [_run histogram $data $options]
}
proc ::GX::NumericAPIv1::ecdf {values {options {}}} {requireCapability ecdf; return [_run ecdf [_vectorData values $values] $options]}
proc ::GX::NumericAPIv1::normalCdf {x mu sigma {options {}}} {
    requireCapability probability_distributions
    return [_run normal_cdf [dict create x [_arrayOperand $x] mu [_arrayOperand $mu] sigma [_arrayOperand $sigma]] $options]
}
proc ::GX::NumericAPIv1::studentTCdf {t degreesOfFreedom {options {}}} {
    requireCapability probability_distributions
    return [_run student_t_cdf [dict create t [_arrayOperand $t] df [_arrayOperand $degreesOfFreedom]] $options]
}
proc ::GX::NumericAPIv1::fCdf {f df1 df2 {options {}}} {
    requireCapability probability_distributions
    return [_run f_cdf [dict create f [_arrayOperand $f] df1 [_arrayOperand $df1] df2 [_arrayOperand $df2]] $options]
}
proc ::GX::NumericAPIv1::matrixSvd {matrix {options {}}} {
    requireCapability matrix_svd
    return [_run matrix_svd [dict create matrix [dict create kind matrix value $matrix]] $options]
}
proc ::GX::NumericAPIv1::_complexMatrixData {name operand} {
    if {[catch {dict size $operand}] || ![dict exists $operand real]} {_error "$name requires a real matrix field"}
    set real [dict get $operand real]
    if {[dict exists $operand imaginary]} {set imaginary [dict get $operand imaginary]} else {
        set imaginary {}; foreach row $real {lappend imaginary [lrepeat [llength $row] 0]}
    }
    lassign [_matrixShapeAndValues $real "$name real"] nr nc unused
    lassign [_matrixShapeAndValues $imaginary "$name imaginary"] ni nj unused
    if {$nr != $ni || $nc != $nj} {_error "$name real and imaginary shapes differ"}
    return [dict create "${name}_real" [dict create kind matrix value $real] "${name}_imaginary" [dict create kind matrix value $imaginary]]
}
proc ::GX::NumericAPIv1::linearMatrix {action matrix {other {}} {options {}}} {
    requireCapability complex_linear_algebra
    set data [_complexMatrixData a $matrix]
    dict set data action [dict create kind string value $action]
    if {$other ne {}} {set data [_mergeData $data [_complexMatrixData b $other]]}
    return [_run linear_matrix $data $options]
}
proc ::GX::NumericAPIv1::foundation {family action a b c {options {kind struct fields {}}}} {
    requireCapability mathematical_foundation
    if {$family in {ode constrained equations variational} || ($family eq "calculus" && $action in {gradient jacobian hessian directional})} {
        return -code error -errorcode {GXTXT NUMERIC CallbackRequired} "callback-based foundation operations require direct Octave binding"
    }
    set result [::GX::ScientificTransportv1::call math.numeric gxtxt_numeric_foundation_public_v1 $family $action $a $b $c $options]
    variable lastResultTypes
    set lastResultTypes [dict get $result types]
    return [dict get $result values]
}
proc ::GX::NumericAPIv1::resampleIndices {populationSize drawCount replicates seed {options {}}} {
    requireCapability random_resampling
    set data [_vectorData population_size [list $populationSize] draw_count [list $drawCount] replicates [list $replicates] seed [list $seed]]
    return [_run resample_indices $data $options]
}
proc ::GX::NumericAPIv1::residualMetrics {observed predicted {options {}}} {requireCapability residual_metrics; return [_run residual_metrics [_vectorData observed $observed predicted $predicted] $options]}
proc ::GX::NumericAPIv1::quantiles {values probabilities {options {}}} {requireCapability quantiles; return [_run quantiles [_vectorData values $values probabilities $probabilities] $options]}
proc ::GX::NumericAPIv1::weightedQuantiles {values weights probabilities {options {}}} {requireCapability weighted_quantiles; return [_run weighted_quantiles [_vectorData values $values weights $weights probabilities $probabilities] $options]}
proc ::GX::NumericAPIv1::cumulativeSum {values {options {}}} {requireCapability cumulative_sum; return [_run cumulative_sum [_vectorData values $values] $options]}
proc ::GX::NumericAPIv1::normalizeVector {values {options {}}} {requireCapability vector_normalization; return [_run vector_normalize [_vectorData values $values] $options]}
proc ::GX::NumericAPIv1::vectorSimilarity {a b {options {}}} {requireCapability vector_similarity; return [_run vector_similarity [_vectorData a $a b $b] $options]}
proc ::GX::NumericAPIv1::weightedStatistics {values weights {options {}}} {requireCapability weighted_statistics; return [_run weighted_statistics [_vectorData values $values weights $weights] $options]}
proc ::GX::NumericAPIv1::leastSquares {design response {weights {}} {options {}}} {requireCapability linear_least_squares; set d [dict create design [dict create kind matrix value $design] response [dict create kind vector value $response]]; if {[llength $weights]} {requireCapability weighted_linear_least_squares; dict set d weights [dict create kind vector value $weights]}; return [_run least_squares $d $options]}
proc ::GX::NumericAPIv1::linearRegression {x y {weights {}} {options {}}} {requireCapability linear_regression; set d [_vectorData x $x y $y]; if {[llength $weights]} {dict set d weights [dict create kind vector value $weights]}; return [_run linear_regression $d $options]}
proc ::GX::NumericAPIv1::polynomialFit {x y degree {weights {}} {options {}}} {requireCapability polynomial_fit; set d [_vectorData x $x y $y degree [list $degree]]; if {[llength $weights]} {requireCapability weighted_polynomial_fit; dict set d weights [dict create kind vector value $weights]}; return [_run polynomial_fit $d $options]}
proc ::GX::NumericAPIv1::_polynomialModelData {model} {
    if {![dict exists $model coefficients]} {_error "polynomial model is missing coefficients"}; set d [dict create model_coefficients [dict create kind vector value [dict get $model coefficients]]]
    if {[dict exists $model scaled_coefficients]} {foreach k {x_center x_scale} {if {![dict exists $model $k]} {_error "polynomial model is missing '$k'"}}; dict set d model_scaled_coefficients [dict create kind vector value [dict get $model scaled_coefficients]]; dict set d model_x_center [dict create kind vector value [list [dict get $model x_center]]]; dict set d model_x_scale [dict create kind vector value [list [dict get $model x_scale]]]}; return $d
}
proc ::GX::NumericAPIv1::polynomialEvaluate {model xq {options {}}} {requireCapability polynomial_fit; set d [_polynomialModelData $model]; dict set d xq [dict create kind vector value $xq]; return [_run polynomial_evaluate $d $options]}
proc ::GX::NumericAPIv1::smooth {x y {options {}}} {requireCapability smoothing; return [_run smooth [_vectorData x $x y $y] $options]}
proc ::GX::NumericAPIv1::digitalFilter {y b a {options {}}} {requireCapability digital_filter; return [_run digital_filter [_vectorData y $y b $b a $a] $options]}
proc ::GX::NumericAPIv1::findPeaks {x y {options {}}} {requireCapability peak_detection; return [_run find_peaks [_vectorData x $x y $y] $options]}
proc ::GX::NumericAPIv1::baseline {x y {options {}}} {requireCapability baseline_estimation; return [_run baseline [_vectorData x $x y $y] $options]}
proc ::GX::NumericAPIv1::baselineAnchored {x y anchorX anchorY {options {}}} {requireCapability baseline_estimation; set d [_vectorData x $x y $y anchor_x $anchorX anchor_y $anchorY]; dict set options method anchors; return [_run baseline $d $options]}
proc ::GX::NumericAPIv1::propagateIndependentUncertainty {jacobian standardUncertainty {options {}}} {requireCapability uncertainty_propagation; set d [dict create jacobian [dict create kind matrix value $jacobian] uncertainty [dict create kind vector value $standardUncertainty]]; dict set options input_kind standard_uncertainty; return [_run propagate_uncertainty $d $options]}
proc ::GX::NumericAPIv1::propagateCovariance {jacobian covariance {options {}}} {requireCapability uncertainty_propagation; set d [dict create jacobian [dict create kind matrix value $jacobian] uncertainty [dict create kind matrix value $covariance]]; dict set options input_kind covariance; return [_run propagate_uncertainty $d $options]}

# Reusable transform/spectral primitives. The Tcl transport accepts real FFT
# input and represents complex transform values as separate real/imaginary vectors.
proc ::GX::NumericAPIv1::fft {values {options {}}} {requireCapability fft; return [_run fft [_vectorData values $values] $options]}
proc ::GX::NumericAPIv1::ifft {realValues imaginaryValues {options {}}} {requireCapability ifft; return [_run ifft [_vectorData real_values $realValues imaginary_values $imaginaryValues] $options]}
proc ::GX::NumericAPIv1::analyticSignal {values {options {}}} {requireCapability analytic_signal; return [_run analytic_signal [_vectorData values $values] $options]}
proc ::GX::NumericAPIv1::frequencyGrid {sampleRate nfft {options {}}} {requireCapability frequency_grid; return [_run frequency_grid [_vectorData sample_rate [list $sampleRate] nfft [list $nfft]] $options]}
proc ::GX::NumericAPIv1::oneSided {realValues imaginaryValues {options {}}} {requireCapability one_sided_transform; return [_run one_sided [_vectorData real_values $realValues imaginary_values $imaginaryValues] $options]}
proc ::GX::NumericAPIv1::detrend {values {options {}}} {requireCapability detrending; return [_run detrend [_vectorData values $values] $options]}
proc ::GX::NumericAPIv1::window {name length {options {}}} {requireCapability window_generation; set d [dict create name [dict create kind string value $name] length [dict create kind vector value [list $length]]]; return [_run window $d $options]}

# nonlinearFit, rootFind, minimize1D, minimize and datasetNonlinearFit intentionally
# live in the public Octave binding: executable callbacks are not serialized by
# the Tcl one-shot worker.

proc ::GX::NumericAPIv1::_recordGet {record key default} {
    if {[dict exists $record $key]} {return [dict get $record $key]}
    return $default
}

proc ::GX::NumericAPIv1::_selectionForDataset {session datasetId selectionId} {
    if {$selectionId eq ""} {return {}}
    set session [file normalize $session]
    set record [::GX::sessionInspectionSelection $selectionId $session]
    set source [dict get $record source_dataset_id]
    if {$source ne $datasetId} {
        _error "Dataset Selection '$selectionId' belongs to dataset '$source', not '$datasetId'"
    }
    set type [string tolower [dict get $record type]]
    if {$type ni {x_range rectangle}} {_error "unsupported Dataset Selection type '$type'"}
    set xid [_recordGet $record x_variable_id ""]
    if {$xid eq ""} {
        set xname [_recordGet $record x_variable ""]
        if {$xname eq ""} {_error "Dataset Selection '$selectionId' has no stable X variable identity"}
        set xid [_selectionVariableId $session $datasetId $xname]
    }
    set yid [_recordGet $record y_variable_id ""]
    if {$type eq "rectangle" && $yid eq ""} {
        set yname [_recordGet $record y_variable ""]
        if {$yname eq ""} {_error "Dataset Selection '$selectionId' has no stable Y variable identity"}
        set yid [_selectionVariableId $session $datasetId $yname]
    }
    set selection [dict create \
        enabled 1 id $selectionId type $type source_dataset_id $source \
        x_variable_id $xid x_min [_recordGet $record x_min ""] \
        x_max [_recordGet $record x_max ""] \
        x_unit [_recordGet $record x_unit ""] \
        x_coordinate_space [_recordGet $record x_coordinate_space source] \
        x_binding_count [_recordGet $record x_binding_count 0]]
    if {$type eq "rectangle"} {
        dict set selection y_variable_id $yid
        dict set selection y_min [_recordGet $record y_min ""]
        dict set selection y_max [_recordGet $record y_max ""]
        dict set selection y_unit [_recordGet $record y_unit ""]
    }
    return $selection
}

proc ::GX::NumericAPIv1::_selectionVariableId {session datasetId name} {
    set handle [::GX::datasetAccessOpen $session $datasetId]
    try {
        foreach variable [dict get [::GX::datasetAccessMetadata $handle] variables] {
            if {[dict get $variable variable_id] eq $name ||
                [_recordGet $variable canonical ""] eq $name} {
                return [dict get $variable variable_id]
            }
        }
    } finally {::GX::datasetAccessClose $handle}
    _error "Dataset '$datasetId' has no variable '$name'"
}

proc ::GX::NumericAPIv1::_datasetData {session datasetId pairs} {
    set session [file normalize $session]
    if {![file isdirectory $session]} {_error "Dataset session directory does not exist: $session"}
    set out [dict create \
        session [dict create kind string value $session] \
        dataset_id [dict create kind string value $datasetId]]
    foreach {name value} $pairs {
        if {[string trim $value] eq ""} {_error "$name is required"}
        dict set out $name [dict create kind string value $value]
    }
    return $out
}

proc ::GX::NumericAPIv1::_splitDatasetOptions {session datasetId options} {
    set options [_validateOptions $options]
    set selectionId ""
    if {[dict exists $options selection_id]} {
        set selectionId [dict get $options selection_id]
        dict unset options selection_id
    }
    set selection [_selectionForDataset $session $datasetId $selectionId]
    return [list $options $selection]
}


proc ::GX::NumericAPIv1::integrateDataset {session datasetId xVariableId yVariableId {options {}}} {requireCapability dataset_calculus; lassign [_splitDatasetOptions $session $datasetId $options] options selection; return [_run dataset_integrate [_datasetData $session $datasetId [list x_variable_id $xVariableId y_variable_id $yVariableId]] $options $selection]}
proc ::GX::NumericAPIv1::cumulativeIntegrateDataset {session datasetId xVariableId yVariableId {options {}}} {requireCapability dataset_calculus; lassign [_splitDatasetOptions $session $datasetId $options] options selection; return [_run dataset_cumulative_integrate [_datasetData $session $datasetId [list x_variable_id $xVariableId y_variable_id $yVariableId]] $options $selection]}
proc ::GX::NumericAPIv1::differentiateDataset {session datasetId xVariableId yVariableId {options {}}} {requireCapability dataset_calculus; lassign [_splitDatasetOptions $session $datasetId $options] options selection; return [_run dataset_differentiate [_datasetData $session $datasetId [list x_variable_id $xVariableId y_variable_id $yVariableId]] $options $selection]}
proc ::GX::NumericAPIv1::interpolateDataset {session datasetId xVariableId yVariableId targetX {options {}}} {requireCapability dataset_interpolation; lassign [_splitDatasetOptions $session $datasetId $options] options selection; set d [_datasetData $session $datasetId [list x_variable_id $xVariableId y_variable_id $yVariableId]]; dict set d xq [dict create kind vector value $targetX]; return [_run dataset_interpolate $d $options $selection]}
proc ::GX::NumericAPIv1::resampleUniformDataset {session datasetId xVariableId yVariableId step {options {}}} {requireCapability dataset_resampling; lassign [_splitDatasetOptions $session $datasetId $options] options selection; set d [_datasetData $session $datasetId [list x_variable_id $xVariableId y_variable_id $yVariableId]]; dict set d step [dict create kind vector value [list $step]]; return [_run dataset_resample_uniform $d $options $selection]}
# Backward-compatible name from math.numeric 1.0.0.
proc ::GX::NumericAPIv1::resampleDataset {session datasetId xVariableId yVariableId targetOrStep {options {}}} {
    # Explicit target-grid resampling is selected with options grid=explicit; the
    # legacy/default form interprets the fifth argument as a uniform step.
    set grid [expr {[dict exists $options grid] ? [string tolower [dict get $options grid]] : "uniform"}]
    if {[dict exists $options grid]} {dict unset options grid}
    if {$grid eq "explicit"} {return [resampleExplicitDataset $session $datasetId $xVariableId $yVariableId $targetOrStep $options]}
    return [resampleUniformDataset $session $datasetId $xVariableId $yVariableId $targetOrStep $options]
}
proc ::GX::NumericAPIv1::resampleExplicitDataset {session datasetId xVariableId yVariableId targetX {options {}}} {requireCapability dataset_resampling; lassign [_splitDatasetOptions $session $datasetId $options] options selection; set d [_datasetData $session $datasetId [list x_variable_id $xVariableId y_variable_id $yVariableId]]; dict set d xq [dict create kind vector value $targetX]; return [_run dataset_resample $d $options $selection]}
proc ::GX::NumericAPIv1::statisticsDataset {session datasetId variableId {options {}}} {requireCapability dataset_statistics; lassign [_splitDatasetOptions $session $datasetId $options] options selection; return [_run dataset_statistics [_datasetData $session $datasetId [list variable_id $variableId]] $options $selection]}
proc ::GX::NumericAPIv1::reduceSummaryDataset {session datasetId variableId {options {}}} {requireCapability dataset_linear_reductions; lassign [_splitDatasetOptions $session $datasetId $options] options selection; return [_run dataset_reduce_summary [_datasetData $session $datasetId [list variable_id $variableId]] $options $selection]}
proc ::GX::NumericAPIv1::weightedStatisticsDataset {session datasetId variableId weightVariableId {options {}}} {requireCapability dataset_statistics; lassign [_splitDatasetOptions $session $datasetId $options] options selection; return [_run dataset_weighted_statistics [_datasetData $session $datasetId [list variable_id $variableId weight_variable_id $weightVariableId]] $options $selection]}
proc ::GX::NumericAPIv1::gridInfoDataset {session datasetId xVariableId {options {}}} {requireCapability dataset_variables; lassign [_splitDatasetOptions $session $datasetId $options] options selection; return [_run dataset_grid_info [_datasetData $session $datasetId [list x_variable_id $xVariableId]] $options $selection]}
proc ::GX::NumericAPIv1::polynomialFitDataset {session datasetId xVariableId yVariableId degree {options {}}} {requireCapability dataset_fitting; lassign [_splitDatasetOptions $session $datasetId $options] options selection; set d [_datasetData $session $datasetId [list x_variable_id $xVariableId y_variable_id $yVariableId]]; dict set d degree [dict create kind vector value [list $degree]]; return [_run dataset_polynomial_fit $d $options $selection]}
proc ::GX::NumericAPIv1::smoothDataset {session datasetId xVariableId yVariableId {options {}}} {requireCapability dataset_smoothing; lassign [_splitDatasetOptions $session $datasetId $options] options selection; return [_run dataset_smooth [_datasetData $session $datasetId [list x_variable_id $xVariableId y_variable_id $yVariableId]] $options $selection]}
proc ::GX::NumericAPIv1::findPeaksDataset {session datasetId xVariableId yVariableId {options {}}} {requireCapability dataset_peaks; lassign [_splitDatasetOptions $session $datasetId $options] options selection; return [_run dataset_find_peaks [_datasetData $session $datasetId [list x_variable_id $xVariableId y_variable_id $yVariableId]] $options $selection]}
proc ::GX::NumericAPIv1::baselineDataset {session datasetId xVariableId yVariableId {options {}}} {requireCapability dataset_baseline; lassign [_splitDatasetOptions $session $datasetId $options] options selection; return [_run dataset_baseline [_datasetData $session $datasetId [list x_variable_id $xVariableId y_variable_id $yVariableId]] $options $selection]}
proc ::GX::NumericAPIv1::arrayUnaryDataset {session datasetId variableId name {options {}}} {
    requireCapability dataset_elementwise
    lassign [_splitDatasetOptions $session $datasetId $options] options selection
    set data [_datasetData $session $datasetId [list variable_id $variableId]]
    dict set data name [dict create kind string value $name]
    return [_run dataset_array_unary $data $options $selection]
}
proc ::GX::NumericAPIv1::arrayBinaryDataset {session datasetId leftVariableId rightVariableId name {options {}}} {
    requireCapability dataset_elementwise
    lassign [_splitDatasetOptions $session $datasetId $options] options selection
    set data [_datasetData $session $datasetId [list left_variable_id $leftVariableId right_variable_id $rightVariableId]]
    dict set data name [dict create kind string value $name]
    return [_run dataset_array_binary $data $options $selection]
}
proc ::GX::NumericAPIv1::arrayScalarDataset {session datasetId variableId scalar name {options {}}} {
    requireCapability dataset_elementwise
    lassign [_splitDatasetOptions $session $datasetId $options] options selection
    set data [_datasetData $session $datasetId [list variable_id $variableId]]
    dict set data scalar [dict create kind vector value [list $scalar]]
    dict set data name [dict create kind string value $name]
    return [_run dataset_array_scalar $data $options $selection]
}
