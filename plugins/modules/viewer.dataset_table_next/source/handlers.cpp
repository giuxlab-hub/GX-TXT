// Author presentation policy only. CORE owns Dataset bytes, schema and paging.
void on_event(gx::Host& host, gx::State& state, const gx::Event& event) {
    if (event.kind == gx::EventKind::open) {
        host.text(1, "Read-only canonical Dataset consultation");
        host.document_bind(3, 4);
    }
    if ((event.kind == gx::EventKind::invoke && event.component == 5) ||
        (event.kind == gx::EventKind::changed && event.component == 4)) {
        host.document_bind(3, 4);
    }
}
