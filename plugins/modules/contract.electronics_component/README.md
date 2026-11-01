# Electronics Component Record Contract

Independently installable companion. Contract `electronics.component.record` describes one typed opaque JSON record with no numerical Variables. Original JSON bytes and namespaced structured metadata pass through the existing Acquisition transaction. Library population never invokes this handler. Explicit selected Library-to-Session import or the ordinary Acquisition page invokes the same handler. Actual PDF/image/SDF files remain separate resources with their own existing handlers.

The input is a `record_type: electronics.component` Library record envelope, with `fields`, stable `entry_id`, `revision`, source `provenance` and optional typed relationships/resources. The handler validates required fields and source provenance without executing content. No source/network credentials are accepted.
