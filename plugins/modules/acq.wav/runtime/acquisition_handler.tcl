# GX-TXT Acquisition Handler Plugin API v1 - WAV / PCM raw audio import
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Imports raw (neutral) PCM audio as a binary audio.waveform dataset. The WAV
# bytes stay opaque; decoding is a downstream step (analysis.audio_decode).
# Neutrality is enforced by CONTENT (the fmt chunk audio format), never by the
# .wav extension: a compressed payload wrapped in a .wav container is refused.

namespace eval ::AcqWav {}

# --- WAV header inspection (fmt + data chunks only; no sample decoding) ------
# Returns a dict: audio_format channels sample_rate bits byte_rate data_bytes
#   duration_s pcm(0/1) codec(text). Errors on a non-RIFF/WAVE file.
proc ::AcqWav::inspectHeader {path} {
    set fd [open $path r]
    fconfigure $fd -encoding binary -translation binary
    try {
        set hdr [read $fd 12]
        if {[string length $hdr] < 12} { error "file too small to be a WAV" }
        binary scan $hdr a4 riff
        binary scan [string range $hdr 8 11] a4 wave
        if {$riff ne "RIFF"} { error "not a RIFF file (no RIFF marker)" }
        if {$wave ne "WAVE"} { error "not a WAVE file" }

        set fmtFound 0; set dataBytes -1
        set audioFormat 0; set channels 0; set sampleRate 0; set bits 0; set byteRate 0
        while {1} {
            set ch [read $fd 8]
            if {[string length $ch] < 8} break
            binary scan $ch a4 cid
            binary scan [string range $ch 4 7] i sz
            set sz [expr {$sz & 0xFFFFFFFF}]
            if {$cid eq "fmt "} {
                set body [read $fd $sz]
                if {[string length $body] < 16} { error "fmt chunk truncated" }
                binary scan $body s af;  set audioFormat [expr {$af & 0xFFFF}]
                binary scan [string range $body 2 3]  s c;  set channels   [expr {$c & 0xFFFF}]
                binary scan [string range $body 4 7]  i sr; set sampleRate [expr {$sr & 0xFFFFFFFF}]
                binary scan [string range $body 8 11] i br; set byteRate   [expr {$br & 0xFFFFFFFF}]
                binary scan [string range $body 14 15] s b; set bits       [expr {$b & 0xFFFF}]
                if {$audioFormat == 0xFFFE && [string length $body] >= 26} {
                    # WAVE_FORMAT_EXTENSIBLE: effective format is the first 2
                    # bytes of the SubFormat GUID (offset 24 within fmt body).
                    binary scan [string range $body 24 25] s sub
                    set audioFormat [expr {$sub & 0xFFFF}]
                }
                set fmtFound 1
                if {[expr {$sz & 1}]} { seek $fd 1 current }
            } elseif {$cid eq "data"} {
                set dataBytes $sz
                seek $fd [expr {$sz + ($sz & 1)}] current
            } else {
                # skip unknown chunk (chunks are word-aligned: pad to even)
                seek $fd [expr {$sz + ($sz & 1)}] current
            }
            if {$fmtFound && $dataBytes >= 0} break
        }
        if {!$fmtFound}       { error "no fmt chunk found" }
        if {$dataBytes < 0}   { error "no data chunk (fmt present but no audio data)" }
        if {$channels <= 0}   { error "invalid channel count ($channels)" }
        if {$sampleRate <= 0} { error "invalid sample rate ($sampleRate)" }
        if {$bits <= 0}       { error "invalid bit depth ($bits)" }
    } finally {
        close $fd
    }

    # linear PCM only: 1 = PCM integer, 3 = IEEE float. Anything else = codec.
    set pcm [expr {$audioFormat == 1 || $audioFormat == 3}]
    set codec [::AcqWav::codecName $audioFormat]
    set dur 0.0
    if {$dataBytes > 0 && $byteRate > 0} { set dur [expr {double($dataBytes)/$byteRate}] }
    return [dict create audio_format $audioFormat channels $channels \
        sample_rate $sampleRate bits $bits byte_rate $byteRate \
        data_bytes $dataBytes duration_s $dur pcm $pcm codec $codec]
}

