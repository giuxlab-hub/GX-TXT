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
}

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
    set fd [open $path w]
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
}

proc ::GX::pluginRegistryIsManaged {id} {
    variable pluginRegistry
    if {![info exists pluginRegistry($id,id)]} { pluginRegistryLoad }
    return [expr {[info exists pluginRegistry($id,id)] ? 1 : 0}]
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
        set exists [file exists $target]
        set managed [pluginRegistryIsManaged $id]
        if {$mode eq "install" && $exists} { error "Plugin '$id' is already installed" }
        if {$mode eq "update" && !$exists} { error "Plugin '$id' is not installed" }
        if {$exists && !$managed} {
            error "Plugin '$id' already exists but is not managed by Plugin Install API v1; refusing to overwrite it"
        }
        set oldver [expr {$managed ? [pluginInstalledField $id version ""] : ""}]
        if {$exists && $oldver ne ""} {
            set cmp [pluginVersionCompare $newver $oldver]
            if {$mode eq "update" && $cmp <= 0} { error "Update must be newer than installed version $oldver (package is $newver)" }
            if {$mode eq "auto" && $cmp < 0} { error "Refusing downgrade from $oldver to $newver" }
        }

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
        set oldInstalledAt [expr {$managed ? [pluginInstalledField $id installed_at ""] : ""}]
        set hadTarget [file exists $target]
        if {$hadTarget} { file rename -force $target $rollback }
        if {[catch {
            file rename -force $stage $target
            # Validate the complete live discovery before committing registry state.
            loadModuleCatalog
        } e opts]} {
            catch {file delete -force $target}
            if {$hadTarget && [file exists $rollback]} { catch {file rename -force $rollback $target} }
            catch {file delete -force $stage}
            catch {loadModuleCatalog}
            return -options $opts $e
        }
        catch {file delete -force $rollback}
        pluginRegistrySetFromPackage $info $oldInstalledAt
        pluginRegistryWrite
        pluginRefreshAfterChange
        return [dict create action [expr {$hadTarget ? "updated" : "installed"}] id $id type $type version $newver old_version $oldver target $target]
    } finally {
        pluginPackageClose $info
    }
}

proc ::GX::pluginUninstall {type id} {
    variable pluginRegistry
    variable pluginRegistryOrder
    pluginRegistryLoad
    set id [pluginSafeId $id]
    if {$type eq "module" && ![moduleField $id selectable 1]} {error "Module '$id' is ALWAYS and cannot be uninstalled."}
    if {[pluginIsCore $type $id]} { error "Plugin '$id' is CORE and cannot be uninstalled." }
    if {![pluginRegistryIsManaged $id]} { error "Plugin '$id' is not managed by Plugin Install API v1" }
    set regType [pluginInstalledField $id type ""]
    if {$regType ne $type} { error "Plugin '$id' is registered as type '$regType', not '$type'" }
    set target [pluginTargetPath $type $id]
    if {![file exists $target]} { error "Managed plugin directory is missing: $target" }
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
    set f [tk_getOpenFile -title $title -filetypes {{{GX-TXT plugin or bundle} {.zip plugin-package.ini plugin-bundle.ini}} {{ZIP archives} {.zip}} {{INI files} {.ini}} {{All files} *}}]
    return $f
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
    if {![pluginRegistryIsManaged $id]} {
        tk_messageBox -icon info -title "Plugin update" -message "The selected module is bundled or unmanaged and cannot be updated through Plugin Install API v1."
        return
    }
    set f [pluginInstallChoosePackage "Update $id"]
    if {$f eq ""} return
    if {[catch {set r [pluginInstallPackage $f update $id]} e]} {
        tk_messageBox -icon error -title "Plugin update failed" -message $e
        return
    }
    tk_messageBox -icon info -title "Plugin updated" -message "Updated $id from [dict get $r old_version] to [dict get $r version]."
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
    .gxPluginManager.buttons.update state [expr {$managed ? "!disabled" : "disabled"}]
    set removable $managed
    if {$managed} {
        set type [pluginInstalledField $id type]
        if {[pluginIsCore $type $id] || ($type eq "module" && ![moduleField $id selectable 1])} {set removable 0}
    }
    .gxPluginManager.buttons.remove state [expr {$removable ? "!disabled" : "disabled"}]
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
    foreach i [$t children {}] { $t delete $i }
    set n 0
    foreach id $pluginRegistryOrder {
        incr n
        set bid [pluginInstalledField $id bundle_id ""]
        set bver [pluginInstalledField $id bundle_version ""]
        set btxt [expr {$bid eq "" ? "" : "$bid $bver"}]
        $t insert {} end -id "p$n" -values [list $id [pluginInstalledField $id type] [pluginInstalledField $id version] $btxt [pluginInstalledField $id name]]
        set ::GX::ui(pluginManagerId,p$n) $id
        if {$id eq $selected} {$t selection set p$n}
    }
    pluginInstallRefreshButtons
    if {[llength [info commands configurationModulesReload]]} {configurationModulesReload}
}

proc ::GX::pluginManagerDialog {} {
    catch {destroy .gxPluginManager}
    toplevel .gxPluginManager
    wm title .gxPluginManager "Plugin Manager"
    wm geometry .gxPluginManager 850x420
    grid columnconfigure .gxPluginManager 0 -weight 1
    grid rowconfigure .gxPluginManager 0 -weight 1
    ttk::treeview .gxPluginManager.tree -columns {id type version bundle name} -show headings -selectmode browse
    foreach {c title width} {id "Plugin ID" 240 type "Type" 130 version "Version" 85 bundle "Bundle" 210 name "Name" 260} {
        .gxPluginManager.tree heading $c -text $title
        .gxPluginManager.tree column $c -width $width -stretch 1
    }
    ttk::scrollbar .gxPluginManager.sy -orient vertical -command {.gxPluginManager.tree yview}
    .gxPluginManager.tree configure -yscrollcommand {.gxPluginManager.sy set}
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
    grid .gxPluginManager.tree -row 0 -column 0 -sticky nsew -padx {8 0} -pady 8
    grid .gxPluginManager.sy -row 0 -column 1 -sticky ns -pady 8
    grid .gxPluginManager.buttons -row 1 -column 0 -columnspan 2 -sticky w -padx 8 -pady {0 8}
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
    exec $python -B $builder gui &
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
