# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::AcqImageBinary {
    variable metadataHelper [file normalize [file join [file dirname [info script]] image_metadata.py]]
}

proc ::AcqImageBinary::detect_format {path} {
    if {![file exists $path] || ![file isfile $path]} { return "" }
    set fd [open $path r]
    fconfigure $fd -translation binary -encoding binary
    set head [read $fd 8]
    close $fd

    if {[string length $head] < 2} { return "" }

    # PNG: 89 50 4E 47 0D 0A 1A 0A
    if {[string range $head 0 7] eq [binary format H* 89504e470d0a1a0a]} {
        return [list png image/png .png]
    }
    # JPEG: FF D8 FF
    if {[string range $head 0 2] eq [binary format H* ffd8ff]} {
        return [list jpeg image/jpeg .jpg]
    }
    # BMP: 42 4D (BM)
    if {[string range $head 0 1] eq "BM"} {
        return [list bmp image/bmp .bmp]
    }
    # TIFF: II* (49 49 2a 00) or MM* (4d 4d 00 2a)
    if {[string range $head 0 3] eq [binary format H* 49492a00] ||
        [string range $head 0 3] eq [binary format H* 4d4d002a]} {
        return [list tiff image/tiff .tif]
    }
    return ""
}

proc ::AcqImageBinary::basic_metadata {source_path raw_path format media_type} {
    set metadata [dict create \
        source.original_filename [file tail $source_path] \
        source.file_size_bytes [file size $raw_path] \
        image.format $format \
        image.media_type $media_type]
    set ext [string tolower [file extension $source_path]]
    if {$ext ne ""} { dict set metadata source.original_extension $ext }
    return $metadata
}

proc ::AcqImageBinary::_decode_utf8_b64 {payload} {
    return [encoding convertfrom utf-8 [binary decode base64 $payload]]
}

# Read extended image/container metadata with the module-owned Pillow helper.
# Failure is deliberately soft: signature validation and opaque binary import do
# not depend on Pillow. The caller receives basic metadata plus a preview warning.
proc ::AcqImageBinary::extended_metadata {path} {
    variable metadataHelper
    set warnings [list]
    set metadata [dict create]

    if {![file isfile $metadataHelper]} {
        return [dict create metadata $metadata warnings [list "Extended image metadata helper is missing; only basic file metadata is available."]]
    }
    if {[catch {set python [::GX::runtimeToolRequired python]}]} {
        return [dict create metadata $metadata warnings [list "Python was not found; only basic image metadata is available."]]
    }

    set cmd [list $python $metadataHelper --input $path]
    if {[catch {set output [exec {*}$cmd]} err]} {
        return [dict create metadata $metadata warnings [list "Extended image metadata could not be read: $err"]]
    }

    set protocolSeen 0
    foreach rawLine [split $output "\n"] {
        set line [string trimright $rawLine "\r"]
        if {$line eq ""} continue
        if {!$protocolSeen} {
            if {$line ne "GXIMGMD1"} {
                lappend warnings "Extended image metadata helper returned an unsupported protocol."
                break
            }
            set protocolSeen 1
            continue
        }
        set fields [split $line "\t"]
        set kind [lindex $fields 0]
        if {$kind eq "M" && [llength $fields] == 3} {
            if {[catch {
                set key [_decode_utf8_b64 [lindex $fields 1]]
                set value [_decode_utf8_b64 [lindex $fields 2]]
            } decodeErr]} {
                lappend warnings "Extended image metadata contained an invalid encoded field: $decodeErr"
                continue
            }
            if {![regexp {^[[:alnum:]_-]+([.][[:alnum:]_-]+)+$} $key]} {
                lappend warnings "Extended image metadata contained an invalid key and it was ignored."
                continue
            }
            dict set metadata $key $value
        } elseif {$kind eq "W" && [llength $fields] == 2} {
            if {![catch {set warning [_decode_utf8_b64 [lindex $fields 1]]}]} {
                lappend warnings $warning
            }
        }
    }
    if {!$protocolSeen && ![llength $warnings]} {
        lappend warnings "Extended image metadata helper returned no protocol data."
    }
    return [dict create metadata $metadata warnings $warnings]
}

proc ::AcqImageBinary::preview_metadata {structured format media_type file_size} {
    set preview [dict create \
        "Format" [string toupper $format] \
        "Media Type" $media_type \
        "File Size" "$file_size bytes"]
    foreach {key label suffix} {
        image.width_px "Width" " px"
        image.height_px "Height" " px"
        image.mode "Color mode" ""
        image.frame_count "Frames" ""
        image.camera_make "Camera make" ""
        image.camera_model "Camera model" ""
        image.datetime_original "Captured" ""
        image.orientation "Orientation" ""
    } {
        if {[dict exists $structured $key]} {
            dict set preview $label "[dict get $structured $key]$suffix"
        }
    }
    dict set preview "Structured metadata fields" [dict size $structured]
    return $preview
}

proc ::AcqImageBinary::inspect {request} {
    set source [dict get $request source_path]
    set file_size [file size $source]

    set format_info [detect_format $source]
    if {$format_info eq ""} {
        return [dict create recognized 0]
    }

    lassign $format_info format media_type canon_ext

    set ext [string tolower [file extension $source]]
    set warnings [list]
    if {$ext ne "" && $ext ne $canon_ext} {
        # Tolerate common variants like .jpeg vs .jpg and .tiff vs .tif.
        if {!(($canon_ext eq ".jpg" && $ext eq ".jpeg") || ($canon_ext eq ".tif" && $ext eq ".tiff"))} {
            lappend warnings "File extension '$ext' does not match detected content ($format). Extension was used as a hint, content is authoritative."
        }
    }

    set structured [basic_metadata $source $source $format $media_type]
    set extended [extended_metadata $source]
    set structured [dict merge $structured [dict get $extended metadata]]
    set warnings [concat $warnings [dict get $extended warnings]]
    set preview [preview_metadata $structured $format $media_type $file_size]

    return [dict create \
        recognized 1 \
        format $format \
        metadata $preview \
        variables [list] \
        warnings $warnings \
        preview_kind metadata \
        preview_metadata $preview]
}

proc ::AcqImageBinary::import {request} {
    set raw_path [dict get $request raw_path]
    set source_path [dict get $request source_path]
    set outdir [dict get $request output_dir]
    set id [dict get $request dataset_id]

    # Re-verify magic number from framework-owned raw_path.
    set format_info [detect_format $raw_path]
    if {$format_info eq ""} {
        error "acq.image_binary: Invalid image format during import verification. Security or corruption issue suspected."
    }
    lassign $format_info format media_type canon_ext

    set rel "${id}${canon_ext}"
    set dst [file join $outdir $rel]
    file copy -force -- $raw_path $dst

    # Metadata is extracted from the exact framework-owned RAW snapshot that is
    # being registered, not from source_path, so metadata and canonical bytes
    # share the same provenance anchor.
    set structured [basic_metadata $source_path $raw_path $format $media_type]
    set extended [extended_metadata $raw_path]
    set structured [dict merge $structured [dict get $extended metadata]]

    return [dict create datasets [list [dict create \
        dataset_id $id \
        contract image.raster \
        format $format \
        path $rel \
        storage_kind binary \
        media_type $media_type \
        variables {} \
        units {} \
        semantic_roles {} \
        source "Image File" \
        provenance "Acquired as opaque binary image; structured container metadata read without intentional pixel decoding" \
        structured_metadata $structured]]]
}
