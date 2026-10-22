# SPDX-License-Identifier: GPL-3.0-or-later
# TeX orchestration only: existing Workspace/Document/Resource/Runtime/Job and
# File Publication owners retain all storage, execution and commit authority.
namespace eval ::GX::TeXDocument {variable pending {};variable owner_bindings {}}

proc ::GX::interactiveDocumentTeXApiInfo {} {
    return [dict create api_id INTERACTIVE_DOCUMENT_API_v1 api_version 1 profile tex_project operations {register create read read_source save import_asset build status cancel export_source export_pdf} schema gxtxt.tex_project.v1 source_bytes_max 16777216 assets_max 4095 implicit_dataset_publication 0 compiler native_configured_runtime build_owner_window optional lifecycle INTERACTIVE_DOCUMENT_API_v1]
}
proc ::GX::_interactiveDocumentTeXManifestsEqual {left right} {
    if {[lsort [dict keys $left]] ne [lsort [dict keys $right]]} {return 0}
    dict for {key value} $left {if {$value ne [dict get $right $key]} {return 0}}
    return 1
}
proc ::GX::interactiveDocumentTeXRegister {module provider viewer} {
    sessionWorkspaceProviderRegister $provider [dict create module_id $module type {LaTeX article} schema gxtxt.tex_project.v1 version 1 validate ::GX::_interactiveDocumentTeXValidate open [list ::GX::_interactiveDocumentTeXOpen $module $viewer] viewer_provider $viewer]
}
proc ::GX::_interactiveDocumentTeXOpen {module viewer document} {
    return [viewerOpen $module $viewer [dict create tex_document_id $document]]
}
proc ::GX::_interactiveDocumentTeXName {name} {
    if {$name eq {} || [file pathtype $name] ne {relative} || [string first \\ $name]>=0 || [regexp {[\x00-\x1f]} $name]} {error {TeX assets need a normalized relative filename}}
    foreach part [split $name /] {if {$part in {{} . .. .gxtxt-build}} {error {TeX asset escapes the project or uses a reserved output name}}}
    return $name
}
proc ::GX::_interactiveDocumentTeXValidate {payload} {
    foreach key {source source_revision assets last_build last_good_pdf} {if {![dict exists $payload $key]} {error "TeX document requires $key"}}
    if {![string is entier -strict [dict get $payload source_revision]] || [dict get $payload source_revision]<0} {error {Invalid TeX source revision}}
    if {[dict size [dict get $payload assets]]>4095} {error {TeX project exceeds 4095 explicit assets}}
    dict for {name reference} [dict get $payload assets] {
        _interactiveDocumentTeXName $name
        if {$name eq {main.tex}} {error {main.tex is the article source, not an asset}}
        if {![dict exists $reference sha256] || ![dict exists $reference document_id]} {error {TeX assets require managed resource references}}
    }
    set source [dict get $payload source]
    if {$source ne {} && (![dict exists $source size_bytes] || [dict get $source size_bytes]>16777216)} {error {TeX source exceeds 16 MiB}}
    if {$source eq {} && [dict get $payload source_revision]!=0} {error {Saved TeX revision has no source resource}}
}
proc ::GX::interactiveDocumentTeXCreate {provider name} {
    return [sessionWorkspaceCreate $provider $name [dict create source {} source_revision 0 assets {} last_build {} last_good_pdf {}]]
}
proc ::GX::interactiveDocumentTeXRead {document} {
    set workspace [sessionWorkspaceGet $document]
    if {[dict get $workspace schema] ne {gxtxt.tex_project.v1}} {error {Select a LaTeX article Workspace}}
    _interactiveDocumentTeXValidate [dict get $workspace payload]
    # Keep structural inspection and repair available when an old asset is
    # missing. Save candidates, Build and Export validate their actual inputs.
    return $workspace
}
proc ::GX::interactiveDocumentTeXReadSource {document} {
    set reference [dict get [interactiveDocumentTeXRead $document] payload source]
    if {$reference eq {}} {return {}}
    if {[dict get $reference document_id] ne $document} {error {TeX source belongs to another Workspace}}
    interactiveDocumentResourceInfo $reference
    set bytes {}
    for {set start 0} {$start<[dict get $reference size_bytes]} {incr start 1048576} {
        append bytes [interactiveDocumentResourceReadChunk $reference $start [expr {min(1048576,[dict get $reference size_bytes]-$start)}]]
    }
    set source [encoding convertfrom utf-8 $bytes]
    if {[encoding convertto utf-8 $source] ne $bytes} {error {Saved TeX source is not exact UTF-8}}
    return $source
}
proc ::GX::_interactiveDocumentTeXReferences {document source assets} {
    if {$source eq {}} {error {Save the article source before building}}
    set result [dict create main.tex $source]
    dict for {name reference} $assets {dict set result [_interactiveDocumentTeXName $name] $reference}
    set total 0
    dict for {name reference} $result {
        if {[dict get $reference document_id] ne $document} {error {TeX source/assets belong to another Workspace}}
        interactiveDocumentResourceInfo $reference
        incr total [dict get $reference size_bytes]
    }
    if {$total>268435456} {error {TeX source/assets exceed the 256 MiB build input budget}}
    return $result
}
proc ::GX::interactiveDocumentTeXSave {document source assets {history {}}} {
    set workspace [interactiveDocumentTeXRead $document];set payload [dict get $workspace payload]
    set bytes [encoding convertto utf-8 $source]
    if {[string length $bytes]>16777216} {error {TeX source exceeds 16 MiB}}
    # Every byte is owned by the existing content-addressed Resource writer.
    set reference [managedResourceWrite $document [dict create format tex media_type text/x-tex encoding utf-8 role article_source] $bytes]
    _interactiveDocumentTeXReferences $document $reference $assets
    # Article revisions describe named input bytes, not dictionary insertion
    # order or resource-origin metadata. Match the build's content identity.
    set previousAssets {};set nextAssets {}
    dict for {name asset} [dict get $payload assets] {dict set previousAssets $name [dict get $asset sha256]}
    dict for {name asset} $assets {dict set nextAssets $name [dict get $asset sha256]}
    set changed [expr {[dict get $payload source] eq {} || [dict get [dict get $payload source] sha256] ne [dict get $reference sha256] || ![_interactiveDocumentTeXManifestsEqual $previousAssets $nextAssets]}]
    if {$changed} {dict incr payload source_revision}
    dict set payload source $reference;dict set payload assets $assets
    if {$history ne {}} {
        scientificHistoryValidate [dict get $workspace module_id] $history
        dict set payload history $history
    }
    return [sessionWorkspaceUpdate $document $payload]
}
proc ::GX::_interactiveDocumentTeXCopyResource {reference destination} {
    interactiveDocumentResourceInfo $reference
    set output [open $destination {WRONLY CREAT EXCL}]
    fconfigure $output -translation binary -encoding binary
    try {
        for {set start 0} {$start<[dict get $reference size_bytes]} {incr start 1048576} {puts -nonewline $output [interactiveDocumentResourceReadChunk $reference $start [expr {min(1048576,[dict get $reference size_bytes]-$start)}]]}
    } finally {close $output}
    if {[sha256File $destination] ne [dict get $reference sha256]} {error {Staged TeX resource fingerprint differs}}
}
proc ::GX::_interactiveDocumentTeXImportResource {document path metadata} {
    if {![file isfile $path] || [file type $path] ne {file}} {error {TeX output must be a regular file}}
    set writer [interactiveDocumentResourceOpenWriter $document $metadata]
    set input [open $path rb]
    try {
        while {![eof $input]} {set bytes [read $input 1048576];if {$bytes ne {}} {interactiveDocumentResourceAppend $writer $bytes}}
        set result [interactiveDocumentResourceFinalize $writer];set writer {}
        return $result
    } finally {close $input;if {$writer ne {}} {interactiveDocumentResourceAbort $writer}}
}
proc ::GX::interactiveDocumentTeXImportAsset {document name path} {
    interactiveDocumentTeXRead $document;_interactiveDocumentTeXName $name
    if {$name eq {main.tex}} {error {Use the Source Surface to edit main.tex}}
    if {![file isfile $path] || [file size $path]>268435456} {error {Select an existing asset within the 256 MiB project budget}}
    return [_interactiveDocumentTeXImportResource $document $path [dict create format [string trimleft [file extension $name] .] role tex_asset filename $name]]
}
proc ::GX::interactiveDocumentTeXBuild {document callback {engine pdflatex} {ownerWindow {}}} {
    variable ::GX::TeXDocument::pending
    if {$engine ni {pdflatex xelatex lualatex}} {error {Select pdflatex, xelatex or lualatex}}
    if {[dict exists $pending $document]} {error {Cancel or finish the current article build first}}
    if {$ownerWindow ne {} && (![llength [info commands winfo]] || ![winfo exists $ownerWindow])} {error {TeX build owner window is unavailable}}
    set workspace [interactiveDocumentTeXRead $document];set payload [dict get $workspace payload]
    set references [_interactiveDocumentTeXReferences $document [dict get $payload source] [dict get $payload assets]]
    set runtime [runtimeToolRequired latex];set driver [string tolower [file rootname [file tail $runtime]]]
    # Unix executable names commonly have no extension (file rootname is inert).
    if {$driver ni {latexmk pdflatex xelatex lualatex}} {error {Configured LaTeX runtime must identify latexmk, pdflatex, xelatex or lualatex}}
    set allocation [resourceManagementAllocate tex_build [dict create category retained_diagnostic lifetime job session $::GX::currentSession retention_seconds 86400]]
    set directory [dict get $allocation path];set manifest {}
    try {
        dict for {name reference} $references {
            set destination [file join $directory $name];file mkdir [file dirname $destination]
            _interactiveDocumentTeXCopyResource $reference $destination
            dict set manifest $name [dict get $reference sha256]
        }
        set token [interactiveDocumentSessionToken]
        set request [dict create directory $directory runtime $runtime driver $driver engine $engine inputs $manifest source_revision [dict get $payload source_revision] session_token $token owner_generation [dict get $workspace generation]]
        # These are runtime-owner resolved dependencies, never Viewer commands.
        foreach tool {bibtex biber} {if {![catch {runtimeToolResolve $tool} path] && $path ne {}} {dict set request $tool $path}}
        set context [dict create token $token generation [dict get $workspace generation] revision [dict get $payload source_revision] manifest $manifest allocation $allocation callback $callback owner_window $ownerWindow]
        dict set pending $document $context
        set lifecycle [interactiveDocumentLifecycleSubscribe [list ::GX::_interactiveDocumentTeXLifecycle $document $token [dict get $workspace generation]] {} $document]
        dict set pending $document lifecycle $lifecycle
        set command [list [runtimeToolRequired python] -B [file join $::GX::scriptDir core python gxtxt_tex_build.py]]
        set job [scriptJobAsync $command $request [list ::GX::_interactiveDocumentTeXBuilt $document] {timeout_ms 300000 max_bytes 4194304 process_group 1 ui_lifetime 1 label {Native TeX article build}}]
        dict set pending $document request $job
        if {$ownerWindow ne {} && ![dict exists $::GX::TeXDocument::owner_bindings $ownerWindow]} {
            bind $ownerWindow <Destroy> +[list ::GX::_interactiveDocumentTeXOwnerClosed $ownerWindow %W]
            dict set ::GX::TeXDocument::owner_bindings $ownerWindow 1
        }
        return [dict create status running request $job source_revision [dict get $payload source_revision] inputs $manifest]
    } on error {message options} {
        if {[info exists job]} {catch {scriptJobRequestCancel $job}}
        if {[dict exists $pending $document lifecycle]} {interactiveDocumentLifecycleUnsubscribe [dict get $pending $document lifecycle]}
        if {[dict exists $pending $document]} {dict unset pending $document}
        catch {resourceManagementRelease [dict get $allocation id] retained_diagnostic 86400}
        return -options $options $message
    }
}
proc ::GX::_interactiveDocumentTeXLifecycle {document token generation event} {
    if {[dict get $event document_id] ne $document || [dict get $event session_token] ne $token || [dict get $event owner_generation] ne $generation} return
    if {[dict exists $::GX::TeXDocument::pending $document] && [dict get $::GX::TeXDocument::pending $document token] eq $token && [dict get $::GX::TeXDocument::pending $document generation] eq $generation} {interactiveDocumentTeXCancel $document}
}
proc ::GX::_interactiveDocumentTeXOwnerClosed {owner actual} {
    if {$owner ne $actual} return
    dict unset ::GX::TeXDocument::owner_bindings $owner
    dict for {document context} $::GX::TeXDocument::pending {
        if {[dict get $context owner_window] eq $owner} {
            # A new window may later reuse the same Tk pathname. Retire the
            # old UI callback before cancellation can deliver a completion.
            dict set ::GX::TeXDocument::pending $document callback {}
            interactiveDocumentTeXCancel $document
        }
    }
}
proc ::GX::interactiveDocumentTeXCancel {document {expectedGeneration {}}} {
    variable ::GX::TeXDocument::pending
    if {![dict exists $pending $document request]} {return [dict create status idle]}
    if {$expectedGeneration ne {} && [dict get $pending $document generation] ne $expectedGeneration} {error {TeX cancellation belongs to another Document generation}}
    set requested [scriptJobRequestCancel [dict get $pending $document request] cancelled]
    if {$requested} {dict set pending $document cancellation_requested 1}
    set status [expr {[datasetPublicationV2DictDefault [dict get $pending $document] cancellation_requested 0] ? {cancelling} : {awaiting_completion}}]
    return [dict create status $status request [dict get $pending $document request]]
}
proc ::GX::interactiveDocumentTeXStatus {document} {
    # Auxiliary requests are already managed by Script Jobs; this is a typed
    # projection of this Document's existing pending context, not a Job store.
    set item [interactiveDocumentTeXRead $document]
    set payload [dict get $item payload];set good [dict get $payload last_good_pdf]
    set result [dict create status idle source_revision [dict get $payload source_revision] last_build [dict get $payload last_build] pdf_status unbuilt]
    if {$good ne {}} {
        dict set result compiled_source_revision [dict get $good source_revision]
        dict set result pdf_status stale
        if {[catch {
            if {[dict get $good resource document_id] ne $document} {error {TeX PDF belongs to another Workspace}}
            set inputs {};dict for {name reference} [_interactiveDocumentTeXReferences $document [dict get $payload source] [dict get $payload assets]] {dict set inputs $name [dict get $reference sha256]}
            interactiveDocumentResourceInfo [dict get $good resource]
            if {[dict get $good source_revision]==[dict get $payload source_revision] && [_interactiveDocumentTeXManifestsEqual [dict get $good inputs] $inputs]} {dict set result pdf_status current}
        } reason]} {dict set result pdf_status unavailable;dict set result pdf_message $reason}
    }
    if {![dict exists $::GX::TeXDocument::pending $document]} {return $result}
    set context [dict get $::GX::TeXDocument::pending $document]
    if {[dict get $context token] ne [interactiveDocumentSessionToken] || [dict get $context generation] ne [dict get $item generation]} {error {TeX request belongs to another Document lifetime}}
    return [dict merge $result [dict create status [expr {[datasetPublicationV2DictDefault $context cancellation_requested 0] ? {cancelling} : {running}}] request [dict get $context request] build_source_revision [dict get $context revision] owner_generation [dict get $context generation]]]
}
proc ::GX::_interactiveDocumentTeXBuilt {document response} {
    variable ::GX::TeXDocument::pending
    if {![dict exists $pending $document]} return
    set context [dict get $pending $document];dict unset pending $document
    set status [expr {[datasetPublicationV2DictDefault $response error_type {}] eq {cancelled} ? {cancelled} : {failed}}]
    set receipt [dict create status $status response $response source_revision [dict get $context revision]]
    try {
        if {[dict get $context token] ne [interactiveDocumentSessionToken]} {error {TeX completion belongs to another Session lifetime}}
        set workspace [interactiveDocumentTeXRead $document];set payload [dict get $workspace payload]
        if {[dict get $workspace generation] ne [dict get $context generation] || [dict get $payload source_revision]!=[dict get $context revision]} {error {TeX completion is stale; current source/assets are preserved}}
        set current {};dict for {name reference} [_interactiveDocumentTeXReferences $document [dict get $payload source] [dict get $payload assets]] {dict set current $name [dict get $reference sha256]}
        if {![_interactiveDocumentTeXManifestsEqual $current [dict get $context manifest]]} {error {TeX completion source/assets do not match current document}}
        if {[dict get $response ok]} {
            set receipt [dict get $response result]
            foreach key {source_revision session_token owner_generation inputs inputs_after source_integrity status log_path log_sha256} {if {![dict exists $receipt $key]} {error {Incomplete native TeX worker result}}}
            if {[dict get $receipt source_revision]!=[dict get $context revision] || [dict get $receipt session_token] ne [dict get $context token] || [dict get $receipt owner_generation] ne [dict get $context generation] || ![_interactiveDocumentTeXManifestsEqual [dict get $receipt inputs] $current] || ![_interactiveDocumentTeXManifestsEqual [dict get $receipt inputs_after] $current] || ![dict get $receipt source_integrity]} {error {Native TeX result does not match its exact source snapshot}}
            set root [file join [dict get $context allocation path] .gxtxt-build]
            foreach key {log_path pdf_path} {
                if {[dict exists $receipt $key] && [dict get $receipt $key] ne {} && [file normalize [dict get $receipt $key]] ne [file join $root [expr {$key eq {log_path} ? {gxtxt-native-output.txt} : {main.pdf}}]]} {error {TeX worker output escapes its allocation}}
            }
            if {[sha256File [dict get $receipt log_path]] ne [dict get $receipt log_sha256]} {error {Native TeX diagnostic bytes changed}}
            dict set receipt log [_interactiveDocumentTeXImportResource $document [dict get $receipt log_path] [dict create format txt encoding utf-8 role tex_build_diagnostics]]
            if {[dict get $receipt status] eq {succeeded}} {
                if {[sha256File [dict get $receipt pdf_path]] ne [dict get $receipt pdf_sha256]} {error {Native TeX PDF bytes changed}}
                set pdf [_interactiveDocumentTeXImportResource $document [dict get $receipt pdf_path] [dict create format pdf media_type application/pdf role tex_compiled_pdf source_revision [dict get $context revision] inputs $current]]
                dict set receipt pdf $pdf
                dict set payload last_good_pdf [dict create source_revision [dict get $context revision] inputs $current resource $pdf]
            }
            set receipt [dict remove $receipt log_path pdf_path]
        }
        dict set payload last_build $receipt
        sessionWorkspaceUpdate $document $payload
    } on error {message options} {
        set receipt [dict create status rejected message $message source_revision [dict get $context revision] errorcode [datasetPublicationV2DictDefault $options -errorcode NONE]]
    } finally {
        if {[dict exists $context lifecycle]} {interactiveDocumentLifecycleUnsubscribe [dict get $context lifecycle]}
        catch {resourceManagementRelease [dict get $context allocation id] retained_diagnostic 86400}
    }
    # A destroyed owning Viewer must never receive its asynchronous UI callback.
    set owner [dict get $context owner_window]
    if {[dict get $context callback] ne {} && ($owner eq {} || [winfo exists $owner])} {uplevel #0 [list {*}[dict get $context callback] $receipt]}
}
proc ::GX::_interactiveDocumentTeXPublishWriter {reference channel context} {
    interactiveDocumentResourceInfo $reference
    for {set start 0} {$start<[dict get $reference size_bytes]} {incr start 1048576} {puts -nonewline $channel [interactiveDocumentResourceReadChunk $reference $start [expr {min(1048576,[dict get $reference size_bytes]-$start)}]]}
    interactiveDocumentResourceInfo $reference
}
proc ::GX::interactiveDocumentTeXExport {document kind destination {policy create_only} {includeAssets 0}} {
    if {![string is boolean -strict $includeAssets]} {error {Include-assets must be boolean}}
    set payload [dict get [interactiveDocumentTeXRead $document] payload]
    if {$kind eq {source}} {
        set reference [dict get $payload source];set extension .tex
    } elseif {$kind eq {pdf}} {
        set good [dict get $payload last_good_pdf]
        if {$good eq {} || [dict get $good source_revision]!=[dict get $payload source_revision]} {error {Build the current source/assets revision before exporting PDF}}
        set current {};dict for {name ref} [_interactiveDocumentTeXReferences $document [dict get $payload source] [dict get $payload assets]] {dict set current $name [dict get $ref sha256]}
        if {![_interactiveDocumentTeXManifestsEqual $current [dict get $good inputs]]} {error {Compiled PDF belongs to different source/assets}}
        set reference [dict get $good resource];set extension .pdf
    } else {error {LaTeX document exports are source .tex or compiled .pdf}}
    if {[string tolower [file extension $destination]] ne $extension} {error "Choose a $extension export filename"}
    if {$reference eq {}} {error {Save the source before exporting}}
    if {[dict get $reference document_id] ne $document} {error {TeX export resource belongs to another Workspace}}
    set artifacts [list [dict create id $kind destination $destination writer [list ::GX::_interactiveDocumentTeXPublishWriter $reference]]]
    if {$includeAssets} {
        set parent [file dirname [file normalize $destination]]
        dict for {name asset} [dict get $payload assets] {
            _interactiveDocumentTeXName $name
            if {[dict get $asset document_id] ne $document} {error {TeX asset belongs to another Workspace}}
            interactiveDocumentResourceInfo $asset
            lappend artifacts [dict create id asset:$name destination [file join $parent $name] writer [list ::GX::_interactiveDocumentTeXPublishWriter $asset]]
        }
    }
    return [filePublicationPublishBundle $artifacts $policy [dict create create_parents $includeAssets]]
}
