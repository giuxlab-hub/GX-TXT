// SPDX-License-Identifier: GPL-3.0-or-later
// Component ordinals are the original Builder declaration positions.
// Selection stages a choice; only an explicit action requests a binding.
// CORE owns source admission, native rendering, ROI Documents and History.
void on_event(gx::Host& host, gx::State& state, const gx::Event& event) {
    if (event.kind == gx::EventKind::open) {
        host.text(1, "Select a source, then use its explicit action. Save the ROI Workspace before starting a new scene.");
        return;
    }
    if (event.kind == gx::EventKind::changed) {
        if (event.component == 5 || event.component == 22) {
            host.text(1, "Selection staged; use Open PDF or Open table to consult it.");
        } else if (event.component == 9) {
            host.text(1, "Selection staged. Save the existing Workspace; Start new ROI scene creates a separate ROI owner.");
        }
        return;
    }
    if (event.kind != gx::EventKind::invoke) return;
    if (event.component == 6) {
        host.document_bind(7, 5);
        host.text(1, "PDF consultation requested; CORE checks current Session and source.");
        state.counter += 1;
    } else if (event.component == 10) {
        host.raster_bind(12, 9);
        host.text(1, "New ROI scene requested. Save this Workspace before starting another scene.");
        state.counter += 1;
    } else if (event.component == 23) {
        host.document_bind(24, 22);
        host.text(1, "Table consultation requested; values and units remain canonical.");
        state.counter += 1;
    }
}
