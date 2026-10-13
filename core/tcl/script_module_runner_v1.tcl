# GX-TXT packaged Script Module runner. Scientific source stays in its module.
# SPDX-License-Identifier: GPL-3.0-or-later

proc ::GX::scriptModuleSafeRelative {root relative} {
    if {[file pathtype $relative] ne "relative" || [regexp {(^|[/\\])\.\.([/\\]|$)} $relative]} {
        error "Unsafe packaged script path '$relative'."
    }
    set path [file normalize [file join $root $relative]]
    if {![string match "[file normalize $root]/*" $path]} { error "Packaged script path escapes its module." }
    if {![file isfile $path] || [file type $path] eq "link"} { error "Packaged script file is missing: $relative" }
    return $path
}

proc ::GX::scriptModuleDescriptor {id} {
    set descriptor [moduleField $id descriptor ""]
    if {$descriptor eq "" || ![file isfile $descriptor] || [moduleField $id runner ""] ne "script_module"} {
        error "$id is not an installed packaged Script Module."
    }
    set d [parseIni $descriptor]
    set root [file dirname $descriptor]
    set language [descriptorValue $d script language ""]
    if {$language ni {Octave Python}} { error "$id has an unsupported script language '$language'." }
    set main [descriptorValue $d script main ""]
    set source [scriptModuleSafeRelative $root $main]
    set suffix [expr {$language eq "Python" ? ".py" : ".m"}]
    if {[file extension $source] ne $suffix} { error "$id main script extension disagrees with $language." }
    set expected [string tolower [descriptorValue $d script sha256 ""]]
    if {![regexp {^[a-f0-9]{64}$} $expected] || [scriptRegistryHash $source] ne $expected} {
        error "$id authoritative script SHA-256 verification failed."
    }
    set inventory [scriptModuleSafeRelative $root [descriptorValue $d script bundle_inventory "bundle/SHA256SUMS"]]
    set fd [open $inventory r]
    fconfigure $fd -encoding utf-8 -translation lf
    try { set records [split [read $fd] "\n"] } finally { close $fd }
    set foundMain 0
    set bundleFiles [dict create]
    foreach line $records {
        if {$line eq ""} continue
        if {![regexp {^([a-f0-9]{64})  (.+)$} $line -> sha rel]} { error "$id has an invalid bundle checksum record." }
        set path [scriptModuleSafeRelative [file dirname $inventory] $rel]
        if {[dict exists $bundleFiles $rel]} { error "$id bundle checksum inventory repeats '$rel'." }
        if {[scriptRegistryHash $path] ne $sha} { error "$id bundle file '$rel' failed SHA-256 verification." }
        dict set bundleFiles $rel $sha
        if {[file normalize $path] eq [file normalize $source]} { set foundMain 1 }
    }
    if {!$foundMain} { error "$id main script is absent from its bundle checksum inventory." }
    foreach path [pluginWalkPaths [file dirname $inventory]] {
        if {[file type $path] eq "link"} { error "$id bundle contains a symbolic link." }
        if {[file isdirectory $path]} continue
        if {[file normalize $path] eq [file normalize $inventory]} continue
        set rel [string range [file normalize $path] [expr {[string length [file normalize [file dirname $inventory]]] + 1}] end]
        if {![dict exists $bundleFiles $rel]} { error "$id bundle contains unlisted file '$rel'." }
    }
    return [dict create id $id descriptor $d root $root source $source language $language sha256 $expected \
        required_apis [descriptorValue $d script required_apis ""] version [moduleField $id version ""] \
        bundle_files $bundleFiles bundle_inventory_sha256 [scriptRegistryHash $inventory]]
}

proc ::GX::scriptModuleParameters {id template} {
    set d [parseIni $template]
    set out [dict create]
    foreach key [moduleConfigKeys $id] {
        set kind [string tolower [moduleConfigField $id $key type string]]
        if {$kind eq "table"} { continue }
        set value [expr {[dict exists $d config.$key] ? [dict get $d config.$key] : ""}]
        set required [string tolower [moduleConfigField $id $key required 0]]
        if {$value eq "" && $required in {1 true yes on}} { error "$id: configuration '$key' is required." }
        if {$kind in [dict get [uiFieldApiInfo] types]} {
            set descriptor [dict create type $kind required [expr {$required in {1 true yes on}}]]
            foreach field {min max alpha allow_inherit} {
                set supplied [moduleConfigField $id $key $field ""]
                if {$supplied ne ""} {dict set descriptor $field $supplied}
            }
            if {$kind eq "choice"} {dict set descriptor values [splitList [moduleConfigField $id $key values ""]]}
            set value [uiFieldNormalize $descriptor $value]
        }
        dict set out $key [list [expr {$kind in {integer double number boolean} ? $kind : "string"}] $value]
    }
    foreach role [moduleBindingRoles $id] {
        set value [expr {[dict exists $d bindings.$role] ? [dict get $d bindings.$role] : ""}]
        if {$value eq "" && [moduleBindingField $id $role required 0]} {
            error "$id: variable binding '$role' is required."
        }
        dict set out $role [list string $value]
    }
    return $out
}

