# SPDX-License-Identifier: GPL-3.0-or-later
# AIA/ANDI-CHROM Acquisition Handler Plugin API v1, no CORE modifications.
namespace eval ::AcqAiaAndi {
    variable helper [file normalize [file join [file dirname [info script]] andi_chromatography.py]]
}

proc ::AcqAiaAndi::_decode {value} {
    return [encoding convertfrom utf-8 [binary decode base64 $value]]
}

proc ::AcqAiaAndi::_helperCall {path mode {tracePath ""} {peaksPath ""}} {
    variable helper
    if {![file isfile $path] || ![file readable $path]} {
        error "AIA source must be a readable regular file."
    }
    if {![file isfile $helper]} { error "AIA parser helper is missing." }
    set python [::GX::runtimeToolRequired python]
    set argv [list $python $helper --input $path --mode $mode]
    if {$mode eq "import"} {
        lappend argv --trace-path $tracePath --peaks-path $peaksPath
    }
    if {[catch {set output [exec {*}$argv]} issue]} {
        set diagnostic [string trim $issue]
        foreach line [split $issue "\n"] {
            if {[string first "AIA/ANDI import: " $line] == 0} {
                set diagnostic [string range $line 17 end]
                break
            }
        }
        error "AIA/ANDI parser: $diagnostic"
    }
    set gotHeader 0
    set metadata [dict create]
    set warnings [list]
    set columns [dict create T {} K {}]
    set previews [list]
    foreach line [split $output "\n"] {
        set line [string trimright $line "\r"]
        if {$line eq ""} continue
        if {!$gotHeader} {
            if {$line ne "GXANDI1"} {error "Unexpected AIA helper protocol."}
            set gotHeader 1
            continue
        }
        set parts [split $line "\t"]
        set kind [lindex $parts 0]
        switch -- $kind {
            M {
                if {[llength $parts] != 3} {error "Invalid AIA metadata record."}
                set key [_decode [lindex $parts 1]]
                set val [_decode [lindex $parts 2]]
                if {![regexp {^[a-zA-Z0-9_-]+([.][a-zA-Z0-9_-]+)+$} $key]} {
                    error "Invalid namespaced AIA metadata key."
                }
                dict set metadata $key $val
            }
            W {
                if {[llength $parts] != 2} {error "Invalid AIA warning record."}
                lappend warnings [_decode [lindex $parts 1]]
            }
            C {
                if {[llength $parts] != 8} {error "Invalid AIA schema record."}
                set tag [lindex $parts 1]
                if {$tag ni {T K}} {error "Invalid AIA schema group."}
                set index [lindex $parts 2]
                if {![string is integer -strict $index] || $index != [expr {[llength [dict get $columns $tag]] + 1}]} {
                    error "Invalid AIA schema column order."
                }
                lassign [lmap v [lrange $parts 3 7] {_decode $v}] name unit dtype role label
                if {![regexp {^[A-Za-z][A-Za-z0-9_]*$} $name] || $dtype ni {int32 float64 string}} {
                    error "Invalid AIA variable descriptor."
                }
                dict lappend columns $tag [dict create name $name unit $unit dtype $dtype role $role label $label]
            }
            P {
                if {[llength $parts] != 3} {error "Invalid AIA preview record."}
                lappend previews [list [_decode [lindex $parts 1]] [_decode [lindex $parts 2]]]
            }
            default {error "Unsupported AIA helper record '$kind'."}
        }
    }
    if {!$gotHeader || ![dict exists $metadata chromatography.sample_count] ||
        [llength [dict get $columns T]] != 3} {
        error "Incomplete AIA/ANDI parser response."
    }
    return [dict create metadata $metadata warnings $warnings columns $columns previews $previews]
}

proc ::AcqAiaAndi::_preview {information path} {
    set md [dict get $information metadata]
    set info [dict create \
        "Format" "AIA/ANDI chromatography (NetCDF Classic)" \
        "Container" [dict get $md chromatography.netcdf_variant] \
        "File size (bytes)" [file size $path] \
        "Signal samples" [dict get $md chromatography.sample_count] \
        "Retention unit (source)" [dict get $md chromatography.retention_unit_original] \
        "Detector unit" [dict get $md chromatography.detector_unit] \
        "Sampling" [expr {[dict get $md chromatography.uniform_sampling] eq "Y" ? "uniform" : "nonuniform"}] \
        "Peak results" [dict get $md chromatography.peak_count]]
    foreach {key label} {
        instrument.detector Detector
        experimental.sample_name Sample
        experimental.title Experiment
        experimental.injection_timestamp {Injection time}
        experimental.method Method
        experimental.operator Operator
    } {
        if {[dict exists $md $key]} {dict set info $label [dict get $md $key]}
    }
    return $info
}

