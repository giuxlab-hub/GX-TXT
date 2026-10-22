# GX-TXT Documentation Browser API v1.
# SPDX-License-Identifier: GPL-3.0-or-later
# Plugin descriptors own their manuals. This index is rebuilt from the live
# catalog so plugin install, update and removal cannot leave stale documents.
namespace eval ::GX {
    variable documentationBrowserEntries [dict create]
    variable documentationBrowserOrder {}
    variable documentationBrowserPackageIssues {}
}

proc ::GX::documentationBrowserApiInfo {} {
    return [dict create api_name DOCUMENTATION_BROWSER_API_v1 api_version 1 source descriptor_index host_operations {documentationBrowserOpenModuleWindow documentationBrowserAttachViewerHelp documentationBrowserOpenApi documentationBrowserResolve documentationBrowserModuleTutorials}]
}

proc ::GX::documentationBrowserAdd {id category title type path {owner ""} {version ""}} {
    variable documentationBrowserEntries
    variable documentationBrowserOrder
    if {$path ne ""} {
        set path [file normalize $path]
        if {![file isfile $path]} return
        if {[string tolower [file extension $path]] ni {.md .markdown .txt .html .htm} && $type ne "license"} return
    }
    dict set documentationBrowserEntries $id [dict create id $id category $category title $title \
        type $type path $path owner $owner version $version]
    lappend documentationBrowserOrder $id
}

