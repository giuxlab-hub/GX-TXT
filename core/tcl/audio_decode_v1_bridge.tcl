#!/usr/bin/env tclsh
set root [file normalize [file join [file dirname [info script]] .. ..]]
set argv0 __not_main__
source [file join $root gxtxt_pipeline.tcl]
::GX::defaults
proc enc value { binary encode base64 -maxlen 0 $value }
proc err value { puts "ERROR\t[enc [encoding convertto utf-8 $value]]"; flush stdout }

lassign $argv path format frames stream inputFormat sampleRate channels
set options [dict create sample_format $format chunk_frames $frames]
if {[string trim $stream] ne ""} { dict set options stream_index $stream }
foreach {key value} [list input_format $inputFormat sample_rate $sampleRate channels $channels] {
    if {[string trim $value] ne ""} { dict set options $key $value }
}
if {[catch {
    set handle [::GX::audioDecodeOpen $path $options]
    set metadata [::GX::audioDecodeMetadata $handle]
} error]} {
    err $error
    exit 2
}
puts "READY\t[pid]\t[dict get $metadata selected_stream_index]\t[dict get $metadata sample_rate]\t[dict get $metadata channels]\t[enc [dict get $metadata codec_name]]\t[enc [dict get $metadata channel_layout]]\t[enc [dict get $metadata sample_format]]\t[::GX::audioDecodeDiagnostics $handle]"
flush stdout

set finished 0
try {
    while {[gets stdin command] >= 0} {
        if {[catch {
            switch -- [string toupper [string trim $command]] {
                NEXT {
                    set chunk [::GX::audioDecodeNext $handle]
                    puts "CHUNK\t[dict get $chunk frames]\t[dict get $chunk channels]\t[dict get $chunk eof]\t[enc [dict get $chunk bytes]]"
                    flush stdout
                }
                DIAG {
                    puts "DIAG\t[enc [encoding convertto utf-8 [::GX::audioDecodeDiagnostics $handle]]]"
                    flush stdout
                }
                CLOSE {
                    ::GX::audioDecodeClose $handle
                    puts CLOSED
                    flush stdout
                    set finished 1
                }
                default { error "Unknown Audio Decode bridge command" }
            }
        } error]} { err $error }
        if {$finished} break
    }
} finally {
    catch {::GX::audioDecodeClose $handle}
}
