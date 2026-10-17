# SPDX-License-Identifier: GPL-3.0-or-later
# GX-TXT Acquisition Handler API v1 adapter, not CORE code.
# Extraction boundary: portable/ is framework-independent; text_worker.py maps
# its results to the documented Dataset metadata schema. Never override GX commands.
namespace eval ::AcqTextDocument {
    variable helper [file normalize [file join [file dirname [info script]] text_worker.py]]
    variable serial 0
    variable jobs [dict create]
    variable wake
}

proc ::AcqTextDocument::_pause {token} {
    # Wait through the Tcl event loop; no direct Tk widget manipulation.
    after 15 [list set ::AcqTextDocument::wake($token) 1]
    vwait ::AcqTextDocument::wake($token)
    unset -nocomplain ::AcqTextDocument::wake($token)
}

proc ::AcqTextDocument::_arg {value} {
    return [binary encode base64 -maxlen 0 [encoding convertto utf-8 $value]]
}

proc ::AcqTextDocument::_setting {request key {default auto}} {
    if {[dict exists $request config $key]} {
        set value [string trim [dict get $request config $key]]
        if {$value ne ""} { return $value }
    }
    return $default
}

proc ::AcqTextDocument::_launch {request importMode} {
    variable helper
    variable serial
    variable jobs
    if {![file isfile $helper]} { error "Text import helper is missing: $helper" }
    set python [::GX::runtimeToolRequired python]
    set token "job[incr serial]"
    set marker ""
    set source [dict get $request source_path]
    set original [expr {[dict exists $request original_name] ? [dict get $request original_name] : [file tail $source]}]
    # -I isolates Python from the source/CWD/PYTHONPATH; -B disables bytecode.
    # Arbitrary arguments are base64 so Tcl pipeline redirection syntax cannot
    # reinterpret a filename such as ">report.py". No shell or eval is used.
    set cmd [list $python -I -B $helper]
    if {$importMode} {
        set source [dict get $request raw_path]
        set out [dict get $request output_dir]
        set marker [file join $out ".textdocument-cancel-[pid]-[clock clicks]-$token"]
        lappend cmd --import-source --output-dir-b64 [_arg $out] \
            "--dataset-id=[dict get $request dataset_id]" --cancel-file-b64 [_arg $marker]
    }
    lappend cmd --source-b64 [_arg $source] --original-name-b64 [_arg $original] \
        --encoding-b64 [_arg [_setting $request encoding]] \
        --language-b64 [_arg [_setting $request language]] \
        --import-as-b64 [_arg [_setting $request import_as]]
    set channel [open [linsert [concat $cmd [list 2>@1]] 0 |] r]
    fconfigure $channel -blocking 0 -buffering none -encoding utf-8 -translation lf
    dict set jobs $token [dict create channel $channel marker $marker buffer "" \
        header 0 complete 0 error "" fields {} metadata {} warnings {} progress {}]
    return $token
}

proc ::AcqTextDocument::_decode {value} {
    return [encoding convertfrom utf-8 [binary decode base64 -strict $value]]
}

proc ::AcqTextDocument::_record {job line} {
    if {![dict get $job header]} {
        if {$line ne "GXTEXTIMPORT1"} { error "text/code helper protocol mismatch: $line" }
        dict set job header 1
        return $job
    }
    set columns [split $line "\t"]
    set kind [lindex $columns 0]
    switch -- $kind {
        F - M {
            if {[llength $columns] != 3} { error "Malformed text/code helper metadata record." }
            set key [_decode [lindex $columns 1]]
            set value [_decode [lindex $columns 2]]
            if {$kind eq "M" && ![regexp {^[A-Za-z0-9_-]+([.][A-Za-z0-9_-]+)+$} $key]} {
                error "Invalid namespaced text metadata key."
            }
            dict set job [expr {$kind eq "M" ? "metadata" : "fields"}] $key $value
        }
        W - E {
            if {[llength $columns] != 2} { error "Malformed text/code helper diagnostic." }
            set value [_decode [lindex $columns 1]]
            if {$kind eq "W"} { dict lappend job warnings $value } else { dict set job error $value }
        }
        P {
            if {[llength $columns] != 4 || ![string is wideinteger -strict [lindex $columns 1]] ||
                ![string is wideinteger -strict [lindex $columns 2]]} { error "Malformed text progress record." }
            set stage [_decode [lindex $columns 3]]
            dict set job progress [dict create state running mode determinate \
                current [lindex $columns 1] total [lindex $columns 2] stage $stage \
                message "text/code import: $stage"]
        }
        OK {
            if {[llength $columns] != 1} { error "Malformed text completion marker." }
            dict set job complete 1
        }
        default { error "Unexpected output from the text/code helper: [string range $line 0 300]" }
    }
    return $job
}

