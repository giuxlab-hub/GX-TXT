#!/usr/bin/env tclsh
fconfigure stdout -buffering none -translation lf -encoding utf-8
set root [file normalize [file join [file dirname [info script]] .. ..]]; set argv0 __not_main__; source [file join $root gxtxt_pipeline.tcl]; ::GX::defaults
proc enc x {::GX::datasetB64Encode $x}; proc dec x {::GX::datasetB64Decode $x}
proc emitError x {puts "ERROR\t[enc $x]"; flush stdout}
proc vals x {set out {}; if {$x eq ""} {return $out}; foreach v [split $x ,] {lappend out [dec $v]}; return $out}
proc block {kind dtype endian shape payload} {
 set kind [string toupper $kind]
 if {$kind eq "BINARY"} {return [dict create __gxtxt_binary_block 1 dtype [string tolower $dtype] endian [string tolower $endian] shape $shape base64 $payload]}
 if {$kind eq "RESOURCE"} {
  if {$::resourceScope eq ""} {error {Managed publication resources were not negotiated}}
  lassign [split [dec $payload] |] version order id resourceShape count bytes
  set r [dict create version $version order $order dtype $dtype endian $endian resource_id $id shape $resourceShape count $count byte_count $bytes resource_root $::resourceScope]
  ::GX::datasetBinaryResourceValidate $r
  lappend ::requestResources [file join $::resourceScope $id]
  return [dict create __gxtxt_binary_resource 1 shape $shape resource $r]
 }
 if {$kind eq "TEXT"} {
  # A scalar empty string has an empty Base64 payload. Its declared shape
  # distinguishes it from a zero-length text array.
  if {$payload eq "" && [::GX::datasetPublicationV2ElementCount [::GX::datasetPublicationV2Shape $shape]] == 1} {
   return [list ""]
  }
  return [vals $payload]
 }
 error "Unknown Publication v2 transport block '$kind'"
}
set resourceScope {};set ownedResource {};set requestResources {}
if {[catch {
 if {[llength $argv] ni {7 13 14 15 16}} {error "Publication bridge requires legacy/provenance arguments and optional metadata/managed transport negotiation"}
 lassign [lrange $argv 0 6] session module id contract storage required preferred
 set definition [dict create dataset_id $id contract $contract storage $storage capabilities_required [split $required {;}] capabilities_preferred [split $preferred {;}]]
 if {[llength $argv] >= 13} {
  lassign [lrange $argv 7 12] producerVersion sourceDatasetIds sourceVariableIds source provenance notes
  if {$producerVersion ne ""} {dict set definition producer_version $producerVersion}
  if {$sourceDatasetIds ne ""} {dict set definition source_dataset_ids [split $sourceDatasetIds {;}]}
  if {$sourceVariableIds ne ""} {dict set definition source_variable_ids [split $sourceVariableIds {;}]}
  if {$source ne ""} {dict set definition source $source}
  if {$provenance ne ""} {dict set definition provenance $provenance}
  if {$notes ne ""} {dict set definition notes $notes}
 }
 if {[llength $argv] >= 14} {dict set definition replace_owned [lindex $argv 13]}
 if {[llength $argv] >= 15 && [lindex $argv 14] ne ""} {
  set metadataPath [lindex $argv 14]
  if {![file isfile $metadataPath]||[file size $metadataPath]>16777216} {error "Invalid bounded publication metadata transport"}
  set metadataChannel [open $metadataPath r];fconfigure $metadataChannel -encoding utf-8
  try {dict set definition structured_metadata [read $metadataChannel]} finally {close $metadataChannel}
 }
 set plan [::GX::datasetPublicationV2Prepare $session $module $definition]
 if {[llength $argv]==16} {
  if {[lindex $argv 15] ne "resources_v2"} {error {Unknown publication transport negotiation}}
  if {[dict get [::GX::datasetPublicationV2PlanInfo $plan] provider] eq "hdf5"} {
   set ownedResource [::GX::resourceManagementAllocate dataset_publication [dict create kind directory session $session lifetime publication]]
   set resourceScope [dict get $ownedResource path];set ::env(GXTXT_BRIDGE_WORKSPACE) $resourceScope
  }
 }
 set writer [::GX::datasetPublicationV2OpenWriter $plan]
} e]} {
 if {$ownedResource ne ""} {catch {::GX::resourceManagementRelease [dict get $ownedResource id]};catch {::GX::resourceManagementCleanup [list [dict get $ownedResource id]]}}
 emitError $e; exit 2
}
set ready "READY\t[pid]\t[enc $plan]\t[enc $writer]\t[enc $::GX::datasetPublicationWriter($writer,provider)]"
if {[llength $argv]==16} {append ready "\t[enc $resourceScope]"}
puts $ready; flush stdout
set finished 0
try {
 while {[gets stdin line]>=0} {
  if {$line eq ""} continue; set p [split $line \t]; set op [string toupper [lindex $p 0]]
  set requestResources {}
  if {[catch {
   switch -- $op {
    DIM {puts "OK\t[enc [::GX::datasetPublicationV2DeclareDimension $writer [dec [lindex $p 1]] [lindex $p 2] [dict create extendible [lindex $p 3]]]]"}
    VAR {
     set fields {dtype dimension_ids name unit semantic_role coordinate_role axis_kind axis_origin axis_step group_id component_ids coordinate_variable_ids chunks}
     set spec [dict create]; set i 2; foreach f $fields {set v [dec [lindex $p $i]]; incr i; if {$v ne ""} {dict set spec $f $v}}
     puts "OK\t[enc [::GX::datasetPublicationV2DeclareVariable $writer [dec [lindex $p 1]] $spec]]"
    }
    UNIFORM {set spec [dict create name [dec [lindex $p 5]] unit [dec [lindex $p 6]] dtype [dec [lindex $p 7]] semantic_role [dec [lindex $p 8]]]; puts "OK\t[enc [::GX::datasetPublicationV2DeclareUniformCoordinate $writer [dec [lindex $p 1]] [dec [lindex $p 2]] [dec [lindex $p 3]] [dec [lindex $p 4]] $spec]]"}
    WRITE {::GX::datasetPublicationV2WriteVariable $writer [dec [lindex $p 1]] [block {*}[lrange $p 3 7]] [dec [lindex $p 2]]; puts OK}
    RANGE {::GX::datasetPublicationV2WriteRange $writer [dec [lindex $p 1]] [lindex $p 2] [block {*}[lrange $p 3 7]]; puts OK}
    APPEND {
     set data [dict create]; set n [lindex $p 2]; set i 3
     for {set k 0} {$k<$n} {incr k} {
      set vid [dec [lindex $p $i]]; set shape [dec [lindex $p [expr {$i+1}]]]; set value [block {*}[lrange $p [expr {$i+2}] [expr {$i+6}]]]
      if {$shape eq ""} {dict set data $vid $value} else {dict set data $vid [dict create shape $shape values $value]}; incr i 7
     }
     puts "OK\t[::GX::datasetPublicationV2Append $writer [dec [lindex $p 1]] $data]"
    }
    HYPER {::GX::datasetPublicationV2WriteHyperslab $writer [dec [lindex $p 1]] [split [dec [lindex $p 2]] {;}] [split [dec [lindex $p 3]] {;}] [block {*}[lrange $p 4 8]]; puts OK}
    FLUSH {::GX::datasetPublicationV2Flush $writer; puts OK}
    DIAG {puts "DIAG\t[enc [::GX::datasetPublicationV2Diagnostics $writer]]"}
    FINALIZE {set r [::GX::datasetPublicationV2Finalize $writer]; puts "FINAL\t[enc $r]"; set finished 1}
    ABORT {::GX::datasetPublicationV2Abort $writer; puts ABORTED; set finished 1}
    default {error "Unknown Publication bridge command '$op'"}
   }; flush stdout
  } e]} {emitError $e}
  foreach path $requestResources {if {[file exists $path] && [file type $path] eq "file"} {file delete -- $path}}
  if {$finished} break
 }
} finally {
 if {!$finished} {catch {::GX::datasetPublicationV2Abort $writer}}
 if {$ownedResource ne ""} {::GX::resourceManagementRelease [dict get $ownedResource id];::GX::resourceManagementCleanup [list [dict get $ownedResource id]]}
}