proc ::AcqAiaAndi::inspect {request} {
    set path [dict get $request source_path]
    if {[catch {set info [_helperCall $path inspect]} issue]} {
        return [dict create recognized 0 format aia.andi.chrom metadata {} \
            variables {} preview_rows {} warnings [list $issue] \
            preview_kind metadata preview_metadata [dict create Status "Unsupported/invalid AIA/ANDI-CHROM" Diagnostic $issue]]
    }
    return [dict create recognized 1 format aia.andi.chrom \
        metadata [dict get $info metadata] \
        variables {} preview_rows [dict get $info previews] \
        warnings [dict get $info warnings] \
        preview_kind metadata preview_metadata [_preview $info $path]]
}

proc ::AcqAiaAndi::_descriptor {id contract rel columns origin md} {
    set names {}; set units {}; set roles {}; set schema {}
    set columnIndex 0
    foreach col $columns {
        incr columnIndex
        set name [dict get $col name]
        set unit [dict get $col unit]
        set role [dict get $col role]
        lappend names $name
        lappend units $unit
        lappend roles $role
        set declaration [dict create variable_id $name canonical $name source_column $columnIndex \
            dtype [dict get $col dtype] semantic_role $role display_label [dict get $col label]]
        if {$unit ne ""} {dict set declaration unit $unit}
        if {$name eq "time_s" || $name eq "peak_retention_s"} {
            dict set declaration coordinate_role coordinate
            dict set declaration axis_kind explicit
        } elseif {$name eq "signal_value" || $name eq "time_min"} {
            dict set declaration coordinate_variable_ids time_s
            if {$name eq "time_min"} {dict set declaration coordinate_role auxiliary}
        }
        lappend schema $declaration
    }
    return [dict create dataset_id $id contract $contract \
        format csv path $rel \
        variables $names units $units semantic_roles $roles \
        variable_schema $schema structured_metadata $md \
        source "AIA/ANDI-CHROM NetCDF export" provenance $origin]
}

proc ::AcqAiaAndi::import {request} {
    set source [dict get $request source_path]
    set raw [dict get $request raw_path]
    set dir [dict get $request output_dir]
    set id [dict get $request dataset_id]
    set profile trace_and_peaks
    if {[dict exists $request config output_profile]} {
        set profile [dict get $request config output_profile]
    }
    if {$profile ni {trace_and_peaks trace_only complete}} {
        error "Unsupported AIA output profile '$profile'."
    }
    set traceId "${id}.trace"
    set peakId "${id}.peaks"
    set traceRel "${traceId}.csv"
    set peakRel "${peakId}.csv"
    set info [_helperCall $raw import [file join $dir $traceRel] [file join $dir $peakRel]]
    set md [dict get $info metadata]
    dict set md source.original_filename [file tail $source]
    set notes "AIA/ANDI-CHROM NetCDF Classic; untouched RAW retained by GX-TXT; physical values read directly from ordinate_values without smoothing, scaling, reprocessing or interpolation."
    set trace [_descriptor $traceId timeseries.table $traceRel [dict get $info columns T] $notes $md]
    set datasets [list $trace]
    set peaks [dict get $info columns K]
    if {[llength $peaks] && $profile ne "trace_only"} {
        set resultMd [dict merge $md [dict create chromatography.table_kind vendor_peak_results]]
        set p [_descriptor $peakId chromatography.aia.peaks $peakRel $peaks \
            "Original exporter peak integration results; no recalculation performed by GX-TXT importer." $resultMd]
        lappend datasets $p
    }
    if {$profile eq "complete"} {
        set preservedRel "${id}.cdf"
        file copy -- $raw [file join $dir $preservedRel]
        lappend datasets [dict create dataset_id $id contract chromatography.aia.raw \
            format netcdf path $preservedRel storage_kind binary \
            media_type application/x-netcdf variables {} units {} semantic_roles {} \
            source "AIA/ANDI-CHROM preserved NetCDF export" \
            provenance "Exact original CDF bytes copied from framework-owned RAW; no numerical interpretation in this binary Dataset." \
            structured_metadata $md]
    }
    return [dict create datasets $datasets]
}

proc ::AcqAiaAndi::datasetPreview {request} {
    if {[catch {set info [_helperCall [dict get $request dataset_path] inspect]} issue]} {
        return [dict create preview_kind metadata \
            preview_metadata [dict create Status "Unsupported CDF" Diagnostic $issue]]
    }
    return [dict create preview_kind metadata \
        preview_metadata [_preview $info [dict get $request dataset_path]]]
}
