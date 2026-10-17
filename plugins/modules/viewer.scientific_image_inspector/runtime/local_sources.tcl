# Explicit user-chosen read-only local files; transient UI sources, not Dataset identities.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::SII {variable localFiles [dict create]}
rename ::GX::SII::datasetIds ::GX::SII::canonicalDatasetIds
proc ::GX::SII::datasetIds {} {
    variable localFiles
    return [concat [canonicalDatasetIds] [lsort [dict keys $localFiles]]]
}
rename ::GX::SII::sourceInfo ::GX::SII::canonicalSourceInfo
proc ::GX::SII::sourceInfo {sourceId} {
    variable localFiles
    if {[dict exists $localFiles $sourceId]} {
        set info [dict get $localFiles $sourceId]
        set path [dict get $info path]
        if {![file isfile $path] || [file type $path] ne "file"} {error {Local file is no longer available}}
        if {[::GX::sha256File $path] ne [dict get $info sha256]} {error {Local file changed; reopen it explicitly}}
        return $info
    }
    return [canonicalSourceInfo $sourceId]
}
proc ::GX::SII::openLocalFile {} {
    variable ui
    variable localFiles
    set filename [tk_getOpenFile -parent $ui(window) -title {Open image without importing} \
        -filetypes {{{Raster images} {.png .jpg .jpeg .bmp .tif .tiff}} {{All files} *}}]
    if {$filename eq ""} return
    if {[catch {
        set filename [file normalize $filename]
        if {![file isfile $filename] || [file type $filename] ne "file"} {error {Select a regular image file}}
        inspectFile $filename
        set sha [::GX::sha256File $filename]
        set id "local:[string range $sha 0 11]"
        dict set localFiles $id [dict create id $id sha256 $sha path $filename contract image.raster \
            metadata {} format [string trimleft [string tolower [file extension $filename]] .] \
            media_type image/raster size_bytes [file size $filename] local_file 1]
        refreshSources
        set ui(sourceId) $id
        loadSource
        set ui(status) {Local file opened read-only. Export is available; canonical Dataset publication requires an imported Dataset.}
    } err]} {guiError $err}
}
