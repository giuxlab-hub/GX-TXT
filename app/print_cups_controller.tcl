# SPDX-License-Identifier: GPL-3.0-or-later
# Existing Print tab's CUPS presentation adapter. CORE owns bounded requests.
namespace eval ::GX::PrintStudio {variable state;array set state {capabilities {} verified 0 job {} optionsPrinter {}}}
proc ::GX::printDiagnostic {message} {
    variable ui
    if {![info exists ui(printerOptions)] || ![winfo exists $ui(printerOptions)]} return
    set text $ui(printerOptions);$text configure -state normal;$text insert end "$message\n"
    if {[lindex [split [$text index end] .] 0]>2001} {$text delete 1.0 end-2000lines}
    $text see end;$text configure -state disabled
}
proc ::GX::discoverPrinters {{force 0}} {
    variable cfg;variable ui
    if {![info exists ui(printerCombo)] || ![winfo exists $ui(printerCombo)]} return
    set state [printCupsState discovery]
    if {!$force && [dict get $state request] ne {}} return
    set last [dict get $state last]
    if {!$force && $last ne {} && [dict get $last response ok] && [clock seconds]-[dict get $last verified_at]<15} return
    set ui(cupsStatus) {Discovering printers… PDF export remains available.}
    if {[catch {printCupsQuery discovery discover {} ::GX::printersDiscovered} message]} {set ui(cupsStatus) $message;printDiagnostic $message}
}
proc ::GX::printersDiscovered {response} {
    variable cfg;variable ui
    printDiagnostic "Printer discovery: $response"
    if {![dict get $response ok]} {
        set ui(cupsStatus) "CUPS [datasetPublicationV2DictDefault $response error_type unavailable]: [string range [dict get $response error] 0 220]"
        set ::GX::PrintStudio::state(verified) 0;printPrinterControlsRefresh
        return
    }
    set result [dict get $response result];set printers [dict get $result printers]
    $ui(printerCombo) configure -values $printers
    if {$printers eq {}} {set cfg(print_printer) {};set ui(cupsStatus) {No CUPS destinations are configured. PDF export is available.};refreshPrinterOptions;return}
    if {$cfg(print_printer) ni $printers} {
        set preferred [configurationGet printing.last_printer]
        if {$preferred in $printers} {set cfg(print_printer) $preferred} elseif {[dict get $result default] in $printers} {set cfg(print_printer) [dict get $result default]} else {set cfg(print_printer) [lindex $printers 0]}
    }
    set ui(cupsStatus) "Found [llength $printers] CUPS destinations."
    refreshPrinterOptions
}
proc ::GX::refreshPrinterOptions {} {
    variable cfg;variable ui
    set printer [string trim $cfg(print_printer)]
    if {$::GX::PrintStudio::state(optionsPrinter) ne {} && $::GX::PrintStudio::state(optionsPrinter) ne $printer} {array unset ::GX::PrintStudio::state option,*;set cfg(print_duplex) auto}
    set ::GX::PrintStudio::state(capabilities) {};set ::GX::PrintStudio::state(verified) 0
    set ::GX::PrintStudio::state(optionsPrinter) $printer
    printPrinterControlsRefresh
    if {$printer eq {}} {printCupsCancel capabilities;set ui(cupsStatus) {Select a printer; PDF export does not require one.};return}
    set ui(cupsStatus) "Checking $printer capabilities and status…"
    if {[catch {printCupsQuery capabilities capabilities [dict create printer $printer] [list ::GX::printerOptionsReceived $printer]} message]} {set ui(cupsStatus) $message;printDiagnostic $message}
}
proc ::GX::printerOptionsReceived {printer response} {
    variable cfg;variable ui
    if {$printer ne [string trim $cfg(print_printer)]} return
    printDiagnostic "Printer $printer: $response"
    if {![dict get $response ok]} {set ui(cupsStatus) "$printer: [datasetPublicationV2DictDefault $response error_type unavailable]; open diagnostics for details.";set ::GX::PrintStudio::state(verified) 0;printPrinterControlsRefresh;return}
    set caps [dict get $response result]
    if {[dict get $caps printer] ne $printer} return
    set ::GX::PrintStudio::state(capabilities) $caps;set ::GX::PrintStudio::state(verified) 1
    set ui(cupsStatus) "$printer: capabilities verified; submission revalidates them."
    configurationSet printing.last_printer $printer
    configurationSet printing.capabilities_cache [dict create printer $printer verified_at [clock seconds] capabilities $caps]
    configurationSave {printing.last_printer printing.capabilities_cache} 0
    printPrinterControlsRefresh
}
proc ::GX::printPrinterControlsRefresh {} {
    variable cfg;variable ui
    set caps $::GX::PrintStudio::state(capabilities)
    if {[info exists ui(printerDuplexCombo)] && [winfo exists $ui(printerDuplexCombo)]} {
        set choices [expr {$caps eq {} ? [list $cfg(print_duplex)] : [dict get $caps duplex]}]
        $ui(printerDuplexCombo) configure -values $choices -state [expr {$::GX::PrintStudio::state(verified) && [llength $choices]>1 ? {readonly} : {disabled}}]
        if {$caps ne {} && $cfg(print_duplex) ni $choices} {set cfg(print_duplex) auto}
    }
    if {![info exists ui(printPrinterGroups)] || ![winfo exists $ui(printPrinterGroups)]} return
    set host $ui(printPrinterGroups);foreach child [winfo children $host] {destroy $child}
    if {$caps eq {}} {ttk::label $host.loading -text {Options require verified printer metadata.} -wraplength 270;pack $host.loading -fill x;return}
    foreach group {media color resolution tray} {
        set descriptor [dict get $caps groups $group]
        if {$descriptor eq {}} continue
        set key [dict get $descriptor key]
        if {![info exists ::GX::PrintStudio::state(option,$key)] || $::GX::PrintStudio::state(option,$key) ni [dict get $descriptor choices]} {set ::GX::PrintStudio::state(option,$key) [dict get $descriptor default]}
        ttk::label $host.l$group -text [dict get $descriptor label] -anchor w
        ttk::combobox $host.$group -state [expr {$::GX::PrintStudio::state(verified) ? {readonly} : {disabled}}] -values [dict get $descriptor choices] -textvariable ::GX::PrintStudio::state(option,$key)
        uiFieldSelectorWithinViewer $host.$group .
        pack $host.l$group $host.$group -fill x -pady 2
    }
}
proc ::GX::cancelPrinterRequests {} {
    foreach channel {discovery capabilities} {printCupsCancel $channel}
    set ::GX::PrintStudio::state(verified) 0
    printPrinterControlsRefresh
    set ::GX::ui(cupsStatus) {Printer query cancelled. Refresh to revalidate; PDF export is available.}
}
proc ::GX::printPdf {} {
    variable cfg;variable ui
    if {[llength [info commands ::GX::printStudioDocumentReady]] && ![printStudioDocumentReady 1]} {set ui(printStatus) {Document is stale or absent. Update and review its page Preview before printing.};return}
    if {$cfg(print_output_pdf) eq {} || ![file isfile $cfg(print_output_pdf)]} {set ui(printStatus) {Create and review a current PDF before printing.};return}
    if {!$::GX::PrintStudio::state(verified) || $::GX::PrintStudio::state(capabilities) eq {}} {set ui(cupsStatus) {Select and verify a printer before explicit submission.};return}
    set caps $::GX::PrintStudio::state(capabilities)
    if {[dict get $caps printer] ne $cfg(print_printer)} {set ui(cupsStatus) {Printer selection changed; refresh its capabilities.};return}
    set options {}
    dict for {group descriptor} [dict get $caps groups] {if {$descriptor ne {}} {set key [dict get $descriptor key];if {[info exists ::GX::PrintStudio::state(option,$key)] && $::GX::PrintStudio::state(option,$key) ne {}} {dict set options $key $::GX::PrintStudio::state(option,$key)}}}
    set request [dict create printer $cfg(print_printer) capability_sha256 [dict get $caps fingerprint] pdf [file normalize $cfg(print_output_pdf)] pdf_sha256 [dict get $::GX::PrintStudio::state(document) pdf_sha256] source_manifest [dict get $::GX::PrintStudio::state(document) source_manifest] source_resource [dict get $::GX::PrintStudio::state(document) resource_id] copies $cfg(print_copies) duplex $cfg(print_duplex) options $options pages [expr {[info exists ::GX::PrintStudio::state(pages)] ? $::GX::PrintStudio::state(pages) : {}}]]
    if {[dict get [printCupsState submission] request] ne {}} {set ui(cupsStatus) {A submission is pending. Wait for its CUPS receipt.};return}
    set ui(cupsStatus) {Revalidating printer and submitting the explicit current PDF…}
    if {[catch {printCupsQuery submission submit $request ::GX::printSubmissionReceived} message]} {set ui(cupsStatus) $message;printDiagnostic $message}
}
proc ::GX::printSubmissionReceived {response} {
    printDiagnostic "CUPS submission: $response"
    if {![dict get $response ok]} {set ::GX::ui(cupsStatus) "Submission failed: [dict get $response error]";return}
    set ::GX::PrintStudio::state(job) [dict get $response result]
    set ::GX::ui(cupsStatus) "CUPS [dict get $response result status]: [dict get $response result job_id]. Physical completion is unconfirmed."
    if {[winfo exists .top.nb.print]} {viewerGuiActionsRefresh .top.nb.print}
}
proc ::GX::printJobAction {operation} {
    set job $::GX::PrintStudio::state(job)
    if {$job eq {} || [dict get $job job_id] eq {}} {set ::GX::ui(cupsStatus) {No identified CUPS submission is available.};return}
    set arguments [dict create job_id [dict get $job job_id]]
    if {$operation eq {job_status}} {dict set arguments printer [dict get $job printer]}
    printCupsQuery status $operation $arguments ::GX::printJobStatusReceived
}
proc ::GX::printJobStatusReceived {response} {
    printDiagnostic "CUPS job status: $response"
    if {[dict get $response ok]} {set ::GX::ui(cupsStatus) "[dict get $response result job_id]: [dict get $response result status]; physical completion remains unconfirmed."} else {set ::GX::ui(cupsStatus) [dict get $response error]}
}
