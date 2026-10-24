# SPDX-License-Identifier: GPL-3.0-or-later
if {[llength $argv] != 2} {error {usage: contract.tcl FRAMEWORK NEW_OUTPUT}}
lassign $argv framework out
if {[file exists $out]} {error {Output must be fresh}}
file mkdir $out
load [file join $framework core history libgxtxt_history.so] Gxtxt_history
proc check {label expression} {
    if {![uplevel 1 [list expr $expression]]} {error "FAIL $label"}
    puts "PASS $label"
}
proc native {args} {::GX::historyNative {*}$args}
proc base {snapshot} {
    return [dict create format gxtxt.scientific_recipe.v1 workbench_id test.owner required_apis SCIENTIFIC_RECIPE_API_v1 plugin_versions {} sources {} retention complete base $snapshot steps {} cursor 0]
}
set initial [base [dict create a 1 b {complex value {x} [ y ] \n café 😎}]]
set path [file join $out basic.gxh]
set h [native open test.owner $initial $path {session#one idoc_0001 generation#one}]
check {open accepted pending} {[dict get [native status $h] accepted_revision]==1}
native append $h [dict create a 2 b {complex value {x} [ y ] \n café 😎}] {first move}
native appendPatch $h [dict create c 3] {second move} [dict create group move operation cad_translate]
check {immediate RAM state} {[dict get [native state $h] c]==3}
check {description and grouping} {[dict get [lindex [native rows $h 1 1] 0] group] eq "move"}
check {browse pure state} {[dict get [native state $h 0] a]==1 && [dict get [native status $h] cursor]==2}
native navigate $h 1
check {undo inverse removes inserted key} {![dict exists [native state $h] c] && [dict get [native state $h] a]==2}
native navigate $h 0
check {undo restores original} {[native state $h] eq [dict get $initial base]}
native navigate $h 2
check {redo restores latest} {[dict get [native state $h] c]==3}
set rev [dict get [native status $h] revision]
native append $h [native state $h] {no-op}
check {no-op not recorded} {[dict get [native status $h] revision]==$rev}
check {recovery rejects active writer} {[catch {native recover $path {session#one idoc_0001 generation#one}}]}
check {lock excludes concurrent owner} {[catch {native open test.owner $initial $path {session#one idoc_0001 generation#one}}]}
native checkpoint $h
native flush $h 30000
set record [native record $h]
set status [native close $h]
check {fsynced accepted revision} {[dict get $status revision]==[dict get $status durable_revision] && [dict get $status pending]==0}
set recovered [native recover $path {session#one idoc_0001 generation#one}]
check {checkpoint roundtrip complete scientific data} {[dict get $recovered record] eq $record}
check {identity rejects other document} {[catch {native recover $path {session#one idoc_0002 generation#one}}]}
set h [native open test.owner [dict get $recovered record] $path {session#one idoc_0001 generation#one}]
native navigate $h 1
check {append old cursor requires explicit branch} {[catch {native appendPatch $h [dict create x 8] bad}]}
native branch $h 1
native appendPatch $h [dict create x 8 a @gxtxt.recipe.delete] {branch edit}
check {branch retained prior steps} {[dict get [native status $h] count]==2 && ![dict exists [native state $h] a]}
native navigate $h 1
check {inverse deleted scientific key} {[dict get [native state $h] a]==2}
native navigate $h 2
native flush $h
set complete [native record $h]
set durable [dict get [native status $h] durable_revision]
native close $h
set f [open $path ab];fconfigure $f -translation binary;puts -nonewline $f abc;close $f
set r [native recover $path {session#one idoc_0001 generation#one}]
check {torn final header recovers complete prefix} {[dict get $r torn_tail] && [dict get $r record] eq $complete && [dict get $r revision]==$durable}
set h [native open test.owner [dict get $r record] $path {session#one idoc_0001 generation#one}]
native appendPatch $h [dict create z 9] {after interrupted write}
native flush $h
set complete [native record $h]
native close $h
check {repaired tail accepts ordered append} {[dict get [native recover $path {session#one idoc_0001 generation#one}] record] eq $complete}
file copy $path [file join $out corrupt.gxh]
file copy $path.checkpoint [file join $out corrupt.gxh.checkpoint]
set p [file join $out corrupt.gxh]
set f [open $p r+b];fconfigure $f -translation binary;seek $f -1 end;set b [read $f 1];seek $f -1 end;puts -nonewline $f [expr {$b eq "x" ? "y" : "x"}];close $f
check {complete frame corruption rejected} {[catch {native recover $p {session#one idoc_0001 generation#one}}]}

# Length/header corruption must not be mistaken for an incomplete write.
set p [file join $out bad_length.gxh]
file copy $path $p
file copy $path.checkpoint $p.checkpoint
set f [open $p r+b];fconfigure $f -translation binary
# Header size is the constant preamble+identity+digest; byte8 of first frame
# is the length field. XOR its low byte without touching payload checksum.
set frameStart [expr {12+[string length {session#one idoc_0001 generation#one}]+32}]
seek $f [expr {$frameStart+8}]
binary scan [read $f 1] cu value
seek $f [expr {$frameStart+8}]
puts -nonewline $f [binary format cu [expr {$value^128}]]
close $f
check {length corruption rejected before torn-tail handling} {[catch {native recover $p {session#one idoc_0001 generation#one}}]}

set memory [native open test.owner $initial {} {}]
native appendPatch $memory [dict create value 3] one
native clear $memory [native state $memory]
check {clear preserves current scientific state} {[dict get [native status $memory] count]==0 && [dict get [native state $memory] value]==3}
native close $memory
# Worker publication error is asynchronous and remains visible; failed close
# retains RAM ownership so a caller can export rather than silently drop edits.
set bad [file join $out failed.gxh]
file mkdir $bad.checkpoint.pending.[pid]
set fail [native open test.owner $initial $bad {failure fixture}]
check {failed IO flush explicit} {[catch {native flush $fail 30000}]}
set failed [native status $fail]
check {failed IO state and no durability claim} {[dict get $failed failed] && [dict get $failed durable_revision]==0}
check {failed IO rejects subsequent edits} {[catch {native appendPatch $fail [dict create q 8] rejected}]}
check {failed close preserves RAM for export} {[catch {native close $fail}] && [native record $fail] eq $initial}

# Truncated payload recovers precisely the preceding complete frame.
set payloadPath [file join $out payload.gxh]
set p [native open test.owner [base [dict create a 0]] $payloadPath payload#one]
native appendPatch $p {a 1} one
native flush $p
set prefix [native record $p]
native appendPatch $p {a 2} two
native flush $p
native close $p
set f [open $payloadPath r+b];chan truncate $f [expr {[file size $payloadPath]-5}];close $f
set r [native recover $payloadPath payload#one]
check {torn payload recovers preceding complete frame} {[dict get $r torn_tail] && [dict get $r record] eq $prefix}

# A checkpoint published before its suffix reset must dominate an old suffix.
set cpPath [file join $out checkpoint.gxh]
set p [native open test.owner [base {a 0}] $cpPath checkpoint#one]
native appendPatch $p {a 1} one
native flush $p
file copy $cpPath $cpPath.old
native appendPatch $p {a 2} two
native checkpoint $p
native flush $p
set newest [native record $p]
native close $p
file copy -force $cpPath.old $cpPath
check {new checkpoint dominates stale suffix} {[dict get [native recover $cpPath checkpoint#one] record] eq $newest}
file delete $cpPath
set recovered [native recover $cpPath checkpoint#one]
check {checkpoint survives missing suffix} {[dict get $recovered record] eq $newest}
set p [native open test.owner [dict get $recovered record] $cpPath checkpoint#one]
native appendPatch $p {a 3} three
native flush $p
set newest [native record $p]
native close $p
check {missing suffix initialized and resumes revisions} {[dict get [native recover $cpPath checkpoint#one] record] eq $newest}

# Resource backpressure must reject before any revision or state change.
set p [native open test.owner [base {a 0}] [file join $out bounded.gxh] bounded#one]
native flush $p
native queueLimit $p 1024
set prior [native status $p]
check {bounded queue rejects oversized event} {[catch {native appendPatch $p [dict create a [string repeat x 2048]] rejected}]}
check {queue rejection leaves accepted state unchanged} {[dict get [native status $p] revision]==[dict get $prior revision] && [native state $p] eq {a 0}}
native queueLimit $p 33554432
native appendPatch $p {a 1} accepted
native flush $p
native close $p

# Kill only this contract's subprocess after a known durable prefix, then
# verify that recovery yields a complete ordered prefix of accepted operations.
set childDir [file join $out killed]
set child [lindex [exec [info nameofexecutable] [file join $framework validation dev111_p017 native interruption_writer.tcl] $framework $childDir >[file join $out child.log] 2>@1 &] 0]
set deadline [expr {[clock milliseconds]+30000}]
while {![file exists [file join $childDir ready]] && [clock milliseconds]<$deadline} {after 5}
if {![file exists [file join $childDir ready]]} {catch {exec kill -KILL -- $child};error {Interrupted writer did not become ready}}
exec kill -KILL -- $child
# Wait for the kernel to release the writer's lock before reading its files.
set deadline [expr {[clock milliseconds]+10000}]
while {[catch {set r [native recover [file join $childDir killed.gxh] interruption#one]} message options]} {
    if {![string match {*active writer*} $message] || [clock milliseconds]>=$deadline} {return -options $options $message}
    after 20
}
set count [llength [dict get $r record steps]]
check {SIGKILL preserves fsynced prefix and complete accepted order} {$count>=32 && $count<=1000 && [dict get $r revision]==$count+1}


# Legacy Scientific Recipe steps deliberately lack display-only fields. Preserve
# exact semantic bytes and unknown metadata while adding the CORE envelope once.
set oldStep [dict create api_id NATIVE_2D_GEOMETRY_API_v1 api_version 1 operation geometry_state semantic_operation translate parameters {dx 1} targets object_1 result_ids object_1 working_unit mm patch {value 1} vendor_note {preserve unknown operation metadata}]
set old [dict create base {value 0} steps [list $oldStep] retention complete vendor_header {preserve unknown record metadata}]
set normalized [dict merge $old [dict create format gxtxt.scientific_recipe.v1 workbench_id test.owner required_apis SCIENTIFIC_RECIPE_API_v1 plugin_versions {} sources {} cursor 1 legacy_import 1]]
set p [native open test.owner $normalized {} {}]
set exported [native record $p]
check {legacy step bytes and unknown metadata preserved} {[dict get $exported steps] eq [dict get $old steps] && [dict get $exported vendor_header] eq [dict get $old vendor_header] && ![dict exists [lindex [dict get $exported steps] 0] description] && ![dict exists [lindex [dict get $exported steps] 0] timestamp]}
set row [lindex [native rows $p] 0]
check {legacy UI description and unknown time synthesized only for presentation} {[dict get $row description] eq "translate" && [dict get $row timestamp]==0}
native appendPatch $p {value 2} {new operation}
set added [lindex [dict get [native record $p] steps] end]
check {new operations retain display metadata} {[dict get $added description] eq {new operation} && [dict get $added timestamp]>0}
check {unsupported semantic API rejects before acceptance} {[catch {native appendPatch $p {value 3} invalid {api_id UNTRUSTED_API_v1}}] && [dict get [native state $p] value]==2}
native close $p

# Build a scientific-only legacy record at exactly the existing 8-MiB cap.
# An import envelope may add <=4096 bytes, without rewriting each old step.
set oldStep [dict replace $oldStep parameters [dict create blob x]]
set old [dict create base {value 0} steps [list $oldStep] retention complete]
set fill [expr {8388608-[string bytelength $old]+1}]
dict set oldStep parameters [dict create blob [string repeat x $fill]]
dict set old steps [list $oldStep]
# A second correction handles empty/single-word Tcl quoting boundaries exactly.
set fill [expr {$fill+8388608-[string bytelength $old]}]
dict set oldStep parameters [dict create blob [string repeat x $fill]]
dict set old steps [list $oldStep]
check {legacy scientific fixture exactly eight MiB} {[string bytelength $old]==8388608}
set normalized [dict merge $old [dict create format gxtxt.scientific_recipe.v1 workbench_id test.owner required_apis SCIENTIFIC_RECIPE_API_v1 plugin_versions {} sources {} cursor 1 legacy_import 1]]
set capPath [file join $out legacy_cap.gxh]
set p [native open test.owner $normalized $capPath legacy#cap]
check {near-cap import preserves scientific bytes without display-field inflation} {[dict get [native record $p] steps] eq [dict get $old steps] && [string bytelength [native record $p]]>8388608}
check {normal append cannot spend import allowance} {[catch {native appendPatch $p {value 2} capped}] && [dict get [native state $p] value]==1}
native checkpoint $p
native flush $p
set exported [native record $p]
native close $p
check {near-cap legacy import checkpoint recovery preserves all metadata} {[dict get [native recover $capPath legacy#cap] record] eq $exported}
check {same oversize envelope rejects without import flag} {[catch {native open test.owner [dict remove $normalized legacy_import] {} {}}]}
set excessive [dict replace $normalized vendor_oversize [string repeat x 4096]]
check {import envelope allowance is bounded} {[catch {native open test.owner $excessive {} {}}]}
check {unsupported supplied format rejects} {[catch {native open test.owner [dict replace $initial format other.recipe.v1] {} {}}]}
set p [native open test.owner $normalized {} {}]
native clear $p [native state $p]
native appendPatch $p {value 2} {explicitly restarted recording}
check {explicit clear permits normal new recording after capped import} {[dict get [native status $p] count]==1 && [dict get [native state $p] value]==2}
native close $p

# Same small snapshot, growing retained log. Measure acceptance separately from
# disk durability. Total retained history stays below the legacy 8-MiB boundary.
set stress [native open test.owner [base [dict create value {}]] [file join $out stress.gxh] stress#one]
set block [string repeat abcdefghijklmnopqrstuvwxyz012345 72]
set samples {}
for {set n 1} {$n<=3200} {incr n} {
    set t [clock microseconds]
    native appendPatch $stress [dict create value "$n:$block"] "move $n"
    lappend samples [expr {[clock microseconds]-$t}]
}
set accept [native status $stress]
set t [clock microseconds];native flush $stress 60000;set flush [expr {[clock microseconds]-$t}]
set stressRecord [native record $stress]
check {stress retains all operations} {[dict get $accept count]==3200 && [llength [dict get $stressRecord steps]]==3200}
check {stress near eight MiB} {[string bytelength $stressRecord]>7500000 && [string bytelength $stressRecord]<8388608}
set first [lsort -integer [lrange $samples 0 99]]
set last [lsort -integer [lrange $samples end-99 end]]
set receipt [dict create operations 3200 record_bytes [string bytelength $stressRecord] first100_median_us [lindex $first 50] first100_p95_us [lindex $first 95] last100_median_us [lindex $last 50] last100_p95_us [lindex $last 95] pending_at_acceptance [dict get $accept pending] durability_wait_us $flush final_status [native status $stress]]
set f [open [file join $out performance.tcldict] w];puts $f $receipt;close $f
puts "PERFORMANCE $receipt"
native close $stress
set recovered [native recover [file join $out stress.gxh] stress#one]
check {stress checkpoint and incremental suffix recovery} {[dict get $recovered record] eq $stressRecord}
puts {PASS native P017 contract}
