# SPDX-License-Identifier: GPL-3.0-or-later
if {[llength $argv]!=2} {error {usage: auxiliary.tcl FRAMEWORK NEW_OUTPUT}}
lassign $argv framework out
set framework [file normalize $framework]
set out [file normalize $out]
if {[file exists $out]} {error {Fresh output required}}
file mkdir $out
load [file join $framework core history libgxtxt_history.so] Gxtxt_history
set checks {}
proc check {name expression} {
    if {![uplevel 1 [list expr $expression]]} {error "FAIL $name"}
    lappend ::checks $name
    puts "PASS $name"
}
proc native {args} {::GX::historyNative {*}$args}
proc record {value} {return [dict create format gxtxt.scientific_recipe.v1 workbench_id auxiliary.owner required_apis SCIENTIFIC_RECIPE_API_v1 plugin_versions {} sources {} retention complete base [dict create value $value] steps {} cursor 0]}
proc output {name value} {set f [open [file join $::out $name] w];try {fconfigure $f -encoding utf-8;puts $f $value} finally {close $f}}
set path [file join $out main.gxh]
set initial [record 0]
set first [dict create view [dict create zoom 1 pan {0 0}] visibility [dict create history 1 details 0]]
set h [native open auxiliary.owner $initial $path aux#one $first]
check {new open accepts separate initial auxiliary dictionary} {[native auxiliary $h] eq $first && [native record $h] eq $initial}
set before [native status $h]
# Use list construction to preserve intentionally difficult inert strings.
set second [dict create view [dict create zoom 2 pan {10 20}] visibility [dict create history 0 details 1] text [list "café 😎" "\{" "\\\n" "trailing\\"]]
set accepted [native auxiliary $h $second]
check {auxiliary setter increments accepted revision only} {[dict get $accepted revision]==[dict get $before revision]+1 && [dict get $accepted count]==0 && [dict get $accepted cursor]==0}
check {auxiliary never enters legacy record or scientific state} {[native record $h] eq $initial && [native state $h] eq {value 0} && [native auxiliary $h] eq $second}
set revision [dict get $accepted revision]
native auxiliary $h $second
check {identical auxiliary is an operation no-op} {[dict get [native status $h] revision]==$revision}
set reordered [dict create text [dict get $second text] visibility [dict get $second visibility] view [dict get $second view]]
native auxiliary $h $reordered
check {equal dictionary with reordered keys is a no-op} {[dict get [native status $h] revision]==$revision && [native auxiliary $h] eq $second}
check {non-dictionary auxiliary rejected before acceptance} {[catch {native auxiliary $h {one two three}}] && [dict get [native status $h] revision]==$revision}
set large [dict create blob [string repeat x 8388603]]
check {auxiliary exact eight MiB fixture} {[string bytelength $large]==8388608}
native auxiliary $h $large
set revision [dict get [native status $h] revision]
check {bounded auxiliary accepts exact limit} {[dict get [native status $h] auxiliary_bytes]==8388608 && [native auxiliary $h] eq $large}
check {oversized auxiliary rejected preserving accepted RAM and revision} {[catch {native auxiliary $h [dict create blob [string repeat x 8388604]]}] && [native auxiliary $h] eq $large && [dict get [native status $h] revision]==$revision}
# Selection descriptors can legally exceed the previous 64-KiB proposal.
set selection [dict create type curve.selection.v1 manual_overrides [lrepeat 4096 {curve_id curve_a sample 1 delta_x 1 delta_y 2}] rectangles {{0 0 100 100}}]
check {selection-like auxiliary exceeds sixty-four KiB within supported bound} {[string bytelength $selection]>65536 && [string bytelength $selection]<8388608}
set selectionPath [file join $out selection.gxh]
set selectionHandle [native open auxiliary.owner [record 5] $selectionPath aux#selection $selection]
native checkpoint $selectionHandle
native flush $selectionHandle
native close $selectionHandle
check {large legal selection descriptor checkpoints and recovers intact} {[dict get [native recover $selectionPath aux#selection] auxiliary] eq $selection}
# Separate limits coexist in one verifiable bundle, without spending the
# scientific record allowance on auxiliary presentation state.
set combinedPath [file join $out combined.gxh]
set combinedScience [record [string repeat p 7800000]]
set combined [native open auxiliary.owner $combinedScience $combinedPath aux#combined $large]
native checkpoint $combined
native flush $combined 60000
native close $combined
set recoveredCombined [native recover $combinedPath aux#combined]
check {near-eight-MiB science and eight-MiB auxiliary share bounded checkpoint} {[dict get $recoveredCombined record] eq $combinedScience && [dict get $recoveredCombined auxiliary] eq $large}
unset combinedScience recoveredCombined
native auxiliary $h $second
native appendPatch $h {value 1} one {undo_auxiliary {zoom 2}}
native appendPatch $h {value 2} two
set science [native record $h]
set entry [native entry $h 1]
check {constant-time entry getter preserves complete semantic metadata} {[dict get $entry undo_auxiliary] eq {zoom 2} && [dict get $entry patch] eq {value 1}}
dict set entry patch {value -99}
check {entry reference honors Tcl immutable sharing} {[dict get [native entry $h 1] patch] eq {value 1}}
check {entry getter bounds checked independently of cursor} {[catch {native entry $h 0}] && [catch {native entry $h 3}]}
native navigate $h 1
set oldCursor [dict get [native status $h] cursor]
set presentation [dict create viewport [dict create center {17 35} scale 0.5] description_visible 1]
native auxiliary $h $presentation
check {presentation acceptance preserves historical scientific cursor} {[dict get [native status $h] cursor]==$oldCursor && [dict get [native status $h] count]==2 && [native state $h] eq {value 1}}
native navigate $h 2
check {Redo still restores scientific state independent of auxiliary} {[native state $h] eq {value 2} && [native auxiliary $h] eq $presentation && [native record $h] eq $science}
native navigate $h 0
native navigate $h 2
check {Undo and Redo leave auxiliary presentation untouched} {[native auxiliary $h] eq $presentation}
set science [native record $h]
native checkpoint $h
native flush $h
set final [native status $h]
check {checkpoint does not create a scientific History step} {[native record $h] eq $science && [dict get $final count]==2 && [dict get $final pending]==0}
native close $h
set recovered [native recover $path aux#one]
check {snapshot bundle restores exact scientific and auxiliary dictionaries} {[dict get $recovered record] eq $science && [dict get $recovered auxiliary] eq $presentation && [dict get $recovered revision]==[dict get $final revision]}
check {existing open rejects explicitly mismatched initial auxiliary} {[catch {native open auxiliary.owner $science $path aux#one {wrong value}}]}
set h [native open auxiliary.owner $science $path aux#one]
check {old open signature resumes recovered auxiliary automatically} {[native auxiliary $h] eq $presentation}
set oldRevision [dict get [native status $h] revision]
native auxiliary $h {view newest}
native flush $h
check {resumed auxiliary revision is monotonic} {[dict get [native status $h] durable_revision]==$oldRevision+1}
set latest [native auxiliary $h]
native close $h
set h [native open auxiliary.owner $science $path aux#one $latest]
check {strict initial auxiliary accepts exact recovered state} {[native auxiliary $h] eq $latest}
native branch $h 1
check {branch preserves independent auxiliary} {[dict get [native status $h] count]==1 && [native auxiliary $h] eq $latest}
native clear $h [native state $h]
check {Clear preserves independent auxiliary without History step} {[dict get [native status $h] count]==0 && [native auxiliary $h] eq $latest}
native flush $h
native queueLimit $h 1024
set before [native status $h]
check {auxiliary queue backpressure rejects before RAM acceptance} {[catch {native auxiliary $h [dict create large [string repeat x 2048]]}] && [native auxiliary $h] eq $latest && [dict get [native status $h] revision]==[dict get $before revision]}
native queueLimit $h 33554432
native close $h

# A torn auxiliary frame can only lose the incomplete presentation event; it
# cannot truncate or change earlier durable scientific History.
set path [file join $out torn.gxh]
set h [native open auxiliary.owner [record 0] $path aux#torn]
native appendPatch $h {value 1} {durable science}
native flush $h
set science [native record $h]
set prefix [dict get [native status $h] revision]
native auxiliary $h $second
native flush $h
native close $h
file copy $path [file join $out corrupt.gxh]
file copy $path.checkpoint [file join $out corrupt.gxh.checkpoint]
set f [open $path r+b];chan truncate $f [expr {[file size $path]-5}];close $f
set r [native recover $path aux#torn]
check {torn auxiliary payload preserves complete scientific prefix} {[dict get $r torn_tail] && [dict get $r record] eq $science && [dict get $r auxiliary] eq {} && [dict get $r revision]==$prefix}
set h [native open auxiliary.owner [dict get $r record] $path aux#torn]
native auxiliary $h {view repaired}
native flush $h
native close $h
check {torn auxiliary suffix resumes with ordered persistence} {[dict get [native recover $path aux#torn] auxiliary] eq {view repaired}}
set corrupt [file join $out corrupt.gxh]
set f [open $corrupt r+b];fconfigure $f -translation binary;seek $f -1 end;set b [read $f 1];seek $f -1 end;puts -nonewline $f [expr {$b eq "x" ? "y" : "x"}];close $f
check {complete auxiliary corruption is rejected} {[catch {native recover $corrupt aux#torn}]}
file copy $path [file join $out corrupt_checkpoint.gxh]
file copy $path.checkpoint [file join $out corrupt_checkpoint.gxh.checkpoint]
set cp [file join $out corrupt_checkpoint.gxh.checkpoint]
set f [open $cp r+b];fconfigure $f -translation binary;seek $f -1 end;puts -nonewline $f x;close $f
check {snapshot bundle corruption is rejected} {[catch {native recover [file join $out corrupt_checkpoint.gxh] aux#torn}]}

# Atomic checkpoint publication dominates an older complete auxiliary suffix.
set path [file join $out atomic_aux.gxh]
set h [native open auxiliary.owner [record 3] $path aux#atomic {view original}]
native auxiliary $h {view older}
native flush $h
file copy $path $path.old
native auxiliary $h {view newest}
native checkpoint $h
native flush $h
native close $h
file copy -force $path.old $path
set r [native recover $path aux#atomic]
check {new auxiliary checkpoint dominates stale complete suffix} {[dict get $r auxiliary] eq {view newest} && [dict get $r record] eq [record 3]}
file delete $path
check {auxiliary checkpoint survives absent journal suffix} {[dict get [native recover $path aux#atomic] auxiliary] eq {view newest}}

# Explicit interpreter deletion drains its independently owned native context
# and unregisters process-exit cleanup rather than leaving a dangling callback.
set child [interp create]
interp eval $child [list load [file join $framework core history libgxtxt_history.so] Gxtxt_history]
set path [file join $out deleted_interp.gxh]
set handle [interp eval $child [list ::GX::historyNative open auxiliary.owner [record 4] $path aux#interp {view initial}]]
interp eval $child [list ::GX::historyNative auxiliary $handle {view retained}]
interp delete $child
check {interpreter deletion drains auxiliary writer and releases ownership} {[dict get [native recover $path aux#interp] auxiliary] eq {view retained}}

# Independent encoder constructs the old documented `snapshot` frame, without
# auxiliary metadata. New code must read it and append a new-format suffix.
set payload [file join $out legacy_payload.tcldict]
set f [open $payload w];puts -nonewline $f [list snapshot [record 7]];close $f
set path [file join $out old_snapshot.gxh]
exec python3 [file join $framework validation dev111_p017 native frame_fixture.py] $path aux#legacy 41 $payload
set r [native recover $path aux#legacy]
check {old snapshot checkpoint remains compatible with empty auxiliary} {[dict get $r record] eq [record 7] && [dict get $r auxiliary] eq {} && [dict get $r revision]==41}
set h [native open auxiliary.owner [dict get $r record] $path aux#legacy]
native auxiliary $h {legacy upgraded}
native flush $h
check {old snapshot upgrade keeps scientific record and advances revision} {[native record $h] eq [record 7] && [dict get [native status $h] revision]==42}
native checkpoint $h
native flush $h
native close $h
check {old snapshot upgrades atomically to a snapshot bundle} {[dict get [native recover $path aux#legacy] auxiliary] eq {legacy upgraded}}

# Implicit process completion and a top-level Tcl error both drain native
# writers before extension unload; the child deliberately does not call close.
foreach mode {normal error} {
    set path [file join $out "exit_$mode.gxh"]
    set code [catch {exec [info nameofexecutable] [file join $framework validation dev111_p017 native exit_writer.tcl] $framework $path $mode 2>@1} message options]
    if {$mode eq "normal"} {check {normal interpreter exit drains accepted auxiliary writes} {$code==0}} else {
        check {controlled Tcl error exits normally without writer crash} {$code==1 && [lindex [dict get $options -errorcode] 0] eq "CHILDSTATUS" && [lindex [dict get $options -errorcode] 2]==1}
    }
    set r [native recover $path exit#one]
    check {process exit preserves accepted auxiliary and scientific record} {[dict get [dict get $r auxiliary] exit_mode] eq $mode && [dict get $r record] eq [record 0] && [dict get $r revision]==2}
}

# A background checkpoint failure must retain separately accepted RAM metadata.
set path [file join $out failed.gxh]
set h [native open auxiliary.owner [record 9] $path aux#failed {initial retained}]
native flush $h
native auxiliary $h {accepted metadata}
file mkdir $path.checkpoint.pending.[pid]
native checkpoint $h
check {auxiliary pending failure surfaces on explicit flush} {[catch {native flush $h}]}
check {failed persistence retains auxiliary and scientific state in RAM} {[dict get [native status $h] failed] && [native auxiliary $h] eq {accepted metadata} && [native record $h] eq [record 9]}
check {failed auxiliary writer rejects later changes without mutation} {[catch {native auxiliary $h {new rejected}}] && [native auxiliary $h] eq {accepted metadata}}
check {failed Close preserves accepted auxiliary for explicit recovery/export} {[catch {native close $h}] && [native auxiliary $h] eq {accepted metadata}}
output receipt.tcldict [dict create status PASS_NATIVE_AUXILIARY checks $checks maximum_auxiliary_bytes 8388608 scientific_history_unchanged 1 no_tcl_worker_callbacks 1]
puts {PASS native auxiliary contract}
