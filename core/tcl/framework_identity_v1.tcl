# SPDX-License-Identifier: GPL-3.0-or-later
# Installation-local display identity. VERSION.txt remains the compatibility
# version; PATCH_LEVEL.txt is shipped by each cumulative patch.
namespace eval ::GX {}
proc ::GX::_frameworkIdentityMetadata {path maximum} {
    file lstat $path before
    if {$before(type) ne {file} || $before(size)>$maximum} {
        error {Installed framework identity metadata is not a bounded regular file}
    }
    set channel [open $path {RDONLY NONBLOCK}]
    try {
        fconfigure $channel -translation binary -encoding binary
        set raw [read $channel [expr {$maximum+1}]]
        if {[string length $raw]>$maximum || ![eof $channel]} {
            error {Installed framework identity metadata exceeds its bound}
        }
    } finally {close $channel}
    file lstat $path after
    foreach key {type dev ino size mtime ctime} {
        if {$before($key) ne $after($key)} {error {Installed framework identity metadata changed while reading}}
    }
    return [string trim $raw]
}
proc ::GX::frameworkInstalledIdentity {} {
    variable scriptDir
    variable version
    set base $version
    set path [file join $scriptDir VERSION.txt]
    if {[file exists $path]} {
        set text [_frameworkIdentityMetadata $path 128]
        if {![regexp {^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-dev-[0-9]+$} $text]} {
            error {Invalid installed framework version metadata}
        }
        set base $text
    }
    set patch {}
    set path [file join $scriptDir PATCH_LEVEL.txt]
    if {[file exists $path]} {
        set text [_frameworkIdentityMetadata $path 16]
        if {![regexp {^[0-9]{3}$} $text]} {error {Invalid installed framework patch metadata}}
        set patch $text
    }
    set display $base
    if {$patch ne {}} {append display -p $patch}
    return [dict create schema gxtxt.framework_installed_identity.v1 version $base patch $patch display_version $display framework_root [file normalize $scriptDir]]
}
proc ::GX::frameworkDisplayVersion {} {
    return [dict get [frameworkInstalledIdentity] display_version]
}
