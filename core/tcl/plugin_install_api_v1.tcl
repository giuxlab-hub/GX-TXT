# GX-TXT Plugin Install API v1
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Giuseppe Lanzani / giux-lab.it
#
# Framework-owned installation/update/removal of descriptor-driven plugins.
# Packages are data-only: no install scripts are executed.  The installation
# target is derived from package.type + package.id and can never be supplied as
# an arbitrary filesystem path by the package.

namespace eval ::GX {
    variable pluginInstallApiVersion 1
    variable pluginRegistry
    variable pluginRegistryOrder {}
    variable pluginManagerLayoutAfter {}
}
source [file join [file dirname [info script]] plugin_runtime_lifecycle_v1.tcl]

proc ::GX::pluginTypeSpec {type} {
    switch -- [string tolower [string trim $type]] {
        module { return [dict create dir modules descriptor module.ini label Module] }
        model { return [dict create dir models descriptor model.ini label {Mathematical model}] }
        instrument { return [dict create dir instruments descriptor instrument.ini label Instrument] }
        analysis_definition { return [dict create dir analysis_definitions descriptor analysis.ini label {Analysis definition}] }
        default { error "Unsupported plugin package type '$type'" }
    }
}

proc ::GX::pluginSafeId {id} {
    set id [string trim $id]
    if {$id eq ""} { error "Plugin package id is empty" }
    if {![regexp {^[A-Za-z0-9][A-Za-z0-9._-]*$} $id]} {
        error "Invalid plugin id '$id'. Allowed characters: letters, digits, dot, underscore, hyphen."
    }
    if {$id in {. ..}} { error "Invalid plugin id '$id'" }
    return $id
}

proc ::GX::pluginVersionCompare {a b} {
    if {![catch {package vcompare $a $b} cmp]} { return $cmp }
    return [string compare $a $b]
}

proc ::GX::pluginRegistryPath {} {
    variable scriptDir
    return [file join $scriptDir plugins .registry installed.ini]
}

proc ::GX::pluginRegistryClear {} {
    variable pluginRegistry
    variable pluginRegistryOrder
    array unset pluginRegistry *
    set pluginRegistryOrder {}
}

proc ::GX::pluginRegistryLoad {} {
    variable pluginRegistry
    variable pluginRegistryOrder
    pluginRegistryClear
    set path [pluginRegistryPath]
    if {![file isfile $path]} { return }
    set d [parseIni $path]
    set ids {}
    foreach key [dict keys $d] {
        if {[regexp {^plugin\.(.+)\.id$} $key -> secId]} {
            set id [dict get $d $key]
            if {$id ne "" && [lsearch -exact $ids $id] < 0} { lappend ids $id }
        }
    }
    foreach id $ids {
        set prefix "plugin.$id."
        foreach field {id type version name installed_at updated_at package_file bundle_id bundle_version} {
            set k "$prefix$field"
            set pluginRegistry($id,$field) [expr {[dict exists $d $k] ? [dict get $d $k] : ""}]
        }
        lappend pluginRegistryOrder $id
    }
    set pluginRegistryOrder [lsort -dictionary -unique $pluginRegistryOrder]
}

proc ::GX::pluginRegistryWrite {} {
    variable pluginRegistry
    variable pluginRegistryOrder
    set path [pluginRegistryPath]
    file mkdir [file dirname $path]
    set temporary "$path.write-[pid]-[clock clicks]"
    set fd [open $temporary w]
    try {
        fconfigure $fd -encoding utf-8 -translation lf
        puts $fd "; GX-TXT Plugin Install API v1 managed-plugin registry"
        puts $fd "; Framework-owned. Do not edit while GX-TXT is running."
        foreach id [lsort -dictionary -unique $pluginRegistryOrder] {
            if {![info exists pluginRegistry($id,id)]} continue
            puts $fd "\n\[plugin.$id\]"
            foreach field {id type version name installed_at updated_at package_file bundle_id bundle_version} {
                putKV $fd $field [expr {[info exists pluginRegistry($id,$field)] ? $pluginRegistry($id,$field) : ""}]
            }
        }
        close $fd
        set fd {}
        # Failed writes never truncate the previously functioning registry.
        file rename -force $temporary $path
    } finally {
        if {$fd ne {}} {catch {close $fd}}
        catch {file delete -force $temporary}
    }
}

proc ::GX::pluginRegistryIsManaged {id} {
    variable pluginRegistry
    if {![info exists pluginRegistry($id,id)]} { pluginRegistryLoad }
    return [expr {[info exists pluginRegistry($id,id)] ? 1 : 0}]
}

