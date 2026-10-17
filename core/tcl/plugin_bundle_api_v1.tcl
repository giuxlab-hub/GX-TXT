# GX-TXT Plugin Bundle / Package Set API v1
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Giuseppe Lanzani / giux-lab.it
#
# A bundle is only an atomic orchestration layer above Plugin Install API v1.
# It never installs plugin files directly into live destinations: every member
# is ultimately committed by ::GX::pluginInstallPackage.

namespace eval ::GX {
    variable pluginBundleApiVersion 1
}

proc ::GX::pluginBundleSafeRelativePath {p} {
    set p [string trim [string map {\\ /} $p]]
    if {$p eq ""} { error "Bundle package path is empty" }
    if {[file pathtype $p] ne "relative" || [string match "/*" $p] || [regexp {^[A-Za-z]:/} $p]} {
        error "Bundle package path must be relative: $p"
    }
    foreach part [split $p /] {
        if {$part in {"" . ..}} { error "Unsafe bundle package path: $p" }
    }
    return $p
}

proc ::GX::pluginBundleManifestRead {root} {
    variable version
    set root [file normalize $root]
    set mf [file join $root plugin-bundle.ini]
    if {![file isfile $mf]} { error "plugin-bundle.ini is missing from bundle root: $root" }
    set d [parseIni $mf]
    set api [descriptorValue $d bundle api_version ""]
    if {$api ne "1"} { error "Unsupported Plugin Bundle API version '$api' in $mf" }
    set id [pluginSafeId [descriptorValue $d bundle id ""]]
    set name [string trim [descriptorValue $d bundle name $id]]
    set bver [string trim [descriptorValue $d bundle version ""]]
    if {$bver eq ""} { error "bundle.version is required in $mf" }
    set minv [string trim [descriptorValue $d bundle framework_min "0.9.3.2"]]
    set maxv [string trim [descriptorValue $d bundle framework_max ""]]
    if {$minv ne "" && [pluginVersionCompare $version $minv] < 0} {
        error "Bundle $id $bver requires GX-TXT >= $minv (running $version)"
    }
    if {$maxv ne "" && [pluginVersionCompare $version $maxv] > 0} {
        error "Bundle $id $bver supports GX-TXT <= $maxv (running $version)"
    }
    set rawPaths [descriptorValue $d packages paths ""]
    set relPaths [splitList $rawPaths]
    if {[llength $relPaths] == 0} { error "Bundle $id does not declare any packages.paths" }

    set packageInfos {}
    set seenIds {}
    set seenTargets {}
    foreach rel $relPaths {
        set rel [pluginBundleSafeRelativePath $rel]
        set pkgRoot [file normalize [file join $root {*}[split $rel /]]]
        if {![string match "$root/*" $pkgRoot]} { error "Bundle package path escapes bundle root: $rel" }
        if {![file isdirectory $pkgRoot]} { error "Bundle package directory not found: $rel" }
        pluginValidateTree $pkgRoot
        set info [pluginPackageRead $pkgRoot]
        set pid [dict get $info id]
        set target [pluginTargetPath [dict get $info type] $pid]
        if {[lsearch -exact $seenIds $pid] >= 0} { error "Bundle contains duplicate plugin id '$pid'" }
        if {[lsearch -exact $seenTargets $target] >= 0} { error "Bundle contains duplicate install target '$target'" }
        lappend seenIds $pid
        lappend seenTargets $target
        dict set info bundle_relative_path $rel
        lappend packageInfos $info
    }
    return [dict create root $root manifest $mf id $id name $name version $bver framework_min $minv framework_max $maxv package_paths $relPaths packages $packageInfos dict $d]
}

