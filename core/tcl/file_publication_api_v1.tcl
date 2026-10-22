# SPDX-License-Identifier: GPL-3.0-or-later
# Complete-file publication authority for explicit exports and their sidecars.
proc ::GX::filePublicationApiInfo {} {
    return [dict create api_id FILE_PUBLICATION_API_v1 api_version 1 operations {publish_bundle text_document} partial_files_visible 0 policies {create_only replace} artifacts_max 4096 bundle_options {create_parents}]
}
proc ::GX::filePublicationTextDocument {destination text format {options {}}} {
    if {$format ni {text pdf}} {error {Document export format must be text or pdf}}
    set settings [dict merge [dict create page A4 orientation portrait margin_mm 15] $options]
    foreach key [dict keys $settings] {if {$key ni {page orientation margin_mm}} {error {Unknown printable-document option}}}
    return [filePublicationPublishBundle [list [dict create id document destination $destination writer [list ::GX::_filePublicationDocumentWriter $text $format $settings]]]]
}
proc ::GX::_filePublicationDocumentWriter {text format options channel context} {
    if {$format eq "text"} {puts -nonewline $channel [encoding convertto utf-8 $text];return}
    set handle [file tempfile path];close $handle
    try {
        set command [list [runtimeToolRequired python] [file join $::GX::scriptDir services printing gxtxt_compose_pdf.py] \
            --output $path --text-input - --page [dict get $options page] --orientation [dict get $options orientation] --margin-mm [dict get $options margin_mm]]
        exec {*}$command << $text
        set input [open $path rb]
        try {fcopy $input $channel} finally {close $input}
    } finally {file delete -force -- $path}
}
proc ::GX::_filePublicationIdentity {path} {
    if {[catch {file lstat $path status}]} {return {}}
    if {$status(type) ne "file"} {error "File publication requires a regular destination: $path"}
    return [list $status(dev) $status(ino) $status(size) [sha256File $path]]
}
proc ::GX::filePublicationPublishBundle {artifacts {policy create_only} {options {}}} {
    if {$policy ni {create_only replace}} {error "Unknown File Publication policy"}
    set createParents 0
    dict for {key value} $options {
        if {$key ne {create_parents} || ![string is boolean -strict $value]} {error {File Publication options allow only boolean create_parents}}
        set createParents $value
    }
    if {[llength $artifacts]<1||[llength $artifacts]>4096} {error "File Publication requires 1–4096 artifacts"}
    set missingParents {}
    set ids {};set paths {};set prepared {};set receipts {};set channel ""
    foreach artifact $artifacts {
        foreach key {id destination writer} {if {![dict exists $artifact $key]} {error "File artifact requires $key"}}
        set id [dict get $artifact id];set path [file normalize [dict get $artifact destination]]
        if {$id eq ""||$id in $ids||$path in $paths||![llength [dict get $artifact writer]]} {error "File artifacts need distinct IDs/destinations and writer callbacks"}
        if {![file isdirectory [file dirname $path]]} {
            if {!$createParents} {error "File publication destination directory does not exist"}
            set parent [file dirname $path]
            while {![file exists $parent]} {lappend missingParents $parent;set parent [file dirname $parent]}
            if {![file isdirectory $parent]} {error {File publication destination parent is not a directory}}
        }
        set identity [_filePublicationIdentity $path]
        if {$policy eq "create_only"&&$identity ne {}} {error "Export destination already exists: $path"}
        lappend ids $id;lappend paths $path
        dict set artifact destination $path;dict set artifact identity $identity
        dict set artifact temporary "";dict set artifact backup "";dict set artifact committed 0
        lappend prepared $artifact
    }
    set createdParents {}
    try {
        foreach parent [lsort -unique $missingParents] {
            if {![file exists $parent]} {file mkdir $parent;lappend createdParents $parent}
        }
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
        # Remove only newly created empty directories. Published files or any
        # concurrent contents retain their parent; original directories stay.
        foreach parent [lsort -decreasing $createdParents] {
            if {![file isdirectory $parent]} continue
            set occupied 0
            foreach entry [glob -nocomplain -directory $parent * .*] {if {[file tail $entry] ni {. ..}} {set occupied 1;break}}
            if {!$occupied} {catch {file delete -- $parent}}
        }
    }
    foreach artifact $prepared {if {[dict get $artifact backup] ne ""} {file delete -- [dict get $artifact backup]}}
    return [dict create api_id FILE_PUBLICATION_API_v1 status published files $receipts]
}

# Explicit host export of a verified derived document through this authority.
proc ::GX::filePublicationCopy {source destination expected {policy create_only}} {
    if {![file isfile $source] || [file type $source] ne {file} || [sha256File $source] ne $expected} {error {Export source changed before publication.}}
    return [filePublicationPublishBundle [list [dict create id document destination $destination writer [list ::GX::_filePublicationCopyWriter $source $expected]]] $policy]
}
proc ::GX::_filePublicationCopyWriter {source expected channel context} {
    set input [open $source rb]
    try {fcopy $input $channel} finally {close $input}
    if {[sha256File $source] ne $expected} {error {Export source changed while publishing.}}
}
