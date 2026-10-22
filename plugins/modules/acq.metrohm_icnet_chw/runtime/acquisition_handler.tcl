# Metrohm IC Net CHW importer using the prebuilt native C worker.
# SPDX-License-Identifier: GPL-3.0-or-later
# Uses GX-TXT Acquisition Handler Plugin API v1 and framework-owned RAW snapshot.

namespace eval ::AcqMetrohmCHW {
    variable helper [file normalize [file join [file dirname [info script]] bin linux-x86_64 chw_worker]]
}

proc ::AcqMetrohmCHW::_decode {encoded} {
    return [encoding convertfrom utf-8 [binary decode base64 $encoded]]
}

proc ::AcqMetrohmCHW::_inspectFile {path {signalOutput ""} {peaksOutput ""} {originalFilename ""}} {
    variable helper
    if {![file isfile $path] || ![file readable $path]} {
        error "CHW source must be an accessible regular file."
    }
    if {$::tcl_platform(os) ne "Linux" || $::tcl_platform(machine) ni {x86_64 amd64}} {
        error "The prebuilt Metrohm CHW worker is unavailable for $::tcl_platform(os)/$::tcl_platform(machine)."
    }
    if {![file isfile $helper] || ![file executable $helper]} {
        error "The prebuilt native C CHW worker is missing or not executable. Install the matching complete importer package."
    }
    if {$originalFilename eq ""} { set originalFilename [file tail $path] }
    set cmd [list $helper --input $path --original-filename $originalFilename --output protocol --summary-peaks]
    if {$signalOutput ne ""} { lappend cmd --csv-output $signalOutput }
    if {$peaksOutput ne ""} { lappend cmd --peaks-output $peaksOutput }
    if {[catch {set output [exec {*}$cmd]} msg]} {
        error "Metrohm IC Net CHW inspection: [string trim $msg]"
    }
    set seen 0
    set metadata [dict create]
    set warnings [list]
    foreach raw [split $output "\n"] {
        set line [string trimright $raw "\r"]
        if {$line eq ""} continue
        if {!$seen} {
            if {$line ne "GXCHW1"} { error "Invalid CHW helper response protocol." }
            set seen 1
            continue
        }
        set fields [split $line "\t"]
        switch -- [lindex $fields 0] {
            M {
                if {[llength $fields] != 3} {error "Malformed CHW metadata record."}
                set key [_decode [lindex $fields 1]]
                set val [_decode [lindex $fields 2]]
                if {![regexp {^[[:alnum:]_-]+([.][[:alnum:]_-]+)+$} $key]} {
                    error "Invalid CHW metadata key."
                }
                dict set metadata $key $val
            }
            W {
                if {[llength $fields] != 2} {error "Malformed CHW warning record."}
                lappend warnings [_decode [lindex $fields 1]]
            }
            default {error "Unrecognized CHW helper record."}
        }
    }
    if {!$seen || ![dict exists $metadata chromatography.signal_decode_status]} {
        error "Incomplete CHW helper response."
    }
    set peakCount [dict get $metadata chromatography.integration_peak_count]
    if {![string is integer -strict $peakCount] || $peakCount < 0} { error "Invalid native CHW peak count." }
    return [dict create metadata $metadata warnings $warnings peak_count $peakCount]
}

proc ::AcqMetrohmCHW::_preview {structured peakCount fileSize} {
    set preview [dict create \
        "Format" "Metrohm IC Net CHW" \
        "Bytes" $fileSize \
        "Signal samples declared" [dict get $structured chromatography.declared_sample_count] \
        "Channel" [dict get $structured chromatography.signal_channel] \
        "Signal unit" [dict get $structured chromatography.signal_unit] \
        "Sample interval (s)" [dict get $structured chromatography.sample_interval_s] \
        "Integrated peaks" $peakCount \
        "Compression blocks" [dict get $structured chromatography.trace_block_count] \
        "Response trace" "DECODED (ADC samples preserved as integers)"]
    foreach {key title} {
        instrument.model Instrument
        instrument.software Software
        chromatography.method_filename Method
        chromatography.column_description Column
        chromatography.filename_date {Date in filename}
    } {
        if {[dict exists $structured $key]} {dict set preview $title [dict get $structured $key]}
    }
    return $preview
}

proc ::AcqMetrohmCHW::inspect {request} {
    set path [dict get $request source_path]
    if {[catch {set info [_inspectFile $path]} problem]} {
        return [dict create recognized 0 format metrohm.icnet.chw metadata {} \
            variables {} preview_rows {} warnings [list $problem] \
            preview_kind metadata preview_metadata [dict create Status "Unrecognized CHW container" Diagnostic $problem]]
    }
    set md [dict get $info metadata]
    return [dict create recognized 1 format metrohm.icnet.chw metadata $md \
        variables {} preview_rows {} warnings [dict get $info warnings] \
        preview_kind metadata preview_metadata [_preview $md [dict get $info peak_count] [file size $path]]]
}

