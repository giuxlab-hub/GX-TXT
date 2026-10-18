# SPDX-License-Identifier: GPL-3.0-or-later
set root [lindex $argv 0]
set request [read stdin]
if {[catch {
    load [file join $root core nativegui document libgxtxt_document[info sharedlibextension]] Gxtxtdocument
    set result [::GX::NativeDocument::scan [dict get $request language] [dict get $request source]]
    if {[dict get $request language] eq {python}} {
        set structure [exec python3 -B [file join $root core python gxtxt_source_structure.py] << [dict get $request source]]
        dict set result folds [dict get $structure folds]
        dict set result executable_lines [dict get $structure executable_lines]
    }
} message]} {puts [dict create ok 0 error $message]} else {puts [dict create ok 1 result $result]}
