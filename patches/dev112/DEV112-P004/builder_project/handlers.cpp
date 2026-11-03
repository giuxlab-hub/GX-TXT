// SPDX-License-Identifier: GPL-3.0-or-later
// Builder-authored compact Unified Documents; public CORE owns processing.
#include <string>
void on_event(gx::Host& host, gx::State& state, const gx::Event& event) {
    if (event.kind == gx::EventKind::open) { host.text(78, "Select a PDF or image Dataset, then Open source."); return; }
    if (event.kind != gx::EventKind::invoke) return;
    const std::string menu_action = event.component == 0 ? host.data() : "";
    if (event.component == 3) { host.documents_command(1, "open_source"); state.counter += 1; }
    else if (event.component == 4) { host.documents_command(1, "refresh_sources"); state.counter += 1; }
    else if (event.component == 21) { host.documents_command(1, "previous"); state.counter += 1; }
    else if (event.component == 22) { host.documents_command(1, "next"); state.counter += 1; }
    else if (event.component == 23) { host.documents_command(1, "render"); state.counter += 1; }
    else if (event.component == 24) { host.documents_command(1, "fit"); state.counter += 1; }
    else if (event.component == 0 && menu_action == "doc_fit_width") { host.documents_command(1, "fit_width"); state.counter += 1; }
    else if (event.component == 25) { host.documents_command(1, "zoom_out"); state.counter += 1; }
    else if (event.component == 26) { host.documents_command(1, "zoom_in"); state.counter += 1; }
    else if (event.component == 0 && menu_action == "doc_apply_zoom") { host.documents_command(1, "apply_zoom"); state.counter += 1; }
    else if (event.component == 27) { host.documents_command(1, "roi"); state.counter += 1; }
    else if (event.component == 28) { host.documents_command(1, "pan"); state.counter += 1; }
    else if (event.component == 0 && menu_action == "doc_clear_roi") { host.documents_command(1, "clear_roi"); state.counter += 1; }
    else if (event.component == 0 && menu_action == "doc_select_page") { host.documents_command(1, "select_page"); state.counter += 1; }
    else if (event.component == 43) { host.documents_command(1, "ocr"); state.counter += 1; }
    else if (event.component == 44) { host.documents_command(1, "publish_text"); state.counter += 1; }
    else if (event.component == 45) { host.documents_command(1, "copy_text"); state.counter += 1; }
    else if (event.component == 62) { host.documents_command(1, "table"); state.counter += 1; }
    else if (event.component == 63) { host.documents_command(1, "publish_table"); state.counter += 1; }
    else if (event.component == 70) { host.documents_command(1, "publish_image"); state.counter += 1; }
    else if (event.component == 71) { host.documents_command(1, "publish_page"); state.counter += 1; }
    else if (event.component == 76) { host.documents_command(1, "searchable_pdf"); state.counter += 1; }
    else if (event.component == 79) { host.documents_command(1, "cancel"); state.counter += 1; }
}
