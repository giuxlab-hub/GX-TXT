# SPDX-License-Identifier: GPL-3.0-or-later
# GX-TXT Acquisition Handler API v1 adapter, not CORE code.
# Extraction boundary: move portable/ as a unit; replace only _launch if CORE
# later exposes geometry inspection/preservation. Never override GX commands.
namespace eval ::AcqGeometry3D {
    variable helper [file normalize [file join [file dirname [info script]] geometry_worker.py]]
    variable serial 0
    variable jobs [dict create]
    variable wake
}

proc ::AcqGeometry3D::_pause {token} {
    # Wait through the Tcl event loop; no direct Tk widget manipulation.
    after 15 [list set ::AcqGeometry3D::wake($token) 1]
    vwait ::AcqGeometry3D::wake($token)
    unset -nocomplain ::AcqGeometry3D::wake($token)
}

proc ::AcqGeometry3D::_launch {request importMode} {
    variable helper
    variable serial
    variable jobs
    if {![file isfile $helper]} { error "3D import helper is missing: $helper" }
    set python [::GX::runtimeToolRequired python]
    set token "job[incr serial]"
    set marker ""
    # -B avoids writing Python bytecode into the installed plugin directory.
    set cmd [list $python -B $helper]
    if {$importMode} {
        set out [dict get $request output_dir]
        set marker [file join $out ".geometry3d-cancel-[pid]-[clock clicks]-$token"]
        lappend cmd --import-raw [dict get $request raw_path] --output-dir $out \
            --dataset-id [dict get $request dataset_id] \
            --original-name [file tail [dict get $request source_path]] --cancel-file $marker
    } else {
        lappend cmd --inspect [dict get $request source_path]
    }
    # A Tcl list pipeline, never a shell command assembled from a filename.
    set channel [open [linsert [concat $cmd [list 2>@1]] 0 |] r]
    fconfigure $channel -blocking 0 -buffering none -encoding utf-8 -translation lf
    dict set jobs $token [dict create channel $channel marker $marker buffer "" \
        header 0 complete 0 error "" fields {} metadata {} warnings {} progress {}]
    return $token
}

proc ::AcqGeometry3D::_decode {value} {
    return [encoding convertfrom utf-8 [binary decode base64 -strict $value]]
}

proc ::AcqGeometry3D::_record {job line} {
    if {![dict get $job header]} {
        if {$line ne "GX3DIMPORT1"} { error "3D helper protocol mismatch: $line" }
        dict set job header 1
        return $job
    }
    set columns [split $line "\t"]
    set kind [lindex $columns 0]
    switch -- $kind {
        F - M {
            if {[llength $columns] != 3} { error "Malformed 3D helper metadata record." }
            set key [_decode [lindex $columns 1]]
            set value [_decode [lindex $columns 2]]
            if {$kind eq "M" && ![regexp {^[A-Za-z0-9_-]+([.][A-Za-z0-9_-]+)+$} $key]} {
                error "Invalid namespaced geometry metadata key."
            }
            dict set job [expr {$kind eq "M" ? "metadata" : "fields"}] $key $value
        }
        W - E {
            if {[llength $columns] != 2} { error "Malformed 3D helper diagnostic." }
            set value [_decode [lindex $columns 1]]
            if {$kind eq "W"} { dict lappend job warnings $value } else { dict set job error $value }
        }
        P {
            if {[llength $columns] != 4 || ![string is wideinteger -strict [lindex $columns 1]] ||
                ![string is wideinteger -strict [lindex $columns 2]]} { error "Malformed geometry progress record." }
            set stage [_decode [lindex $columns 3]]
            dict set job progress [dict create state running mode determinate \
                current [lindex $columns 1] total [lindex $columns 2] stage $stage \
                message "3D import: $stage"]
        }
        OK {
            if {[llength $columns] != 1} { error "Malformed geometry completion marker." }
            dict set job complete 1
        }
        default { error "Unexpected output from the 3D helper: [string range $line 0 300]" }
    }
    return $job
}

proc ::AcqGeometry3D::_poll {token} {
    variable jobs
    if {![dict exists $jobs $token]} { error "Unknown 3D import operation." }
    set job [dict get $jobs $token]
    set channel [dict get $job channel]
    if {[catch {
        dict append job buffer [read $channel]
        set buffer [dict get $job buffer]
        if {[string length $buffer] > 8388608} { error "3D helper response exceeds the protocol limit." }
        while {[set nl [string first "\n" $buffer]] >= 0} {
            set line [string trimright [string range $buffer 0 [expr {$nl-1}]] "\r"]
            set buffer [string range $buffer [expr {$nl+1}] end]
            if {$line ne ""} { set job [_record $job $line] }
        }
        dict set job buffer $buffer
    } problem]} {
        # Retain the channel until EOF, so the framework cannot remove staging
        # while a worker still owns an open destination (important on Windows).
        dict set job error $problem
        set marker [dict get $job marker]
        if {$marker ne ""} { catch {set f [open $marker w]; close $f} }
    }
    dict set jobs $token $job
    if {![eof $channel]} {
        set progress [dict get $job progress]
        dict set jobs $token progress {}
        return [dict create state running state_token $token progress $progress]
    }
    fconfigure $channel -blocking 1
    set closeFailed [catch {close $channel} closeError]
    set marker [dict get $job marker]
    if {$marker ne ""} { catch {file delete -- $marker} }
    dict unset jobs $token
    set problem [dict get $job error]
    if {$problem eq "" && $closeFailed} { set problem $closeError }
    if {$problem eq "" && (![dict get $job complete] || [dict get $job buffer] ne "")} {
        set problem "3D helper ended without a complete response. Python 3.10 or newer is required."
    }
    if {$problem ne ""} { return [dict create state failed error $problem] }
    return [dict create state completed result [dict create fields [dict get $job fields] \
        metadata [dict get $job metadata] warnings [dict get $job warnings]]]
}