proc ::AcqTextDocument::_poll {token} {
    variable jobs
    if {![dict exists $jobs $token]} { error "Unknown text/code import operation." }
    set job [dict get $jobs $token]
    set channel [dict get $job channel]
    if {[catch {
        dict append job buffer [read $channel]
        set buffer [dict get $job buffer]
        if {[string length $buffer] > 8388608} { error "text/code helper response exceeds the protocol limit." }
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
        set problem "text/code helper ended without a complete response. Python 3.10 or newer is required."
    }
    if {$problem ne ""} { return [dict create state failed error $problem] }
    return [dict create state completed result [dict create fields [dict get $job fields] \
        metadata [dict get $job metadata] warnings [dict get $job warnings]]]
}

proc ::AcqTextDocument::_wait {token {request {}}} {
    while {1} {
        if {[dict exists $request cancel_callback] && [dict get $request cancel_callback] ne "" &&
            [::GX::acquisitionHandlerInvokeCallback [dict get $request cancel_callback]]} {
            cancel [dict create state_token $token]
            error "text/code import cancelled."
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

proc ::AcqTextDocument::_preview {result} {
    set md [dict get $result metadata]
    set preview [dict create]
    foreach {key label} {
        source.original_filename Filename source.size_bytes {File size (bytes)}
        code.language_name Language code.language {Language ID}
        code.language_detection {Language detection} code.language_confidence {Detection confidence}
        text.encoding Encoding text.encoding_detection {Encoding detection}
        text.bom BOM text.validation_scope {Validation scope}
        text.line_count Lines text.character_count Characters
        text.newline_style {Line endings} text.has_final_newline {Final newline}
        code.language_candidates_json {Ambiguous candidates}
    } {
        if {[dict exists $md $key]} { dict set preview $label [dict get $md $key] }
    }
    if {[dict exists $result fields preview] && [dict get $result fields preview] ne ""} {
        dict set preview "Source preview (read-only, at most 80 lines / 12000 characters)" [dict get $result fields preview]
    }
    if {[llength [dict get $result warnings]]} { dict set preview Notes [join [dict get $result warnings] "\n"] }
    return $preview
}

proc ::AcqTextDocument::inspect {request} {
    if {[catch {set result [_wait [_launch $request 0]]} problem]} {
        return [dict create recognized 0 format "" metadata {} variables {} preview_rows {} \
            warnings [list $problem] preview_kind metadata \
            preview_metadata [dict create Status "Not an importable text/code source" Diagnostic $problem]]
    }
    # CORE supplies the current descriptor config to both Preview and import.
    return [dict create recognized 1 format [dict get $result fields format] \
        metadata [dict get $result metadata] variables {} preview_rows {} \
        warnings [dict get $result warnings] preview_kind metadata preview_metadata [_preview $result]]
}

proc ::AcqTextDocument::_datasetResult {request result} {
    set f [dict get $result fields]
    foreach key {format contract path media_type label} {
        if {![dict exists $f $key]} { error "Text import result is missing $key." }
    }
    set md [dict get $result metadata]
    set language [dict get $md code.language]
    set destination [_setting $request destination auto]
    if {$destination eq {auto} && $language eq {python}} {set destination session_script}
    if {$destination eq {auto} && $language in {matlab matlab-octave octave}} {error {Choose a destination explicitly: Session script with Language = octave confirms GNU Octave intent; Dataset preserves source without claiming MATLAB compatibility.}}
    if {$destination eq {session_script}} {
        if {$language ni {python octave}} {error {Session script destination requires Python or explicitly selected GNU Octave language. Choose Dataset for other source.}}
        return [dict create outcome registered_session_script language [expr {$language eq {python}?{Python}:{Octave}}] script_id [dict get $request dataset_id] name [dict get $f label] source_path [dict get $f path] provenance {Source imported through Text and Source Code Import; UTF-8 Registry snapshot; no execution.}]
    }
    set notes [join [dict get $result warnings] "\n"]
    # Text/code is a file-shaped Dataset, NOT a one-column numerical table.
    # Original encoding, BOM, tabs and line endings remain byte-for-byte intact.
    # CORE owns all registry, RAW, hash and structured-metadata transactions.
    return [dict create datasets [list [dict create dataset_id [dict get $request dataset_id] \
        contract [dict get $f contract] format [dict get $f format] path [dict get $f path] \
        storage_kind text media_type [dict get $f media_type] variables {} units {} semantic_roles {} \
        source "Text and source code: [dict get $f label]" notes $notes structured_metadata $md \
        provenance "Original text/code RAW bytes preserved without re-encoding or newline conversion; full-file text validation; language=[dict get $md code.language]; method=[dict get $md code.language_detection]; no code execution or syntax validation."]]]
}

proc ::AcqTextDocument::import {request} {
    return [_datasetResult $request [_wait [_launch $request 1] $request]]
}

proc ::AcqTextDocument::begin {request} { return [_launch $request 1] }

proc ::AcqTextDocument::step {request} {
    set result [_poll [dict get $request state_token]]
    if {[dict get $result state] eq "completed"} {
        dict set result result [_datasetResult $request [dict get $result result]]
    }
    if {[dict exists $result progress] && ![dict size [dict get $result progress]]} { dict unset result progress }
    return $result
}

proc ::AcqTextDocument::cancel {request} {
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

proc ::AcqTextDocument::datasetPreview {request} {
    set req [dict create source_path [dict get $request dataset_path]]
    set stored {}
    # Reuse the actual imported encoding/name; the canonical filename may be
    # renamed (e.g. Makefile or an extensionless script). Only the public Dataset
    # Metadata API is used. Never read or write metadata sidecars directly.
    if {[dict exists $request dataset_id] && [dict exists $request session_path]} {
        set session [dict get $request session_path]
        set stored [::GX::datasetMetadataRead $session [dict get $request dataset_id]]
        if {[dict exists $stored source.original_filename]} { dict set req original_name [dict get $stored source.original_filename] }
        if {[dict exists $stored text.decoder]} { dict set req config encoding [dict get $stored text.decoder] }
    }
    set result [_wait [_launch $req 0]]
    # Display persisted metadata as authoritative, not newly guessed statistics
    # from a bounded preview sample. Contents are always read from the Dataset.
    if {[dict size $stored]} {
        dict set result metadata $stored
        # A user may supply an additional/custom language label through the
        # metadata editor. Preview must not re-validate it against our catalog.
        # A new Session may preview a Dataset before its first Manifest save.
        # Session Inspection requires a persisted Manifest; descriptive notes
        # are optional in that transient state.
        set notes ""
        if {![catch {set record [::GX::sessionInspectionDataset [dict get $request dataset_id] $session]}] &&
            [dict exists $record notes]} { set notes [dict get $record notes] }
        dict set result warnings [expr {$notes ne "" ? [list $notes] : [list]}]
    }
    return [dict create preview_kind metadata preview_metadata [_preview $result]]
}