# Distribution overlays can deliver a complete external package without an
# installer registry entry. Discovery never adopts it. Only an explicit Update
# may adopt a verified non-CORE package in the ordinary installer transaction.
proc ::GX::pluginUpdateTargetInfo {type id {explicitUpdate 0} {verifyContents 1}} {
    set target [pluginTargetPath $type $id]
    foreach directory [list [file dirname [file dirname $target]] [file dirname $target]] {
        if {![file isdirectory $directory] || [file type $directory] eq {link}} {error {Installed plugin parent must be an ordinary canonical directory}}
    }
    if {![file isdirectory $target] || [file type $target] eq {link}} {error "Plugin '$id' has no ordinary installed directory"}
    set descriptor [pluginDescriptorPath $target $type]
    if {![file isfile $descriptor] || [file type $descriptor] eq {link}} {error "Plugin '$id' has no ordinary descriptor"}
    set data [parseIni $descriptor]
    if {[string trim [descriptorValue $data meta id {}]] ne $id || [descriptorValue $data meta api_version {}] ne {1}} {error "Installed plugin '$id' descriptor identity is invalid"}
    set version [string trim [descriptorValue $data meta version {}]]
    if {$version eq {}} {error "Installed plugin '$id' version is missing"}
    set managed [pluginRegistryIsManaged $id]
    if {$managed && [pluginInstalledField $id type] ne $type} {error "Installed plugin '$id' registry type conflicts with its target"}
    set manifest [file join $target plugin-package.ini]
    set identity [list descriptor [sha256File $descriptor]]
    if {[file exists $manifest]} {
        if {![file isfile $manifest] || [file type $manifest] eq {link}} {error "Installed plugin '$id' package manifest is invalid"}
        set package [parseIni $manifest]
        foreach {field expected} [list api_version 1 id $id type $type version $version] {
            set observed [descriptorValue $package package $field {}]
            # Match the existing package reader's normalization exactly.
            if {$field in {id type version}} {set observed [string trim $observed]}
            if {$field eq {type}} {set observed [string tolower $observed]}
            if {$observed ne $expected} {error "Installed plugin '$id' package $field conflicts with its descriptor"}
        }
        lappend identity manifest [sha256File $manifest]
    }
    if {!$managed} {
        if {!$explicitUpdate} {error "Plugin '$id' requires an explicit Update to adopt its packaged installation"}
        if {[string tolower [string trim [descriptorValue $data meta core 0]]] in {1 true yes on}} {error "Unmanaged CORE plugin '$id' is distribution-protected"}
        if {![file isfile $manifest]} {error "Installed plugin '$id' is not a standalone packaged installation"}
        if {$verifyContents} {
            pluginValidateTree $target
            set info [pluginPackageRead $target]
            if {[dict get $info id] ne $id || [dict get $info type] ne $type} {error "Installed plugin '$id' package identity conflicts with its target"}
            lappend identity members [pluginVerifyInstalledInventory $target]
        }
    }
    return [dict create version $version managed $managed target $target identity $identity]
}

proc ::GX::pluginVerifyInstalledInventory {root} {
    set inventories {}
    foreach name {SHA256SUMS.txt SHA256SUMS checksums.sha256} {
        if {[file isfile [file join $root $name]]} {lappend inventories $name}
    }
    if {![llength $inventories]} {error {Adopting an installed package requires its SHA-256 file inventory}}
    set baseline {}
    set inventoryHashes {}
    foreach inventory $inventories {
        dict set inventoryHashes $inventory [sha256File [file join $root $inventory]]
        set f [open [file join $root $inventory] r]
        try {set lines [split [read $f] \n]} finally {close $f}
        set entries {}
        foreach line $lines {
            if {[string trim $line] eq {}} continue
            if {![regexp {^([0-9A-Fa-f]{64}) [ *](.+)$} $line -> sha relative]} {error {Malformed installed package checksum inventory}}
            if {![pluginZipEntrySafe $relative] || [file pathtype $relative] ne {relative} || [string first {\\} $relative]>=0} {error {Unsafe installed package checksum path}}
            foreach part [split $relative /] {if {$part in {{} . ..}} {error {Noncanonical installed package checksum path}}}
            set path [file normalize [file join $root $relative]]
            if {[string first "[file normalize $root]/" $path]!=0 || ![file isfile $path] || [dict exists $entries $relative]} {error {Invalid or duplicate installed package checksum member}}
            set sha [string tolower $sha]
            if {[sha256File $path] ne $sha} {error "Installed package checksum mismatch: $relative"}
            dict set entries $relative $sha
        }
        set entries [lsort -stride 2 -index 0 $entries]
        if {$entries eq {}} {error {Installed package checksum inventory is empty}}
        if {$baseline ne {} && $entries ne $baseline} {error {Installed package checksum aliases disagree}}
        set baseline $entries
    }
    foreach path [pluginWalkPaths $root] {
        if {![file isfile $path]} continue
        set relative [string range $path [expr {[string length $root]+1}] end]
        if {$relative in $inventories} continue
        if {![dict exists $baseline $relative]} {error "Installed package checksum inventory omits: $relative"}
    }
    return [dict create files $baseline inventories $inventoryHashes]
}

proc ::GX::pluginInstalledField {id field {default ""}} {
    variable pluginRegistry
    if {![info exists pluginRegistry($id,id)]} { pluginRegistryLoad }
    if {[info exists pluginRegistry($id,$field)]} { return $pluginRegistry($id,$field) }
    return $default
}

proc ::GX::pluginTargetPath {type id} {
    variable scriptDir
    set id [pluginSafeId $id]
    set spec [pluginTypeSpec $type]
    return [file join $scriptDir plugins [dict get $spec dir] $id]
}

proc ::GX::pluginDescriptorPath {root type} {
    set spec [pluginTypeSpec $type]
    return [file join $root [dict get $spec descriptor]]
}

# CORE is declared by the normal plugin descriptor ([meta] core=1).
# It is independent from enabled/default_enabled and means distribution-protected:
# a CORE plugin cannot be removed through Plugin Install API v1.
proc ::GX::pluginIsCore {type id} {
    set id [pluginSafeId $id]
    if {$type eq "module" && [llength [info commands ::GX::moduleIsCore]]} {
        if {[moduleField $id descriptor ""] ne ""} { return [moduleIsCore $id] }
    }
    set target [pluginTargetPath $type $id]
    set descriptor [pluginDescriptorPath $target $type]
    if {![file isfile $descriptor]} { return 0 }
    set d [parseIni $descriptor]
    set raw [string tolower [string trim [descriptorValue $d meta core 0]]]
    return [expr {$raw in {1 true yes on}}]
}

