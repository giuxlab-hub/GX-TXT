# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::EXP01RegistryTrace {variable total 0;variable groups {};variable samples {}}
proc ::EXP01RegistryTrace::record {command op} {
 variable total;variable groups;variable samples;incr total
 set group {};set chain {}
 for {set i 2} {$i<=9} {incr i} {
  if {[catch {info frame -$i} row]} break
  set item {}
  foreach key {proc method class file line} {if {[dict exists $row $key]} {dict set item $key [dict get $row $key]}}
  lappend group [dict remove $item file line]
  if {[dict exists $row cmd]} {dict set item cmd [string range [dict get $row cmd] 0 180]}
  lappend chain $item
 }
 if {![dict exists $groups $group] && [dict size $groups]>=64} {set group @other}
 dict incr groups $group
 if {![dict exists $samples $group]} {dict set samples $group $chain}
}
proc ::EXP01RegistryTrace::start {} {set ::EXP01RegistryTrace::total 0;set ::EXP01RegistryTrace::groups {};set ::EXP01RegistryTrace::samples {};trace add execution ::GX::_interactiveDocumentRegistryRead enter ::EXP01RegistryTrace::record}
proc ::EXP01RegistryTrace::stop {} {trace remove execution ::GX::_interactiveDocumentRegistryRead enter ::EXP01RegistryTrace::record;return [dict create total $::EXP01RegistryTrace::total groups $::EXP01RegistryTrace::groups samples $::EXP01RegistryTrace::samples truncated 0]}
