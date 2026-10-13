# SPDX-License-Identifier: GPL-3.0-or-later
# Read/render-only transient exporter. Owned by the consultation cancellation path.
lassign $argv octave script cache runtime output python converter
if {[catch {
    exec -- $octave --quiet --no-gui $script $cache $runtime [file join $output plot] 2>@1
    puts [exec -- $python -B $converter $output 2>@1]
} message]} {puts stderr $message;exit 1}
