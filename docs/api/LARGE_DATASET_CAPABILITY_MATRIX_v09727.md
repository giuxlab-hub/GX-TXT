# Large Dataset capability matrix

| Capability | CSV read | CSV write | HDF5 read | HDF5 write | Table Stream |
|---|---:|---:|---:|---:|---:|
| Sequential/chunk | yes | yes | yes | yes | yes |
| Selected variables | yes | n/a | yes | n/a | yes |
| Direct random range | no; sequential fallback is explicit | no | yes | yes | follows provider |
| Append | n/a | yes | n/a | yes | no |
| Hyperslab | no | no | yes | yes | no; use Canonical |
| Multidimensional | no | no | yes | yes | rejects non-table |
| Groups | no | no | yes | yes | table view only |
| Implicit axis | synthesize from schema | explicit CSV column | synthesize from schema | stored as schema metadata | chunk-local synthesis |
| Typed numeric | parsed values | text serialization | yes | yes | preserves provider dtype |

CSV to HDF5 supports lossless flat tables with bounded streaming. HDF5 to CSV supports only explicitly lossless flat views. Expensive CSV prefix scanning is reported as sequential fallback and is never advertised as direct random access.
