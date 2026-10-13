# SPDX-License-Identifier: GPL-3.0-or-later
# Complete-file publication authority for explicit exports and their sidecars.
proc ::GX::filePublicationApiInfo {} {
    return [dict create api_id FILE_PUBLICATION_API_v1 api_version 1 operations publish_bundle partial_files_visible 0 policies {create_only replace}]
}
proc ::GX::_filePublicationIdentity {path} {
    if {[catch {file lstat $path status}]} {return {}}
    if {$status(type) ne "file"} {error "File publication requires a regular destination: $path"}
    return [list $status(dev) $status(ino) $status(size) [sha256File $path]]
}
proc ::GX::filePublicationPublishBundle {artifacts {policy create_only}} {
    if {$policy ni {create_only replace}} {error "Unknown File Publication policy"}
    if {[llength $artifacts]<1||[llength $artifacts]>64} {error "File Publication requires 1–64 artifacts"}
    set ids {};set paths {};set prepared {};set receipts {};set channel ""
    foreach artifact $artifacts {
        foreach key {id destination writer} {if {![dict exists $artifact $key]} {error "File artifact requires $key"}}
        set id [dict get $artifact id];set path [file normalize [dict get $artifact destination]]
        if {$id eq ""||$id in $ids||$path in $paths||![llength [dict get $artifact writer]]} {error "File artifacts need distinct IDs/destinations and writer callbacks"}
        if {![file isdirectory [file dirname $path]]} {error "File publication destination directory does not exist"}
        set identity [_filePublicationIdentity $path]
        if {$policy eq "create_only"&&$identity ne {}} {error "Export destination already exists: $path"}
        lappend ids $id;lappend paths $path
        dict set artifact destination $path;dict set artifact identity $identity
        dict set artifact temporary "";dict set artifact backup "";dict set artifact committed 0
        lappend prepared $artifact
    }
    try {
        for {set i 0} {$i<[llength $prepared]} {incr i} {
            set artifact [lindex $prepared $i];set path [dict get $artifact destination]
            set channel [file tempfile temporary [file join [file dirname $path] .gxtxt-publication-]]
            dict set artifact temporary $temporary;lset prepared $i $artifact
            fconfigure $channel -translation binary -encoding binary
            uplevel #0 [list {*}[dict get $artifact writer] $channel [dict create completed $receipts]]
            close $channel;set channel ""
            dict set receipts [dict get $artifact id] [dict create destination $path sha256 [sha256File $temporary] byte_count [file size $temporary]]
        }
        # All producers complete before any visible destination changes.
        foreach artifact $prepared {
            if {[_filePublicationIdentity [dict get $artifact destination]] ne [dict get $artifact identity]} {error "Export destination changed while preparing: [dict get $artifact destination]"}
        }
        for {set i 0} {$i<[llength $prepared]} {incr i} {
            set artifact [lindex $prepared $i];set path [dict get $artifact destination]
            if {[dict get $artifact identity] ne {}} {
                set f [file tempfile backup [file join [file dirname $path] .gxtxt-backup-]];close $f;file delete -- $backup
                file rename -- $path $backup
                dict set artifact backup $backup;lset prepared $i $artifact
            }
            # Hard-link publication is atomic and fails if another writer wins
            # the destination after preflight; incomplete temporary bytes stay hidden.
            file link -hard $path [dict get $artifact temporary]
            dict set artifact committed 1;lset prepared $i $artifact
        }
    } on error {message options} {
        if {$channel ne ""} {close $channel;set channel ""}
        set failures {}
        foreach artifact [lreverse $prepared] {
            set path [dict get $artifact destination]
            if {[dict get $artifact committed]} {
                if {[catch {
                    file stat [dict get $artifact temporary] own
                    file lstat $path visible
                    if {$visible(type) ne "file"||$visible(dev)!=$own(dev)||$visible(ino)!=$own(ino)} {error "Destination replaced by another writer"}
                    file delete -- $path
                } failure]} {lappend failures "$path: $failure"}
            }
            if {[dict get $artifact backup] ne ""&&[catch {file rename -- [dict get $artifact backup] $path} failure]} {lappend failures "$path: $failure"}
        }
        if {$failures ne {}} {return -code error -errorcode {GX FILE_PUBLICATION ROLLBACK} "$message; rollback requires recovery: [join $failures {; }]"}
        return -options $options $message
    } finally {
        foreach artifact $prepared {
            if {[dict get $artifact temporary] ne ""} {file delete -- [dict get $artifact temporary]}
        }
    }
    foreach artifact $prepared {if {[dict get $artifact backup] ne ""} {file delete -- [dict get $artifact backup]}}
    return [dict create api_id FILE_PUBLICATION_API_v1 status published files $receipts]
}
