# GX-TXT Acquisition Handler Plugin API v1 - generic audio source importer
# SPDX-License-Identifier: GPL-3.0-or-later
#
# The importer preserves source bytes exactly and uses the public CORE Audio
# Decode API only for probing. Decoding to numeric sample variables remains a
# downstream analysis operation.

namespace eval ::AcqAudio {}

proc ::AcqAudio::rawCandidate {path} {
    set ext [string tolower [file extension [file tail $path]]]
    return [expr {$ext in {.pcm .raw}}]
}

proc ::AcqAudio::cfg {request key {default ""}} {
    if {![dict exists $request config]} { return $default }
    set c [dict get $request config]
    if {[dict exists $c $key]} { return [string trim [dict get $c $key]] }
    return $default
}

proc ::AcqAudio::streamIndexFromRequest {request} {
    set value [::AcqAudio::cfg $request audio_stream_index ""]
    if {$value eq ""} { return "" }
    if {![string is integer -strict $value] || $value < 0} {
        error "Audio stream index must be blank or an integer >= 0."
    }
    return $value
}

proc ::AcqAudio::rawHintsFromRequest {request} {
    set fmt [string tolower [::AcqAudio::cfg $request raw_pcm_input_format none]]
    set rate [::AcqAudio::cfg $request raw_pcm_sample_rate 0]
    set channels [::AcqAudio::cfg $request raw_pcm_channels 0]
    if {$fmt eq "none" || $fmt eq ""} {
        error "Raw PCM import requires an explicit Raw PCM sample format."
    }
    if {![string is integer -strict $rate] || $rate < 1} {
        error "Raw PCM import requires a sample rate >= 1 Hz."
    }
    if {![string is integer -strict $channels] || $channels < 1} {
        error "Raw PCM import requires a channel count >= 1."
    }
    return [dict create input_format $fmt sample_rate $rate channels $channels]
}

proc ::AcqAudio::probeSelected {path {streamIndex ""} {hints {}}} {
    if {[dict size $hints]} {
        if {$streamIndex eq ""} { return [::GX::audioProbe $path $hints] }
        return [::GX::audioProbe $path $streamIndex $hints]
    }
    if {$streamIndex eq ""} { return [::GX::audioProbe $path] }
    return [::GX::audioProbe $path $streamIndex]
}

proc ::AcqAudio::nonempty {d key {default ""}} {
    if {[dict exists $d $key] && [string trim [dict get $d $key]] ne ""} {
        return [dict get $d $key]
    }
    return $default
}

proc ::AcqAudio::tagValueNoCase {tags wanted} {
    foreach key [dict keys $tags] {
        if {[string equal -nocase $key $wanted]} { return [dict get $tags $key] }
    }
    return ""
}

proc ::AcqAudio::metadataTagKey {scope original} {
    set clean [string tolower [string trim $original]]
    regsub -all {[^[:alnum:]_-]+} $clean _ clean
    set clean [string trim $clean _]
    if {$clean eq ""} { set clean tag }
    return "tags.${scope}.${clean}"
}

proc ::AcqAudio::addRawTags {metadataVar scope tags} {
    upvar 1 $metadataVar metadata
    foreach original [dict keys $tags] {
        set key [::AcqAudio::metadataTagKey $scope $original]
        if {[dict exists $metadata $key]} {
            set crc [format %08x [zlib crc32 [encoding convertto utf-8 $original]]]
            set key "${key}_${crc}"
        }
        dict set metadata $key [dict get $tags $original]
    }
}

proc ::AcqAudio::firstTag {streamTags containerTags names} {
    foreach name $names {
        set v [::AcqAudio::tagValueNoCase $streamTags $name]
        if {$v ne ""} { return $v }
        set v [::AcqAudio::tagValueNoCase $containerTags $name]
        if {$v ne ""} { return $v }
    }
    return ""
}

