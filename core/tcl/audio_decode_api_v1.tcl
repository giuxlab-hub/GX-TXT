# GX-TXT Audio Decode API v1 - generic FFmpeg backend
# SPDX-License-Identifier: GPL-3.0-or-later

namespace eval ::GX {
    variable audioDecodeApiVersion 1
    variable audioDecodeState
    variable audioDecodeCounter 0
    array set audioDecodeState {}
}

proc ::GX::audioDecodeDependencyInfo {} {
    if {[llength [info commands ::GX::runtimeToolResolve]]} {
        if {[catch {set ffmpeg [runtimeToolResolve ffmpeg]}]} { set ffmpeg "" }
        if {[catch {set ffprobe [runtimeToolResolve ffprobe]}]} { set ffprobe "" }
    } else {
        set ffmpeg [auto_execok ffmpeg]
        set ffprobe [auto_execok ffprobe]
    }
    if {$ffmpeg eq "" || $ffprobe eq ""} {
        return [dict create available 0 ffmpeg $ffmpeg ffprobe $ffprobe reason "FFmpeg and FFprobe executables are required"]
    }
    set fv [lindex [split [exec $ffmpeg -version] \n] 0]
    set pv [lindex [split [exec $ffprobe -version] \n] 0]
    return [dict create available 1 backend ffmpeg ffmpeg_path $ffmpeg ffprobe_path $ffprobe ffmpeg_version $fv ffprobe_version $pv]
}

proc ::GX::audioDecodeRequireDependencies {} {
    set d [audioDecodeDependencyInfo]
    if {![dict get $d available]} { error "Audio Decode API v1 requires configured FFmpeg and FFprobe executables" }
    return $d
}

proc ::GX::audioInputHintsNormalize {options} {
    if {[catch {dict size $options}]} { error "Audio input options must be a dictionary." }
    set present {}
    foreach key {input_format sample_rate channels} {
        if {[dict exists $options $key]} { lappend present $key }
    }
    if {![llength $present]} { return [dict create] }
    if {[llength $present] != 3} {
        error "Raw PCM input hints require input_format, sample_rate, and channels."
    }

    set inputFormat [string tolower [string trim [dict get $options input_format]]]
    set supported {u8 s16le s16be s24le s24be s32le s32be f32le f32be f64le f64be}
    if {$inputFormat ni $supported} {
        error "Unsupported raw PCM input_format '$inputFormat'."
    }
    set sampleRate [dict get $options sample_rate]
    if {![string is integer -strict $sampleRate] || $sampleRate < 1} {
        error "Raw PCM sample_rate must be an integer >= 1."
    }
    set channels [dict get $options channels]
    if {![string is integer -strict $channels] || $channels < 1} {
        error "Raw PCM channels must be an integer >= 1."
    }
    return [dict create input_format $inputFormat sample_rate $sampleRate channels $channels]
}

proc ::GX::audioProbeArguments {probe path hints} {
    set cmd [list $probe -v error]
    if {[dict size $hints]} {
        lappend cmd -f [dict get $hints input_format]
        lappend cmd -sample_rate [dict get $hints sample_rate]
        lappend cmd -channels [dict get $hints channels]
    }
    lappend cmd -select_streams a
    lappend cmd -show_entries {stream=index,codec_name,sample_rate,channels,channel_layout,sample_fmt,bits_per_sample,bits_per_raw_sample,duration,nb_frames:stream_tags}
    lappend cmd -show_entries {format=format_name,duration:format_tags}
    lappend cmd -of {default=noprint_wrappers=0}
    lappend cmd $path
    return $cmd
}

