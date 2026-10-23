# SPDX-License-Identifier: GPL-3.0-or-later
# SOURCE ONLY; fixed driver-owned synthetic inputs, no Tk/framework bootstrap.
namespace eval ::GX210CaptureQA {variable checks {}; variable evidence {}; variable phase admission}
proc ::GX210CaptureQA::need {value label} {
    if {!$value} {error "CAPTURE_QA:$label"}
}
proc ::GX210CaptureQA::check {label value} {
    variable checks
    dict set checks $label [expr {!!$value}]
    need $value $label
}
proc ::GX210CaptureQA::readData {path} {
    need [expr {[file type $path] eq {file} && [file size $path] <= 65536}] fixture_data
    set ch [open $path rb]
    try {set bytes [read $ch 65537]} finally {close $ch}
    need [expr {[string length $bytes] <= 65536}] fixture_data_bound
    return [encoding convertfrom utf-8 $bytes]
}
proc ::GX210CaptureQA::fds {} {return [llength [glob -nocomplain /proc/[pid]/fd/*]]}
proc ::GX210CaptureQA::captureOne {label row snapshot args} {
    variable evidence
    if {[llength $args] == 1} {
        set value [lindex $args 0]
    } else {
        need [expr {[llength $args] == 0}] captured_argument
        set value [::GX::NativeDocument::sourceCapture [dict get $row path]]
    }
    check ${label}_schema [expr {[lsort [dict keys $value]] eq {bytes identity schema}
        && [dict get $value schema] eq {gxtxt.native_source_capture.v1}}]
    set bytes [dict get $value bytes]
    # Observe the actual type before any string/binary conversion can shimmer it.
    check ${label}_true_bytearray [string match {value is a bytearray*} \
        [::tcl::unsupported::representation $bytes]]
    set identity [dict get $value identity]
    set expected [dict get $row identity]
    check ${label}_identity_keys [expr {[lsort [dict keys $identity]] eq
        {ctime_ns device gid inode links mode mtime_ns size uid}}]
    foreach field {device inode size mode uid gid links mtime_ns ctime_ns} {
        check ${label}_identity_${field} [expr {[string is wideinteger -strict [dict get $identity $field]]
            && [dict get $identity $field] == [dict get $expected $field]}]
    }
    check ${label}_byte_count [expr {[string length $bytes] == [dict get $expected size]}]
    if {$snapshot ne {}} {
        set ch [open $snapshot {WRONLY CREAT EXCL} 0600]
        try {fconfigure $ch -translation binary -encoding binary; puts -nonewline $ch $bytes} finally {close $ch}
        set actual [lindex [exec /usr/bin/sha256sum -- $snapshot] 0]
        check ${label}_snapshot_sha [expr {$actual eq [dict get $row sha256]}]
        check ${label}_snapshot_mode [expr {([file attributes $snapshot -permissions] & 0777) == 0600}]
        dict set evidence snapshots $label [dict create path $snapshot sha256 $actual \
            bytes [string length $bytes] identity $identity true_bytearray 1]
    }
    return $value
}
proc ::GX210CaptureQA::refuse {label path} {
    set code [catch {::GX::NativeDocument::sourceCapture $path} value options]
    check ${label}_refused [expr {$code == 1 && [dict exists $options -errorcode]
        && [dict get $options -errorcode] eq {GXTXT DOCUMENT SOURCE_CAPTURE REFUSED}}]
}
if {$argc != 3} {puts stderr {Capture QA requires exactly three driver arguments.}; exit 2}
lassign $argv native fixtureFile resultFile
set status FAIL
try {
    encoding system utf-8
    set fixture [::GX210CaptureQA::readData $fixtureFile]
    ::GX210CaptureQA::need [expr {[dict get $fixture schema] eq {gx210.capture.fixtures.v1}}] fixture_schema
    ::GX210CaptureQA::need [expr {![llength [info commands winfo]] && ![info exists ::env(DISPLAY)]}] headless
    set ::GX210CaptureQA::phase load
    load $native Gxtxtdocument
    ::GX210CaptureQA::check native_command_available [expr {
        [llength [info commands ::GX::NativeDocument::sourceCapture]] == 1}]
    ::GX210CaptureQA::check package_unchanged [expr {[package present gxtxt_document] eq {1.0}}]
    dict set ::GX210CaptureQA::evidence loaded [info loaded]
    ::GX210CaptureQA::need [expr {[llength [info commands ::tcl::unsupported::representation]] == 1}] type_observer
    set ::GX210CaptureQA::phase capture
    set output [dict get $fixture snapshots]
    foreach name {binary empty limit} {
        ::GX210CaptureQA::captureOne $name [dict get $fixture positives $name] [file join $output $name.bin]
    }
    set unicode [dict get $fixture positives unicode]
    set rc [catch {::GX::NativeDocument::sourceCapture [dict get $unicode path]} unicodeValue unicodeOptions]
    if {!$rc} {
        ::GX210CaptureQA::captureOne unicode $unicode [file join $output unicode.bin] $unicodeValue
        dict set ::GX210CaptureQA::evidence unicode_path SUPPORTED_LOSSLESS_EXACT_IDENTITY
    } else {
        ::GX210CaptureQA::check unicode_refusal_closed [expr {$rc == 1
            && [dict get $unicodeOptions -errorcode] eq {GXTXT DOCUMENT SOURCE_CAPTURE REFUSED}
            && $unicodeValue in {{Source path native conversion is not lossless and literal}
                {Source path has no supported native representation}
                {Source path has no supported absolute native representation}}}]
        dict set ::GX210CaptureQA::evidence unicode_path UNSUPPORTED_PATH_REFUSED_NO_WRONG_FILE_ACCEPTED
    }
    foreach name {oversized directory fifo hardlink leaf_symlink ancestor_symlink dotdot relative} {
        ::GX210CaptureQA::refuse $name [dict get $fixture negatives $name]
    }
    ::GX210CaptureQA::refuse embedded_unicode_nul "[dict get $fixture positives binary path][format %c 0]suffix"
    set before [::GX210CaptureQA::fds]
    for {set n 0} {$n < 4} {incr n} {
        ::GX210CaptureQA::captureOne repeat$n [dict get $fixture positives binary] {}
        ::GX210CaptureQA::refuse repeat${n}_link [dict get $fixture negatives leaf_symlink]
        ::GX210CaptureQA::refuse repeat${n}_fifo [dict get $fixture negatives fifo]
    }
    set after [::GX210CaptureQA::fds]
    ::GX210CaptureQA::check own_fd_count_stable [expr {$before == $after}]
    dict set ::GX210CaptureQA::evidence fd_counts [dict create before $before after $after scope own_Tcl_PID_only]
    set ::GX210CaptureQA::phase compatibility
    set doc [::GX::NativeDocument::xml parse {<root><item id="one">value</item></root>}]
    try {
        set node [::GX::NativeDocument::xml root $doc]
        ::GX210CaptureQA::check xml_parse_root [expr {[dict get [::GX::NativeDocument::xml describe $doc $node] name] eq {root}}]
    } finally {::GX::NativeDocument::xml release $doc}
    ::GX210CaptureQA::check xml_released_refused [catch {::GX::NativeDocument::xml root $doc}]
    set scan [::GX::NativeDocument::scan python "def sample():\n    return 1\n"]
    ::GX210CaptureQA::check scan_compatibility [expr {[dict get $scan engine] eq {gxtxt.native_source.v1}
        && [llength [dict get $scan tokens]] > 0 && ![dict get $scan truncated]}]
    set runs [::GX::NativeDocument::render html {<p>Capture compatibility <strong>only</strong>.</p>}]
    ::GX210CaptureQA::check inert_render_compatibility [expr {[llength $runs] > 0
        && [string first {Capture compatibility} $runs] >= 0}]
    set status PASS_SCOPED_NATIVE_CAPTURE
} on error {ignored options} {
    # No raw object/bytearray/path exception or reconstructed diagnostic dump.
    dict set ::GX210CaptureQA::evidence failure_phase $::GX210CaptureQA::phase
} finally {
    set value [dict create schema gx210.capture.result.v1 status $status checks $::GX210CaptureQA::checks \
        evidence $::GX210CaptureQA::evidence not_tested \
        {within_read_races integer_time_overflow hostile_filesystem_responsiveness canonical_parent_commit PCB_GUI installed_behavior}]
    set ch [open $resultFile {WRONLY CREAT EXCL} 0600]
    try {fconfigure $ch -encoding utf-8 -translation lf; puts -nonewline $ch $value} finally {close $ch}
}
if {$status ne {PASS_SCOPED_NATIVE_CAPTURE}} {puts stderr {Native source capture qualification failed; preserve outputs.}; exit 1}
puts {Scoped native source capture completed; no canonical/GUI/release acceptance.}