proc ::GX::scriptExecutionRunPackaged {id runtimeTemplate moduleOutputDir {apiOperation ""}} {
    variable currentSession
    variable scriptDir
    set info [scriptModuleDescriptor $id]
    if {$currentSession eq "" || ![file isdirectory $currentSession]} { error "$id: open a Session first." }
    if {![file isfile $runtimeTemplate]} { error "$id: runtime template is missing." }
    set parameters [scriptModuleParameters $id $runtimeTemplate]
    set language [dict get $info language]
    set suffix [expr {$language eq "Python" ? ".py" : ".m"}]
    set runId "script-[clock format [clock seconds] -gmt 1 -format %Y%m%dT%H%M%SZ]-[pid]-[clock clicks]"
    set outDir [file join $currentSession analysis scripts $runId]
    if {[file exists $outDir]} { error "$id: run directory already exists." }
    file mkdir $outDir
    set snapshot [file join $outDir packaged_script$suffix]
    file copy -- [dict get $info source] $snapshot
    if {[scriptRegistryHash $snapshot] ne [dict get $info sha256]} { error "$id: execution snapshot differs from authoritative source." }
    set bundleDir [file join $outDir bundle]
    file mkdir $bundleDir
    dict for {rel expected} [dict get $info bundle_files] {
        set origin [scriptModuleSafeRelative [file join [dict get $info root] bundle] $rel]
        set target [file join $bundleDir $rel]
        file mkdir [file dirname $target]
        file copy -- $origin $target
        if {[scriptRegistryHash $target] ne $expected} { error "$id: bundle snapshot '$rel' changed during preparation." }
    }
    set runtime [file join $outDir runtime.ini]
    file copy -- $runtimeTemplate $runtime
    set ch [open $runtime a]
    fconfigure $ch -encoding utf-8 -translation lf
    try {
        puts $ch "\n\[runtime\]"
        foreach {key value} [list api_version 1 module_id $id session $currentSession output_dir $outDir \
            run_id $runId operation script_execution python_cmd [runtimeToolResolve python]] { putKV $ch $key $value }
        puts $ch "\n\[config\]"
        foreach {key value} [list source_mode registered_script registered_script "package:$id" script_file $snapshot \
            script_id $id script_scope package script_name [moduleField $id name $id] \
            script_version [dict get $info version] script_revision 1 script_sha256 [dict get $info sha256] \
            script_language $language module_version [dict get $info version] \
            bundle_dir $bundleDir working_directory $outDir \
            include_script_directory 0 arguments "" required_apis [dict get $info required_apis] \
            public_operation $apiOperation] { putKV $ch $key $value }
        dict for {key typed} $parameters {
            lassign $typed kind value
            puts $ch "\n\[script_parameter.$key\]"
            putKV $ch type $kind
            putKV $ch value $value
        }
    } finally { close $ch }
    if {$language eq "Python"} {
        set runner [file join $scriptDir core python gxtxt_python_script_execution.py]
        set command [list [runtimeToolRequired python] -B $runner --config $runtime]
    } else {
        set runner [file join $scriptDir core octave gxtxt_script_execution.m]
        set command [list [runtimeToolRequired octave] --quiet --no-gui $runner --config $runtime]
    }
    set started [clock seconds]
    set rc [catch {exec {*}$command 2>@1} output options]
    set report [file join $outDir execution.ini]
    set ch [open $report w]
    fconfigure $ch -encoding utf-8 -translation lf
    try {
        puts $ch "; GX-TXT packaged Script Module execution provenance"
        puts $ch "\[execution\]"
        foreach {key value} [list run_id $runId module_id $id module_version [dict get $info version] \
            language $language script_id $id script_scope package script_reference "package:$id" \
            script_version [dict get $info version] script_revision 1 script_sha256 [dict get $info sha256] \
            bundle_inventory_sha256 [dict get $info bundle_inventory_sha256] \
            required_apis [dict get $info required_apis] status [expr {$rc ? "FAILED" : "PASS"}] \
            public_operation $apiOperation \
            started_at $started finished_at [clock seconds] source_snapshot $snapshot output_dir $outDir] { putKV $ch $key $value }
        puts $ch "\n\[parameters\]"
        dict for {key typed} $parameters { putKV $ch $key [lindex $typed 1] }
    } finally { close $ch }
    set logName [expr {$language eq "Python" ? "python.log" : "octave.log"}]
    set log [open [file join $outDir $logName] w]
    fconfigure $log -encoding utf-8 -translation lf
    try { puts $log $output } finally { close $log }
    file mkdir $moduleOutputDir
    set names [expr {$language eq "Python" ? {python_script_run_report.txt executed_script.py execution.ini python.log} : {octave_script_run_report.txt executed_script.m execution.ini octave.log}}]
    foreach name $names {
        set from [file join $outDir $name]
        if {[file isfile $from]} { file copy -force -- $from [file join $moduleOutputDir $name] }
    }
    if {$rc} { return -options $options "$id: packaged $language script failed: $output" }
    return [dict create status PASS run_id $runId output_dir $outDir]
}

