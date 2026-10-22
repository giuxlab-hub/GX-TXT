# Focused error-boundary tests with explicit service doubles. NOT GUI acceptance.
lassign $argv root
namespace eval ::GX {variable ui;variable moduleOrder {provider consumer};variable flags {provider 0 consumer 0};variable mode ok;variable choice cancel;variable calls 0;variable notices {}}
source [file join $root app modules_page_controller.tcl]
source [file join $root app gui modules_page.tcl]
rename ::GX::refreshModuleCatalog ::GX::refreshModuleCatalog_real
proc ::GX::refreshModuleCatalog {} {dict for {id value} $::GX::flags {set ::GX::ui(moduleQuick,$id) $value}}
proc ::GX::moduleField {id field {fallback {}}} {if {$field eq {name}} {return $id};if {$field eq {depends} && $id eq {consumer}} {return provider};return $fallback}
proc ::GX::moduleIsAlwaysAvailable {id} {expr {$id eq {locked}}}
proc ::GX::moduleIsEnabled {id} {if {$id eq {locked}} {return 1};return [dict get $::GX::flags $id]}
proc ::GX::moduleOperationalState {id} {if {$id eq {locked}} {return ALWAYS};return [expr {[moduleIsEnabled $id]?{ON}:{OFF}}]}
proc ::GX::splitList {value} {return $value}
proc ::GX::pluginRuntimeInfo {id} {return [dict create status $::runtimeStatus]}
proc ::GX::moduleSetEnabled {id state} {incr ::GX::calls;if {$::GX::mode eq {reject}} {error {Owner rejected activation}};dict set ::GX::flags $id $state;if {$id eq {consumer} && $state} {dict set ::GX::flags provider 1}}
proc ::GX::rebuildNativeAnalysisGui {} {if {$::GX::mode eq {refresh_error}} {error {Refresh fault}}}
proc ::GX::refreshAnalysisStatus {} {}
proc ::GX::refreshManifestPreview {} {}
proc tk_messageBox {args} {lappend ::GX::notices $args;return $::GX::choice}
proc check {expression message} {if {![uplevel 1 [list expr $expression]]} {error $message};puts "PASS $message"}
set ::GX::ui(moduleQuick,consumer) 1
::GX::moduleCardToggle consumer
check {$::GX::calls==0 && $::GX::flags eq {provider 0 consumer 0} && !$::GX::ui(moduleQuick,consumer)} {Cancel performs no owner mutation and restores switch}
check {[string match {Cancelled.*} $::GX::ui(moduleFeedback)]} {Cancel is explicit}
set ::GX::choice ok;set ::GX::mode reject;set ::GX::ui(moduleQuick,consumer) 1
::GX::moduleCardToggle consumer
check {!$::GX::ui(moduleQuick,consumer) && [string match {Activation failed.*OFF*Owner rejected*} $::GX::ui(moduleFeedback)]} {Owner rejection projects actual OFF and reason}
set ::GX::mode refresh_error;set ::GX::ui(moduleQuick,consumer) 1
::GX::moduleCardToggle consumer
check {$::GX::ui(moduleQuick,consumer) && [string match {*consumer: ON*provider: ON*Display refresh failed*} $::GX::ui(moduleFeedback)]} {Display error preserves truthful committed ON and dependency changes}
set count $::GX::calls;set ::GX::ui(moduleQuick,locked) 0
::GX::moduleCardToggle locked
check {$::GX::calls==$count && [string match {*ALWAYS*always available*} $::GX::ui(moduleFeedback)]} {Locked handler guard rejects mutation}
set ::runtimeStatus {Updated — restart required}
check {[::GX::moduleCardStateText consumer] eq "ON\nRestart required"} {Public pending-update status remains distinct from ON}
set ::runtimeStatus Available
check {[::GX::moduleCardStateText locked] eq {Always available}} {Normal locked state remains explicit}
puts {Service doubles only; real GUI and canonical integration are tested separately.}