# Fixed installed package discovery extends this same descriptor-backed index.
# It does not install archives or maintain another registry.
proc ::GX::documentationBrowserContainedFile {root relative {maximum 2097152}} {
    set root [file normalize $root]
    if {[file pathtype $relative] ne {relative} || [string first \\ $relative]>=0 || [string first % $relative]>=0 || [string first \x00 $relative]>=0} {error {Documentation asset path must be an ordinary package-relative path.}}
    set path $root
    foreach part [file split $relative] {
        if {$part in {{} . ..}} {error {Documentation asset traversal is unsupported.}}
        set path [file join $path $part]
        if {[file exists $path] && [file type $path] eq {link}} {error {Linked documentation assets are unsupported.}}
    }
    set path [file normalize $path]
    if {[string first "$root/" "$path/"]!=0 || ![file isfile $path] || [file type $path] ne {file} || [file size $path]>$maximum} {error {Documentation asset is missing, outside its package or oversized.}}
    return $path
}
proc ::GX::documentationBrowserPackageRead {manifest} {
    set docs [file normalize [file join $::GX::scriptDir docs]]
    if {[string first "$docs/" "$manifest/"]!=0} {error {Documentation package is outside installed framework documentation.}}
    set relative [string range $manifest [expr {[string length $docs]+1}] end]
    set manifest [documentationBrowserContainedFile $docs $relative 16384]
    set root [file normalize [file dirname $manifest]]
    if {[string first "$docs/guides/" "$root/"]!=0 && [string first "$docs/tutorials/" "$root/"]!=0} {error {Documentation package is outside supported installed roots.}}
    set d [parseIni $manifest]
    set required {api_version id module_id kind version title entrypoint entry_sha256 license}
    set optional {tested_module_version generator_library_id generator_id tested_generator_version}
    foreach key [dict keys $d] {
        if {![string match documentation_package.* $key] || [string range $key 22 end] ni [concat $required $optional]} {error {Unknown version-1 documentation package field.}}
    }
    foreach key $required {if {![dict exists $d documentation_package.$key] || [dict get $d documentation_package.$key] eq {}} {error "Missing documentation package field '$key'."}}
    foreach key [concat $required $optional] {dict set values $key [descriptorValue $d documentation_package $key {}]}
    if {[dict get $values api_version] ne {1}} {error {Unsupported documentation package manifest version.}}
    foreach key {id module_id} {if {![regexp {^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$} [dict get $values $key]]} {error {Invalid documentation content/module identity.}}}
    if {[dict get $values kind] ni {manual tutorial}} {error {Documentation package kind must be manual or tutorial.}}
    if {![regexp {^[A-Za-z0-9][A-Za-z0-9.+_-]{0,63}$} [dict get $values version]]} {error {Invalid documentation content version.}}
    foreach key {title license tested_module_version tested_generator_version} {
        set value [dict get $values $key]
        if {[string bytelength $value]>256 || [regexp {[\x00\r\n]} $value]} {error {Documentation display/provenance text is invalid or oversized.}}
    }
    set module [dict get $values module_id]
    if {[moduleField $module descriptor {}] eq {}} {error {Documentation package owner module is not installed.}}
    set relative [dict get $values entrypoint]
    if {[string tolower [file extension $relative]] ni {.html .htm}} {error {Documentation package entrypoint must be HTML.}}
    set path [documentationBrowserContainedFile $root $relative]
    set sha [dict get $values entry_sha256]
    if {![regexp {^[0-9a-f]{64}$} $sha] || [sha256File $path] ne $sha} {error {Documentation package entrypoint hash mismatch.}}
    set library [dict get $values generator_library_id];set generator [dict get $values generator_id]
    if {($library eq {}) != ($generator eq {})} {error {Generator library and generator IDs must be declared together.}}
    foreach value [list $library $generator] {if {$value ne {} && ![regexp {^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$} $value]} {error {Invalid declared generator identity.}}}
    return [dict merge $values [dict create path $path asset_root $root manifest_path $manifest manifest_sha256 [sha256File $manifest]]]
}
proc ::GX::documentationBrowserPackagesRefresh {} {
    variable documentationBrowserEntries;variable documentationBrowserPackageIssues
    set documentationBrowserPackageIssues {};set candidates {};set manualOwners {}
    set docs [file normalize [file join $::GX::scriptDir docs]]
    set paths [concat [glob -nocomplain [file join $docs guides * * documentation-package.ini]] [glob -nocomplain [file join $docs tutorials * * documentation-package.ini]]]
    if {[llength $paths]>1024} {dict set documentationBrowserPackageIssues catalog {Installed documentation package count exceeds1024.};return}
    foreach manifest [lsort -dictionary $paths] {
        if {[catch {set package [documentationBrowserPackageRead $manifest]} reason]} {dict set documentationBrowserPackageIssues $manifest $reason;continue}
        set id [dict get $package id]
        dict lappend candidates $id $package
        if {[dict get $package kind] eq {manual}} {dict lappend manualOwners [dict get $package module_id] $id}
    }
    dict for {id packages} $candidates {
        if {[llength $packages]!=1} {dict set documentationBrowserPackageIssues $id {Conflicting installed content ID; no version was guessed.};continue}
        set package [lindex $packages 0];set module [dict get $package module_id];set kind [dict get $package kind]
        if {$kind eq {manual} && [llength [lsort -unique [dict get $manualOwners $module]]]!=1} {dict set documentationBrowserPackageIssues $id {Conflicting installed manuals for this module.};continue}
        set key content:$id
        set category [expr {$kind eq {manual}?{Plugin manuals}:{Tutorials / DEMOs}}]
        documentationBrowserAdd $key $category [dict get $package title] $kind [dict get $package path] $module [dict get $package version]
        set entry [dict get $documentationBrowserEntries $key]
        dict set entry format html
        foreach field {asset_root manifest_path manifest_sha256 entry_sha256 generator_library_id generator_id tested_generator_version tested_module_version license} {dict set entry $field [dict get $package $field]}
        dict set entry content_id $id
        dict set documentationBrowserEntries $key $entry
        # Selection alias does not replace or modify module:MODULE:guide reads.
        if {$kind eq {manual}} {dict set entry id module:$module:html_manual;dict set documentationBrowserEntries module:$module:html_manual $entry}
    }
}
proc ::GX::documentationBrowserResolve {id} {
    variable documentationBrowserEntries
    if {![dict exists $documentationBrowserEntries $id]} {error "Unknown documentation ID '$id'."}
    set entry [dict get $documentationBrowserEntries $id]
    set path [dict get $entry path]
    if {$path eq {}} {error {This documentation entry has no renderable source file.}}
    if {[dict exists $entry asset_root]} {
        if {[moduleField [dict get $entry owner] descriptor {}] eq {}} {error {Documentation package owner module is no longer installed.}}
        set root [dict get $entry asset_root]
        set relative [string range $path [expr {[string length $root]+1}] end]
        set path [documentationBrowserContainedFile $root $relative]
        set manifest [dict get $entry manifest_path]
        if {![file isfile $manifest] || [file type $manifest] eq {link} || [sha256File $manifest] ne [dict get $entry manifest_sha256]} {error {Documentation package manifest changed; refresh the catalog.}}
        if {[sha256File $path] ne [dict get $entry entry_sha256]} {error {Documentation package source changed; refresh the catalog.}}
    } else {
        set module [dict get $entry owner];set descriptor [moduleField $module descriptor {}]
        set root [file dirname $path]
        if {$descriptor ne {}} {
            set moduleRoot [file normalize [file dirname $descriptor]]
            if {[string first "$moduleRoot/" "$path/"]==0} {set root $moduleRoot}
        }
        set relative [string range $path [expr {[string length $root]+1}] end]
        set path [documentationBrowserContainedFile $root $relative]
    }
    dict set entry path $path;dict set entry asset_root $root;dict set entry source_sha256 [sha256File $path]
    set extension [string tolower [file extension $path]]
    dict set entry format [expr {$extension in {.html .htm}?{html}:($extension in {.md .markdown}?{markdown}:{text})}]
    return $entry
}
proc ::GX::documentationBrowserModuleTutorials {module} {
    set rows {}
    foreach entry [documentationBrowserList] {
        if {[dict get $entry owner] eq $module && [dict get $entry type] eq {tutorial}} {lappend rows $entry}
    }
    return $rows
}