proc ::AcqGeometry3D::_wait {token {request {}}} {
    while {1} {
        if {[dict exists $request cancel_callback] && [dict get $request cancel_callback] ne "" &&
            [::GX::acquisitionHandlerInvokeCallback [dict get $request cancel_callback]]} {
            cancel [dict create state_token $token]
            error "3D import cancelled."
        }
        set state [_poll $token]
        if {[dict exists $state progress] && [dict size [dict get $state progress]] &&
            [dict exists $request progress_callback] && [dict get $request progress_callback] ne ""} {
            ::GX::acquisitionHandlerInvokeCallback [dict get $request progress_callback] [dict get $state progress]
        }
        switch -- [dict get $state state] {
            completed { return [dict get $state result] }
            failed { error [dict get $state error] }
        }
        _pause $token
    }
}

proc ::AcqGeometry3D::_preview {result} {
    set md [dict get $result metadata]
    set preview [dict create]
    foreach {key label} {
        geometry.format Format source.original_filename Filename source.size_bytes {File size (bytes)}
        geometry.encoding Encoding geometry.validation_level {Checks performed}
        geometry.triangle_count Triangles geometry.vertex_count Vertices geometry.face_count Faces
        geometry.cell_count Cells geometry.counts_scope {Count scope} geometry.units_status {Coordinate units}
        step.schemas {STEP schemas} vtu.piece_count {VTU pieces} vtu.compressor {VTU compressor}
        vtu.array_summary {VTU arrays} vtp.piece_count {VTP pieces}
        vtp.array_summary {VTP arrays} vti.piece_count {VTI pieces}
        vti.origin {VTI origin} vti.spacing {VTI spacing} vti.wholeextent {VTI extent}
        vti.array_summary {VTI arrays} obj.material_library_references {External material references}
    } {
        if {[dict exists $md $key]} { dict set preview $label [dict get $md $key] }
    }
    if {[llength [dict get $result warnings]]} {
        dict set preview Notes [join [dict get $result warnings] "\n"]
    }
    return $preview
}

proc ::AcqGeometry3D::inspect {request} {
    if {[catch {set result [_wait [_launch $request 0]]} problem]} {
        return [dict create recognized 0 format "" metadata {} variables {} preview_rows {} \
            warnings [list $problem] preview_kind metadata \
            preview_metadata [dict create Status "Not an importable 3D source" Diagnostic $problem]]
    }
    return [dict create recognized 1 format [dict get $result fields format] \
        metadata [dict get $result metadata] variables {} preview_rows {} \
        warnings [dict get $result warnings] preview_kind metadata preview_metadata [_preview $result]]
}

proc ::AcqGeometry3D::_datasetResult {request result} {
    set f [dict get $result fields]
    foreach key {format contract path media_type label} {
        if {![dict exists $f $key]} { error "3D import result is missing $key." }
    }
    set md [dict get $result metadata]
    set notes [join [dict get $result warnings] "\n"]
    # CORE owns registration, RAW/canonical hashes, metadata validation, commit
    # and rollback. Opaque geometry has no fabricated tabular variables.
    return [dict create datasets [list [dict create dataset_id [dict get $request dataset_id] \
        contract [dict get $f contract] format [dict get $f format] path [dict get $f path] \
        storage_kind binary media_type [dict get $f media_type] variables {} units {} semantic_roles {} \
        source [dict get $f label] notes $notes structured_metadata $md \
        provenance "Original 3D RAW bytes preserved without conversion; checks=[dict get $md geometry.validation_level]; no tessellation, mesh repair, coordinate conversion or numeric table extraction."]]]
}

proc ::AcqGeometry3D::import {request} {
    return [_datasetResult $request [_wait [_launch $request 1] $request]]
}

proc ::AcqGeometry3D::begin {request} { return [_launch $request 1] }

proc ::AcqGeometry3D::step {request} {
    set result [_poll [dict get $request state_token]]
    if {[dict get $result state] eq "completed"} {
        dict set result result [_datasetResult $request [dict get $result result]]
    }
    # The Progress API expects a real progress dict, not an empty placeholder.
    if {[dict exists $result progress] && ![dict size [dict get $result progress]]} { dict unset result progress }
    return $result
}

proc ::AcqGeometry3D::cancel {request} {
    variable jobs
    set token [dict get $request state_token]
    if {![dict exists $jobs $token]} { return }
    set marker [dict get $jobs $token marker]
    if {$marker ne ""} { set f [open $marker w]; close $f }
    while {[dict exists $jobs $token]} {
        _poll $token
        if {[dict exists $jobs $token]} { _pause $token }
    }
}

proc ::AcqGeometry3D::datasetPreview {request} {
    set r [inspect [dict create source_path [dict get $request dataset_path]]]
    return [dict create preview_kind metadata preview_metadata [dict get $r preview_metadata] \
        text [join [dict get $r warnings] "\n"]]
}
