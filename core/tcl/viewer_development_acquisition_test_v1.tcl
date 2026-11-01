# SPDX-License-Identifier: GPL-3.0-or-later
# Shared host presentation for the existing Development Test request.
namespace eval ::GX::AcquisitionProjectTest {variable dialogs {};variable serial 0}
proc ::GX::viewerDevelopmentAcquisitionTestChoose {parent description initialProfile valid callback} {
    variable ::GX::AcquisitionProjectTest::dialogs;variable ::GX::AcquisitionProjectTest::serial
    if {![{*}$valid]} {error {Project context changed; refresh before Test}}
    set profiles {};foreach profile [dict get $description formats] {lappend profiles [dict get $profile id]}
    if {![llength $profiles]} {error {Save at least one format profile before Test}}
    if {$initialProfile ni $profiles} {set initialProfile [lindex $profiles 0]}
    set sources [tk_getOpenFile -parent $parent -title {Choose source files for project Test; outputs will be discarded} -multiple 1]
    if {$sources eq {}} {return {}}
    if {![{*}$valid]} {error {Project context changed during source selection}}
    if {[llength $sources]>64 || [llength $sources]!=[llength [lsort -unique $sources]]} {error {Choose1..64 unique source files}}
    set fields [dict create format_profile [dict create type choice label {Saved format profile} values $profiles required 1]]
    set initial [dict create format_profile $initialProfile]
    foreach field [dict get $description config_fields] {
        set key [dict get $field id];set descriptor [dict remove $field id default]
        if {[dict get $field type] eq {integer}} {
            if {![dict exists $descriptor min]} {dict set descriptor min -9223372036854775808}
            if {![dict exists $descriptor max]} {dict set descriptor max 9223372036854775807}
        }
        dict set fields $key $descriptor
        dict set initial $key [dict get $field default]
    }
    set w .gxAcquisitionProjectTest[incr serial]
    dict set dialogs $w [dict create description $description valid $valid callback $callback sources $sources]
    uiFieldFormCreate $w {Acquisition project Test} $fields $initial [list ::GX::_viewerDevelopmentAcquisitionTestApply $w] $parent
    $w.actions.apply configure -text {Run Test}
    set ::GX::UiField::formStatus($w) "[llength $sources] explicitly selected source files. Test uses the compiled candidate and discards outputs; no module installation, Session or Dataset publication. Configuration here applies only to this Test."
    bind $w <Destroy> +[list ::GX::_viewerDevelopmentAcquisitionTestDestroyed $w %W]
    return $w
}
proc ::GX::_viewerDevelopmentAcquisitionTestDestroyed {window actual} {
    if {$window eq $actual && [dict exists $::GX::AcquisitionProjectTest::dialogs $window]} {dict unset ::GX::AcquisitionProjectTest::dialogs $window}
}
proc ::GX::_viewerDevelopmentAcquisitionTestApply {window values} {
    set dialog [dict get $::GX::AcquisitionProjectTest::dialogs $window]
    if {![{*}[dict get $dialog valid]]} {error {Test belongs to an earlier project context; choose the files again}}
    set config {}
    foreach field [dict get $dialog description config_fields] {
        set key [dict get $field id];set kind [dict get $field type]
        set value [dict get $values $key]
        if {$kind eq {integer}} {set value [_acquisitionNativeConfigInt64 $value]}
        set kind [expr {$kind eq {integer}?{int}:($kind eq {boolean}?{bool}:($kind in {number double}?{real}:{text}))}]
        dict set config $key [list $kind $value]
    }
    set profile [dict get $values format_profile]
    set paths [lmap path [dict get $dialog sources] {list text $path}]
    set request [list object [dict create schema {text gxtxt.acquisition_project_test.v1} expected_revision [list text [dict get $dialog description revision]] profile_id [list text $profile] sources [list array $paths] config [list object $config]]]
    {*}[dict get $dialog callback] $profile [nativeWorkspaceJsonEncode $request]
    destroy $window
}
