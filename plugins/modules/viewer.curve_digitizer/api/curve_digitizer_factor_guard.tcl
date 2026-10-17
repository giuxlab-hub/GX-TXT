# SPDX-License-Identifier: GPL-3.0-or-later
# Full factor-integrity boundary for Curve Digitalizer and public Numeric CORE.
namespace eval ::GX::CurveDigitizerNumericCore {}

# Avoid ambiguous, falsely convertible derived units: simple atomic symbols
# are combined as an intrinsic unit product; compound symbols remain grouped.
# In either case the same physical unit string is placed in Schema v3 and
# the supplementary metadata. No local Unit Registry is introduced.
proc ::GX::CurveDigitizerNumericCore::covarianceUnit {xUnit yUnit} {
    set xUnit [string trim $xUnit]
    set yUnit [string trim $yUnit]
    if {$xUnit eq {} || $yUnit eq {} || [string length $xUnit]>128 || [string length $yUnit]>128} {
        error {CORE-reviewed covariance requires two explicit bounded axis units}
    }
    if {[regexp {^[[:alnum:]_.µΩ]+(\^-?[0-9]+)?$} $xUnit] &&
        [regexp {^[[:alnum:]_.µΩ]+(\^-?[0-9]+)?$} $yUnit]} {
        return "${xUnit}*${yUnit}"
    }
    return "(${xUnit})*(${yUnit})"
}

# Preflight factor values must reproduce both independent and shared Numeric
# factors. Marginal sigma/covariance checks alone miss cross-point differences.
# The first 4N little-endian float64 values are 2N x 2 local factors;
# the next 24N values are 2N x 12 shared factors, in original point order.
proc ::GX::CurveDigitizerNumericCore::_checkPreflightFactors {json state n} {
    # Narrow integration adapter for this flat canonical wire record. Reject
    # duplicate/unknown fields and trailing content before inspecting factors.
    if {[string length $json]>1150000} {error {Factor record exceeds its bound}}
    set rest [string trim $json]
    if {[string index $rest 0] ne "\{" || [string index $rest end] ne "\}"} {error {Invalid factor record object}}
    set rest [string trim [string range $rest 1 end-1]];set fields {}
    while {$rest ne {}} {
        if {![regexp {^"(format|shape_local|shape_shared|raw_sha256|payload)"\s*:\s*("[^"\\]*"|\[[0-9,[:space:]]+\])} $rest whole key value]} {error {Invalid canonical factor field}}
        if {[dict exists $fields $key]} {error {Duplicate factor field}}
        dict set fields $key $value
        set rest [string trim [string range $rest [string length $whole] end]]
        if {$rest ne {}} {
            if {[string index $rest 0] ne ","} {error {Invalid factor field separator}}
            set rest [string trim [string range $rest 1 end]]
            if {$rest eq {}} {error {Trailing factor separator}}
        }
    }
    if {[dict size $fields]!=5 || ![dict exists $fields raw_sha256] || ![regexp {^"([a-f0-9]{64})"$} [dict get $fields raw_sha256] -> rawSha]} {error {Factor record requires a canonical raw SHA-256}}
    if {[string length $json] > 1150000 ||
        ![regexp {"format"\s*:\s*"zlib-base64-float64-le-v1"} $json] ||
        ![regexp {"shape_local"\s*:\s*\[\s*([0-9]+)\s*,\s*2\s*,\s*2\s*\]} $json -> localRows] ||
        ![regexp {"shape_shared"\s*:\s*\[\s*([0-9]+)\s*,\s*12\s*\]} $json -> sharedRows] ||
        ![regexp {"payload"\s*:\s*"([A-Za-z0-9+/=]+)"} $json -> payload] ||
        $localRows != $n || $sharedRows != 2*$n} {
        error {Uncertainty preflight has an invalid full-factor shape or representation}
    }
    set independent [dict get $state independent_factor]
    set shared [dict get $state shared_factor]
    if {[llength $independent] != 2*$n || [llength $shared] != 2*$n} {
        error {CORE full-factor row alignment differs from preflight}
    }
    set expectedBytes [expr {$n*28*8}]
    set inflater [zlib stream decompress]
    try {
        $inflater put [binary decode base64 -strict $payload]
        set raw [$inflater get [expr {$expectedBytes+1}]]
        if {[string length $raw] != $expectedBytes || [$inflater get 1] ne {}} {
            error {Uncertainty preflight factor binary payload has an invalid length}
        }
    } finally {
        $inflater close
    }
    if {[::GX::datasetStorageSha256Bytes [::GX::sessionInspectionCurrentSession] $raw] ne $rawSha} {error {Factor raw SHA-256 mismatch}}
    binary scan $raw q* scalarFactors
    if {[llength $scalarFactors] != 28*$n} {
        error {Preflight factors are not binary64 arrays}
    }
    set at 0
    foreach row $independent {
        if {[llength $row] != 2} {error {CORE independent factor width differs}}
        foreach core $row {
            set old [lindex $scalarFactors $at]
            if {![expr {abs(double($core)) < Inf && abs(double($old)) < Inf}] ||
                abs(double($core)-double($old)) > 4.e-12*max(abs(double($core)),abs(double($old)),1.e-15)} {
                error "Full-factor mismatch at local component $at; publication aborted"
            }
            incr at
        }
    }
    foreach row $shared {
        if {[llength $row] != 12} {error {CORE shared factor width differs}}
        foreach core $row {
            set old [lindex $scalarFactors $at]
            if {![expr {abs(double($core)) < Inf && abs(double($old)) < Inf}] ||
                abs(double($core)-double($old)) > 4.e-12*max(abs(double($core)),abs(double($old)),1.e-15)} {
                error "Full-factor mismatch at shared component [expr {$at-4*$n}]; publication aborted"
            }
            incr at
        }
    }
    return verified
}
