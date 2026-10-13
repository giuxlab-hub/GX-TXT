# GX-TXT Elapsed Time Requested-Unit API v1
# SPDX-License-Identifier: GPL-3.0-or-later
#
# `value_kind=elapsed_time` crosses the public numeric boundary in seconds.
# This API is intentionally one-way from those canonical seconds to a consumer-
# requested representation.  It never consults Dataset `source_unit`, because
# doing so would apply source parsing metadata a second time and corrupt values.

namespace eval ::GX {
    variable elapsedTimeRequestedUnitApiVersion 1
}

proc ::GX::elapsedTimeCanonicalUnit {} {
    return s
}

proc ::GX::elapsedTimeRequestedUnit {{targetUnit ""}} {
    set target [string trim $targetUnit]
    if {$target eq ""} { return [elapsedTimeCanonicalUnit] }

    # Requested elapsed-time units are Unit Registry resources.  Requiring a
    # registered symbol keeps spelling, lifecycle and physical definitions in
    # one public registry rather than creating a second temporal unit table.
    if {[lsearch -exact [unitRegistryList] $target] < 0} {
        error "Unknown requested elapsed-time unit '$target'."
    }
    if {![unitTclCompatible [elapsedTimeCanonicalUnit] $target]} {
        error "Incompatible requested elapsed-time unit '$target'; expected a temporal unit compatible with seconds."
    }
    return $target
}

# Return the number of canonical seconds represented by one target-unit value.
# The required CORE duration units are either intrinsic linear time units or
# Unit Registry scale relations.  Affine/nonlinear relations are rejected: an
# elapsed duration must not acquire an origin-dependent offset or nonlinear map.
proc ::GX::_elapsedTimeSecondsPerUnit {targetUnit {seen {}}} {
    if {$targetUnit eq [elapsedTimeCanonicalUnit]} { return 1.0 }
    if {[lsearch -exact $seen $targetUnit] >= 0} {
        error "Cyclic Unit Registry relation while resolving elapsed-time unit '$targetUnit'."
    }
    lappend seen $targetUnit

    set def [unitRegistryDefinition $targetUnit]
    set canonical [string trim [dict get $def canonical_unit]]
    set kind [dict get $def conversion_kind]

    if {$canonical eq ""} {
        if {$kind ne "intrinsic"} {
            error "Requested elapsed-time unit '$targetUnit' has no linear conversion to seconds."
        }
        if {[catch {lassign [unitTclSingle $targetUnit] scale base dims} err]} {
            error "Requested elapsed-time unit '$targetUnit' cannot be converted to seconds: $err"
        }
        if {$base ne "s" || ![unitTclCompatible s $targetUnit]} {
            error "Incompatible requested elapsed-time unit '$targetUnit'; expected a temporal unit compatible with seconds."
        }
        return [expr {double($scale)}]
    }

    if {$kind ne "scale"} {
        error "Requested elapsed-time unit '$targetUnit' must use a linear scale relation to seconds."
    }
    set scale [dict get $def scale]
    if {![string is double -strict $scale] || double($scale) <= 0.0} {
        error "Requested elapsed-time unit '$targetUnit' has an invalid Unit Registry scale."
    }
    set parent [_elapsedTimeSecondsPerUnit $canonical $seen]
    return [expr {double($scale) * $parent}]
}

proc ::GX::elapsedTimeConvert {values {targetUnit ""}} {
    set target [elapsedTimeRequestedUnit $targetUnit]
    set secondsPerUnit [_elapsedTimeSecondsPerUnit $target]
    set out {}
    foreach value $values {
        if {![string is double -strict $value]} {
            error "Elapsed-time canonical value '$value' is not numeric."
        }
        lappend out [expr {double($value) / $secondsPerUnit}]
    }
    return $out
}