proc ::AcqWav::codecName {af} {
    switch -- $af {
        1  { return "PCM integer" }
        3  { return "IEEE float" }
        6  { return "A-law (compressed)" }
        7  { return "mu-law (compressed)" }
        2  { return "MS ADPCM (compressed)" }
        17 { return "IMA ADPCM (compressed)" }
        85 { return "MP3-in-WAV (compressed)" }
        default { return "non-PCM codec (format 0x[format %x $af])" }
    }
}

proc ::AcqWav::refuseText {codec} {
    return "acq.wav refuses '$codec': it is a compressed / non-neutral source, not raw audio.\
 By design this importer accepts linear PCM only (the bytes must be the measurement, not a codec's\
 reconstruction). Decode it to WAV/PCM upstream (e.g. with ffmpeg) if you need it."
}

# --- inspect_proc ------------------------------------------------------------
proc ::AcqWav::inspect {request} {
    set path [dict get $request source_path]
    set previewDir ""
    if {[dict exists $request preview_dir]} { set previewDir [dict get $request preview_dir] }

    if {[catch {::AcqWav::inspectHeader $path} h]} {
        return [dict create recognized 0 format wav warnings [list "acq.wav: $h"] \
            variables {} preview_rows {} metadata {} \
            preview_kind metadata preview_metadata [dict create "Status" "Not a readable WAV: $h"]]
    }

    set fmt [dict get $h audio_format]
    set warnings {}
    if {![dict get $h pcm]} { lappend warnings [::AcqWav::refuseText [dict get $h codec]] }

    set md [dict create \
        "Codec"       [dict get $h codec] \
        "Sample rate" "[dict get $h sample_rate] Hz" \
        "Channels"    [dict get $h channels] \
        "Bit depth"   "[dict get $h bits]-bit" \
        "Duration"    "[format %.3f [dict get $h duration_s]] s" \
        "Neutral raw" [expr {[dict get $h pcm] ? "yes (PCM)" : "NO - refused on import"}]]

    return [dict create recognized 1 format wav \
        metadata $h variables {} preview_rows {} warnings $warnings \
        preview_kind metadata preview_metadata $md]
}

# --- import_proc -------------------------------------------------------------
proc ::AcqWav::import {request} {
    set outDir [dict get $request output_dir]
    set id     [dict get $request dataset_id]
    set src    [dict get $request source_path]
    set raw    $src
    if {[dict exists $request raw_path] && [dict get $request raw_path] ne ""} {
        set raw [dict get $request raw_path]
    }

    # Validate the exact bytes that will be registered (the RAW snapshot),
    # not the original source, to avoid a TOCTOU window between snapshot and
    # import where source_path could change under us.
    set h [::AcqWav::inspectHeader $raw]
    if {![dict get $h pcm]} {
        error [::AcqWav::refuseText [dict get $h codec]]
    }

    set rel "${id}.wav"
    file copy -force -- $raw [file join $outDir $rel]

    set prov [format "raw PCM audio; %d Hz, %d ch, %d-bit, %.3f s; %s" \
        [dict get $h sample_rate] [dict get $h channels] [dict get $h bits] \
        [dict get $h duration_s] [dict get $h codec]]

    return [dict create datasets [list [dict create \
        dataset_id $id contract audio.waveform format wav path $rel \
        storage_kind binary media_type audio/wav \
        variables {} units {} semantic_roles {} \
        source "raw PCM audio (WAV)" provenance $prov]]]
}

# --- dataset_preview_proc ----------------------------------------------------
proc ::AcqWav::datasetPreview {request} {
    set md [dict create]
    if {[dict exists $request storage_kind]} { dict set md "Storage" [dict get $request storage_kind] }
    if {[dict exists $request media_type]}   { dict set md "Media type" [dict get $request media_type] }
    if {[dict exists $request dataset_path]} {
        if {![catch {::AcqWav::inspectHeader [dict get $request dataset_path]} h]} {
            dict set md "Codec"       [dict get $h codec]
            dict set md "Sample rate" "[dict get $h sample_rate] Hz"
            dict set md "Channels"    [dict get $h channels]
            dict set md "Bit depth"   "[dict get $h bits]-bit"
            dict set md "Duration"    "[format %.3f [dict get $h duration_s]] s"
        }
    }
    return [dict create preview_kind metadata preview_metadata $md]
}
