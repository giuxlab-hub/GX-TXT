# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root output modelsFile
if {[file exists $output]} {error {Fresh private output required}}
file mkdir $output;set output [file normalize $output]
foreach {key dir} {HOME home XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache XDG_STATE_HOME state GXTXT_INSTALLATION_ROOT installation GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE buffers GXTXT_JOB_ROOT jobs TMPDIR tmp} {set ::env($key) [file join $output $dir];file mkdir $::env($key);file attributes $::env($key) -permissions 0700}
set argv0 __EXP01_QUICK_OPEN_CONTRACT__;source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
::GX::configurationSet storage.session_root [file join $output Sessions]
::GX::configurationSet storage.temp_dir [file join $output tmp]
::GX::configurationSet storage.cache_dir [file join $output cache]
::GX::configurationSave
::GX::projectCreate {EXP01 derived Sketch descriptors} {Private synthetic fault injection only}
set session [::GX::createNewSession Descriptor_A {} 0]
proc check {condition message} {if {![uplevel 1 [list expr $condition]]} {error $message}}
proc writeBytes {path bytes} {set f [open $path wb];try {puts -nonewline $f $bytes} finally {close $f}}
proc readBytes {path} {set f [open $path rb];try {return [read $f]} finally {close $f}}
set f [open $modelsFile];set exact [dict get [read $f] 1];close $f
set documents {};set payloads {};set result {};set planes {{origin {0 0 0} normal {0 0 1} u_axis {1 0 0}} {origin {0 1 0} normal {0 1 0} u_axis {1 0 0}} {origin {2 0 0} normal {1 1 1} u_axis {1 -1 0}}}
foreach plane $planes {
 set model $exact;dict set model plane $plane;set payload [dict create model $model allocation_counter 1]
 set id [dict get [::GX::interactiveDocumentCreate core.native2d sketch gxtxt.native_cad_sketch.v1 1 $payload] id]
 lappend documents $id;dict set payloads $id $payload
}
check {[dict get [::GX::nativeCadSketchQuickOpenStatus] publications]==3} {Creation did not publish every descriptor}
set first [::GX::nativeCadSketchQuickOpenList $documents]
::GX::interactiveDocumentCacheClear
set begin [clock microseconds];set cold [::GX::nativeCadSketchQuickOpenList $documents];set coldUs [expr {[clock microseconds]-$begin}]
set begin [clock microseconds];set warm [::GX::nativeCadSketchQuickOpenList $documents];set warmUs [expr {[clock microseconds]-$begin}]
check {$first eq $cold && $cold eq $warm} {Cold/warm descriptors differ}
foreach id $documents plane $planes {
 check {[dict get $first $id plane] eq $plane} {Scientific plane changed}
 check {[dict get $first $id object_count]==1 && [dict get $first $id relationship_count]==0} {Descriptor counts differ}
 check {[dict get [::GX::interactiveDocumentRead $id] payload] eq [dict get $payloads $id]} {Preview changed science}
}
dict set result cold_warm [dict create status PASS cold_batch_us $coldUs warm_batch_us $warmUs status [::GX::nativeCadSketchQuickOpenStatus]]
set id [lindex $documents 0];set rootCache [::GX::_nativeCadQuickRoot];set indexPath [file join $rootCache index.tcldict]
writeBytes $indexPath {BROKEN_INDEX}
set restored [::GX::nativeCadSketchQuickOpenPresentation $id]
check {[dict exists $restored layers]} {Corrupt index did not recover}
dict set result corrupt_index PASS
set descriptor [dict get [::GX::nativeCadSketchQuickOpenList [list $id]] $id]
set assetPath [file join $rootCache [dict get $descriptor asset]]
writeBytes $assetPath {CORRUPT_PREVIEW}
set restored [::GX::nativeCadSketchQuickOpenPresentation $id]
check {[dict size [dict get $restored layers]]>0} {Corrupt asset did not recover}
dict set result corrupt_asset PASS
file delete -- $assetPath
set restored [::GX::nativeCadSketchQuickOpenPresentation $id]
check {[dict size [dict get $restored layers]]>0} {Missing asset did not recover}
dict set result missing_asset PASS
set meta [::GX::interactiveDocumentMetadata $id];set payload [dict get $payloads $id];dict set payload allocation_counter 2
::GX::interactiveDocumentUpdate $id $payload
set changed [dict get [::GX::nativeCadSketchQuickOpenList [list $id]] $id]
check {[dict get $changed source revision]>[dict get $meta revision]} {Saved revision did not invalidate descriptor}
dict set result revision PASS
set item [dict get [::GX::_interactiveDocumentRegistryRead $session] $id];set path [::GX::_interactiveDocumentPayloadPath $session $item];set bytes [readBytes $path]
writeBytes $path [string replace $bytes 0 0 X]
check {[dict get [::GX::nativeCadSketchQuickOpenList [list $id] {} 0] $id unavailable]} {Changed canonical file identity was accepted}
check {[catch {::GX::nativeCadSketchQuickOpenPresentation $id}]} {Corrupt science was accepted as preview/edit source}
check {[catch {::GX::interactiveDocumentRead $id}]} {Explicit read integrity was weakened}
writeBytes $path $bytes
check {[dict size [dict get [::GX::nativeCadSketchQuickOpenPresentation $id] layers]]>0} {Restored authority failed to recover}
dict set result canonical_corruption PASS
set sourceBefore [::GX::interactiveDocumentSourceIdentities $documents]
::GX::interactiveDocumentCacheConfigure {byte_budget 1048576 entry_budget 1}
foreach doc $documents {::GX::nativeCadSketchQuickOpenPresentation $doc}
check {$sourceBefore eq [::GX::interactiveDocumentSourceIdentities $documents]} {Eviction changed source identity}
dict set result eviction PASS
# Deliberate derived-cache faults never roll back a successful science save.
set lock [file join $rootCache publish.lock]
writeBytes $lock {pid 999999999 start 0 boot old-boot}
::GX::nativeCadSketchQuickOpenPublish $id
dict set result abandoned_publisher PASS
::GX::_nativeCadQuickLock $lock
check {[catch {::GX::nativeCadSketchQuickOpenPublish $id}]} {Took a live publisher lock}
check {[dict exists [::GX::nativeCadSketchQuickOpenPresentation $id] layers]} {Busy cache prevented verified display fallback}
file delete -- $lock
dict set result live_publisher_fallback PASS
set before [::GX::interactiveDocumentMetadata $id];set payload [dict get [::GX::interactiveDocumentRead $id] payload]
dict incr payload allocation_counter
file attributes $rootCache -permissions 0500
try {
 set committed [::GX::interactiveDocumentUpdate $id $payload]
 check {[dict get $committed revision]>[dict get $before revision]} {Cache failure rolled back science save}
 check {[dict get [::GX::interactiveDocumentRead $id] payload] eq $payload} {Saved science differs after cache write failure}
 check {[dict exists [::GX::nativeCadSketchQuickOpenPresentation $id] layers]} {Read-only cache broke authoritative display}
} finally {file attributes $rootCache -permissions 0700}
::GX::nativeCadSketchQuickOpenPublish $id
check {[llength [glob -nocomplain -directory $rootCache *.tmp]]==0} {Failed cache publication leaked a temporary file}
dict set result failed_publication_preserves_save PASS
set index [::GX::_nativeCadQuickIndex $rootCache];dict set index entries $id mm schema unsupported
::GX::_nativeCadQuickAtomic [file join $rootCache index.tcldict] $index
set recovered [::GX::nativeCadSketchQuickOpenPresentation $id]
check {[dict get $recovered descriptor schema] eq {gxtxt.sketch.quick_open.exp01}} {Unsupported descriptor was accepted}
dict set result schema_recovery PASS
# Unsupported native stroke styles remain visible in closed previews and
# explicitly retain the exact existing overlay style during active editing.
set styled $exact;dict set styled object/s1 style line_style 1
set styledId [dict get [::GX::interactiveDocumentCreate core.native2d sketch gxtxt.native_cad_sketch.v1 1 [dict create model $styled allocation_counter 1]] id]
set styleView [::GX::nativeCadSketchQuickOpenPresentation $styledId]
check {[dict size [dict get $styleView layers]]>0 && [dict get $styleView descriptor editing_overlay_required]} {Dashed geometry disappeared or lost its edit fallback}
dict set result closed_style_preservation PASS
::GX::nativeCadSketchQuickOpenPublish $styledId {} m
check {[dict get [::GX::nativeCadSketchQuickOpenPresentation $styledId] working_unit] eq {mm}} {Default preview silently changed scientific display unit}
dict set result default_unit PASS
set index [::GX::_nativeCadQuickIndex $rootCache];dict set index entries $styledId mm object_count 999
::GX::_nativeCadQuickAtomic [file join $rootCache index.tcldict] $index
check {[dict get [::GX::nativeCadSketchQuickOpenPresentation $styledId] descriptor object_count]==1} {Well-formed descriptor corruption bypassed its checksum}
dict set result descriptor_checksum PASS
set oldCache [::GX::_nativeCadQuickRoot]
set session2 [::GX::createNewSession Descriptor_B {} 0]
set reused [dict get [::GX::interactiveDocumentCreate core.native2d sketch gxtxt.native_cad_sketch.v1 1 [dict get $payloads $id]] id]
check {$reused eq $id && [::GX::_nativeCadQuickRoot] ne $oldCache} {Session aliases a previous descriptor}
dict set result session_isolation PASS
set f [open [file join $output RESULT.tcldict] w];puts $f [dict create status PASS cases $result];close $f
puts [dict create status PASS cases [dict keys $result]]
