void on_event(gx::Host& host, gx::State& state, const gx::Event& event) {
    if (event.kind == gx::EventKind::open) {
        host.document_bind(5, 3);
    }
    if (event.kind == gx::EventKind::invoke || event.kind == gx::EventKind::changed) {
        if (event.component == 3 || event.component == 6) {
            host.document_bind(5, 3);
        }
    }
}