proc ::GX::pluginBundleOpen {source} {
    variable scriptDir
    set source [file normalize $source]
    if {[file isdirectory $source]} {
        pluginValidateTree $source
        return [dict merge [pluginBundleManifestRead $source] [dict create temporary_root "" source $source]]
    }
    if {![file isfile $source]} { error "Plugin bundle not found: $source" }
    if {[file tail $source] eq "plugin-bundle.ini"} {
        set root [file dirname $source]
        pluginValidateTree $root
        return [dict merge [pluginBundleManifestRead $root] [dict create temporary_root "" source $source]]
    }
    if {[string tolower [file extension $source]] ne ".zip"} {
        error "Choose a plugin-bundle.ini file, a bundle directory, or a .zip bundle"
    }
    if {[auto_execok unzip] eq ""} { error "ZIP plugin bundles require the 'unzip' command" }
    set listing [exec unzip -Z1 -- $source]
    set bundleEntries {}
    foreach line [split $listing "\n"] {
        set line [string trim $line]
        if {$line eq ""} continue
        if {![pluginZipEntrySafe $line]} { error "Unsafe path in plugin bundle ZIP: $line" }
        if {[file tail [string map {\\ /} $line]] eq "plugin-bundle.ini"} { lappend bundleEntries $line }
    }
    if {[llength $bundleEntries] != 1} { error "Bundle ZIP must contain exactly one plugin-bundle.ini; found [llength $bundleEntries]" }
    set stagingRoot [file join $scriptDir plugins .staging]
    file mkdir $stagingRoot
    set temp [file join $stagingRoot "bundle-open-[pid]-[clock clicks]"]
    file mkdir $temp
    if {[catch {exec unzip -qq -- $source -d $temp} e opts]} {
        file delete -force $temp
        return -options $opts $e
    }
    if {[catch {pluginValidateTree $temp} e opts]} {
        file delete -force $temp
        return -options $opts $e
    }
    set manifest [lindex [pluginFindNamedFiles $temp plugin-bundle.ini] 0]
    if {$manifest eq ""} {
        file delete -force $temp
        error "plugin-bundle.ini disappeared after extraction"
    }
    set root [file dirname $manifest]
    if {[catch {set info [pluginBundleManifestRead $root]} e opts]} {
        file delete -force $temp
        return -options $opts $e
    }
    return [dict merge $info [dict create temporary_root $temp source $source]]
}

proc ::GX::pluginFindNamedFiles {root filename} {
    set out {}
    if {[file isfile [file join $root $filename]]} { lappend out [file join $root $filename] }
    foreach p [pluginWalkPaths $root] {
        if {[file isfile $p] && [file tail $p] eq $filename && [lsearch -exact $out $p] < 0} { lappend out $p }
    }
    return $out
}

proc ::GX::pluginBundleClose {info} {
    if {[dict exists $info temporary_root]} {
        set t [dict get $info temporary_root]
        if {$t ne "" && [file exists $t]} { catch {file delete -force $t} }
    }
}

proc ::GX::pluginBundlePreflightPackage {info mode} {
    pluginRegistryLoad
    set id [dict get $info id]
    set type [dict get $info type]
    set newver [dict get $info version]
    set target [pluginTargetPath $type $id]
    set exists [file exists $target]
    set managed [pluginRegistryIsManaged $id]
    if {$mode eq "install" && $exists} { error "Plugin '$id' is already installed" }
    if {$mode eq "update" && !$exists} { error "Plugin '$id' is not installed" }
    if {$exists && !$managed} { error "Plugin '$id' exists but is not managed by Plugin Install API v1" }
    set oldver [expr {$managed ? [pluginInstalledField $id version ""] : ""}]
    if {$exists && $oldver ne ""} {
        set cmp [pluginVersionCompare $newver $oldver]
        if {$mode eq "update" && $cmp <= 0} { error "Update of '$id' must be newer than installed version $oldver (package is $newver)" }
        if {$mode eq "auto" && $cmp < 0} { error "Refusing downgrade of '$id' from $oldver to $newver" }
    }
    return [dict create id $id type $type version $newver target $target exists $exists managed $managed old_version $oldver]
}