proc ::GX::scriptModuleApiInvoke {id apiId operation arguments} {
    variable moduleCfg
    variable moduleBinding
    variable moduleAnalysisSource
    if {![moduleIsEnabled $id]} { error "$id is disabled in this Session." }
    set info [scriptModuleDescriptor $id]
    set descriptor [dict get $info descriptor]
    if {$apiId ni [splitList [descriptorValue $descriptor public_apis ids ""]]} {
        error "$id does not declare public API '$apiId'."
    }
    if {$operation ni [splitList [descriptorValue $descriptor public_api_operations ids ""]]} {
        error "$apiId has no public operation '$operation'."
    }
    if {[descriptorValue $descriptor "public_api_operation.$operation" api_id ""] ne $apiId} {
        error "$apiId/$operation has an invalid operation registration."
    }
    if {[catch {dict size $arguments}]} { error "$apiId/$operation requires structured arguments." }
    set ids [splitList [descriptorValue $descriptor "public_api_operation.$operation" argument_ids ""]]
    foreach key [dict keys $arguments] {
        if {$key ni $ids} { error "$apiId/$operation: unknown argument '$key'." }
    }
    set changes {}
    foreach key $ids {
        set section "public_api_argument.$operation.$key"
        set required [string tolower [descriptorValue $descriptor $section required 1]]
        if {![dict exists $arguments $key]} {
            if {$required in {1 true yes on}} { error "$apiId/$operation: argument '$key' is required." }
            continue
        }
        set value [dict get $arguments $key]
        set kind [string tolower [descriptorValue $descriptor $section kind string]]
        switch -- $kind {
            integer { if {![string is integer -strict $value]} { error "$apiId/$operation: '$key' requires an integer." } }
            number { if {![string is double -strict $value]} { error "$apiId/$operation: '$key' requires a number." } }
            boolean { if {![string is boolean -strict $value]} { error "$apiId/$operation: '$key' requires a boolean." } }
        }
        set choices [splitList [descriptorValue $descriptor $section options ""]]
        if {[llength $choices] && $value ni $choices} { error "$apiId/$operation: '$key' is outside its declared options." }
        set target [descriptorValue $descriptor $section target ""]
        if {![regexp {^(config|binding|source)\.([A-Za-z][A-Za-z0-9_]*)$} $target -> family targetId]} {
            error "$apiId/$operation: invalid argument target '$target'."
        }
        switch -- $family {
            config { if {$targetId ni [moduleConfigKeys $id]} { error "$apiId/$operation: unknown config target '$targetId'." } }
            binding { if {$targetId ni [moduleBindingRoles $id]} { error "$apiId/$operation: unknown binding target '$targetId'." } }
            source { if {$targetId ni [moduleAnalysisSourceDeclaredIds $id]} { error "$apiId/$operation: unknown source target '$targetId'." } }
        }
        lappend changes [list $family $targetId $value]
    }
    set saved [dict create]
    try {
        foreach change $changes {
            lassign $change family key value
            switch -- $family {
                config {
                    dict set saved "config.$key" [expr {[info exists moduleCfg($id,$key)] ? $moduleCfg($id,$key) : ""}]
                    set moduleCfg($id,$key) $value
                }
                binding {
                    dict set saved "binding.$key" [expr {[info exists moduleBinding($id,$key)] ? $moduleBinding($id,$key) : "auto"}]
                    set moduleBinding($id,$key) $value
                }
                source {
                    set row [analysisSourceFindRow $id $key]
                    if {!$row} { error "$apiId/$operation: source '$key' is unavailable." }
                    dict set saved "source.$key" $moduleAnalysisSource($id,$row,dataset_id)
                    set moduleAnalysisSource($id,$row,dataset_id) $value
                }
            }
        }
        set runtime [writeStandardRuntimeConfig $id]
        set result [scriptExecutionRunPackaged $id $runtime [file dirname $runtime] $operation]
    } finally {
        dict for {target value} $saved {
            lassign [split $target .] family key
            switch -- $family {
                config { set moduleCfg($id,$key) $value }
                binding { set moduleBinding($id,$key) $value }
                source {
                    set row [analysisSourceFindRow $id $key]
                    if {$row} { set moduleAnalysisSource($id,$row,dataset_id) $value }
                }
            }
        }
    }
    return [dict create status [dict get $result status] run_id [dict get $result run_id] \
        module_id $id module_version [dict get $info version] operation $operation]
}

proc ::GX::scriptModuleBuildQueueItem {id} {
    variable currentSession
    set runtime [writeStandardRuntimeConfig $id]
    set output [file dirname $runtime]
    set statusPath [file join $output .registered_queue_status]
    set status [open $statusPath w]
    try { puts $status RUNNING } finally { close $status }
    set runId [progressNewRunId $id analysis]
    set command [list tclsh [file join $::GX::scriptDir core tcl script_module_cli.tcl] \
        $::GX::scriptDir $currentSession $id $runtime $output $statusPath]
    return [list "Analysis - [moduleField $id name $id]" $command $id $runId]
}
