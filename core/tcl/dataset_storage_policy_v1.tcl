# GX-TXT CORE Storage Auto and Dataset materialization extension
# SPDX-License-Identifier: GPL-3.0-or-later
# Extends Canonical Dataset API v2 and Dataset Publication API v2.
namespace eval ::GX {variable datasetStoragePolicyVersion 1; variable datasetMaterializationFormatVersion 1; variable datasetMaterializationChunkRows 4096; variable datasetMaterializationCounter 0}
proc ::GX::datasetStorageRequirementNames {} {return {read_full read_selected_variables chunk_read chunk_write row_range_read range_write random_access append_write hyperslab_read hyperslab_write multidimensional groups implicit_axis complete_variable typed_numeric sequential_chunks}}
proc ::GX::datasetStoragePreferenceNames {} {return {compact_numeric human_readable fast_sequential random_access compression}}
proc ::GX::datasetStoragePolicyProviderCapabilities {p mode} {
 variable datasetStorageProviderCommand; variable datasetWriterProviderCommand
 set p [string tolower [string trim $p]]; set out [dict create]
 foreach n [concat [datasetStorageRequirementNames] [datasetStoragePreferenceNames]] {dict set out $n 0}
 if {$mode in {read access}} {if {![info exists datasetStorageProviderCommand($p)]} {error "Dataset storage provider '$p' is unavailable for reading"}; dict for {n v} [datasetStorageProviderCapabilities $p] {if {[dict exists $out $n]} {dict set out $n $v}}}
 if {$mode in {write access}} {if {![info exists datasetWriterProviderCommand($p)]} {error "Dataset storage provider '$p' is unavailable for writing"}; set w [datasetWriterProviderCapabilities $p]; dict for {n v} $w {if {[dict exists $out $n]} {dict set out $n $v}}; dict set out chunk_write [dict get $w sequential_chunks]}
 if {$p eq "csv"} {dict set out human_readable 1; dict set out fast_sequential 1}
 if {$p eq "hdf5"} {dict set out compact_numeric 1; dict set out fast_sequential 1; dict set out random_access 1}
 return $out
}
proc ::GX::datasetStoragePolicyProviders {mode} {
 variable datasetStorageProviderCommand; variable datasetWriterProviderCommand; set ids {}
 if {$mode eq "read"} {set ids [array names datasetStorageProviderCommand]} elseif {$mode eq "write"} {set ids [array names datasetWriterProviderCommand]} elseif {$mode eq "access"} {foreach p [array names datasetStorageProviderCommand] {if {[info exists datasetWriterProviderCommand($p)]} {lappend ids $p}}} else {error "Storage policy mode must be read, write, or access"}
 set out {}; foreach p {csv hdf5} {if {$p in $ids} {lappend out $p}}; foreach p [lsort $ids] {if {$p ni $out} {lappend out $p}}; return $out
}
proc ::GX::datasetStoragePolicyValidate {required preferred} {foreach n $required {if {$n ni [datasetStorageRequirementNames]} {error "Unknown storage requirement: $n"}}; foreach n $preferred {if {$n ni [concat [datasetStoragePreferenceNames] [datasetStorageRequirementNames]]} {error "Unknown storage preference: $n"}}}
proc ::GX::datasetStoragePolicySelect {mode request required preferred} {
 set request [string tolower [string trim $request]]; if {$request eq ""} {set request auto}; datasetStoragePolicyValidate $required $preferred; set ps [datasetStoragePolicyProviders $mode]
 if {$request ne "auto"} {if {$request ni $ps} {error "Requested dataset storage provider '$request' is unavailable for $mode"}; set ps [list $request]}
 set valid {}; set rejected [dict create]
 foreach p $ps {set caps [datasetStoragePolicyProviderCapabilities $p $mode]; set missing {}; foreach n $required {if {![dict get $caps $n]} {lappend missing $n}}; if {[llength $missing]} {dict set rejected $p $missing; continue}; set score 0; foreach n $preferred {if {[dict get $caps $n]} {incr score}}; lappend valid [list $p $score]}
 if {![llength $valid]} {set d {}; dict for {p m} $rejected {lappend d "$p missing [join $m ,]"}; error "No dataset storage provider satisfies required capabilities: [join $required {, }] ([join $d {; }])"}
 set best [lindex $valid 0]; foreach c [lrange $valid 1 end] {if {[lindex $c 1]>[lindex $best 1]} {set best $c}}; lassign $best provider score
 set r {}; dict for {p m} $rejected {lappend r "${p}([join $m ,])"}
 if {$request eq "auto"} {set reason "auto policy v1 selected $provider; required capabilities satisfied; preferred score $score"; if {[llength $r]} {append reason "; rejected [join $r {; }]"}} else {set reason "explicit $request request validated; required capabilities satisfied"}
 return [dict create requested $request provider $provider reason $reason required $required preferred $preferred preferred_score $score rejected $rejected policy_version 1]
}
proc ::GX::datasetPublicationV2SelectProvider {request required preferred {hints {}}} {
 set rows [datasetPublicationV2DictDefault $hints expected_rows -1]
 set bytes [datasetPublicationV2DictDefault $hints estimated_numeric_bytes -1]
 foreach {name value} [list expected_rows $rows estimated_numeric_bytes $bytes] {
  if {![string is entier -strict $value] || $value < -1} {error "$name must be -1 (unknown) or a nonnegative integer"}
 }
 set requested [string tolower [string trim $request]]
 set sizeReason "explicit storage request"
 if {$requested in {"" auto}} {
  # One deterministic CORE policy: small known tables prefer human-readable CSV;
  # large or unknown-size streams prefer a compact append-capable provider.
  set large [expr {$rows>=100000 || $bytes>=8388608 || ($rows<0 && $bytes<0)}]
  if {$large} {
   set preferred [concat {compact_numeric append_write} $preferred]
   set sizeReason [expr {$rows<0 && $bytes<0 ? "unknown logical size prefers bounded binary append" : "logical size exceeds 100000 rows or 8 MiB"}]
  } else {set preferred [concat {human_readable} $preferred];set sizeReason "known small logical table"}
 }
 set effective $request
 if {$requested in {"" auto}} {
  set candidate [expr {$large ? "hdf5" : "csv"}]
  if {![catch {datasetStoragePolicySelect write $candidate $required $preferred}]} {set effective $candidate}
 }
 if {[catch {set s [datasetStoragePolicySelect write $effective $required $preferred]} e o]} {
  if {$requested ne "" && $requested ne "auto" && [string match {*is unavailable for write} $e]} {error "Requested dataset writer backend '$requested' is unavailable"}
  return -options $o $e
 }
 if {$requested in {"" auto}} {dict set s requested auto;dict set s reason "auto selected [dict get $s provider]; required capabilities satisfied"}
 dict set s size_policy_version 2
 dict set s expected_rows $rows
 dict set s estimated_numeric_bytes $bytes
 dict set s size_reason $sizeReason
 return [dict create provider [dict get $s provider] reason "[dict get $s reason]; size policy v2: $sizeReason" diagnostics $s]
}
proc ::GX::datasetStorageSha256Text {session value} {set root [file join [file normalize $session] cache dataset_materializations]; file mkdir $root; set tmp [file join $root ".identity.[pid].[clock clicks].tmp"]; set f [open $tmp w]; fconfigure $f -encoding utf-8 -translation lf; puts -nonewline $f $value; close $f; try {return [sha256File $tmp]} finally {catch {file delete -force -- $tmp}}}
proc ::GX::datasetStorageSha256Bytes {session bytes} {
    set root [file join [file normalize $session] cache dataset_materializations];file mkdir $root
    set path [file join $root .binary-identity.[pid].[clock clicks].tmp]
    set f [open $path {WRONLY CREAT EXCL}]
    try {fconfigure $f -translation binary -encoding binary;puts -nonewline $f $bytes;close $f;set f {};return [sha256File $path]} finally {if {$f ne {}} {close $f};file delete -force $path}
}
proc ::GX::datasetStorageSchemaIdentity {session id} {variable currentSession; set currentSession [file normalize $session]; loadDatasetRegistry $currentSession; set lines [list "dataset_id=$id" "schema_api=[datasetField $id variable_schema_api_version 3]"]; set fields {variable_id canonical unit semantic_role value_kind dtype rank shape dimension_ids coordinate_variable_ids coordinate_role axis_kind axis_origin axis_step axis_count component_ids group_id}; foreach v [datasetVariableSchemaV3 $id] {foreach f $fields {lappend lines "$f=[dict get $v $f]"}; lappend lines --}; return [datasetStorageSha256Text $session [join $lines "\n"]]}
proc ::GX::datasetStorageTableDescription {session id {target ""}} {
 variable currentSession; set currentSession [file normalize $session]; loadDatasetRegistry $currentSession; if {[datasetField $id id ""] eq ""} {error "Unknown dataset: $id"}; set vars [datasetVariableSchemaV3 $id]; if {![llength $vars]} {error "Dataset $id has no variables"}; set dim ""; set count -1; set ids {}
 foreach v $vars {set vid [dict get $v variable_id]; lappend ids $vid; if {[dict get $v rank]!=1} {error "Dataset $id is not losslessly table-shaped: variable $vid has rank [dict get $v rank]"}; set ds [datasetSchemaV3SplitIds [dict get $v dimension_ids]]; set sh [datasetSchemaV3SplitIds [dict get $v shape]]; if {[llength $ds]!=1 || [llength $sh]!=1} {error "Dataset $id is not losslessly table-shaped"}; if {$dim eq ""} {set dim [lindex $ds 0]}; if {[lindex $ds 0] ne $dim} {error "Dataset $id is not losslessly table-shaped: variables use different dimensions"}; set n [lindex $sh 0]; if {![string is integer -strict $n] || $n<0} {error "Dataset $id has an unknown table row count"}; if {$count<0} {set count $n}; if {$n!=$count} {error "Dataset $id is not losslessly table-shaped: variable row counts differ"}; if {$target eq "csv" && [dict get $v group_id] ne ""} {error "Dataset $id has grouped structure and no explicit lossless flat-table view"}}
 return [dict create dataset_id $id row_dimension $dim row_count $count variables $vars variable_ids $ids]
}
proc ::GX::datasetStorageSourceState {session id target options} {
 variable datasetStoragePolicyVersion; variable datasetMaterializationFormatVersion; variable datasetWriterProviderVersion; set session [file normalize $session]; set source [datasetResolvePath $session $id]
 if {$source eq "" || ![file isfile $source]} {error "Dataset $id has no readable authoritative storage object"}; if {![info exists datasetWriterProviderVersion($target)]} {error "Dataset writer provider '$target' is unavailable"}
 set actual [sha256File $source]; set declared [datasetField $id canonical_sha256 [datasetField $id sha256 ""]]; if {$declared eq ""} {set declared $actual}; set schema [datasetStorageSchemaIdentity $session $id]; set chunk [expr {[dict exists $options chunk_rows]?[dict get $options chunk_rows]:$::GX::datasetMaterializationChunkRows}]; if {![string is integer -strict $chunk] || $chunk<1} {error "Materialization chunk_rows must be an integer >= 1"}; set pv $datasetWriterProviderVersion($target); set params "table-v1;chunk_rows=$chunk"
 set identity [join [list "dataset_id=$id" "source_actual_sha256=$actual" "source_declared_sha256=$declared" "schema_sha256=$schema" "target_provider=$target" "provider_format_version=$pv" "materialization_format_version=$datasetMaterializationFormatVersion" "policy_version=$datasetStoragePolicyVersion" "parameters=$params"] "\n"]; set key [datasetStorageSha256Text $session $identity]
 return [dict create dataset_id $id source_path $source source_actual_sha256 $actual source_declared_sha256 $declared schema_sha256 $schema target_provider $target provider_format_version $pv materialization_format_version $datasetMaterializationFormatVersion policy_version $datasetStoragePolicyVersion parameters $params chunk_rows $chunk cache_key $key identity $identity]
}
proc ::GX::datasetStorageCacheRoot {session} {return [file join [file normalize $session] cache dataset_materializations]}
proc ::GX::datasetStorageCachePaths {session state} {set root [datasetStorageCacheRoot $session]; set key [dict get $state cache_key]; set dir [file join $root $key]; set ext [expr {[dict get $state target_provider] eq "hdf5"?"h5":"csv"}]; return [dict create root $root directory $dir data [file join $dir "representation.$ext"] metadata [file join $dir metadata.tcl] lock [file join $root "$key.lock"]]}
proc ::GX::datasetStorageMetadataRead {path} {if {![file isfile $path]} {error "Materialization metadata is missing"}; set f [open $path r]; set raw [read $f]; close $f; set m [lindex $raw 0]; if {[catch {dict size $m}]} {error "Materialization metadata is invalid"}; return $m}
proc ::GX::datasetAccessOpenRepresentation {session id provider path} {variable currentSession; variable datasetAccessHandle; variable datasetAccessCounter; variable datasetStorageProviderCommand; set session [file normalize $session]; set path [file normalize $path]; set currentSession $session; loadDatasetRegistry $session; if {![file isfile $path]} {error "Dataset representation is missing: $path"}; set token [uplevel #0 [list {*}$datasetStorageProviderCommand($provider) open {} [dict create session $session dataset_id $id path $path representation 1]]]; set h "dataset#[incr datasetAccessCounter]"; foreach {k v} [list dataset_id $id session $session provider $provider provider_token $token metadata "" path $path is_representation 1] {set datasetAccessHandle($h,$k) $v}; return $h}
proc ::GX::datasetStorageCacheValidate {session state paths} {
 set dir [dict get $paths directory]; set data [dict get $paths data]; set mp [dict get $paths metadata]; if {![file isdirectory $dir] || ![file isfile $data] || ![file isfile $mp]} {return [dict create valid 0 reason "cache files are missing"]}; if {[catch {set m [datasetStorageMetadataRead $mp]} e]} {return [dict create valid 0 reason $e]}
 foreach f {cache_key source_actual_sha256 source_declared_sha256 schema_sha256 target_provider provider_format_version materialization_format_version policy_version parameters} {if {![dict exists $m $f] || [dict get $m $f] ne [dict get $state $f]} {return [dict create valid 0 reason "cache metadata mismatch: $f"]}}
 if {![dict exists $m representation_sha256] || [catch {set a [sha256File $data]}] || $a ne [dict get $m representation_sha256]} {return [dict create valid 0 reason "cache representation hash mismatch"]}
 if {[dict get $state target_provider] eq "hdf5"} {set h ""; if {[catch {set h [datasetAccessOpenRepresentation $session [dict get $state dataset_id] hdf5 $data]; datasetAccessMetadata $h} e]} {if {$h ne ""} {catch {datasetAccessClose $h}}; return [dict create valid 0 reason "invalid HDF5 representation: $e"]}; datasetAccessClose $h}
 return [dict create valid 1 reason "cache identity and integrity verified" metadata $m]
}
proc ::GX::datasetStorageWriterOpen {p temp id} {variable datasetWriterProviderCommand; variable datasetPublicationWriter; variable datasetMaterializationCounter; set token [uplevel #0 [list {*}$datasetWriterProviderCommand($p) open {} [dict create temp_path $temp dataset_id $id contract representation.cache]]]; set w "materialization-writer#[incr datasetMaterializationCounter]"; foreach {k v} [list status open provider $p provider_token $token temp_path $temp dimension_ids {} variable_ids {}] {set datasetPublicationWriter($w,$k) $v}; return $w}
proc ::GX::datasetStorageWriterDiscard {w} {variable datasetPublicationWriter; variable datasetWriterProviderCommand; if {![info exists datasetPublicationWriter($w,status)]} {return}; set p $datasetPublicationWriter($w,provider); set token $datasetPublicationWriter($w,provider_token); catch {uplevel #0 [list {*}$datasetWriterProviderCommand($p) abort $token]}; foreach n [array names datasetPublicationWriter "$w,*"] {unset datasetPublicationWriter($n)}}
proc ::GX::datasetStorageWriterFinish {w} {variable datasetPublicationWriter; variable datasetWriterProviderCommand; datasetPublicationV2RequireWriter $w; set p $datasetPublicationWriter($w,provider); set token $datasetPublicationWriter($w,provider_token); set r [uplevel #0 [list {*}$datasetWriterProviderCommand($p) finalize $token]]; foreach n [array names datasetPublicationWriter "$w,*"] {unset datasetPublicationWriter($n)}; return $r}
proc ::GX::datasetStorageVariableSpec {v} {set s [dict create name [dict get $v canonical]]; foreach f {dtype rank shape dimension_ids coordinate_variable_ids coordinate_role axis_kind axis_origin axis_step component_ids group_id unit semantic_role} {dict set s $f [dict get $v $f]}; return $s}
proc ::GX::datasetStorageBuildTableRepresentation {session id target temp chunk} {
 set table [datasetStorageTableDescription $session $id $target]; set dim [dict get $table row_dimension]; set total [dict get $table row_count]; set vars [dict get $table variables]; set ids [dict get $table variable_ids]; set w ""; set stream ""; set chunks 0; set rows 0; set max 0
 try {set w [datasetStorageWriterOpen $target $temp $id]; if {$target eq "csv"} {datasetPublicationV2DeclareDimension $w $dim 0 [dict create extendible 1]} else {datasetPublicationV2DeclareDimension $w $dim $total}; foreach v $vars {set s [datasetStorageVariableSpec $v]; if {$target eq "csv"} {dict set s shape 0}; datasetPublicationV2DeclareVariable $w [dict get $v variable_id] $s}; set stream [tableStreamOpenDataset $session $id $ids $chunk]
  while 1 {set c [tableStreamNext $stream]; set n [dict get $c nrows]; if {$n>0} {set values [dict get $c values]; if {$target eq "csv"} {datasetPublicationV2Append $w $dim $values} else {dict for {vid column} $values {set v [datasetVariableV3ById $id $vid]; if {[dict get $v axis_kind] ne "uniform"} {datasetPublicationV2WriteRange $w $vid [dict get $c offset] $column}}}; incr chunks; incr rows $n; set e [expr {$n*[llength $ids]}]; if {$e>$max} {set max $e}}; if {[dict get $c eof]} break}
  set sd [tableStreamDiagnostics $stream]; tableStreamClose $stream; set stream ""; set wd [datasetPublicationV2Diagnostics $w]; set pf [datasetStorageWriterFinish $w]; set w ""; return [dict create chunks $chunks rows $rows max_chunk_elements $max stream $sd writer $wd provider_finalize $pf]
 } finally {if {$stream ne ""} {catch {tableStreamClose $stream}}; if {$w ne ""} {catch {datasetStorageWriterDiscard $w}}}
}
proc ::GX::datasetStorageAcquireLock {path} {for {set i 0} {$i<100} {incr i} {if {![catch {file mkdir $path}]} {set f [open [file join $path owner] w]; puts $f "[pid] [clock seconds]"; close $f; return}; if {[file isdirectory $path] && [clock seconds]-[file mtime $path]>300} {catch {file delete -force -- $path}; continue}; after 50}; error "Timed out waiting for materialization cache builder lock"}
proc ::GX::datasetStorageMaterialize {session id target {options {}}} {
 set session [file normalize $session]; set target [string tolower [string trim $target]]; set state [datasetStorageSourceState $session $id $target $options]; datasetStorageTableDescription $session $id $target; set paths [datasetStorageCachePaths $session $state]; file mkdir [dict get $paths root]; set valid [datasetStorageCacheValidate $session $state $paths]
 if {[dict get $valid valid]} {return [dict create dataset_id $id provider $target path [dict get $paths data] cache_key [dict get $state cache_key] reused 1 created 0 metadata [dict get $valid metadata]]}; datasetStorageAcquireLock [dict get $paths lock]
 try {set valid [datasetStorageCacheValidate $session $state $paths]; if {[dict get $valid valid]} {return [dict create dataset_id $id provider $target path [dict get $paths data] cache_key [dict get $state cache_key] reused 1 created 0 metadata [dict get $valid metadata]]}; if {[file exists [dict get $paths directory]]} {file delete -force -- [dict get $paths directory]}; set stage "[dict get $paths directory].partial.[pid].[clock clicks]"; file mkdir $stage; set ext [expr {$target eq "hdf5"?"h5":"csv"}]; set data [file join $stage "representation.$ext"]
  if {[catch {set build [datasetStorageBuildTableRepresentation $session $id $target $data [dict get $state chunk_rows]]; set hash [sha256File $data]; if {$target eq "hdf5"} {set h [datasetAccessOpenRepresentation $session $id hdf5 $data]; try {datasetAccessMetadata $h} finally {datasetAccessClose $h}}; set m [dict merge $state [dict create representation_relative [file join cache dataset_materializations [dict get $state cache_key] "representation.$ext"] representation_sha256 $hash created_at [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S%z"] build_diagnostics $build scientific_dataset_id $id storage_object_id [dict get $state cache_key]]]; set f [open [file join $stage metadata.tcl] w]; puts $f [list $m]; close $f; file rename -- $stage [dict get $paths directory]} e o]} {catch {file delete -force -- $stage}; return -options $o "Dataset materialization failed: $e"}
  set valid [datasetStorageCacheValidate $session $state $paths]; if {![dict get $valid valid]} {file delete -force -- [dict get $paths directory]; error "Dataset materialization failed post-placement validation: [dict get $valid reason]"}; return [dict create dataset_id $id provider $target path [dict get $paths data] cache_key [dict get $state cache_key] reused 0 created 1 metadata [dict get $valid metadata]]
 } finally {catch {file delete -force -- [dict get $paths lock]}}
}
proc ::GX::datasetStorageCapabilitiesSatisfy {p required} {set caps [datasetStoragePolicyProviderCapabilities $p read]; foreach n $required {if {![dict get $caps $n]} {return 0}}; return 1}
proc ::GX::datasetAccessRequest {session id request} {
 variable currentSession; variable datasetAccessHandle; set session [file normalize $session]; set currentSession $session; loadDatasetRegistry $session; if {[datasetField $id id ""] eq ""} {error "Unknown dataset: $id"}; set required [expr {[dict exists $request capabilities_required]?[dict get $request capabilities_required]:{}}]; if {[dict exists $request characteristics_preferred]} {set preferred [dict get $request characteristics_preferred]} elseif {[dict exists $request capabilities_preferred]} {set preferred [dict get $request capabilities_preferred]} else {set preferred {}}; set requested [expr {[dict exists $request storage]?[string tolower [string trim [dict get $request storage]]]:"auto"}]; if {$requested eq ""} {set requested auto}; datasetStoragePolicyValidate $required $preferred; set active [datasetProviderFor $id]
 if {[datasetStorageCapabilitiesSatisfy $active $required] && ($requested eq "auto" || $requested eq $active)} {set h [datasetAccessOpen $session $id]; set path [datasetResolvePath $session $id]; set datasetAccessHandle($h,path) $path; set datasetAccessHandle($h,is_representation) 0; set datasetAccessHandle($h,storage_diagnostics) [dict create requested_storage $requested effective_provider $active selection_reason "active $active representation already satisfies required capabilities; materialization avoided" required $required preferred $preferred materialization_required 0 cache_reused 0 compatibility_materialization 0 source_dataset_id $id source_sha256 [sha256File $path]]; return $h}
 set selection [datasetStoragePolicySelect access $requested $required $preferred]; set p [dict get $selection provider]; if {$p eq $active} {error "Active $active representation does not satisfy required capabilities: [join $required {, }]"}; set mat [datasetStorageMaterialize $session $id $p $request]; set h [datasetAccessOpenRepresentation $session $id $p [dict get $mat path]]; set m [dict get $mat metadata]; set datasetAccessHandle($h,storage_diagnostics) [dict create requested_storage $requested effective_provider $p selection_reason [dict get $selection reason] required $required preferred $preferred materialization_required 1 cache_reused [dict get $mat reused] cache_key [dict get $mat cache_key] compatibility_materialization [expr {$p eq "csv" && $active ne "csv"}] source_dataset_id $id source_sha256 [dict get $m source_actual_sha256] source_schema_sha256 [dict get $m schema_sha256] representation_sha256 [dict get $m representation_sha256] materialization_policy_version [dict get $m policy_version]]; return $h
}
proc ::GX::datasetAccessDiagnostics {h} {variable datasetAccessHandle; set p [datasetAccessDiagnostics_before_storage_policy $h]; set provider [dict get [datasetAccessMetadata $h] storage_provider]; set s [dict create requested_storage $provider effective_provider $provider selection_reason "canonical representation opened directly" materialization_required 0 cache_reused 0 compatibility_materialization 0]; if {[info exists datasetAccessHandle($h,storage_diagnostics)]} {set s $datasetAccessHandle($h,storage_diagnostics)}; return [dict merge $p [dict create storage $s]]}
proc ::GX::datasetCompatibilityCsv {session id {options {}}} {dict set options storage csv; dict set options capabilities_required {chunk_read row_range_read}; set h [datasetAccessRequest $session $id $options]; try {return [dict create dataset_id $id path $::GX::datasetAccessHandle($h,path) diagnostics [dict get [datasetAccessDiagnostics $h] storage]]} finally {datasetAccessClose $h}}
proc ::GX::datasetMaterializationCacheDelete {session {key ""}} {set root [datasetStorageCacheRoot $session]; if {$key eq ""} {if {[file exists $root]} {file delete -force -- $root}; return}; if {![regexp {^[0-9a-f]{64}$} $key]} {error "Invalid materialization cache key"}; catch {file delete -force -- [file join $root $key]}}