proc ::GX::nativeWorkspaceDescriptorAdmission {data {label {Plugin}}} {
    foreach provider [splitList [descriptorValue $data workspaces ids {}]] {
        set section workspace.$provider
        if {[descriptorValue $data $section native_contract {}] ne {NATIVE_WORKSPACE_API_v1}} {error "$label Workspace provider '$provider' requires NATIVE_WORKSPACE_API_v1; obsolete providers are unsupported"}
        foreach field {entrypoint type schema version validate open encode} {
            if {[string trim [descriptorValue $data $section $field {}]] eq {}} {error "$label native Workspace provider '$provider' requires $field"}
        }
        if {![dict exists $data $section.native_required_fields]} {error "$label native Workspace provider '$provider' requires an explicit native_required_fields declaration"}
        set required [descriptorValue $data $section native_required_fields {}]
        if {[catch {dict size $required}]} {error "$label has an invalid native Workspace field declaration"}
        dict for {field kind} $required {if {$kind ni {null text bool int real object array resource}} {error "$label has an unsupported native Workspace field kind '$kind'"}}
    }
}
proc ::GX::pluginPackageRead {root} {
    variable version
    set mf [file join $root plugin-package.ini]
    if {![file isfile $mf]} { error "plugin-package.ini is missing from package root: $root" }
    set d [parseIni $mf]
    set api [descriptorValue $d package api_version ""]
    if {$api ne "1"} { error "Unsupported Plugin Install API version '$api' in $mf" }
    set id [pluginSafeId [descriptorValue $d package id ""]]
    set type [string tolower [string trim [descriptorValue $d package type ""]]]
    pluginTypeSpec $type
    set pver [string trim [descriptorValue $d package version ""]]
    if {$pver eq ""} { error "package.version is required in $mf" }
    set name [string trim [descriptorValue $d package name $id]]
    set minv [string trim [descriptorValue $d package framework_min "0.9.3"]]
    set maxv [string trim [descriptorValue $d package framework_max ""]]
    if {$minv ne "" && [pluginVersionCompare $version $minv] < 0} {
        error "Plugin $id $pver requires GX-TXT >= $minv (running $version)"
    }
    if {$maxv ne "" && [pluginVersionCompare $version $maxv] > 0} {
        error "Plugin $id $pver supports GX-TXT <= $maxv (running $version)"
    }
    set descriptor [pluginDescriptorPath $root $type]
    if {![file isfile $descriptor]} { error "Package $id does not contain the required [file tail $descriptor]" }
    set pd [parseIni $descriptor]
    if {$type eq {module}} {nativeWorkspaceDescriptorAdmission $pd "Package $id"}
    set did [string trim [descriptorValue $pd meta id ""]]
    set dver [string trim [descriptorValue $pd meta version ""]]
    if {$did ne $id} { error "Package id '$id' does not match descriptor meta.id '$did'" }
    if {$dver ne $pver} { error "Package version '$pver' does not match descriptor meta.version '$dver'" }
    if {[descriptorValue $pd meta api_version ""] ne "1"} { error "Descriptor for $id is not API version 1" }
    set docsApi [string trim [descriptorValue $pd documentation api_version ""]]
    if {$docsApi ne ""} {
        if {$docsApi ne "1"} { error "Package $id declares unsupported Documentation API '$docsApi'" }
        if {[string trim [descriptorValue $pd documentation guide ""]] eq ""} {
            error "Package $id declares Documentation API v1 without a guide"
        }
        foreach field {guide manual quick_start scientific_method parameter_reference tutorials examples changelog third_party_notices} {
            foreach rel [splitList [descriptorValue $pd documentation $field ""]] {
                if {[file pathtype $rel] ne "relative"} {
                    error "Package $id documentation path is not relative: $rel"
                }
                set resource [file normalize [file join $root $rel]]
                set packageRoot [file normalize $root]
                if {[string first "$packageRoot/" "$resource/"] != 0 || ![file isfile $resource]} {
                    error "Package $id declares missing or unsafe $field resource: $rel"
                }
            }
        }
    }
    if {$type eq {module} && ({RESTRICTED_VIEWER_CLIENT_API_v1} in [splitList [descriptorValue $pd public_apis ids {}]] || ([descriptorValue $pd meta kind {}] eq {preview} && [descriptorValue $pd preview_provider runtime {}] eq {managed_cpp}))} {
        # An installable C++ Viewer supplies its binary. Admission verifies the
        # actual artifact and current SDK/runtime; it never invokes Build.
        viewerDevelopmentPackageVerify $root
    }
    return [dict create root [file normalize $root] manifest $mf id $id type $type version $pver name $name descriptor $descriptor dict $d]
}

proc ::GX::pluginWalkPaths {root} {
    set out {}
    foreach p [glob -nocomplain -directory $root * .*] {
        set tail [file tail $p]
        if {$tail in {. ..}} continue
        lappend out $p
        if {[file isdirectory $p] && [file type $p] ne "link"} {
            lappend out {*}[pluginWalkPaths $p]
        }
    }
    return $out
}

proc ::GX::pluginValidateTree {root} {
    set r [file normalize $root]
    foreach p [pluginWalkPaths $r] {
        if {[file type $p] eq "link"} { error "Plugin packages may not contain symbolic links: $p" }
        if {[file type $p] ni {file directory}} {error "Plugin packages may contain only ordinary files and directories: $p"}
        set n [file normalize $p]
        if {![string match "$r/*" $n] && $n ne $r} { error "Package path escapes package root: $p" }
    }
}

proc ::GX::pluginZipEntrySafe {name} {
    set n [string map {\\ /} $name]
    if {$n eq ""} { return 1 }
    if {[string match "/*" $n] || [regexp {^[A-Za-z]:/} $n]} { return 0 }
    foreach part [split $n /] {
        if {$part eq ".."} { return 0 }
    }
    return 1
}

proc ::GX::pluginFindPackageManifests {root} {
    set out {}
    foreach p [pluginWalkPaths $root] {
        if {[file isfile $p] && [file tail $p] eq "plugin-package.ini"} { lappend out $p }
    }
    return $out
}