proc ::AcqAudio::buildStructuredMetadata {sourcePath bytesPath probe isRaw} {
    set metadata [dict create]
    set original [file tail $sourcePath]
    set ext [string tolower [string trimleft [file extension $original] .]]
    dict set metadata source.original_filename $original
    if {$ext ne ""} { dict set metadata source.extension $ext }
    dict set metadata source.byte_size [file size $bytesPath]

    foreach {probeKey metadataKey} {
        container_format audio.container
        codec_name audio.codec
        sample_rate audio.sample_rate_hz
        channels audio.channels
        channel_layout audio.channel_layout
        sample_fmt audio.sample_format
        bits_per_sample audio.bits_per_sample
        bits_per_raw_sample audio.bits_per_raw_sample
        duration audio.stream_duration_s
        container_duration audio.duration_s
        nb_frames audio.frame_count
        selected_stream_index audio.selected_stream_index
        audio_stream_count audio.stream_count
    } {
        if {[dict exists $probe $probeKey] && [string trim [dict get $probe $probeKey]] ne ""} {
            dict set metadata $metadataKey [dict get $probe $probeKey]
        }
    }

    dict set metadata processing.audio_probe_api_version [::AcqAudio::nonempty $probe api_version 1]
    dict set metadata processing.audio_probe_backend [::AcqAudio::nonempty $probe backend ffmpeg]
    foreach {probeKey metadataKey} {
        ffmpeg_version processing.ffmpeg_version
        ffprobe_version processing.ffprobe_version
    } {
        if {[dict exists $probe $probeKey] && [string trim [dict get $probe $probeKey]] ne ""} {
            dict set metadata $metadataKey [dict get $probe $probeKey]
        }
    }

    if {$isRaw} {
        dict set metadata audio.raw_pcm 1
        if {[dict exists $probe input_hints]} {
            set hints [dict get $probe input_hints]
            foreach {hintKey metadataKey} {
                input_format audio.raw_input_format
                sample_rate audio.raw_sample_rate_hz
                channels audio.raw_channels
            } {
                if {[dict exists $hints $hintKey]} { dict set metadata $metadataKey [dict get $hints $hintKey] }
            }
        }
    } else {
        dict set metadata audio.raw_pcm 0
    }

    set containerTags [expr {[dict exists $probe container_tags] ? [dict get $probe container_tags] : [dict create]}]
    set streamTags [expr {[dict exists $probe stream_tags] ? [dict get $probe stream_tags] : [dict create]}]
    ::AcqAudio::addRawTags metadata container $containerTags
    ::AcqAudio::addRawTags metadata stream $streamTags

    foreach {metadataKey names} {
        audio.title {title}
        audio.artist {artist performer}
        audio.album {album}
        audio.album_artist {album_artist albumartist}
        audio.genre {genre}
        audio.date {date year}
        audio.comment {comment description}
        audio.encoder {encoder encoded_by}
        audio.language {language}
        audio.track {track tracknumber}
        audio.disc {disc discnumber}
        audio.copyright {copyright}
    } {
        set value [::AcqAudio::firstTag $streamTags $containerTags $names]
        if {$value ne ""} { dict set metadata $metadataKey $value }
    }
    return $metadata
}

proc ::AcqAudio::previewMetadata {probe {rawNote ""}} {
    set md [dict create]
    if {$rawNote ne ""} { dict set md "Input" $rawNote }
    foreach {key label suffix} {
        container_format "Container" ""
        codec_name "Codec" ""
        sample_rate "Sample rate" " Hz"
        channels "Channels" ""
        channel_layout "Channel layout" ""
        sample_fmt "Sample format" ""
        bits_per_raw_sample "Raw bit depth" " bit"
        bits_per_sample "Bit depth" " bit"
        duration "Stream duration" " s"
        container_duration "Container duration" " s"
        audio_stream_count "Audio streams" ""
        selected_stream_index "Selected stream" ""
    } {
        if {[dict exists $probe $key] && [string trim [dict get $probe $key]] ne ""} {
            dict set md $label "[dict get $probe $key]$suffix"
        }
    }
    set ct [expr {[dict exists $probe container_tags] ? [dict get $probe container_tags] : [dict create]}]
    set st [expr {[dict exists $probe stream_tags] ? [dict get $probe stream_tags] : [dict create]}]
    foreach {name label} {title Title artist Artist album Album genre Genre date Date encoder Encoder language Language} {
        set v [::AcqAudio::firstTag $st $ct [list $name]]
        if {$v ne ""} { dict set md $label $v }
    }
    return $md
}

