// Existing CORE owns compatible Dataset selection and the read-only PDF reader.
// Ordinals retain the exact original Builder declaration order.
void on_event(gx::Host& host, gx::State& state, const gx::Event& event) {
    if (event.kind == gx::EventKind::open ||
        (event.kind == gx::EventKind::invoke && event.component == 5)) {
        host.document_bind(4, 3);
    }
}
