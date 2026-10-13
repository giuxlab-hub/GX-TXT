# GX-TXT Acquisition Handler Plugin API v1 - PDF document importer
# SPDX-License-Identifier: GPL-3.0-or-later
#
# One source PDF becomes one opaque canonical document.pdf Dataset. The module
# validates content/structure and preserves the framework-owned RAW snapshot
# byte-for-byte. OCR, text extraction, rendering, repair and optimization are
# intentionally outside this acquisition module.

namespace eval ::AcqPdfDocument {
    variable inspectHelper [file normalize [file join [file dirname [info script]] pdf_inspect.py]]
}

proc ::AcqPdfDocument::_decodeUtf8B64 {payload} {
    return [encoding convertfrom utf-8 [binary decode base64 $payload]]
}

proc ::AcqPdfDocument::_python {} {
    return [::GX::runtimeToolRequired python]
}

proc ::AcqPdfDocument::_inspectStructured {path} {
    variable inspectHelper
    if {![file isfile $path]} { error "PDF source is not a regular file." }
    if {![file readable $path]} { error "PDF source is not readable." }
    if {![file isfile $inspectHelper]} { error "PDF inspection helper is missing." }

    set cmd [list [::AcqPdfDocument::_python] $inspectHelper --input $path]
    if {[catch {set output [exec {*}$cmd 2>@1]} err]} {
        set err [string trim $err]
        if {$err eq ""} { set err "PDF inspection failed." }
        error $err
    }

    set protocolSeen 0
    set metadata [dict create]
    set warnings [list]
    foreach rawLine [split $output "\n"] {
        set line [string trimright $rawLine "\r"]
        if {$line eq ""} continue
        if {!$protocolSeen} {
            if {$line ne "GXPDF1"} { error "PDF inspection helper returned an unsupported protocol." }
            set protocolSeen 1
            continue
        }
        set fields [split $line "\t"]
        set kind [lindex $fields 0]
        if {$kind eq "M" && [llength $fields] == 3} {
            set key [::AcqPdfDocument::_decodeUtf8B64 [lindex $fields 1]]
            set value [::AcqPdfDocument::_decodeUtf8B64 [lindex $fields 2]]
            if {![regexp {^[[:alnum:]_-]+([.][[:alnum:]_-]+)+$} $key]} {
                error "PDF inspection helper returned an invalid metadata key."
            }
            dict set metadata $key $value
        } elseif {$kind eq "W" && [llength $fields] == 2} {
            lappend warnings [::AcqPdfDocument::_decodeUtf8B64 [lindex $fields 1]]
        } else {
            error "PDF inspection helper returned a malformed protocol record."
        }
    }
    if {!$protocolSeen} { error "PDF inspection helper returned no protocol data." }
    foreach key {document.format document.page_count} {
        if {![dict exists $metadata $key]} { error "PDF inspection did not provide mandatory field '$key'." }
    }
    if {[dict get $metadata document.format] ne "PDF"} { error "PDF format identity was not established." }
    set pages [dict get $metadata document.page_count]
    if {![string is integer -strict $pages] || $pages < 1} { error "PDF page count is invalid." }
    return [dict create metadata $metadata warnings $warnings]
}

proc ::AcqPdfDocument::_previewMetadata {metadata fileSize} {
    set preview [dict create \
        "Format" "PDF" \
        "Pages" [dict get $metadata document.page_count] \
        "PDF version" [expr {[dict exists $metadata pdf.version] ? [dict get $metadata pdf.version] : "Unavailable"}] \
        "Encrypted" [expr {[dict exists $metadata pdf.encrypted] ? [dict get $metadata pdf.encrypted] : "Unavailable"}] \
        "File size" "$fileSize bytes"]
    foreach {key label} {
        pdf.title Title
        pdf.author Author
        pdf.subject Subject
        pdf.creator Creator
        pdf.producer Producer
        pdf.creation_date {Creation date}
        pdf.modification_date {Modification date}
    } {
        if {[dict exists $metadata $key]} { dict set preview $label [dict get $metadata $key] }
    }
    return $preview
}

proc ::AcqPdfDocument::_sha256 {path} {
    if {![llength [info commands ::GX::sha256File]]} {
        error "GX-TXT SHA-256 service is unavailable."
    }
    return [::GX::sha256File $path]
}

