# SPDX-License-Identifier: GPL-3.0-or-later
source [file join $::GX::scriptDir app gui acquisition_page.tcl]
source [file join $::GX::scriptDir app gui preview_page.tcl]
source [file join $::GX::scriptDir app gui dataset_page.tcl]
source [file join $::GX::scriptDir app gui instrumentation_page.tcl]
source [file join $::GX::scriptDir app gui experiment_page.tcl]
source [file join $::GX::scriptDir app gui modules_page.tcl]
source [file join $::GX::scriptDir app gui configuration_page.tcl]
source [file join $::GX::scriptDir app gui analysis_page.tcl]
source [file join $::GX::scriptDir app gui graphs_page.tcl]
source [file join $::GX::scriptDir app gui print_page.tcl]
source [file join $::GX::scriptDir app gui manifest_page.tcl]
source [file join $::GX::scriptDir app gui run_page.tcl]
source [file join $::GX::scriptDir app gui results_page.tcl]
source [file join $::GX::scriptDir app gui help_page.tcl]
proc ::GX::launchGui_v048 {} {
    variable cfg
    variable ch
    variable probe
    variable extra
    variable ui
    variable version

    package require Tk 8.6
    uiAppearanceInitialize
    uiFieldComboboxInstall
    wm title . "GX-TXT Pipeline v$version"
    ::GX::uiFieldWindowFit . 1280 840
    wm minsize . 920 650
    bind all <Map> +[list ::GX::uiFieldWindowMapped %W]

    ttk::frame .top
    pack .top -fill both -expand 1 -padx 8 -pady 8

    # The authoritative session identity remains the normalized full path.
    # The persistent bar shows only its directory name to keep the GUI compact;
    # clicking that name reveals the complete path without changing identity.
    ttk::frame .top.sessionbar
    ttk::label .top.sessionbar.lab -text "Session:"
    set ui(sessionPath) "No session open"
    ttk::button .top.sessionbar.path -textvariable ::GX::ui(sessionPath) -command ::GX::showCurrentSessionInfo -width 24
    ttk::button .top.sessionbar.open -text "Open Session" -command ::GX::chooseSession
    ttk::button .top.sessionbar.new -text "New Session" -command ::GX::newSessionDialog
    ttk::button .top.sessionbar.save -text "Save Config" -command ::GX::saveCurrentSessionConfig
    ttk::button .top.sessionbar.export -text "Export Session..." -command ::GX::sessionPortableGuiExport
    ttk::button .top.sessionbar.import -text "Import Session..." -command ::GX::sessionPortableGuiImport
    pack .top.sessionbar.lab -side left -padx {0 5}
    pack .top.sessionbar.path -side left -padx 3
    pack .top.sessionbar.open .top.sessionbar.new .top.sessionbar.save .top.sessionbar.export .top.sessionbar.import -side left -padx 3
    pack .top.sessionbar -fill x -pady {0 6}

    ttk::notebook .top.nb
    pack .top.nb -fill both -expand 1

    foreach {tab text} {acq "Acquisition" preview "CSV Preview" channels "Channels" instr "Instrumentation" exp "Experiment" projects "Projects" modules "Modules" configuration "Configuration" analysis "Analysis" graphs "Plots" print "Print / PDF" run "Run" results "Results" help "Help"} {
        ttk::frame .top.nb.$tab
        .top.nb add .top.nb.$tab -text $text
    }

    ::GX::buildAcquisitionPage
    ::GX::buildPreviewPage
    ::GX::buildDatasetPage
    ::GX::buildInstrumentationPage
    ::GX::buildExperimentPage
    ::GX::buildModulesPage
    ::GX::buildConfigurationPage
    ::GX::buildAnalysisPage
    ::GX::buildGraphsPage
    ::GX::buildPrintPage
    ::GX::buildRunPage
    ::GX::buildResultsPage
    ::GX::buildHelpPage
    bind .top.nb <<NotebookTabChanged>> {::GX::onNotebookChanged .top.nb;::GX::datasetPageTabChanged}
    after 100 {::GX::refreshCsvPreview; ::GX::refreshManifestPreview; ::GX::refreshResults; ::GX::refreshModuleCatalog; ::GX::refreshCustomCompareTree; ::GX::refreshAnalysisStatus; ::GX::refreshGraphs; ::GX::discoverPrinters}

    guiLog "GX-TXT Pipeline v$version"
    guiLog "Default worker: $cfg(worker_file)"
    guiLog "The RAW source file is never modified."
    guiLog "Block-based streaming import; intermediate .part files are stored in the channels directory."
}
