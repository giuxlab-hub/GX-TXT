# SPDX-License-Identifier: GPL-3.0-or-later
# SOURCE ONLY: actual public owners, no replacement/stub callbacks or Tk.
namespace eval ::GX210IconAdmission {variable stage bootstrap;variable current {};variable deadline 0}
proc ::GX210IconAdmission::require {condition message} {if {!$condition} {error $message}}
proc ::GX210IconAdmission::budget {} {
    variable deadline
    require [expr {[clock milliseconds]<$deadline}] {Qualification deadline reached}
}
proc ::GX210IconAdmission::save {path bytes {binary 0}} {
    require [expr {[string bytelength $bytes]<=1048576}] {Bounded data output exceeded}
    set f [open $path {WRONLY CREAT EXCL} 0600]
    if {$binary} {fconfigure $f -translation binary -encoding binary} else {fconfigure $f -translation lf -encoding utf-8}
    try {puts -nonewline $f $bytes} finally {close $f}
}
proc ::GX210IconAdmission::run {arguments} {
    variable stage;variable current;variable deadline
    require [expr {[llength $arguments]==5}] {Expected framework output python magick deadline_ms}
    lassign $arguments framework output python magick deadline
    require [expr {[info exists ::env(DISPLAY)]==0 && [info exists ::env(WAYLAND_DISPLAY)]==0}] {No display is authorized}
    namespace eval ::GX {}
    set ::GX::scriptDir $framework
    # Source genuine owners, not a sliced/rewritten function. Dataset v2 supplies
    # Configuration's existing dictionary-default helper; no publication occurs.
    source [file join $framework core tcl dataset_publication_api_v2.tcl]
    source [file join $framework core tcl configuration_api_v1.tcl]
    source [file join $framework core tcl viewer_gui_icons_v1.tcl]
    foreach {name tool} [list python $python magick $magick] {
        ::GX::configurationRegister runtime.$name [dict create group Runtime label $name type command default $tool scope user]
        require [expr {[::GX::runtimeToolRequired $name] eq $tool}] {Pinned runtime resolution differs}
    }
    set stage public_catalog;budget
    set catalog [::GX::viewerGuiIconCatalog]
    require [expr {[dict get $catalog schema] eq {gxtxt.viewer_shared_icons.v1} && [dict get $catalog count]==100 && [dict size [dict get $catalog icons]]==100}] {Public catalog must contain100 unique entries}
    set categories {};set result {}
    dict for {id row} [dict get $catalog icons] {
        set current $id;budget
        foreach key {id title category license path sha256 source_format width height action origin} {
            require [dict exists $row $key] {Actual catalog metadata is incomplete}
        }
        require [expr {$id eq [dict get $row id] && [dict get $row action] ne {} && [dict get $row origin] ne {}}] {Catalog action/origin identity differs}
        dict incr categories [dict get $row category]
        set stage public_import
        set asset [::GX::viewerGuiIconImport [dict get $row path] [dict get $row title] [dict get $row category] [dict get $row license]]
        require [expr {[dict get $asset sha256] eq [dict get $row sha256]}] {Actual imported source SHA differs}
        set stage public_validate
        set validated [::GX::viewerGuiIconsValidate [dict create $id $asset]]
        require [expr {[dict get $validated $id] eq $asset}] {Public validation changed the resource}
        save [file join $output admitted $id.png] [binary decode base64 [dict get $asset png]] 1
        set sizes {}
        foreach size {16 24 32 48} {
            budget;set stage public_photo_$size
            # Existing trusted photo CLI owns PNG validation/resizing, with no
            # Tk image creation and no caller codec, renderer or callback.
            set response [exec $python -I -B [file join $framework core python gxtxt_viewer_icons.py] photo $size $magick << $asset]
            require [dict get $response ok] {Public photo operation failed}
            set relative [file join sizes $id-$size.png]
            save [file join $output $relative] [binary decode base64 [dict get $response result png]] 1
            dict set sizes $size $relative
        }
        set record $row
        foreach key {png_sha256 width height alpha} {dict set record admitted_$key [dict get $asset $key]}
        dict set record admitted_png [file join admitted $id.png]
        dict set record sizes $sizes
        dict set result $id $record
        unset asset validated response
    }
    require [expr {[lsort [dict keys $categories]] eq {{Data, Plots & Analysis} {Documents & Workflow} {Geometry & Editing} {Scientific Tools & Simulation} {Selection & Navigation}}}] {Actual five families differ}
    dict for {category count} $categories {require [expr {$count==20}] {Actual family count differs from20}}
    set stage complete;set current {}
    require [expr {[package provide Tk] eq {} && [llength [info commands ::winfo]]==0}] {Tk was not authorized}
    save [file join $output PUBLIC_ADMISSION.tcldict] [dict create schema gx210.icon_public_admission.v1 status PUBLIC_ADMISSION_COMPLETE count 100 category_counts $categories icons $result visual_review NOT_REVIEWED GUI NOT_TESTED]
    puts {status PUBLIC_ADMISSION_COMPLETE count100 visual_review NOT_REVIEWED GUI NOT_TESTED}
}
if {[catch {::GX210IconAdmission::run $argv} message options]} {
    # No errorInfo/full admitted/base64 resource is logged. Preserve bounded
    # literal owner diagnostic, current ID/stage and actual Tcl error code only.
    if {[string bytelength $message]>1024} {set message {Owner diagnostic exceeds1024bytes; full resource output suppressed}}
    if {[llength $argv]>=2} {
        catch {::GX210IconAdmission::save [file join [lindex $argv 1] DRIVER_FAILURE.tcldict] [dict create status FAILED stage $::GX210IconAdmission::stage id $::GX210IconAdmission::current message $message errorcode [dict get $options -errorcode]]}
    }
    puts stderr {Icon qualification stopped at first failure; see bounded driver receipt}
    exit 1
}