# Backward-compatible forms:
#   audioProbe path
#   audioProbe path streamIndex
# Additive forms:
#   audioProbe path optionsDict
#   audioProbe path streamIndex optionsDict
proc ::GX::audioProbe {path {streamIndex ""} {options {}}} {
    if {![catch {dict size $streamIndex}] &&
        ([dict exists $streamIndex input_format] ||
         [dict exists $streamIndex sample_rate] ||
         [dict exists $streamIndex channels] ||
         [dict exists $streamIndex stream_index])} {
        if {$options ne ""} { error "Audio probe options were supplied twice." }
        set options $streamIndex
        set streamIndex [expr {[dict exists $options stream_index] ? [dict get $options stream_index] : ""}]
    }
    if {[catch {dict size $options}]} { error "Audio probe options must be a dictionary." }
    if {$streamIndex eq "" && [dict exists $options stream_index]} {
        set streamIndex [dict get $options stream_index]
    }
    set hints [audioInputHintsNormalize $options]

    set d [audioDecodeRequireDependencies]
    set path [file normalize $path]
    if {![file isfile $path]} { error "Audio source does not exist: $path" }
    set cmd [audioProbeArguments [dict get $d ffprobe_path] $path $hints]
    if {[catch {set raw [exec {*}$cmd]} e]} { error "FFprobe could not inspect audio source: $e" }

    set streams {}
    set current {}
    set currentTags [dict create]
    set formatMeta [dict create]
    set formatTags [dict create]
    set section ""
    foreach line [split $raw \n] {
        set line [string trim $line]
        if {$line eq {[STREAM]}} {
            set current [dict create]
            set currentTags [dict create]
            set section stream
            continue
        }
        if {$line eq {[FORMAT]}} {
            set section format
            continue
        }
        if {$line eq {[/FORMAT]}} {
            set section ""
            continue
        }
        if {$line eq {[/STREAM]}} {
            if {[dict size $current]} {
                dict set current tags $currentTags
                lappend streams $current
            }
            set section ""
            continue
        }
        if {![regexp {^([^=]+)=(.*)$} $line -> key value]} continue
        if {[string match "TAG:*" $key]} {
            set tagKey [string range $key 4 end]
            if {$tagKey eq ""} continue
            if {$section eq "stream"} {
                dict set currentTags $tagKey $value
            } elseif {$section eq "format"} {
                dict set formatTags $tagKey $value
            }
        } elseif {$section eq "stream"} {
            dict set current $key $value
        } elseif {$section eq "format"} {
            dict set formatMeta $key $value
        }
    }

    if {![llength $streams]} { error "Audio source has no decodable audio stream" }
    if {$streamIndex eq ""} {
        set chosen [lindex $streams 0]
    } else {
        set chosen ""
        foreach stream $streams {
            if {[dict get $stream index] eq $streamIndex} { set chosen $stream; break }
        }
        if {$chosen eq ""} { error "Requested audio stream $streamIndex was not found" }
    }

    # Keep the established selected-stream scalar fields before nested tag
    # dictionaries in the Tcl serialization. Existing text bindings that read
    # those scalar fields therefore continue to see the same values.
    set out [dict create \
        api_version 1 backend ffmpeg path $path \
        selected_stream_index [dict get $chosen index]]
    foreach key {codec_name sample_rate channels channel_layout sample_fmt bits_per_sample bits_per_raw_sample duration nb_frames} {
        dict set out $key [expr {[dict exists $chosen $key] && [dict get $chosen $key] ne "N/A" ? [dict get $chosen $key] : ""}]
    }
    dict set out container_format [expr {[dict exists $formatMeta format_name] ? [dict get $formatMeta format_name] : ""}]
    dict set out container_duration [expr {[dict exists $formatMeta duration] ? [dict get $formatMeta duration] : ""}]
    dict set out ffmpeg_version [dict get $d ffmpeg_version]
    dict set out ffprobe_version [dict get $d ffprobe_version]
    dict set out metadata_status [dict create \
        sample_rate known channels known codec_name known \
        channel_layout [expr {[dict get $out channel_layout] eq "" ? "not_reported" : "known"}] \
        duration [expr {[dict get $out duration] eq "" ? "not_reported" : "reported"}] \
        nb_frames [expr {[dict get $out nb_frames] eq "" ? "not_reported" : "reported"}]]
    dict set out audio_stream_count [llength $streams]
    dict set out streams $streams
    dict set out container_tags $formatTags
    dict set out stream_tags [dict get $chosen tags]
    dict set out input_hints $hints
    return $out
}