proc ::AcqAudio::canonicalExtension {sourcePath isRaw probe} {
    set ext [string tolower [file extension [file tail $sourcePath]]]
    if {[regexp {^\.[a-z0-9]{1,12}$} $ext]} { return $ext }
    if {$isRaw} { return .pcm }
    set container [string tolower [::AcqAudio::nonempty $probe container_format audio]]
    set first [lindex [split $container ,] 0]
    regsub -all {[^a-z0-9]+} $first _ first
    if {$first eq ""} { set first audio }
    return ".${first}"
}

proc ::AcqAudio::canonicalFormat {isRaw probe} {
    if {$isRaw} { return raw_pcm }
    set value [string tolower [::AcqAudio::nonempty $probe container_format audio]]
    set first [lindex [split $value ,] 0]
    regsub -all {[^a-z0-9._-]+} $first _ first
    if {$first eq ""} { set first audio }
    return $first
}

proc ::AcqAudio::mediaType {isRaw probe sourcePath} {
    if {$isRaw} { return audio/x-raw }
    set container [string tolower [::AcqAudio::nonempty $probe container_format ""]]
    set codec [string tolower [::AcqAudio::nonempty $probe codec_name ""]]
    set ext [string tolower [file extension [file tail $sourcePath]]]
    if {[string first wav $container] >= 0 || $ext in {.wav .wave}} { return audio/wav }
    if {[string first flac $container] >= 0 || $codec eq "flac" || $ext eq ".flac"} { return audio/flac }
    if {$codec eq "mp3" || [string first mp3 $container] >= 0 || $ext eq ".mp3"} { return audio/mpeg }
    if {[string first ogg $container] >= 0 || $ext in {.ogg .oga .opus}} { return audio/ogg }
    if {[string first webm $container] >= 0 || $ext eq ".webm"} { return audio/webm }
    if {$codec eq "aac" && $ext eq ".aac"} { return audio/aac }
    if {[regexp {(^|,)mov|mp4|m4a|3gp|3g2|mj2} $container] || $ext in {.m4a .mp4}} { return audio/mp4 }
    if {[string first matroska $container] >= 0 || $ext in {.mka .mkv}} { return audio/x-matroska }
    return application/octet-stream
}

