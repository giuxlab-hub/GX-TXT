proc documentPreviewAudit {} {
    set source {const measured = 'Ω'; /* inert canonical source */
function value(x) { return x + 2; }
}
    set file [file join $::out inputs {code Ω.js}];set fd [open $file w];fconfigure $fd -encoding utf-8;puts -nonewline $fd $source;close $fd
    set sha [::GX::sha256File $file]
    set ::GX::moduleCfg(acq.text_document,destination) dataset
    ::GX::acquisitionHandlerImportSourcesToSession acq.text_document $::GX::currentSession [list $file] javascript_preview_final code.source {}
    set widget $::GX::ui(preview)
    set ::GX::variableDatasetChoice [::GX::datasetInspectionImportedChoice javascript_preview_final]
    ::GX::datasetInspectionPreviewFromVariables javascript_preview_final
    guiWait {[winfo exists $widget.source_surface]}
    set surface $widget.source_surface
    gcheck {[winfo exists $surface.text] && [$surface.text cget -state] eq {disabled}} actual_dataset_preview_shared_read_only
    guiWait {[dict exists $::GX::SourceSurface::state($surface,model) engine]}
    gcheck {[::GX::sourceSurfaceGet $surface] eq $source && [$surface.text tag ranges source_keyword] ne {}} source_preview_exact_and_native_highlighted
    gcheck {[::GX::sha256File [::GX::datasetResolvePath $::GX::currentSession javascript_preview_final]] eq $sha} source_preview_preserves_canonical_sha
    raise .;after 400 {set ::captureTick 1};vwait ::captureTick;capture . javascript_shared_preview
    set ::GX::variableDatasetChoice [::GX::datasetInspectionImportedChoice markdown]
    ::GX::datasetInspectionPreviewFromVariables markdown
    guiWait {![winfo exists $surface] && [string first {Measurement notes} [$widget get 1.0 end]]>=0}
    gcheck {![winfo exists $surface] && [string first {Measurement notes} [$widget get 1.0 end]]>=0} markdown_preview_restores_rendered_no_source_controls
    set record [file join $::out association.txt]
    set command [list [::GX::runtimeToolRequired python] -c {from pathlib import Path;import sys;Path(sys.argv[1]).write_text(sys.argv[2],encoding='utf-8')} $record]
    ::GX::configurationSet runtime.markdown_viewer $command
    ::GX::datasetDocumentOpen markdown
    guiWait {[file exists $record]}
    set f [open $record];fconfigure $f -encoding utf-8;set passed [read $f];close $f
    gcheck {$passed eq [::GX::datasetResolvePath $::GX::currentSession markdown]} explicit_external_markdown_argv
    ::GX::configurationSet runtime.markdown_viewer internal
    catch {destroy .gxtxt_html}
    set before [winfo children .]
    foreach module {viewer.html viewer.signal_analysis viewer.statistical_analysis} {::GX::moduleSetEnabled $module 0}
    ::GX::modulePublicApiActivate viewer.html HTML_VIEWER_API_v1
    gcheck {[string first {API still available} [::GX::HTMLViewer::render {<b>API still available</b>}]]>=0} html_headless_api_gui_disabled
    ::GX::modulePublicApiActivate viewer.signal_analysis SIGNAL_ANALYSIS_VIEWER_API_v1
    gcheck {[llength [::GX::SignalAnalysisViewer::methods]]==15} signal_headless_api_gui_disabled
    ::GX::modulePublicApiActivate viewer.statistical_analysis STATISTICAL_ANALYSIS_VIEWER_API_v1
    gcheck {[llength [::GX::StatisticalAnalysisViewer::providers]]==10} statistics_headless_api_gui_disabled
    gcheck {[winfo children .] eq $before} disabled_viewer_api_no_gui_instance
    foreach module {viewer.html viewer.signal_analysis viewer.statistical_analysis} {::GX::moduleSetEnabled $module 1}
    record document_preview_gui [dict create status PASS source_sha256 $sha external_association_path $passed]
}
if {[catch {documentPreviewAudit} reason options]} {record document_preview_failure [dict get $options -errorinfo]}
