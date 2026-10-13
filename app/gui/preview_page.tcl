# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::buildPreviewPage {} {
    variable ui
    set f .top.nb.preview
    grid columnconfigure $f 0 -weight 1
    grid rowconfigure $f 2 -weight 1
    ttk::frame $f.buttons
    ttk::button $f.buttons.apply -text {Use detected CSV structure} -command ::GX::applyDetectedCsvLayout
    ttk::button $f.buttons.render -text Render -command ::GX::datasetPreviewRender
    pack $f.buttons.apply -side left -padx 4
    text $f.txt -wrap none -font TkFixedFont -state disabled
    ttk::scrollbar $f.sy -orient vertical -command [list $f.txt yview]
    ttk::scrollbar $f.sx -orient horizontal -command [list $f.txt xview]
    $f.txt configure -yscrollcommand [list $f.sy set] -xscrollcommand [list $f.sx set]
    grid $f.txt -row 2 -column 0 -sticky nsew -padx {5 0}
    grid $f.sy -row 2 -column 1 -sticky ns
    grid $f.sx -row 3 -column 0 -sticky ew -padx {5 0}
    set ui(preview) $f.txt
    ttk::frame $f.actions -relief raised -borderwidth 1
    ttk::label $f.actions.grip -text ⋮ -cursor fleur
    pack $f.actions.grip -side left
    bind $f.actions.grip <ButtonPress-1> {::GX::datasetPreviewToolsDrag start %X %Y}
    bind $f.actions.grip <B1-Motion> {::GX::datasetPreviewToolsDrag move %X %Y}
    foreach {key glyph command tip} {
        copy copy {copyTextWidget .top.nb.preview.txt {Dataset Preview}} {Copy all readable text; embedded image pixels are not copied}
        pages table {datasetPreviewOpenSelectedTable preview} {Read canonical table pages; unavailable for Pending or opaque payloads}
        clear close datasetPreviewClear {Clear visualization; keep this Dataset and its inspection text}
    } {
        ttk::button $f.actions.$key -image [native2DViewportGlyph $glyph] -command [list ::GX::datasetPageAction {*}$command]
        pack $f.actions.$key -side left -padx 2
        bind $f.actions.$key <Enter> [list ::GX::native2DViewportTooltipShow %W $tip]
        bind $f.actions.$key <Leave> {catch {destroy .gxViewportTip}}
    }
    bind $f.txt <Configure> {::GX::datasetPreviewToolsPlace}
    datasetPreviewToolsPlace
}