proc ::AcqAudio::copyExact {src dst} {
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

# --- inspect_proc ------------------------------------------------------------
proc ::AcqAudio::inspect {request} {
    set path [dict get $request source_path]
    if {![file isfile $path]} {
        return [dict create recognized 0 format audio variables {} preview_rows {} metadata {} \
            warnings [list "Audio source does not exist: $path"] preview_kind metadata \
            preview_metadata [dict create Status "Missing source file"]]
    }

    # .pcm/.raw are explicitly treated as headerless raw PCM. Do not let
    # content heuristics silently reinterpret those bytes as another format.
    if {[::AcqAudio::rawCandidate $path]} {
        set size [file size $path]
        set md [dict create \
            "Input" "Headerless raw PCM candidate" \
            "File size" "$size bytes" \
            "Required settings" "sample format, sample rate, channel count"]
        set warning "Headerless raw PCM cannot be probed without explicit format, sample rate and channel count. Configure the Raw PCM fields before import."
        return [dict create recognized 1 format audio.raw_pcm variables {} preview_rows {} \
            metadata [dict create raw_pcm_candidate 1 byte_size $size] warnings [list $warning] \
            preview_kind metadata preview_metadata $md]
    }

    if {![catch {::GX::audioProbe $path} probe]} {
        set warnings {}
        if {[dict exists $probe audio_stream_count] && [dict get $probe audio_stream_count] > 1} {
            lappend warnings "Multiple audio streams detected. Import uses the first audio stream unless Audio stream index is configured."
        }
        return [dict create recognized 1 format audio.source variables {} preview_rows {} \
            metadata $probe warnings $warnings preview_kind metadata \
            preview_metadata [::AcqAudio::previewMetadata $probe]]
    }

    return [dict create recognized 0 format audio variables {} preview_rows {} metadata {} \
        warnings [list "GX-TXT Audio Decode API v1 / FFprobe did not recognize this file as a decodable audio source."] \
        preview_kind metadata preview_metadata [dict create Status "Unrecognized or unsupported audio source"]]
}

# --- import_proc -------------------------------------------------------------
proc ::AcqAudio::import {request} {
    set outDir [dict get $request output_dir]
    set id [dict get $request dataset_id]
    set original [dict get $request source_path]
    set raw [expr {[dict exists $request raw_path] && [dict get $request raw_path] ne "" ? [dict get $request raw_path] : $original}]
    set streamIndex [::AcqAudio::streamIndexFromRequest $request]

    set isRaw [::AcqAudio::rawCandidate $original]
    set hints [dict create]
    if {$isRaw} {
        set hints [::AcqAudio::rawHintsFromRequest $request]
        # Raw PCM is one elementary stream; an explicit nonzero stream index
        # would be scientifically meaningless.
        if {$streamIndex ne "" && $streamIndex != 0} {
            error "Raw PCM has one elementary audio stream; Audio stream index must be blank or 0."
        }
        set streamIndex ""
        if {[catch {::AcqAudio::probeSelected $raw $streamIndex $hints} probe rawOptions]} {
            return -options $rawOptions "Raw PCM probe failed with the configured hints: $probe"
        }
    } else {
        if {[catch {set probe [::AcqAudio::probeSelected $raw $streamIndex]} probeError]} {
            error "Audio source is not recognized by GX-TXT Audio Decode API v1: $probeError"
        }
    }

    set ext [::AcqAudio::canonicalExtension $original $isRaw $probe]
    set rel "${id}${ext}"
    set dst [file join $outDir $rel]
    ::AcqAudio::copyExact $raw $dst

    set metadata [::AcqAudio::buildStructuredMetadata $original $raw $probe $isRaw]
    set format [::AcqAudio::canonicalFormat $isRaw $probe]
    set mediaType [::AcqAudio::mediaType $isRaw $probe $original]
    set codec [::AcqAudio::nonempty $probe codec_name unknown]
    set rate [::AcqAudio::nonempty $probe sample_rate unknown]
    set channels [::AcqAudio::nonempty $probe channels unknown]
    set duration [::AcqAudio::nonempty $probe container_duration [::AcqAudio::nonempty $probe duration unknown]]
    set stream [::AcqAudio::nonempty $probe selected_stream_index 0]
    set provenance [format "opaque audio source; container=%s; codec=%s; sample_rate=%s; channels=%s; duration=%s; selected_stream=%s; source bytes preserved" \
        [::AcqAudio::nonempty $probe container_format raw_pcm] $codec $rate $channels $duration $stream]

    return [dict create datasets [list [dict create \
        dataset_id $id contract audio.source format $format path $rel \
        storage_kind binary media_type $mediaType variables {} units {} semantic_roles {} \
        source "audio source file" provenance $provenance structured_metadata $metadata]]]
}

# --- dataset_preview_proc ----------------------------------------------------
proc ::AcqAudio::datasetPreview {request} {
    set md [dict create]
    if {[dict exists $request storage_kind]} { dict set md "Storage" [dict get $request storage_kind] }
    if {[dict exists $request media_type]} { dict set md "Media type" [dict get $request media_type] }
    set format [expr {[dict exists $request format] ? [dict get $request format] : ""}]
    if {$format ne ""} { dict set md "Format" $format }
    if {[dict exists $request dataset_path] && $format ne "raw_pcm"} {
        set path [dict get $request dataset_path]
        if {![catch {::GX::audioProbe $path} probe]} {
            set md [dict merge $md [::AcqAudio::previewMetadata $probe]]
        }
    }
    if {$format eq "raw_pcm"} {
        dict set md "Input" "Headerless raw PCM"
        dict set md "Metadata" "See Dataset Metadata for the explicit raw PCM input hints used during import."
    }
    return [dict create preview_kind metadata preview_metadata $md]
}
