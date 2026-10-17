# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::sessionPreviewCacheBuild {parent} {
    set f $parent.previewCache
    if {[winfo exists $f]} {return $f}
    datasetPreviewCacheInit
    ttk::frame $f -padding 8
    ttk::frame $f.tools;pack $f.tools -fill x -pady 5
    foreach {id label operation} {refresh Refresh refresh regenerate Regenerate regenerate clear {Clear selected} clear all {Clear all} all} {
        ttk::button $f.tools.$id -text $label -command [list ::GX::sessionPreviewCacheAction $operation]
        pack $f.tools.$id -side left -padx 3
    }
    ttk::label $f.notice -text {Disposable graphical representations. Clearing this cache preserves canonical Datasets, sources, Graphs and Workspaces.} -wraplength 1000 -anchor w
    pack $f.notice -fill x -pady 6
    ttk::treeview $f.tree -columns {dataset kind status generated size revision error} -show headings -selectmode extended
    foreach {column label width} {dataset Dataset 260 kind Representation 100 status Status 90 generated Generated 170 size Bytes 80 revision {Source SHA / render key} 220 error Error 250} {$f.tree heading $column -text $label;$f.tree column $column -width $width -stretch 1}
    ttk::scrollbar $f.scroll -command [list $f.tree yview];$f.tree configure -yscrollcommand [list $f.scroll set]
    pack $f.scroll -side right -fill y;pack $f.tree -fill both -expand 1
    ttk::frame $f.policy;pack $f.policy -side bottom -fill x -pady 5
    set ::GX::ui(previewCacheEnabled) [configurationGet preview.cache_enabled];set ::GX::ui(previewCacheMiB) [configurationGet preview.cache_mib]
    ttk::checkbutton $f.policy.enabled -text {Prepare automatically after publication} -variable ::GX::ui(previewCacheEnabled)
    ttk::label $f.policy.label -text {Session limit (MiB)};ttk::entry $f.policy.limit -textvariable ::GX::ui(previewCacheMiB) -width 6
    ttk::button $f.policy.apply -text {Save policy} -command [list ::GX::sessionPreviewCacheAction policy]
    pack $f.policy.enabled $f.policy.label $f.policy.limit $f.policy.apply -side left -padx 6
    return $f
}
proc ::GX::sessionPreviewCacheAction {operation} {
    set f .top.nb.sessionfiles.previewCache
    if {![winfo exists $f]} return
    if {[catch {
        set keys [$f.tree selection]
        switch $operation {
            policy {configurationSet preview.cache_enabled $::GX::ui(previewCacheEnabled);configurationSet preview.cache_mib $::GX::ui(previewCacheMiB);configurationSave}
            clear {if {$keys ne {}} {datasetPreviewCacheClear $::GX::currentSession $keys}}
            all {datasetPreviewCacheClear $::GX::currentSession}
            regenerate {
                foreach key $keys {set id [$f.tree set $key dataset];if {$id ne {} && [datasetField $id id {}] ne {}} {datasetPreviewCacheClear $::GX::currentSession [list $key];datasetPreviewCacheRequest $id {} [list ::GX::_sessionPreviewCacheReady]}}
            }
            refresh {}
            default {error {Unknown Preview Cache action}}
        }
        $f.tree delete [$f.tree children {}]
        foreach item [datasetPreviewCacheInventory $::GX::currentSession] {
            $f.tree insert {} end -id [dict get $item key] -values [list [dict get $item dataset_id] [dict get $item kind] [dict get $item status] [dict get $item generated_at] [dict get $item size_bytes] "[dict get $item source_revision] / [dict get $item key]" [dict get $item error]]
        }
    } message]} {$f.notice configure -text $message}
}
proc ::GX::_sessionPreviewCacheReady {response} {if {[winfo exists .top.nb.sessionfiles.previewCache]} {sessionPreviewCacheAction refresh}}