proc ::GX::pluginBundleCopyContents {src dst} {
    catch {file delete -force $dst}
    file mkdir $dst
    foreach p [glob -nocomplain -directory $src * .*] {
        set tail [file tail $p]
        if {$tail in {. ..}} continue
        file copy -force $p [file join $dst $tail]
    }
    pluginValidateTree $dst
}

proc ::GX::pluginBundleRestoreTransaction {txn snapshots registryBackup registryExisted} {
    set reg [pluginRegistryPath]
    foreach snap [lreverse $snapshots] {
        set target [dict get $snap target]
        catch {file delete -force $target}
        if {[dict get $snap existed]} {
            set backup [dict get $snap backup]
            if {[file exists $backup]} {
                file mkdir [file dirname $target]
                catch {file copy -force $backup $target}
            }
        }
    }
    if {$registryExisted} {
        file mkdir [file dirname $reg]
        catch {file copy -force $registryBackup $reg}
    } else {
        catch {file delete -force $reg}
    }
    catch {pluginRefreshAfterChange}
    catch {file delete -force $txn}
}

# mode follows Plugin Install API v1 semantics: install, update, auto.
# All members are validated and pre-staged before the first live commit.  Each
# live commit is delegated to pluginInstallPackage; this API is not a second
# plugin installer.
proc ::GX::pluginInstallBundle {source {mode install}} {
    variable scriptDir
    variable pluginRegistry
    if {$mode ni {install update auto}} { error "Unsupported bundle install mode '$mode'" }
    pluginRegistryLoad
    set bundle ""
    set txn ""
    set previousDefer $::GX::pluginRuntimeDeferActivation
    set runtimeBefore [list $::GX::pluginRuntimeLoaded $::GX::pluginRuntimePending $::GX::pluginRuntimeReceipts]
    try {
        set bundle [pluginBundleOpen $source]
        set bid [dict get $bundle id]
        set bver [dict get $bundle version]
        set packageInfos [dict get $bundle packages]

        # 1. Validate every member and every destination/version conflict before
        #    anything is written to a live plugin destination.
        set checks {}
        foreach pinfo $packageInfos { lappend checks [pluginBundlePreflightPackage $pinfo $mode] }
        foreach pinfo $packageInfos {pluginRuntimePrepareUpdate [dict get $pinfo type] [dict get $pinfo id] [pluginTargetPath [dict get $pinfo type] [dict get $pinfo id]]}

        # 2. Stage every package as a validated package tree before committing
        #    any member. This also makes the transaction independent of an
        #    external source directory changing midway through installation.
        set txnRoot [file join $scriptDir plugins .staging]
        file mkdir $txnRoot
        set txn [file join $txnRoot "bundle-txn-[pid]-[clock clicks]"]
        file mkdir [file join $txn staged]
        file mkdir [file join $txn rollback]
        set staged {}
        set snapshots {}
        set i 0
        foreach pinfo $packageInfos chk $checks {
            incr i
            set sid [format "%03d-%s" $i [dict get $pinfo id]]
            set stage [file join $txn staged $sid]
            pluginBundleCopyContents [dict get $pinfo root] $stage
            # Re-read the staged descriptor so all members are known-good before commit.
            set stagedInfo [pluginPackageRead $stage]
            lappend staged [dict create path $stage info $stagedInfo]

            set target [dict get $chk target]
            set existed [file exists $target]
            set backup [file join $txn rollback $sid]
            if {$existed} { pluginBundleCopyContents $target $backup }
            lappend snapshots [dict create target $target existed $existed backup $backup]
        }

        # Snapshot registry before the first member commit.
        set reg [pluginRegistryPath]
        set registryExisted [file isfile $reg]
        set registryBackup [file join $txn registry-before.ini]
        if {$registryExisted} { file copy -force $reg $registryBackup }

        # 3. Commit every member using the existing Plugin Install API. Registry
        #    provenance and the final discovery are part of the same transaction:
        #    any error through the final refresh restores every live target and
        #    the exact pre-bundle registry.
        set results {}
        set ::GX::pluginRuntimeDeferActivation 1
        if {[catch {
            foreach item $staged {
                lappend results [pluginInstallPackage [dict get $item path] $mode]
            }
            loadModuleCatalog

            # 4. Tag the normal per-plugin registry entries with bundle provenance.
            pluginRegistryLoad
            set sourceTail [file tail [dict get $bundle source]]
            foreach pinfo $packageInfos {
                set id [dict get $pinfo id]
                set pluginRegistry($id,bundle_id) $bid
                set pluginRegistry($id,bundle_version) $bver
                set pluginRegistry($id,package_file) $sourceTail
            }
            pluginRegistryWrite
            pluginRefreshAfterChange
        } e opts]} {
            pluginBundleRestoreTransaction $txn $snapshots $registryBackup $registryExisted
            set retainedRoots {}
            dict for {module pending} [lindex $runtimeBefore 1] {if {[dict exists $pending previous_root]} {lappend retainedRoots [dict get $pending previous_root]}}
            dict for {module pending} $::GX::pluginRuntimePending {
                if {[dict exists $pending previous_root] && [dict get $pending previous_root] ni $retainedRoots} {catch {file delete -force [dict get $pending previous_root]}}
            }
            lassign $runtimeBefore ::GX::pluginRuntimeLoaded ::GX::pluginRuntimePending ::GX::pluginRuntimeReceipts
            set txn ""
            return -options $opts "Bundle '$bid' installation failed and was rolled back: $e"
        }

        catch {file delete -force $txn}
        set txn ""
        return [dict create kind bundle action [expr {$mode eq "update" ? "bundle_updated" : "bundle_installed"}] id $bid name [dict get $bundle name] version $bver packages $results package_count [llength $results]]
    } finally {
        set ::GX::pluginRuntimeDeferActivation $previousDefer
        if {$txn ne "" && [file exists $txn]} { catch {file delete -force $txn} }
        if {$bundle ne ""} { pluginBundleClose $bundle }
    }
}