proc ::AcqMetrohmCHW::import {request} {
    set source [dict get $request source_path]
    # Normal source batching is owned by CORE and invokes one acquisition per
    # selected file. Never silently ignore a grouped multi-file request.
    if {[dict exists $request raw_paths] && [llength [dict get $request raw_paths]] != 1} {
        error "CHW sources must be imported as independent rows in the normal Acquisition source batch."
    }
    set raw [dict get $request raw_path]
    set dir [dict get $request output_dir]
    set id [dict get $request dataset_id]
    # CORE owns the RAW snapshot even in trace-only mode.
    # Decode once while generating the canonical trace and metadata together.
    set profile complete
    if {[dict exists $request config output_profile]} {
        set profile [dict get $request config output_profile]
    }
    if {$profile ni {complete trace_and_peaks trace_only}} {
        error "Invalid CHW output profile: $profile"
    }
    set signalId "${id}.trace"
    set signalRel "${signalId}.csv"
    set peakId "${id}.peaks"
    set peakRel "${peakId}.csv"
    set peakOutput [expr {$profile eq "trace_only" ? "" : [file join $dir $peakRel]}]
    set info [_inspectFile $raw [file join $dir $signalRel] $peakOutput [file tail $source]]
    set md [dict get $info metadata]
    set rel "${id}.chw"
    set dst [file join $dir $rel]
    if {$profile eq "complete"} {file copy -- $raw $dst}
    set preserved [dict create \
        dataset_id $id contract chromatography.icnet.raw \
        format metrohm.icnet.chw path $rel \
        storage_kind binary media_type application/octet-stream \
        variables {} units {} semantic_roles {} \
        source "Metrohm IC Net CHW" \
        provenance "Original CHW bytes preserved from GX-TXT RAW snapshot. Numeric signal is independently decoded without modifying these bytes." \
        structured_metadata $md]
    set datasets [list]
    if {$profile eq "complete"} { lappend datasets $preserved }
    set dt [dict get $md chromatography.sample_interval_s]
    set unit [dict get $md chromatography.signal_unit]
    set signalMd [dict merge $md [dict create \
        chromatography.trace_origin "exact_CHW_integer_differential_decoder" \
        chromatography.trace_scientific_scale "ADC_counts_x_S_section_float32_coefficient" \
        chromatography.trace_time_origin "sample_index_zero" \
        chromatography.trace_dataset_id $signalId]]
    set signalSchema [list \
        [dict create variable_id time_s canonical time_s source_column 1 dtype float64 unit s semantic_role time coordinate_role coordinate axis_kind explicit display_label "Elapsed time (s)"] \
        [dict create variable_id time_min canonical time_min source_column 2 dtype float64 unit min semantic_role time coordinate_role auxiliary coordinate_variable_ids time_s display_label "Elapsed time (min)"] \
        [dict create variable_id signal_value canonical signal_value source_column 3 dtype float64 unit $unit semantic_role measured coordinate_variable_ids time_s display_label "[dict get $md chromatography.signal_channel] ($unit)"] \
        [dict create variable_id adc_count canonical adc_count source_column 4 dtype int32 unit 1 semantic_role raw_adc coordinate_variable_ids time_s display_label "Native ADC count"]]
    lappend datasets [dict create \
        dataset_id $signalId contract timeseries.table \
        format csv path $signalRel \
        variables {time_s time_min signal_value adc_count} \
        units [list s min $unit 1] \
        semantic_roles {time time measured raw_adc} \
        source "Metrohm IC Net CHW signal" \
        provenance "Native C reconstruction of source signed ADC differential runs; physical scale and sampling interval read from the CHW signal descriptor. No resampling or peak reintegration; CORE preserves original RAW bytes and hashes." \
        variable_schema $signalSchema structured_metadata $signalMd]
    set peakCount [dict get $info peak_count]
    if {$peakCount > 0 && $profile ne "trace_only"} {
        set peakMd [dict create \
            source.original_filename [file tail $source] \
            chromatography.format metrohm.icnet.chw \
            chromatography.peak_count $peakCount \
            chromatography.peak_position_basis "file_sample_index_zero_based" \
            chromatography.retention_time_quality "source_sample_index_times_native_interval" \
            chromatography.sample_interval_s [dict get $md chromatography.sample_interval_s]]
        set schema [list \
            [dict create variable_id peak_number canonical peak_number source_column 1 dtype int32 unit 1 semantic_role index] \
            [dict create variable_id start_point canonical start_point source_column 2 dtype int32 unit 1 semantic_role index] \
            [dict create variable_id apex_point canonical apex_point source_column 3 dtype int32 unit 1 semantic_role index] \
            [dict create variable_id end_point canonical end_point source_column 4 dtype int32 unit 1 semantic_role index] \
            [dict create variable_id approx_retention_min canonical approx_retention_min source_column 5 dtype float64 unit min semantic_role time] \
            [dict create variable_id component_label canonical component_label source_column 6 dtype string semantic_role label]]
        lappend datasets [dict create \
            dataset_id $peakId contract chromatography.icnet.peaks \
            format csv path $peakRel \
            variables {peak_number start_point apex_point end_point approx_retention_min component_label} \
            units {1 1 1 1 min 1} \
            semantic_roles {index index index index time label} \
            variable_schema $schema \
            source "Metrohm IC Net CHW integration records" \
            provenance "Original bounded peak-point records extracted from CHW D section; optional component labels from source U audit section. Retention is source sample index times native interval divided by60; historical package reference-export comparisons are separate from current source-implementation parity evidence." \
            structured_metadata $peakMd]
    }
    return [dict create datasets $datasets]
}

proc ::AcqMetrohmCHW::datasetPreview {request} {
    if {[catch {set info [_inspectFile [dict get $request dataset_path]]} problem]} {
        return [dict create preview_kind metadata preview_metadata [dict create Status "Unrecognized CHW" Diagnostic $problem]]
    }
    return [dict create preview_kind metadata \
        preview_metadata [_preview [dict get $info metadata] [dict get $info peak_count] [file size [dict get $request dataset_path]]]]
}