proc ::GX::documentationBrowserRefresh {} {
    variable documentationBrowserEntries
    variable documentationBrowserOrder
    variable scriptDir
    variable moduleOrder
    set documentationBrowserEntries [dict create]
    set documentationBrowserOrder {}
    foreach {id title} {
        getting_started {Getting started} sessions Sessions datasets Datasets
        acquisition {Acquisition / Import} analysis {Analysis modules} viewers Viewers
        instrumentation Instrumentation plotting Plotting scripting Scripting
        tutorials {Tutorials / DEMOs}
    } {
        documentationBrowserAdd "core:$id" {GX-TXT guide} $title guide \
            [file join $scriptDir docs help "$id.md"] framework $::GX::version
    }
    documentationBrowserAdd core:license {License and About} {GX-TXT license — GPLv3} license \
        [file join $scriptDir LICENSE] framework $::GX::version
    documentationBrowserAdd core:third_party {License and About} {Scientific reference licenses} notice \
        [file join $scriptDir docs api REFERENCE_DATABASE_LICENSES.md] framework $::GX::version
    documentationBrowserAdd core:about {License and About} {About GX-TXT} about "" framework $::GX::version
    foreach path [lsort -dictionary [glob -nocomplain -directory [file join $scriptDir docs api] *.md]] {
        set name [file rootname [file tail $path]]
        documentationBrowserAdd "api:$name" {API references} $name api $path framework $::GX::version
    }
    # Provider API references may live beside their implementation rather than
    # under docs/api. The existing descriptor resolver owns path/ambiguity rules.
    foreach module $moduleOrder {
        set info [documentationDescriptorInfo module $module]
        if {$info eq {}} continue
        lassign $info descriptor d name
        foreach api [splitList [descriptorValue $d public_apis ids {}]] {
            if {[dict exists $documentationBrowserEntries api:$api]} continue
            set path [documentationResolveApiRef $api]
            if {$path ne {}} {documentationBrowserAdd api:$api {API references} $api api $path $module [moduleField $module version {}]}
        }
    }
    foreach spec [list [list module $moduleOrder] [list model $::GX::modelOrder] \
        [list analysis_definition $::GX::analysisDefinitionOrder] [list instrument $::GX::instrumentOrder]] {
        lassign $spec kind ids
        foreach id $ids {
        set info [documentationDescriptorInfo $kind $id]
        if {![llength $info]} continue
        lassign $info descriptor d moduleName
        set root [file normalize [file dirname $descriptor]]
        set version [descriptorValue $d meta version ""]
        foreach {field type label} {
            guide guide Guide manual manual Manual quick_start quick_start {Quick start}
            scientific_method scientific_method {Scientific method}
            parameter_reference parameter_reference {Parameter reference}
            changelog changelog Changelog
            third_party_notices notice {Third-party notices}
        } {
            set rel [string trim [descriptorValue $d documentation $field ""]]
            if {$rel eq ""} continue
            if {$field eq "guide" && [string equal -nocase [file tail $rel] MANUAL.md]} {
                set type manual
                set label Manual
            }
            set path [file normalize [file join $root $rel]]
            if {[string first "$root/" "$path/"] != 0} continue
            set category [expr {$type eq "notice" ? "License and About" : "Plugin manuals"}]
            documentationBrowserAdd "$kind:$id:$field" $category "$moduleName — $label" $type $path $id $version
        }
        foreach rel [splitList [descriptorValue $d documentation tutorials ""]] {
            set path [file normalize [file join $root $rel]]
            if {[string first "$root/" "$path/"] != 0} continue
            documentationBrowserAdd "$kind:$id:tutorial:[file tail $rel]" {Tutorials / DEMOs} \
                "$moduleName — [file tail $rel]" tutorial $path $id $version
        }
        }
    }
    documentationBrowserPackagesRefresh
    return $documentationBrowserOrder
}

proc ::GX::documentationBrowserList {{query ""}} {
    variable documentationBrowserEntries
    variable documentationBrowserOrder
    set query [string tolower [string trim $query]]
    set out {}
    foreach id $documentationBrowserOrder {
        set entry [dict get $documentationBrowserEntries $id]
        if {$query ne "" && [string first $query [string tolower \
            "$id [dict get $entry category] [dict get $entry title] [dict get $entry owner]"]] < 0} continue
        # Keep the original public projection. Script Bridge strips only path;
        # host-only asset/manifest metadata must not acquire Script exposure.
        set public {}
        foreach key {id category title type path owner version} {dict set public $key [dict get $entry $key]}
        lappend out $public
    }
    return $out
}

