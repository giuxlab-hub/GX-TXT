# SPDX-License-Identifier: GPL-3.0-or-later
# Read/render-only transient exporter. Owned by the consultation cancellation path.
lassign $argv octave script cache runtime output python converter expectation
if {[catch {
    set arguments [list $cache $runtime [file join $output plot]]
    if {$expectation ne {}} {lappend arguments $expectation}
    exec -- $octave --quiet --no-gui $script {*}$arguments 2>@1
    puts [exec -- $python -B $converter $output 2>@1]
} message]} {puts stderr $message;exit 1}
