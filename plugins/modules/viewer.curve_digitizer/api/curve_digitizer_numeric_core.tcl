# SPDX-License-Identifier: GPL-3.0-or-later
# Public GX-TXT Numeric API transport for the authoritative Curve Digitalizer.
# Interface contract: dev097 NUMERIC_API_v1 digitization_uncertainty.
# The viewer supplies exact analytic Jacobians in a bounded, in-memory RPC.
# CORE owns Octave, temporary directories, scientific transport, and results.
# No exec, filesystem workspace, or local solver process is owned here.
namespace eval ::GX::CurveDigitizerNumericCore {}
source [file join [file dirname [info script]] curve_digitizer_factor_guard.tcl]

proc ::GX::CurveDigitizerNumericCore::_array {shape values} {
    return [::GX::ScientificTransportv1::array $shape $values]
}
proc ::GX::CurveDigitizerNumericCore::_matrix {rows cols values} {
    if {[llength $values] != $rows} {error {CORE matrix row count changed}}
    set flat {}
    # Numeric API typed arrays are flattened in Fortran/column-major order.
    for {set c 0} {$c<$cols} {incr c} {
        foreach row $values {
            if {[llength $row]!=$cols} {error {CORE matrix column count changed}}
            lappend flat [lindex $row $c]
        }
    }
    return [_array [list $rows $cols] $flat]
}
proc ::GX::CurveDigitizerNumericCore::_numberList {raw count} {
    if {$raw eq {}} {return {}}
    set numbers [split $raw ,]
    if {[llength $numbers]!=$count} {error {Explicit uncertainty vector size changed}}
    foreach x $numbers {
        if {![string is double -strict $x] || ![expr {abs(double($x)) < Inf}] || $x<0} {
            error {Explicit uncertainty contains an invalid finite nonnegative value}
        }
    }
    return $numbers
}
proc ::GX::CurveDigitizerNumericCore::_wireMatrix {encoded expectedRows expectedCols} {
    if {![regexp {^([0-9]+):([0-9]+):([A-Za-z0-9+/=]+)$} $encoded -> r c payload] ||
        $r!=$expectedRows || $c!=$expectedCols || [string length $payload]>1600000} {
        error {Uncertainty linearization has an invalid bounded matrix header}
    }
    set compressed [binary decode base64 -strict $payload]
    set data [zlib decompress $compressed]
    if {[string length $data]!=8*$r*$c} {error {Uncertainty matrix byte count changed}}
    binary scan $data q* values
    if {[llength $values]!=$r*$c} {error {Uncertainty matrix could not be decoded as binary64}}
    foreach x $values {if {![expr {abs(double($x)) < Inf}]} {error {Uncertainty Jacobian is not finite}}}
    return [_array [list $r $c] $values]
}
proc ::GX::CurveDigitizerNumericCore::_decoded {item} {
    return [encoding convertfrom utf-8 [binary decode base64 -strict $item]]
}
proc ::GX::CurveDigitizerNumericCore::_strings {item count} {
    set result [split [_decoded $item] {;}]
    if {[llength $result]!=$count || [lsearch -exact $result {}]>=0} {
        error {Uncertainty calibration identity/units do not match declared dimensions}
    }
    set items {}
    foreach value $result {lappend items [::GX::ScientificTransportv1::text $value]}
    return [dict create kind cell items $items]
}
proc ::GX::CurveDigitizerNumericCore::_inline {packet selected count} {
    set fields [split $packet "\t"]
    if {[llength $fields]!=17 || [lindex $fields 0] ne {CORE_LINEARIZATION_V1} ||
        [lindex $fields 1] ne $selected || $count<1 || $count>4096} {
        error {Uncertainty Numeric inline request is missing or mismatched}
    }
    lassign $fields tag measurement mode reason dist pixel cal override xy jp jc units ids calunits mapping method condition
    set n $count
    set linearization [::GX::ScientificTransportv1::struct [dict create \
        schema [::GX::ScientificTransportv1::text gxtxt.digitization_linearization.v1] \
        coordinates [_wireMatrix $xy $n 2] \
        point_jacobian [_wireMatrix $jp [expr {2*$n}] 2] \
        calibration_jacobian [_wireMatrix $jc [expr {2*$n}] 12] \
        coordinate_units [_strings $units 2] \
        calibration_ids [_strings $ids 12] \
        calibration_units [_strings $calunits 12] \
        mapping [::GX::ScientificTransportv1::text [_decoded $mapping]] \
        jacobian_method [::GX::ScientificTransportv1::text [_decoded $method]] \
        condition_number [_array {1 1} [list $condition]]]]
    set why [_decoded $reason]
    if {[string trim $why] eq {} || [string length $why]>2048} {error {An uncertainty rationale is required}}
    set spec [dict create mode [::GX::ScientificTransportv1::text $mode] rationale [::GX::ScientificTransportv1::text $why]]
    if {$mode eq {pixel_calibration}} {
        if {$override ne {}} {error {Mixed uncertainty model is not allowed}}
        set distribution [_decoded $dist]
        if {$distribution ni {rectangular_full_width normal_standard_uncertainty}} {error {Pixel distribution is not declared}}
        dict set spec pixel_distribution [::GX::ScientificTransportv1::text $distribution]
        # Zero is legitimate and is passed exactly, without epsilon substitution.
        dict set spec pixel_scale [_array {1 2} [_numberList $pixel 2]]
        dict set spec calibration_standard_uncertainty [_array {1 12} [_numberList $cal 12]]
    } elseif {$mode eq {physical_override}} {
        if {$pixel ne {} || $cal ne {}} {error {Mixed uncertainty model is not allowed}}
        set values [_numberList $override 2]
        foreach value $values {if {$value<=0} {error {A physical override must contain strictly positive declared uncertainties}}}
        dict set spec override_standard_uncertainty [_array {1 2} $values]
    } else {error {Inactive/unknown uncertainty model must not invoke Numeric}}
    return [list $linearization [::GX::ScientificTransportv1::struct $spec]]
}
proc ::GX::CurveDigitizerNumericCore::_resource {document format content} {
    # The public managed resource writer owns scientific persistence.
    set writer [::GX::interactiveDocumentResourceOpenWriter $document [dict create format $format]]
    try {
        for {set offset 0} {$offset<[string length $content]} {incr offset 65536} {
            ::GX::interactiveDocumentResourceAppend $writer [string range $content $offset [expr {$offset+65535}]]
        }
        set value [::GX::interactiveDocumentResourceFinalize $writer]
        set writer {}
    } finally {if {$writer ne {}} {::GX::interactiveDocumentResourceAbort $writer}}
    return $value
}
proc ::GX::CurveDigitizerNumericCore::_retainedResources {document full rows state meaning columns pointReference} {
    set count [dict get $rows count]
    set resources [dict create]
    dict set resources configuration [_resource $document gxtxt.curve_digitizer.configuration [encoding convertto utf-8 [dict get $full payload]]]
    dict set resources points $pointReference
    # Retain the public Numeric provider's exact state, not a second scientific
    # model. This is a Tcl dictionary transport representation, not a MAT file.
    dict set resources state [_resource $document gxtxt.digitization_numeric_state.tcldict.v1 [encoding convertto utf-8 $state]]
    set values {}
    foreach field {x y sigma_x sigma_y covariance_xy} {foreach value [dict get $columns $field] {lappend values $value}}
    if {[llength $values]!=5*$count} {error {CORE physical column count changed}}
    dict set resources values [_resource $document float64_column_major_le [binary format q* $values]]
    dict set resources interpretation [_resource $document gxtxt.digitization_interpretation.tcldict.v1 [encoding convertto utf-8 $meaning]]
    return $resources
}
proc ::GX::CurveDigitizerNumericCore::propagate {documentId rowsText measurementId rows sourceDataset sourceSha inline {preflightFactors {}}} {
    # Execution goes ONLY through the official Numeric provider. The public
    # Numeric API itself owns invocation, runtime, request/response and cleanup.
    ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
    foreach command {::GX::NumericAPIv1::callOperation ::GX::StatisticsV1::digitizationInterpretation} {
        if {![llength [info commands $command]]} {error "Required GX-TXT dev097 CORE service '$command' is unavailable"}
    }
    set full [::GX::interactiveDocumentRead $documentId]
    if {[dict get $full module_id] ne {viewer.curve_digitizer}} {error {Uncertainty review requires the digitizer-owned scientific document}}
    set sessionToken [::GX::interactiveDocumentSessionToken]
    set documentSha [dict get $full sha256]
    set n [dict get $rows count]
    lassign [_inline $inline $measurementId $n] linearization specification
    # public operation metadata verifies declared operands and invokes CORE.
    set state [::GX::NumericAPIv1::callOperation digitization_uncertainty [list $linearization $specification]]
    if {![dict exists $state summary] || [dict get $state point_count]!=$n ||
        [dict get $state schema] ne {gxtxt.digitization_uncertainty.v1}} {
        error {CORE returned an incompatible digitization uncertainty state}
    }
    # Validate all local and shared factors before retaining CORE resources.
    if {$preflightFactors ne {}} {
        _checkPreflightFactors $preflightFactors $state $n
    }
    set coreXY [dict get $state coordinates];set coreSigma [dict get $state standard_uncertainty]
    set blocks [dict get $state covariance_blocks]
    if {[llength $coreXY]!=$n || [llength $coreSigma]!=$n || [llength $blocks]!=$n} {
        error {CORE response lost publication row alignment}
    }
    set columns [dict create x {} y {} sigma_x {} sigma_y {} covariance_xy {}]
    for {set i 0} {$i<$n} {incr i} {
        set xy [lindex $coreXY $i];set sig [lindex $coreSigma $i];set cov [lindex $blocks $i]
        if {[llength $xy]!=2 || [llength $sig]!=2 || [llength $cov]!=3} {error {Malformed CORE numerical covariance block}}
        foreach {key value expected} [list x [lindex $xy 0] [lindex [dict get $rows x] $i] \
                                        y [lindex $xy 1] [lindex [dict get $rows y] $i]] {
            if {abs(double($value)-double($expected))>1e-10+1e-10*abs(double($expected))} {
                error "CORE $key does not reproduce published scientific coordinate $i"
            }
            dict lappend columns $key $value
        }
        foreach {key value} [list sigma_x [lindex $sig 0] sigma_y [lindex $sig 1] covariance_xy [lindex $cov 1]] {
            if {![expr {abs(double($value)) < Inf}]} {error {Non-finite Numeric result}}
            dict lappend columns $key $value
        }
    }
    if {[::GX::interactiveDocumentSessionToken] ne $sessionToken ||
        [dict get [::GX::interactiveDocumentRead $documentId] sha256] ne $documentSha} {
        error {Session or document changed during Numeric CORE propagation}
    }
    set current [::GX::CurveDigitizer::_sourceInfo $sourceDataset]
    if {![string equal -nocase [dict get $current sha256] $sourceSha]} {
        error {Source raster changed during Numeric CORE propagation}
    }
    # Resource identity is established before interpreting the Numeric result.
    # The CORE-owned document resources remain retained after this call.
    set pre [dict create source_document_id $documentId source_document_sha256 $documentSha \
        source_dataset_id $sourceDataset source_sha256 $sourceSha row_identity original_point_ids]
    # Stage point order first, so the interpretation is tied to its actual SHA.
    set pointParts {}
    for {set i 0} {$i<$n} {incr i} {
        set f [expr {[llength [dict get $rows family_value]] ? [lindex [dict get $rows family_value] $i] : {}}]
        set vals [list [lindex [dict get $rows curve_id] $i] [lindex [dict get $rows curve_label] $i] \
            [lindex [dict get $rows point_id] $i] [lindex [dict get $rows point_index] $i] $f]
        lappend pointParts [join [lmap v $vals {binary encode base64 -maxlen 0 [encoding convertto utf-8 $v]}] "\t"]
    }
    set pointBytes [encoding convertto utf-8 "[join $pointParts \n]\n"]
    set pointRef [_resource $documentId gxtxt.digitizer_point_order.v1 $pointBytes]
    dict set pre point_ids_sha256 [dict get $pointRef sha256]
    set meaning [::GX::StatisticsV1::digitizationInterpretation [dict get $state summary] $pre]
    set resources [_retainedResources $documentId $full $rows $state $meaning $columns $pointRef]
    # Resource points is written via the same format; verify identity before publication.
    if {[dict get [dict get $resources points] sha256] ne [dict get $pointRef sha256]} {
        error {Point identity changed during managed resource capture}
    }
    if {[::GX::interactiveDocumentSessionToken] ne $sessionToken ||
        [dict get [::GX::interactiveDocumentRead $documentId] sha256] ne $documentSha ||
        ![string equal -nocase [dict get [::GX::CurveDigitizer::_sourceInfo $sourceDataset] sha256] $sourceSha]} {
        error {Scientific Session, configuration or source changed while retaining CORE resources}
    }
    return [dict create columns $columns resources $resources meaning $meaning \
        document_sha256 $documentSha point_count $n source_dataset_id $sourceDataset source_sha256 $sourceSha]
}