proc ::AcqPdfDocument::_copyExact {src dst} {
    set in [open $src r]
    set out [open $dst w]
    fconfigure $in -translation binary -encoding binary
    fconfigure $out -translation binary -encoding binary
    try {
        fcopy $in $out
    } finally {
        close $in
        close $out
    }
}

proc ::AcqPdfDocument::inspect {request} {
    set source [dict get $request source_path]
    if {![file isfile $source]} {
        return [dict create recognized 0 format pdf metadata {} variables {} preview_rows {} \
            warnings [list "Source file not found or not a regular file."] preview_kind metadata \
            preview_metadata [dict create Status "Missing source file"]]
    }
    if {![file readable $source]} {
        return [dict create recognized 0 format pdf metadata {} variables {} preview_rows {} \
            warnings [list "Source file is not readable."] preview_kind metadata \
            preview_metadata [dict create Status "Unreadable source file"]]
    }
    if {[catch {set r [::AcqPdfDocument::_inspectStructured $source]} err]} {
        return [dict create recognized 0 format pdf metadata {} variables {} preview_rows {} \
            warnings [list $err] preview_kind metadata \
            preview_metadata [dict create Status "Not a valid importable PDF" Diagnostic $err]]
    }
    set metadata [dict get $r metadata]
    set warnings [dict get $r warnings]
    return [dict create recognized 1 format pdf metadata $metadata variables {} preview_rows {} \
        warnings $warnings preview_kind metadata \
        preview_metadata [::AcqPdfDocument::_previewMetadata $metadata [file size $source]]]
}

proc ::AcqPdfDocument::import {request} {
    set source [dict get $request source_path]
    set raw [dict get $request raw_path]
    set outDir [dict get $request output_dir]
    set id [dict get $request dataset_id]

    # Revalidate the exact RAW snapshot that will anchor Dataset provenance.
    set inspected [::AcqPdfDocument::_inspectStructured $raw]
    set structured [dict get $inspected metadata]

    # Detect a source that changed between selection and preservation. The two
    # source reads bracket the RAW hash so a stable source must match both.
    set sourceHash1 [::AcqPdfDocument::_sha256 $source]
    set rawHash [::AcqPdfDocument::_sha256 $raw]
    set sourceHash2 [::AcqPdfDocument::_sha256 $source]
    if {$sourceHash1 ne $sourceHash2 || $sourceHash1 ne $rawHash} {
        error "Source changed during import / integrity verification failed."
    }

    set rel "${id}.pdf"
    set dst [file join $outDir $rel]
    ::AcqPdfDocument::_copyExact $raw $dst
    set canonicalHash [::AcqPdfDocument::_sha256 $dst]
    if {$canonicalHash ne $rawHash} {
        catch {file delete -force -- $dst}
        error "Preserved PDF payload failed byte-for-byte integrity verification."
    }

    # source.sha256 is intentionally not duplicated in Dataset Metadata because
    # Acquisition Handler API v1 already persists authoritative source_sha256
    # and canonical_sha256 provenance fields in the Dataset Registry.
    dict set structured source.filename [file tail $source]
    dict set structured source.size_bytes [file size $raw]

    set encrypted [expr {[dict exists $structured pdf.encrypted] ? [dict get $structured pdf.encrypted] : "unknown"}]
    set pages [dict get $structured document.page_count]
    set version [expr {[dict exists $structured pdf.version] ? [dict get $structured pdf.version] : "unknown"}]
    set provenance "verified PDF document; PDF $version; pages=$pages; encrypted=$encrypted; original bytes preserved; OCR/rendering/text extraction not performed"

    return [dict create datasets [list [dict create \
        dataset_id $id \
        contract document.pdf \
        format pdf \
        path $rel \
        storage_kind binary \
        media_type application/pdf \
        variables {} \
        units {} \
        semantic_roles {} \
        source "PDF document" \
        provenance $provenance \
        structured_metadata $structured]]]
}

proc ::AcqPdfDocument::datasetPreview {request} {
    set path [dict get $request dataset_path]
    if {[catch {set r [::AcqPdfDocument::_inspectStructured $path]} err]} {
        return [dict create preview_kind metadata preview_metadata [dict create Status "PDF preview metadata unavailable" Diagnostic $err]]
    }
    set md [dict get $r metadata]
    return [dict create preview_kind metadata preview_metadata [::AcqPdfDocument::_previewMetadata $md [file size $path]]]
}
