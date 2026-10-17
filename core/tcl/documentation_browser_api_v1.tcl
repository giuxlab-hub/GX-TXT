# GX-TXT Documentation Browser API v1.
# SPDX-License-Identifier: GPL-3.0-or-later
# Plugin descriptors own their manuals. This index is rebuilt from the live
# catalog so plugin install, update and removal cannot leave stale documents.
namespace eval ::GX {
    variable documentationBrowserEntries [dict create]
    variable documentationBrowserOrder {}
}

proc ::GX::documentationBrowserApiInfo {} {
    return [dict create api_name DOCUMENTATION_BROWSER_API_v1 api_version 1 source descriptor_index host_operations {documentationBrowserOpenModuleWindow documentationBrowserAttachViewerHelp}]
}

proc ::GX::documentationBrowserAdd {id category title type path {owner ""} {version ""}} {
    variable documentationBrowserEntries
    variable documentationBrowserOrder
    if {$path ne ""} {
        set path [file normalize $path]
        if {![file isfile $path]} return
        if {[string tolower [file extension $path]] ni {.md .markdown .txt} && $type ne "license"} return
    }
    dict set documentationBrowserEntries $id [dict create id $id category $category title $title \
        type $type path $path owner $owner version $version]
    lappend documentationBrowserOrder $id
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
        lappend out $entry
    }
    return $out
}

proc ::GX::documentationBrowserRead {id} {
    variable documentationBrowserEntries
    if {![dict exists $documentationBrowserEntries $id]} { error "Unknown documentation ID '$id'." }
    set entry [dict get $documentationBrowserEntries $id]
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