proc ::GX::audioDecodeOpen {path {options {}}} {
    variable audioDecodeState
    variable audioDecodeCounter
    if {[catch {dict size $options}]} { error "Audio decode options must be a dictionary." }

    set streamIndex [expr {[dict exists $options stream_index] ? [dict get $options stream_index] : ""}]
    set hints [audioInputHintsNormalize $options]
    set meta [audioProbe $path $streamIndex $options]

    set format [expr {[dict exists $options sample_format] ? [string tolower [dict get $options sample_format]] : "float32"}]
    if {$format ni {float32 int16 int32}} { error "Unsupported decoded sample format '$format'" }
    set formats [dict create float32 {f32le pcm_f32le 4} int16 {s16le pcm_s16le 2} int32 {s32le pcm_s32le 4}]
    lassign [dict get $formats $format] mux codec bytes

    set frames [expr {[dict exists $options chunk_frames] ? [dict get $options chunk_frames] : 4096}]
    if {![string is integer -strict $frames] || $frames < 1} { error "chunk_frames must be an integer >= 1" }

    set ffmpeg [dict get [audioDecodeRequireDependencies] ffmpeg_path]
    set index [dict get $meta selected_stream_index]
    set cmd [list | $ffmpeg -v error -nostdin]
    if {[dict size $hints]} {
        lappend cmd -f [dict get $hints input_format]
        lappend cmd -ar [dict get $hints sample_rate]
        lappend cmd -ac [dict get $hints channels]
    }
    lappend cmd -i [dict get $meta path] -map "0:$index" -f $mux -acodec $codec -

    if {[catch {set channel [open $cmd r]} e]} { error "FFmpeg decoder could not start: $e" }
    fconfigure $channel -translation binary -encoding binary -buffering none
    set handle "audio-decode#[incr audioDecodeCounter]"
    set pids [pid $channel]
    foreach {key value} [list \
        channel $channel process_id [lindex $pids 0] metadata $meta \
        sample_format $format bytes_per_sample $bytes \
        channels [dict get $meta channels] chunk_frames $frames \
        frames_read 0 chunks_read 0 eof 0 closed 0] {
        set audioDecodeState($handle,$key) $value
    }
    return $handle
}

proc ::GX::audioDecodeRequire {handle} {
    variable audioDecodeState
    if {![info exists audioDecodeState($handle,channel)] || $audioDecodeState($handle,closed)} {
        error "Unknown or closed audio decode handle: $handle"
    }
}

proc ::GX::audioDecodeMetadata {handle} {
    variable audioDecodeState
    audioDecodeRequire $handle
    return [dict merge $audioDecodeState($handle,metadata) [dict create \
        sample_format $audioDecodeState($handle,sample_format) \
        representation interleaved \
        frames_per_chunk $audioDecodeState($handle,chunk_frames) \
        scaling [expr {$audioDecodeState($handle,sample_format) eq "float32" ? "FFmpeg native floating decode; nominal full scale is -1.0 to +1.0" : "signed integer PCM"}]]]
}

proc ::GX::audioDecodeNext {handle} {
    variable audioDecodeState
    audioDecodeRequire $handle
    if {$audioDecodeState($handle,eof)} {
        return [dict create frames 0 channels $audioDecodeState($handle,channels) sample_format $audioDecodeState($handle,sample_format) interleaved 1 bytes "" eof 1]
    }
    set wanted [expr {$audioDecodeState($handle,chunk_frames)*$audioDecodeState($handle,channels)*$audioDecodeState($handle,bytes_per_sample)}]
    set data [read $audioDecodeState($handle,channel) $wanted]
    set byteCount [string length $data]
    set frameBytes [expr {$audioDecodeState($handle,channels)*$audioDecodeState($handle,bytes_per_sample)}]
    if {$byteCount % $frameBytes} { error "FFmpeg returned an incomplete audio frame" }
    set frames [expr {$byteCount/$frameBytes}]
    incr audioDecodeState($handle,frames_read) $frames
    incr audioDecodeState($handle,chunks_read)
    if {$byteCount < $wanted || [eof $audioDecodeState($handle,channel)]} { set audioDecodeState($handle,eof) 1 }
    return [dict create frames $frames channels $audioDecodeState($handle,channels) sample_format $audioDecodeState($handle,sample_format) interleaved 1 bytes $data eof $audioDecodeState($handle,eof)]
}

proc ::GX::audioDecodeDiagnostics {handle} {
    variable audioDecodeState
    audioDecodeRequire $handle
    return [dict create \
        backend ffmpeg process_id $audioDecodeState($handle,process_id) \
        chunks_read $audioDecodeState($handle,chunks_read) \
        frames_read $audioDecodeState($handle,frames_read) \
        chunk_frames $audioDecodeState($handle,chunk_frames) \
        channels $audioDecodeState($handle,channels) \
        max_payload_bytes [expr {$audioDecodeState($handle,chunk_frames)*$audioDecodeState($handle,channels)*$audioDecodeState($handle,bytes_per_sample)}]]
}

proc ::GX::audioDecodeClose {handle} {
    variable audioDecodeState
    if {![info exists audioDecodeState($handle,channel)]} { return }
    set channel $audioDecodeState($handle,channel)
    catch {close $channel}
    foreach name [array names audioDecodeState "$handle,*"] { unset audioDecodeState($name) }
}
