lassign $argv framework output
if {[file exists $output]} {error {New output required}}
file mkdir $output
foreach {key dir} {XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache XDG_STATE_HOME state GXTXT_JOB_ROOT jobs GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE resource-files GXTXT_INSTALLATION_ROOT installation} {set ::env($key) [file join $output $dir]}
set argv0 __p004_async_stderr__
source [file join $framework gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
proc check {e label} {if {![uplevel 1 [list expr $e]]} {error "FAIL $label"};puts "PASS $label";flush stdout}
proc receive {result} {set ::answer $result}
proc runCase {name code options} {
    set ::answer {}
    set channels [lsort [chan names]]
    set command [list [auto_execok setsid] [::GX::runtimeToolResolve python] -B -c $code]
    set request [::GX::scriptJobAsync $command {} receive [dict merge {separate_stderr 1 process_group 1 timeout_ms 5000 max_bytes 4096 label {P004 stderr regression}} $options]]
    set pids [dict get $::GX::scriptJobRequests $request pids]
    set end [expr {[clock milliseconds]+7000}]
    while {$::answer eq {} && [clock milliseconds]<$end} {update;after 5}
    check {$::answer ne {}} "$name completes bounded request"
    check {![dict exists $::GX::scriptJobRequests $request] && [lsort [chan names]] eq $channels} "$name retires both channels and one existing request"
    foreach pid $pids {
        if {[file readable /proc/$pid/stat]} {
            set f [open /proc/$pid/stat];set state [read $f];close $f
            check {[regexp {\) Z } $state]} "$name owned child is no longer running"
        }
    }
    return $::answer
}
set good [runCase footer {import sys
print('ok 1 result ready', flush=True)
print('NATIVE_DIAGNOSTIC_FOOTER live=0', file=sys.stderr, flush=True)
} {}]
check {[dict get $good ok] && [dict get $good result] eq {ready} && [string first NATIVE_DIAGNOSTIC_FOOTER [dict get $good diagnostic_tail]]>=0} {stderr remains diagnostics and cannot corrupt strict stdout control}
set combined [runCase combined {import sys
print('ok 1 result {' + 'v'*80 + '}', flush=True)
print('d'*80, file=sys.stderr, flush=True)
} {max_bytes 128}]
check {![dict get $combined ok] && [dict get $combined error_type] eq {output_limit}} {combined stdout plus stderr budget enforced even though each stream fits separately}
set overflow [runCase overflow {import sys,time
print('ok 1 result ready', flush=True)
print('x'*4096, file=sys.stderr, flush=True)
time.sleep(5)
} {max_bytes 1024}]
check {![dict get $overflow ok] && [dict get $overflow error_type] eq {output_limit}} {stderr overflow uses same cancellation and escalation owner}
set held [runCase held {import os,sys,time
print('ok 1 result ready', flush=True)
os.close(1)
print('stderr remains open', file=sys.stderr, flush=True)
time.sleep(5)
} {timeout_ms 150}]
check {![dict get $held ok] && [dict get $held error_type] eq {timeout}} {stdout EOF cannot bypass stderr lifetime and timeout bound}
puts {PASS P004 bounded separate stderr async regression}
exit 0
