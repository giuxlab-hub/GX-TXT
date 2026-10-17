# SPDX-License-Identifier: GPL-3.0-or-later
# Dataset consultation shares the installed native engine; no script evaluation.
namespace eval ::GX::DocumentSource {variable serial 0}
proc ::GX::documentNativeEnsure {} {
    if {![llength [info commands ::GX::NativeDocument::xml]]} {
        set library [file join $::GX::scriptDir core nativegui document libgxtxt_document[info sharedlibextension]]
        if {![file isfile $library]} {error {Native document/source capability is unavailable; install the matching native library.}}
        load $library Gxtxtdocument
    }
}
proc ::GX::xmlDocumentApiInfo {} {return [dict create api_id XML_DOCUMENT_API_v1 api_version 1 owner CORE native_engine libxml2 operations {create parse parse_file root describe append insert text add_text attribute remove move query serialize write release} limits {input_bytes 4194304 depth 64 nodes 50000 documents 64} entities disabled network disabled]}
proc ::GX::xmlDocument {operation args} {
    documentNativeEnsure
    if {$operation eq {parse_file}} {
        set path [lindex $args 0]
        if {![file isfile $path] || [file type $path] eq {link} || [file size $path]>4194304} {error {XML input must be a regular authorized file of at most 4 MiB}}
        set ch [open $path rb];try {set text [encoding convertfrom utf-8 [read $ch]]} finally {close $ch}
        return [::GX::NativeDocument::xml parse $text]
    }
    if {$operation eq {write}} {
        lassign $args document destination
        if {[llength $args]!=2} {error {XML write requires document and explicitly authorized destination}}
        return [filePublicationTextDocument $destination [::GX::NativeDocument::xml serialize $document 0] text]
    }
    return [::GX::NativeDocument::xml $operation {*}$args]
}
proc ::GX::documentRenderModel {language source} {
    documentNativeEnsure
    return [::GX::NativeDocument::render $language $source]
}
proc ::GX::documentRenderToWidget {widget language source} {
    set model [documentRenderModel $language $source]
    $widget configure -state normal -wrap word
    $widget delete 1.0 end
    $widget tag configure heading -font TkHeadingFont -spacing1 10 -spacing3 6
    $widget tag configure bold -font [list [font actual TkDefaultFont -family] [font actual TkDefaultFont -size] bold]
    $widget tag configure italic -font [list [font actual TkDefaultFont -family] [font actual TkDefaultFont -size] italic]
    foreach tag {code tag attribute string} {$widget tag configure $tag -font TkFixedFont}
    $widget tag configure tag -foreground #084c9e
    $widget tag configure attribute -foreground #753b00
    $widget tag configure link -foreground #064ca8 -underline 1
    foreach run $model {lassign $run tag text;$widget insert end $text $tag}
    if {$language eq {html}} {$widget insert end "\n\nSafe minimal HTML: scripts, external assets, forms and CSS are inactive. Images are omitted.\n"}
    $widget configure -state disabled
    return [dict create renderer native_c language $language runs [llength $model]]
}
proc ::GX::datasetDocumentKind {id} {
    set contract [datasetField $id contract [datasetField $id kind {}]]
    if {$contract ni {document.text code.source}} {return {}}
    set media [string tolower [datasetField $id media_type {}]]
    set metadata [datasetMetadataRead $::GX::currentSession $id]
    set language {};foreach key {code.language text.language} {if {[dict exists $metadata $key]} {set language [string tolower [dict get $metadata $key]];break}}
    set payload [sessionInspectionDatasetPayload $id]
    set extension [string tolower [file extension [dict get $payload path]]]
    if {$media eq {text/markdown} || $language eq {markdown}} {return markdown}
    if {$media eq {text/html} || $language eq {html}} {return html}
    if {$media in {application/xml text/xml} || $language eq {xml}} {return xml}
    if {$language ne {} && $language ni {unknown plaintext}} {return code}
    if {$media ni {{} text/plain application/octet-stream}} {return {}}
    if {$extension in {.md .markdown}} {return markdown}
    if {$extension in {.html .htm}} {return html}
    if {$extension eq {.xml}} {return xml}
    if {$contract eq {code.source}} {return code}
    return {}
}
proc ::GX::datasetDocumentRead {id {limit 262144}} {
    set payload [sessionInspectionDatasetPayload $id]
    set file [dict get $payload path]
    if {[sha256File $file] ne [dict get $payload sha256]} {error {Canonical document integrity changed}}
    set ch [open $file r];fconfigure $ch -encoding utf-8
    try {set text [read $ch $limit];set complete [eof $ch]} finally {close $ch}
    return [dict create source $text complete $complete sha256 [dict get $payload sha256]]
}
proc ::GX::datasetDocumentRender {widget id} {
    set kind [datasetDocumentKind $id]
    set read [datasetDocumentRead $id]
    set source [dict get $read source]
    if {[winfo exists $widget.source_surface]} {destroy $widget.source_surface}
    if {$kind eq {code}} {
        set notice [expr {[dict get $read complete] ? {Read-only canonical source consultation} : {Bounded source Preview: first 256 Ki characters. Open for a larger consultation.}}]
        set text [sourceSurfaceCreate $widget.source_surface [dict create mode read_only language [sourceSurfaceDatasetLanguage $id] notice $notice]]
        place $widget.source_surface -relx 0 -rely 0 -relwidth 1 -relheight 1
        sourceSurfaceSet $text $source
        return 1
    }
    if {$kind eq {markdown}} {markupRenderStringToWidget $widget $source
    } elseif {$kind in {html xml}} {documentRenderToWidget $widget $kind $source
    } else {return 0}
    if {![dict get $read complete]} {$widget configure -state normal;$widget insert end "\n\nTruncated preview: first 256 Ki characters. Open for a larger bounded consultation.\n";$widget configure -state disabled}
    return 1
}
proc ::GX::datasetDocumentOpen {id {obeyAssociation 1}} {
    set kind [datasetDocumentKind $id]
    if {$obeyAssociation && $kind in {markdown html}} {
        set command [configurationGet runtime.${kind}_viewer]
        if {$command ni {{} internal auto}} {
            if {[catch {llength $command}] || ![llength $command]} {error {Viewer association must be a valid executable argv prefix}}
            set executable [auto_execok [lindex $command 0]]
            if {$executable eq {}} {error "Configured $kind viewer is unavailable: [lindex $command 0]"}
            set payload [sessionInspectionDatasetPayload $id]
            return [exec {*}$executable {*}[lrange $command 1 end] [dict get $payload path] &]
        }
    }
    if {$kind eq {html}} {return [viewerOpen viewer.html html [dict create dataset_id $id]]}
    set w [datasetViewerWindow $id {CORE document consultation}]
    if {$kind eq {code}} {
        set read [datasetDocumentRead $id 4194304]
        set notice [expr {[dict get $read complete]?{Read-only canonical source consultation}:{Bounded Open: first 4 Mi characters; original source is preserved.}}]
        set surface [sourceSurfaceCreate $w.source [dict create mode read_only language [sourceSurfaceDatasetLanguage $id] notice $notice]]
        pack $w.source -fill both -expand 1
        sourceSurfaceSet $surface [dict get $read source]
    } else {
        if {$kind eq {xml}} {ttk::button $w.sourceButton -text {View source} -command [list ::GX::datasetDocumentSourceAction $id [interactiveDocumentSessionToken]];pack $w.sourceButton -anchor w -padx 5 -pady 4}
        text $w.content -wrap word -state disabled
        ttk::scrollbar $w.scroll -command [list $w.content yview]
        $w.content configure -yscrollcommand [list $w.scroll set]
        pack $w.scroll -side right -fill y;pack $w.content -fill both -expand 1
        datasetDocumentRender $w.content $id
    }
    return $w
}

proc ::GX::datasetDocumentSourceOpen {id {expectedToken {}}} {
    if {$expectedToken ne {} && $expectedToken ne [interactiveDocumentSessionToken]} {error {Session changed; reopen the document before viewing source}}
    set read [datasetDocumentRead $id 4194304]
    set w [datasetViewerWindow $id {CORE read-only source consultation}]
    set notice [expr {[dict get $read complete]?{Read-only canonical source consultation}:{Bounded source: first 4 Mi characters; original bytes are preserved.}}]
    set source [sourceSurfaceCreate $w.source [dict create mode read_only language [sourceSurfaceDatasetLanguage $id] notice $notice]]
    pack $w.source -fill both -expand 1;sourceSurfaceSet $source [dict get $read source]
    return $w
}
proc ::GX::datasetDocumentSourceAction {id token} {if {[catch {datasetDocumentSourceOpen $id $token} reason]} {tk_messageBox -icon error -type ok -title {Source unavailable} -message $reason}}