proc ::GX::pluginPackageOpen {source} {
    variable scriptDir
    set source [file normalize $source]
    if {[file isdirectory $source]} {
        pluginValidateTree $source
        return [dict merge [pluginPackageRead $source] [dict create temporary_root "" source $source]]
    }
    if {![file isfile $source]} { error "Plugin package not found: $source" }
    if {[file tail $source] eq "plugin-package.ini"} {
        set root [file dirname $source]
        pluginValidateTree $root
        return [dict merge [pluginPackageRead $root] [dict create temporary_root "" source $source]]
    }
    if {[string tolower [file extension $source]] ne ".zip"} {
        error "Choose a plugin-package.ini file, a package directory, or a .zip package"
    }
    if {[auto_execok unzip] eq ""} { error "ZIP plugin packages require the 'unzip' command" }
    set listing [exec unzip -Z1 -- $source]
    foreach line [split $listing "\n"] {
        set line [string trim $line]
        if {$line eq ""} continue
        if {![pluginZipEntrySafe $line]} { error "Unsafe path in plugin ZIP: $line" }
    }
    set stagingRoot [file join $scriptDir plugins .staging]
    file mkdir $stagingRoot
    set temp [file join $stagingRoot "open-[pid]-[clock clicks]"]
    file mkdir $temp
    if {[catch {exec unzip -qq -- $source -d $temp} e opts]} {
        file delete -force $temp
        return -options $opts $e
    }
    if {[catch {pluginValidateTree $temp} e opts]} {
        file delete -force $temp
        return -options $opts $e
    }
    set manifests [pluginFindPackageManifests $temp]
    if {[llength $manifests] != 1} {
        file delete -force $temp
        error "ZIP must contain exactly one plugin-package.ini; found [llength $manifests]"
    }
    set root [file dirname [lindex $manifests 0]]
    if {[catch {set info [pluginPackageRead $root]} e opts]} {
        file delete -force $temp
        return -options $opts $e
    }
    return [dict merge $info [dict create temporary_root $temp source $source]]
}

proc ::GX::pluginPackageClose {info} {
    if {[dict exists $info temporary_root]} {
        set t [dict get $info temporary_root]
        if {$t ne "" && [file exists $t]} { catch {file delete -force $t} }
    }
}

proc ::GX::pluginRegistrySetFromPackage {info {oldInstalledAt ""}} {
    variable pluginRegistry
    variable pluginRegistryOrder
    set id [dict get $info id]
    set now [clock format [clock seconds] -format {%Y-%m-%dT%H:%M:%S%z}]
    set pluginRegistry($id,id) $id
    set pluginRegistry($id,type) [dict get $info type]
    set pluginRegistry($id,version) [dict get $info version]
    set pluginRegistry($id,name) [dict get $info name]
    set pluginRegistry($id,installed_at) [expr {$oldInstalledAt ne "" ? $oldInstalledAt : $now}]
    set pluginRegistry($id,updated_at) $now
    set pluginRegistry($id,package_file) [file tail [dict get $info source]]
    if {[lsearch -exact $pluginRegistryOrder $id] < 0} { lappend pluginRegistryOrder $id }
}

proc ::GX::pluginRefreshAfterChange {} {
    pluginRegistryLoad
    loadModuleCatalog
    catch {rebuildNativeAnalysisGui}
    catch {refreshModuleCatalog}
    catch {refreshAnalysisStatus}
    catch {refreshManifestPreview}
    catch {refreshModuleDetails}
    catch {pluginInstallRefreshButtons}
    catch {sessionActionGuiRefresh}
    catch {configurationModulesReload}
    if {[llength [info commands ::GX::apiBrowserCatalogChanged]]} {apiBrowserCatalogChanged}
}