proc ::GX::pluginSourceIsBundle {source} {
    if {$source eq "" || ![file exists $source]} { return 0 }
    if {[file isdirectory $source]} { return [file isfile [file join $source plugin-bundle.ini]] }
    if {[file tail $source] eq "plugin-bundle.ini"} { return 1 }
    if {[string tolower [file extension $source]] ne ".zip" || [auto_execok unzip] eq ""} { return 0 }
    if {[catch {set listing [exec unzip -Z1 -- $source]}]} { return 0 }
    set n 0
    foreach line [split $listing "\n"] {
        if {[file tail [string map {\\ /} [string trim $line]]] eq "plugin-bundle.ini"} { incr n }
    }
    return [expr {$n == 1}]
}

proc ::GX::pluginInstallAny {source {mode install}} {
    if {[pluginSourceIsBundle $source]} { return [pluginInstallBundle $source $mode] }
    return [dict merge [dict create kind package] [pluginInstallPackage $source $mode]]
}

# Extend the existing Install action: the same GUI button accepts either a
# single Plugin Install API package or a Plugin Bundle API package set.
proc ::GX::pluginInstallUiInstall {} {
    set f [pluginInstallChoosePackage "Install GX-TXT plugin or bundle"]
    if {$f eq ""} return
    if {[catch {set r [pluginInstallAny $f install]} e]} {
        tk_messageBox -icon error -title "Plugin installation failed" -message $e
        return
    }
    if {[dict get $r kind] eq "bundle"} {
        tk_messageBox -icon info -title "Plugin bundle installed" -message "Installed bundle [dict get $r id] version [dict get $r version] ([dict get $r package_count] packages)."
    } else {
        tk_messageBox -icon info -title "Plugin installed" -message "Installed [dict get $r id] version [dict get $r version]."
    }
    catch {pluginManagerRefresh}
}