proc ::GX::documentationBrowserRead {id} {
    variable documentationBrowserEntries
    if {![dict exists $documentationBrowserEntries $id]} { error "Unknown documentation ID '$id'." }
    set entry [dict get $documentationBrowserEntries $id]
    if {[dict exists $entry entry_sha256]} {set entry [documentationBrowserResolve $id]}
    if {[dict get $entry type] eq "about"} {
        return "# About GX-TXT\n\nVersion: $::GX::version\n\nGX-TXT is a Session-centered scientific acquisition, analysis and visualization framework.\n\nLicense: GPL-3.0-or-later. See the License page for the full text.\n\nProject: giux-lab.it\n"
    }
    set path [dict get $entry path]
    if {[file size $path] > 2097152} { error "Documentation file exceeds the 2 MiB browser limit." }
    set fd [open $path r]
    fconfigure $fd -encoding utf-8
    try { return [read $fd] } finally { close $fd }
}

# Plugin Install API reloads the module catalog on install, update and removal.
# Keep an already open Help tree synchronized with the same live catalog.
# Final descriptor discovery path delegates through the named registry layers.
proc ::GX::loadModuleCatalog {} {
    ::GX::loadModuleCatalog_before_documentation_browser
    documentationBrowserRefresh
    configurationChanged {}
    if {[llength [info commands winfo]] && [winfo exists .top.nb.help.left.tree] &&
        [llength [info commands ::GX::documentationBrowserPopulate]]} {
        documentationBrowserPopulate
    }
}

proc ::GX::sessionDocumentationSnapshotModule {moduleId {session ""}} {
    if {$session eq ""} { set session $::GX::currentSession }
    if {$session eq "" || ![file isdirectory $session]} { error "Open a Session before recording module documentation." }
    set descriptor [moduleField $moduleId descriptor ""]
    if {$descriptor eq ""} { error "Unknown module '$moduleId'." }
    set d [parseIni $descriptor]
    set rel [string trim [descriptorValue $d documentation guide ""]]
    if {$rel eq ""} return
    set moduleRoot [file normalize [file dirname $descriptor]]
    set source [file normalize [file join $moduleRoot $rel]]
    if {[string first "$moduleRoot/" "$source/"] != 0 || ![file isfile $source]} {
        error "Module '$moduleId' declares an unavailable guide."
    }
    set version [moduleField $moduleId version ""]
    if {![regexp {^[0-9A-Za-z._-]+$} $version]} { error "Invalid module version for documentation snapshot." }
    set hash [sha256File $source]
    set base [file join [file normalize $session] metadata documentation $moduleId]
    set target [file join $base "$version-$hash"]
    if {[file isfile [file join $target record.ini]]} { return $target }
    file mkdir $base
    set stage [file join $base ".snapshot-[pid]-[clock clicks]"]
    file mkdir $stage
    try {
        file copy -- $source [file join $stage manual.md]
        if {[sha256File [file join $stage manual.md]] ne $hash} { error "Documentation changed while snapshotting." }
        set fd [open [file join $stage record.ini] w]
        fconfigure $fd -encoding utf-8 -translation lf
        try {
            puts $fd {[documentation]}
            foreach {key value} [list module_id $moduleId module_version $version module_name [moduleField $moduleId name $moduleId] \
                source_document $rel sha256 $hash framework_version $::GX::version \
                captured_at [clock format [clock seconds] -gmt 1 -format {%Y-%m-%dT%H:%M:%SZ}]] {
                putKV $fd $key $value
            }
        } finally { close $fd }
        file rename -- $stage $target
    } on error {message options} {
        if {[file exists $stage]} { file delete -force -- $stage }
        return -options $options $message
    }
    return $target
}

proc ::GX::runNextAnalysis_before_plan_status {} {
    if {[llength $::GX::analysisQueue]} {
        set item [lindex $::GX::analysisQueue 0]
        if {[llength $item] >= 3 && [lindex $item 2] ne ""} {
            if {[catch {sessionDocumentationSnapshotModule [lindex $item 2]} problem]} {
                catch {stopAnalysis 0}
                if {[llength [info commands ::GX::runPlanStatus]]} {
                    catch {runPlanStatus [lindex $item 2] FAILED "Documentation snapshot failed: $problem"}
                }
                tk_messageBox -icon error -title "GX-TXT documentation" \
                    -message "Analysis cannot start: $problem"
                return
            }
        }
    }
    ::GX::runNextAnalysis_before_documentation_snapshot
}
