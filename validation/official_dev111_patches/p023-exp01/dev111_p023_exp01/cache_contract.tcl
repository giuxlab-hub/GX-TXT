# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root output
if {[file exists $output]} {error {Fresh output required}}
file mkdir $output;set output [file normalize $output]
foreach {key dir} {HOME home XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache XDG_STATE_HOME state GXTXT_INSTALLATION_ROOT installation GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE buffers GXTXT_JOB_ROOT jobs TMPDIR tmp} {set ::env($key) [file join $output $dir];file mkdir $::env($key);file attributes $::env($key) -permissions 0700}
set argv0 __EXP01_DOCUMENT_CACHE_CONTRACT__;source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
::GX::configurationSet storage.session_root [file join $output Sessions]
::GX::configurationSet storage.temp_dir [file join $output tmp]
::GX::configurationSet storage.cache_dir [file join $output cache]
::GX::configurationSave
::GX::projectCreate {EXP01 document cache contracts} {Private synthetic fault injection only}
set session [::GX::createNewSession Cache_A {} 0]
proc check {condition message} {if {![uplevel 1 [list expr $condition]]} {error $message}}
proc writeBytes {path bytes} {set f [open $path wb];try {puts -nonewline $f $bytes} finally {close $f}}
set result {}
set payload [dict create model [dict create title {Unicode λ and quoted text} values {1 2 3}] note "first\nsecond\nthird"]
set a [dict get [::GX::interactiveDocumentCreate core.native2d sketch gxtxt.test_document.v1 1 $payload] id]
set cold [::GX::interactiveDocumentReadCached $a];set first [::GX::interactiveDocumentCacheStatus]
set warm [::GX::interactiveDocumentReadCached $a];set second [::GX::interactiveDocumentCacheStatus]
check {[dict get $cold payload] eq $payload && $cold eq $warm} {Cached UTF-8 payload differs}
check {[dict get $second hits]>[dict get $first hits]} {No verified warm hit}
check {[dict get [::GX::interactiveDocumentRead $a] payload] eq $payload} {Explicit read differs}
dict set result warm_hit [dict create result PASS before $first after $second]
# Private, isolated fault injection into the canonical source owned by this test.
set item [dict get [::GX::_interactiveDocumentRegistryRead $session] $a]
set path [::GX::_interactiveDocumentPayloadPath $session $item]
set stamp [::GX::NativeDocument::snapshotCache identity $path]
set f [open $path rb];set bytes [read $f];close $f
set corrupt [string replace $bytes 0 0 X];writeBytes $path $corrupt
exec -- python3 -c {import os,sys; p=sys.argv[1]; s=os.stat(p); os.utime(p,ns=(s.st_atime_ns,int(sys.argv[2])))} $path [dict get $stamp mtime_ns]
set newStamp [::GX::NativeDocument::snapshotCache identity $path]
check {[dict get $newStamp mtime_ns]==[dict get $stamp mtime_ns]} {Fault fixture did not restore exact mtime}
check {[dict get $newStamp ctime_ns]!=[dict get $stamp ctime_ns]} {Fault fixture lacks changed ctime}
check {[catch {::GX::interactiveDocumentReadCached $a} error]} {Warm cache accepted corrupt external bytes}
check {[string match {*SHA-256 mismatch*} $error]} {Unexpected cached corruption diagnostic}
check {[catch {::GX::interactiveDocumentRead $a} explicitError]} {Explicit read stopped verifying SHA}
writeBytes $path $bytes
check {[dict get [::GX::interactiveDocumentReadCached $a] payload] eq $payload} {Verified recovery failed}
dict set result external_corruption [dict create result PASS cached_error $error explicit_error $explicitError exact_mtime_restored 1 ctime_invalidated 1]
set payload2 [dict replace $payload note {new revision}]
::GX::interactiveDocumentUpdate $a $payload2
check {[dict get [::GX::interactiveDocumentReadCached $a] payload] eq $payload2} {Cached old revision}
check {[dict get [::GX::interactiveDocumentMetadataBatch [list $a]] $a revision]==2} {Metadata cache missed canonical revision}
dict set result revision PASS
::GX::interactiveDocumentCacheClear
::GX::interactiveDocumentCacheConfigure {byte_budget 1048576 entry_budget 1}
set p1 [string repeat a 700000];set p2 [string repeat b 700000]
set b [dict get [::GX::interactiveDocumentCreate core.native2d sketch gxtxt.test_document.v1 1 $p1] id]
set c [dict get [::GX::interactiveDocumentCreate core.native2d sketch gxtxt.test_document.v1 1 $p2] id]
::GX::interactiveDocumentReadCached $b;::GX::interactiveDocumentReadCached $c
set policy [::GX::interactiveDocumentCacheStatus]
check {[dict get $policy entries]<=1 && [dict get $policy accounted_bytes]<=[dict get $policy byte_budget] && [dict get $policy evictions]>0} {Cache budget or eviction failed}
check {[dict get [::GX::interactiveDocumentReadCached $b] payload] eq $p1} {Evicted source failed to reload}
dict set result eviction [dict create result PASS policy $policy]
# Existing private source-capture API keeps its original4MiB admission policy.
set large [file join $output oversized.bin];writeBytes $large [string repeat z 4194305]
check {[catch {::GX::NativeDocument::sourceCapture $large} rejected]} {Legacy4MiB source cap changed}
check {[string match {*4 MiB*} $rejected]} {Unexpected legacy capture diagnostic}
dict set result legacy_source_capture PASS
set oldToken [::GX::interactiveDocumentSessionToken]
set session2 [::GX::createNewSession Cache_B {} 0]
set scoped [::GX::interactiveDocumentCacheStatus]
check {[dict get $scoped entries]==0 && [dict get $scoped session_token] ne $oldToken} {Session did not release cache}
set replacement [dict get [::GX::interactiveDocumentCreate core.native2d sketch gxtxt.test_document.v1 1 {new Session payload}] id]
check {$replacement eq $a && [dict get [::GX::interactiveDocumentReadCached $replacement] payload] eq {new Session payload}} {Cross-Session ID alias reused cached science}
dict set result session_isolation PASS
# Optional cache bounds must not reject a larger Document accepted by the
# established explicit reader. This is synthetic text, not scientific geometry.
set bigPayload [string repeat x 67108865]
set bigId [dict get [::GX::interactiveDocumentCreate core.native2d sketch gxtxt.test_document.v1 1 $bigPayload] id]
set beforeFallback [dict get [::GX::interactiveDocumentCacheStatus] fallback_reads]
check {[dict get [::GX::interactiveDocumentReadCached $bigId] payload] eq $bigPayload} {Large valid Document was rejected by optional cache}
check {[dict get [::GX::interactiveDocumentCacheStatus] fallback_reads]>$beforeFallback} {Large reader did not report uncached fallback}
check {[dict get [::GX::interactiveDocumentSourceIdentities [list $bigId]] $bigId source_identity size]>67108864} {Large metadata inspection read/capped payload bytes}
unset bigPayload
::GX::interactiveDocumentDelete $bigId
dict set result large_document_fallback PASS
::GX::interactiveDocumentCacheClear
check {[dict get [::GX::interactiveDocumentCacheStatus] entries]==0} {Clear retained resources}
dict set result cleanup PASS
set f [open [file join $output RESULT.tcldict] w];puts $f $result;close $f
puts [dict create status PASS cases [dict keys $result]]