# mode: install (must be absent), update (must exist and be newer), auto (install or update).
proc ::GX::pluginInstallPackage {source {mode auto} {expectedId ""}} {
    variable scriptDir
    pluginRegistryLoad
    set info [pluginPackageOpen $source]
    try {
        set id [dict get $info id]
        set type [dict get $info type]
        set newver [dict get $info version]
        if {$expectedId ne "" && $id ne $expectedId} { error "Selected package id '$id' does not match expected plugin '$expectedId'" }
        set target [pluginTargetPath $type $id]
        # A dangling link is still an existing protected filesystem entry.
        # Following it with `file exists` would let rollback erase that entry.
        set exists [expr {![catch {file lstat $target installedStat}]}]
        set managed [pluginRegistryIsManaged $id]
        if {$mode eq "install" && $exists} { error "Plugin '$id' is already installed" }
        if {$mode eq "update" && !$exists} { error "Plugin '$id' is not installed" }
        set oldver {}
        if {$exists} {
            set targetBefore [pluginUpdateTargetInfo $type $id [expr {$mode eq {update}}]]
            set oldver [dict get $targetBefore version]
        }
        if {$exists && $oldver ne ""} {
            set cmp [pluginVersionCompare $newver $oldver]
            if {$mode eq "update" && $cmp <= 0} { error "Update must be newer than installed version $oldver (package is $newver)" }
            if {$mode eq "auto" && $cmp < 0} { error "Refusing downgrade from $oldver to $newver" }
        }

        if {[dict exists $::GX::pluginRuntimePending $id]} {
            pluginRuntimeTryPending $id
            if {[dict exists $::GX::pluginRuntimePending $id]} {error {This plugin already has a pending activation; close its editor or restart GX-TXT before another update.}}
        }
        set reg [pluginRegistryPath]
        set registryExisted [file isfile $reg]
        set registryBytes {}
        if {$registryExisted} {set f [open $reg rb];set registryBytes [read $f];close $f}
        set plan [pluginRuntimePrepareUpdate $type $id $target]
        set runtimeBefore [list $::GX::pluginRuntimeLoaded $::GX::pluginRuntimePending $::GX::pluginRuntimeReceipts]
        set parent [file dirname $target]
        file mkdir $parent
        set stage [file join $parent ".gx-install-[pid]-[clock clicks]"]
        set rollback [file join $parent ".gx-rollback-[pid]-[clock clicks]"]
        catch {file delete -force $stage}
        file mkdir $stage
        # Copy package CONTENTS, not package root itself.
        foreach p [glob -nocomplain -directory [dict get $info root] * .*] {
            set tail [file tail $p]
            if {$tail in {. ..}} continue
            file copy -force $p [file join $stage $tail]
        }
        pluginValidateTree $stage
        pluginPackageRead $stage
        # Revalidate after lifecycle callbacks/staging, before any replacement.
        if {$exists && ([catch {pluginUpdateTargetInfo $type $id [expr {$mode eq {update}}]} targetNow] || $targetNow ne $targetBefore)} {
            catch {file delete -force $stage}
            error {Installed plugin changed while preparing its update}
        }
        set registryNow {}
        if {[file isfile $reg]} {set f [open $reg rb];try {set registryNow [read $f]} finally {close $f}}
        if {[file isfile $reg] != $registryExisted || $registryNow ne $registryBytes} {
            catch {file delete -force $stage}
            error {Installed plugin registry changed while preparing its update}
        }
        set oldInstalledAt [expr {$managed ? [pluginInstalledField $id installed_at ""] : ""}]
        set hadTarget $exists
        if {$hadTarget} { file rename -force $target $rollback }
        if {[catch {
            file rename -force $stage $target
            # Discovery, registry and certified activation belong to the same
            # transaction. Keep the previous package until every step succeeds.
            loadModuleCatalog
            pluginRegistrySetFromPackage $info $oldInstalledAt
            pluginRegistryWrite
            pluginRefreshAfterChange
            set activation [pluginRuntimeActivate $id $target $newver $plan]
        } e opts]} {
            catch {file delete -force $target}
            if {$hadTarget && [file exists $rollback]} {file rename -force $rollback $target}
            catch {file delete -force $stage}
            if {$registryExisted} {
                file mkdir [file dirname $reg]
                set f [open $reg wb];puts -nonewline $f $registryBytes;close $f
            } else {catch {file delete -force $reg}}
            lassign $runtimeBefore ::GX::pluginRuntimeLoaded ::GX::pluginRuntimePending ::GX::pluginRuntimeReceipts
            set rollbackFailure {}
            if {[dict get $plan mode] eq "hot"} {
                if {[catch {_datasetPrivateWithModule $id [list uplevel #0 [list {*}[dict get $plan hook] rollback $target $oldver]]} why]} {set rollbackFailure "; lifecycle rollback failed; restart required: $why"}
            }
            catch {pluginRefreshAfterChange}
            dict set ::GX::pluginRuntimeReceipts $id [dict create status {Update failed} installed_version $oldver active_version [datasetPublicationV2DictDefault $plan active_version $oldver] reason "$e$rollbackFailure"]
            return -options $opts "Update failed: $e$rollbackFailure"
        }
        if {[dict get $plan mode] eq "restart" && $hadTarget} {
            # Preserve old code/assets while a live old implementation remains.
            # This hidden backup is outside normal descriptor discovery.
            dict set ::GX::pluginRuntimePending $id previous_root $rollback
            dict set ::GX::pluginRuntimePending $id previous_version $oldver
        } else {catch {file delete -force $rollback}}
        return [dict merge [dict create action [expr {$hadTarget ? "updated" : "installed"}] id $id type $type version $newver old_version $oldver target $target] $activation]
    } on error {message options} {
        if {[info exists id]} {
            set version [pluginInstalledField $id version {}]
            set active [expr {[dict exists $::GX::pluginRuntimeLoaded $id] ? [dict get $::GX::pluginRuntimeLoaded $id] : $version}]
            dict set ::GX::pluginRuntimeReceipts $id [dict create status {Update failed} installed_version $version active_version $active reason $message]
        }
        return -options $options $message
    } finally {
        if {[info exists stage] && [file exists $stage]} {catch {file delete -force $stage}}
        pluginPackageClose $info
    }
}

proc ::GX::pluginUninstall {type id} {
    variable pluginRegistry
    variable pluginRegistryOrder
    pluginRegistryLoad
    set id [pluginSafeId $id]
    if {$type eq "module" && ![moduleField $id selectable 1]} {
        # Acquisition availability is a runtime selection policy, not a ban on
        # removing a non-CORE managed package. Keep CORE, ownership and live
        # implementation/quiescence checks below, and the existing service rule.
        set libraryProvider [expr {[moduleField $id runner {}] eq {service} &&
            [info exists ::GX::moduleCatalog($id,dict)] &&
            [descriptorValue $::GX::moduleCatalog($id,dict) library_type_provider api_version {}] eq {1}}]
        if {!$libraryProvider && [moduleField $id kind {}] ne {acquisition}} {error "Module '$id' is ALWAYS and cannot be uninstalled."}
    }
    if {[pluginIsCore $type $id]} { error "Plugin '$id' is CORE and cannot be uninstalled." }
    if {![pluginRegistryIsManaged $id]} { error "Plugin '$id' is not managed by Plugin Install API v1" }
    set regType [pluginInstalledField $id type ""]
    if {$regType ne $type} { error "Plugin '$id' is registered as type '$regType', not '$type'" }
    set target [pluginTargetPath $type $id]
    if {![file exists $target]} { error "Managed plugin directory is missing: $target" }
    # Removal cannot retain the implementation/assets for an active provider.
    # Apply the existing runtime gate before disabling or renaming anything.
    pluginRuntimeCheckQuiescent $target
    if {$type eq "module" && [pluginRuntimeModuleLoaded $id]} {
        return -code error -errorcode {GX PLUGIN RESTART_REQUIRED} \
            "Plugin '$id' has a loaded implementation. Close GX-TXT and uninstall it from a fresh instance before using the plugin."
    }
    set parent [file dirname $target]
    set rollback [file join $parent ".gx-uninstall-[pid]-[clock clicks]"]
    if {$type eq "module"} { catch {moduleSetEnabled $id 0} }
    file rename -force $target $rollback
    if {[catch {loadModuleCatalog} e opts]} {
        catch {file rename -force $rollback $target}
        catch {loadModuleCatalog}
        return -options $opts $e
    }
    catch {file delete -force $rollback}
    foreach k [array names pluginRegistry "$id,*"] { unset pluginRegistry($k) }
    set pos [lsearch -exact $pluginRegistryOrder $id]
    if {$pos >= 0} { set pluginRegistryOrder [lreplace $pluginRegistryOrder $pos $pos] }
    pluginRegistryWrite
    pluginRefreshAfterChange
    return [dict create action uninstalled id $id type $type]
}

proc ::GX::pluginInstallChoosePackage {title} {
    set f [tk_getOpenFile -title $title -initialdir [pluginInstallInitialDirectory] -filetypes {{{GX-TXT plugin or bundle} {.zip plugin-package.ini plugin-bundle.ini}} {{ZIP archives} {.zip}} {{INI files} {.ini}} {{All files} *}}]
    return $f
}

proc ::GX::pluginInstallInitialDirectory {{configured __saved__}} {
    if {$configured eq "__saved__"} {set configured [configurationGet plugins.package_chooser_directory]}
    # Browsing preferences never change canonical package installation/storage.
    foreach directory [list $configured [file normalize ~] [pwd]] {
        if {$directory ne {} && [file isdirectory $directory] && [file readable $directory] && [file executable $directory]} {
            return [file normalize $directory]
        }
    }
    return [pwd]
}

proc ::GX::pluginInstallUiInstall_before_bundle_v1 {} {
    set f [pluginInstallChoosePackage "Install GX-TXT plugin"]
    if {$f eq ""} return
    if {[catch {set r [pluginInstallPackage $f install]} e]} {
        tk_messageBox -icon error -title "Plugin installation failed" -message $e
        return
    }
    tk_messageBox -icon info -title "Plugin installed" -message "Installed [dict get $r id] version [dict get $r version]."
}

proc ::GX::pluginInstallUiUpdateSelected {} {
    set id [pluginManagerSelectedId]
    if {$id eq ""} { return }
    set type [lindex [.gxPluginManager.tree item [lindex [.gxPluginManager.tree selection] 0] -values] 1]
    if {[catch {pluginUpdateTargetInfo $type $id 1} reason]} {
        tk_messageBox -icon info -title "Plugin update" -message $reason
        return
    }
    set f [pluginInstallChoosePackage "Update $id"]
    if {$f eq ""} return
    if {[catch {set r [pluginInstallPackage $f update $id]} e]} {
        set receipt [pluginRuntimeInfo $id]
        dict set receipt status {Update failed}
        dict set receipt reason $e
        dict set ::GX::pluginRuntimeReceipts $id $receipt
        set ::GX::ui(pluginManagerStatus) "Update failed: $e"
        tk_messageBox -icon error -title "Update failed" -message $e
        return
    }
    set ::GX::ui(pluginManagerStatus) "[dict get $r status]: $id [dict get $r version] (active [dict get $r active_version])."
    tk_messageBox -icon info -title [dict get $r status] -message "$::GX::ui(pluginManagerStatus)\n[dict get $r reason]"
}

proc ::GX::pluginInstallUiUninstallSelected {} {
    set id [selectedModuleFromTree]
    if {$id eq ""} return
    if {[pluginIsCore module $id]} {
        tk_messageBox -icon info -title "Plugin uninstall" -message "The selected module is CORE. CORE plugins are distribution-protected and cannot be removed; enable/disable state is independent."
        return
    }
    if {![pluginRegistryIsManaged $id]} {
        tk_messageBox -icon info -title "Plugin uninstall" -message "The selected module is bundled or unmanaged and will not be removed by the plugin manager."
        return
    }
    set ver [pluginInstalledField $id version ""]
    set ans [tk_messageBox -icon warning -type yesno -default no -title "Uninstall plugin" -message "Uninstall $id version $ver?\n\nSession datasets and previous analysis results are NOT deleted."]
    if {$ans ne "yes"} return
    if {[catch {pluginUninstall module $id} e]} {
        tk_messageBox -icon error -title "Plugin uninstall failed" -message $e
        return
    }
    tk_messageBox -icon info -title "Plugin uninstalled" -message "Plugin $id was removed. Session data was left unchanged."
}

proc ::GX::pluginInstallRefreshButtons {} {
    if {![winfo exists .gxPluginManager.buttons.update]} return
    set id [pluginManagerSelectedId]
    set managed [expr {$id ne "" && [pluginRegistryIsManaged $id]}]
    set updateable 0
    set updateReason {}
    if {$id ne {}} {
        set type [lindex [.gxPluginManager.tree item [lindex [.gxPluginManager.tree selection] 0] -values] 1]
        # Selection is metadata-only. Full checksum/native package admission is
        # reserved for the user's explicit Update, never a discovery side effect.
        set updateable [expr {![catch {pluginUpdateTargetInfo $type $id 1 0} updateReason]}]
        if {$updateable} {set updateReason {}}
    }
    .gxPluginManager.buttons.update state [expr {$updateable ? "!disabled" : "disabled"}]
    set removable $managed
    if {$managed} {
        set type [pluginInstalledField $id type]
        if {[pluginIsCore $type $id] || ($type eq "module" && ![moduleField $id selectable 1] && [moduleField $id kind {}] ne {acquisition})} {set removable 0}
    }
    .gxPluginManager.buttons.remove state [expr {$removable ? "!disabled" : "disabled"}]
    if {$id ne {} && [winfo exists .gxPluginManager.status]} {
        set runtime [pluginRuntimeInfo $id]
        set ownership [expr {$managed ? {Managed package} : {Bundled descriptor; registration occurs only after a successful explicit Update}}]
        set row [.gxPluginManager.tree item [lindex [.gxPluginManager.tree selection] 0] -values]
        set ::GX::ui(pluginManagerStatus) "$ownership. $id. Installed [lindex $row 2]; active [dict get $runtime active_version]. [dict get $runtime reason] $updateReason"
    } elseif {[winfo exists .gxPluginManager.status]} {
        set ::GX::ui(pluginManagerStatus) {Select an installed plugin to inspect its installed and active implementation versions.}
    }
}
proc ::GX::pluginManagerSelectedId {} {
    if {![winfo exists .gxPluginManager.tree]} {return ""}
    set selection [.gxPluginManager.tree selection]
    if {[llength $selection] != 1} {return ""}
    return [lindex [.gxPluginManager.tree item [lindex $selection 0] -values] 0]
}

proc ::GX::pluginManagerRefresh {} {
    variable pluginRegistryOrder
    pluginRegistryLoad
    if {![winfo exists .gxPluginManager.tree]} return
    set t .gxPluginManager.tree
    set selected [pluginManagerSelectedId]
    set query [expr {[info exists ::GX::ui(pluginManagerQuery)] ? [string tolower [string trim $::GX::ui(pluginManagerQuery)]] : {}}]
    foreach i [$t children {}] { $t delete $i }
    array unset ::GX::ui pluginManagerId,*
    set n 0
    set records {}
    foreach record [configurationInstalledPlugins] {dict set records [dict get $record id] $record}
    foreach id $pluginRegistryOrder {
        if {![dict exists $records $id]} {dict set records $id [dict create id $id type [pluginInstalledField $id type] version [pluginInstalledField $id version] name [pluginInstalledField $id name]]}
    }
    foreach id [lsort -dictionary [dict keys $records]] {
        set record [dict get $records $id]
        incr n
        set bid [pluginInstalledField $id bundle_id ""]
        set bver [pluginInstalledField $id bundle_version ""]
        set btxt [expr {$bid eq "" ? "" : "$bid $bver"}]
        set runtime [pluginRuntimeInfo $id]
        set status [dict get $runtime status]
        if {![pluginRegistryIsManaged $id]} {set status {Bundled / not registered}}
        set values [list $id [dict get $record type] [dict get $record version] $btxt [dict get $record name] [dict get $runtime active_version] $status]
        if {$query ne {} && [string first $query [string tolower [join $values { }]]]<0} continue
        $t insert {} end -id "p$n" -values $values
        set ::GX::ui(pluginManagerId,p$n) $id
        if {$id eq $selected} {$t selection set p$n}
    }
    pluginInstallRefreshButtons
}

proc ::GX::pluginManagerResetFilter {} {
    set ::GX::ui(pluginManagerQuery) {}
    pluginManagerRefresh
    focus .gxPluginManager.search.query
}

proc ::GX::pluginManagerResize {widget width} {
    if {$widget eq ".gxPluginManager"} {.gxPluginManager.status configure -wraplength [expr {max(220,$width-20)}]}
}

proc ::GX::pluginManagerTableSchedule {tree} {
    if {![winfo exists $tree] || ![winfo ismapped $tree] || $::GX::pluginManagerLayoutAfter ne {}} return
    set ::GX::pluginManagerLayoutAfter [after idle [list ::GX::pluginManagerTableLayout $tree [winfo id $tree]]]
}
proc ::GX::pluginManagerTableLayout {tree identity} {
    set ::GX::pluginManagerLayoutAfter {}
    if {![winfo exists $tree] || ![winfo ismapped $tree] || [winfo id $tree] ne $identity} return
    _uiFieldTreeFontRows $tree GXPluginManager.Treeview
    foreach column [$tree cget -columns] {
        set minimum [expr {[font measure TkHeadingFont [$tree heading $column -text]]+22}]
        if {[$tree column $column -minwidth]!=$minimum} {$tree column $column -minwidth $minimum}
        if {[$tree column $column -width]<$minimum} {$tree column $column -width $minimum}
    }
}
proc ::GX::pluginManagerTableDispose {tree actual} {
    if {$tree eq $actual && $::GX::pluginManagerLayoutAfter ne {}} {
        after cancel $::GX::pluginManagerLayoutAfter
        set ::GX::pluginManagerLayoutAfter {}
    }
}

proc ::GX::pluginManagerDialog {} {
    catch {destroy .gxPluginManager}
    toplevel .gxPluginManager
    wm title .gxPluginManager "Plugin Manager"
    wm geometry .gxPluginManager 850x420
    grid columnconfigure .gxPluginManager 0 -weight 1
    grid rowconfigure .gxPluginManager 1 -weight 1
    set ::GX::ui(pluginManagerQuery) {}
    ttk::frame .gxPluginManager.search
    ttk::label .gxPluginManager.search.label -text {Filter plugins}
    ttk::entry .gxPluginManager.search.query -textvariable ::GX::ui(pluginManagerQuery)
    ttk::button .gxPluginManager.search.reset -text Reset -command ::GX::pluginManagerResetFilter
    pack .gxPluginManager.search.label -side left -padx 4
    pack .gxPluginManager.search.reset -side right -padx 4
    pack .gxPluginManager.search.query -side left -fill x -expand 1 -padx 4
    bind .gxPluginManager.search.query <KeyRelease> ::GX::pluginManagerRefresh
    bind .gxPluginManager.search.query <Escape> ::GX::pluginManagerResetFilter
    grid .gxPluginManager.search -row 0 -column 0 -columnspan 2 -sticky ew -padx 4 -pady 6
    ttk::treeview .gxPluginManager.tree -columns {id type version bundle name active status} -show headings -selectmode browse
    _uiFieldTreeFontRows .gxPluginManager.tree GXPluginManager.Treeview
    foreach event {<Map> <Configure> <<ThemeChanged>>} {bind .gxPluginManager.tree $event +[list ::GX::pluginManagerTableSchedule .gxPluginManager.tree]}
    bind .gxPluginManager.tree <Destroy> +[list ::GX::pluginManagerTableDispose .gxPluginManager.tree %W]
    foreach {c title width} {id "Plugin ID" 200 type "Type" 80 version "Installed" 80 bundle "Bundle" 110 name "Name" 180 active "Active" 75 status "Activation" 190} {
        .gxPluginManager.tree heading $c -text $title
        .gxPluginManager.tree column $c -width $width -stretch 1
    }
    ttk::scrollbar .gxPluginManager.sy -orient vertical -command {.gxPluginManager.tree yview}
    ttk::scrollbar .gxPluginManager.sx -orient horizontal -command {.gxPluginManager.tree xview}
    .gxPluginManager.tree configure -yscrollcommand {.gxPluginManager.sy set} -xscrollcommand {.gxPluginManager.sx set}
    ttk::frame .gxPluginManager.buttons
    ttk::button .gxPluginManager.buttons.install -text "Install..." -command {::GX::pluginInstallUiInstall; ::GX::pluginManagerRefresh}
    ttk::button .gxPluginManager.buttons.update -text "Update selected…" -command {::GX::pluginInstallUiUpdateSelected; ::GX::pluginManagerRefresh}
    bind .gxPluginManager.tree <<TreeviewSelect>> ::GX::pluginInstallRefreshButtons
    ttk::button .gxPluginManager.buttons.remove -text "Uninstall selected" -command {
        set s [.gxPluginManager.tree selection]
        if {[llength $s] == 1} {
            set iid [lindex $s 0]
            if {[info exists ::GX::ui(pluginManagerId,$iid)]} {
                set id $::GX::ui(pluginManagerId,$iid)
                set type [::GX::pluginInstalledField $id type]
                if {[tk_messageBox -icon warning -type yesno -default no -title "Uninstall plugin" -message "Uninstall $id?"] eq "yes"} {
                    if {[catch {::GX::pluginUninstall $type $id} e]} { tk_messageBox -icon error -message $e } else { ::GX::pluginManagerRefresh }
                }
            }
        }
    }
    ttk::button .gxPluginManager.buttons.close -text "Close" -command {destroy .gxPluginManager}
    pack .gxPluginManager.buttons.install .gxPluginManager.buttons.update .gxPluginManager.buttons.remove .gxPluginManager.buttons.close -side left -padx 4
    grid .gxPluginManager.tree -row 1 -column 0 -sticky nsew -padx {8 0} -pady 8
    grid .gxPluginManager.sy -row 1 -column 1 -sticky ns -pady 8
    grid .gxPluginManager.sx -row 2 -column 0 -sticky ew -padx {8 0}
    grid .gxPluginManager.buttons -row 3 -column 0 -columnspan 2 -sticky w -padx 8 -pady {0 8}
    if {![info exists ::GX::ui(pluginManagerStatus)]} {set ::GX::ui(pluginManagerStatus) {Installed package and active implementation versions are shown separately.}}
    ttk::label .gxPluginManager.status -textvariable ::GX::ui(pluginManagerStatus) -wraplength 820 -justify left
    grid .gxPluginManager.status -row 4 -column 0 -columnspan 2 -sticky ew -padx 8 -pady {0 8}
    bind .gxPluginManager <Configure> [list ::GX::pluginManagerResize %W %w]
    pluginManagerRefresh
}

# Main Modules page has no installation actions; Configuration opens the
# existing single manager. Retain the composition hook for existing callers.
proc ::GX::pluginInstallAttachGui {} {}

proc ::GX::scriptModuleBuilderOpen {} {
    set python [runtimeToolRequired python]
    set descriptor [moduleField tool.script_module_builder descriptor ""]
    if {$descriptor eq ""} { error "Script Module Builder tool is unavailable." }
    set d [parseIni $descriptor]
    set relative [descriptorValue $d tool entrypoint ""]
    set builder [file normalize [file join [file dirname $descriptor] $relative]]
    if {![string match "[file dirname $descriptor]/*" $builder]} { error "Unsafe Script Module Builder tool path." }
    if {![file isfile $builder]} { error "Script Module Builder is missing: $builder" }
    set command [list $python -B $builder gui]
    if {[info exists ::GX::currentSession] && $::GX::currentSession ne {} && [file isdirectory $::GX::currentSession]} {lappend command --session [file normalize $::GX::currentSession]}
    exec {*}$command &
}

# Surface package-management state in ordinary module details.
proc ::GX::moduleHelpText {id} {
    set out [::GX::moduleHelpText_before_plugin_install_v1 $id]
    if {[pluginIsCore module $id]} {
        append out "\n\nPLUGIN CLASS\nCORE (bundled/distribution-protected; not removable). Enable/disable state is independent from CORE status.\n"
    }
    if {[pluginRegistryIsManaged $id]} {
        append out "\n\nPLUGIN PACKAGE\nManaged by Plugin Install API v1\nInstalled version: [pluginInstalledField $id version]\nInstalled: [pluginInstalledField $id installed_at]\nLast update: [pluginInstalledField $id updated_at]\n"
        set bid [pluginInstalledField $id bundle_id ""]
        if {$bid ne ""} { append out "Bundle: $bid [pluginInstalledField $id bundle_version ""]\n" }
    } else {
        append out "\n\nPLUGIN PACKAGE\nBundled / unmanaged (not removable by Plugin Install API v1).\n"
    }
    return $out
}

# Attach package-manager controls after the historical GUI has been created.
proc ::GX::launchGui_before_viewer_provider {} {
    ::GX::launchGui_before_plugin_install_v1
    pluginRegistryLoad
    pluginInstallAttachGui
}
