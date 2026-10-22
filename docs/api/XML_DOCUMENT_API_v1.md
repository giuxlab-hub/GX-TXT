# XML Document API v1

CORE owns interpreter-scoped C++ document/node handles and libxml2. Discover with
`::GX::xmlDocumentApiInfo`; invoke `::GX::xmlDocument operation arguments...`.
Python and Octave use their existing `gxtxt_api_call('XML_DOCUMENT_API_v1', ... )`.
Operations: create, parse, parse_file, root, describe, append, insert, text,
add_text, attribute, remove, move, query, serialize, write, release.

`create root_name` returns a document. `root document` returns a node.
`append document parent qualified_name ?text?` appends an element; `insert`
inserts before the supplied node. `attribute document node name ?value?` reads
or writes an attribute. Declare `xmlns:prefix` before adding qualified elements.
`text document node ?value?` reads or replaces content; add_text preserves other
children. Describe returns type, namespace, prefix, attributes and child handles.
Query selects matching elements in the supplied node's subtree, including that
node when it matches, by local name or `*`. Serialize takes optional indent 0/1.
Remove invalidates the subtree's handles; move rejects cycles/cross-document
references. A valid element move preserves its handle. A text move into adjacent
text merges into the destination's existing text node: that destination handle
remains valid, and the consumed source-text handle becomes stale. Obtain the
retained text handle from the destination's `describe` children. A text move
without merging preserves its handle. Rejected cycle/depth moves preserve the
original tree. Release invalidates the
document and its node handles.

## Registered positional argument contracts

Python and GNU Octave use the same Script Bridge operation names and positional
operands. Question marks denote optional trailing operands; they are not part
of a name. Document/node handles are opaque strings scoped to the live Bridge
interpreter and owning document, never native pointers or persistent Dataset IDs.

| Operation | Supported positional operands | Result |
| --- | --- | --- |
| `create` | `root_name` | Opaque document handle; root name must be unqualified. |
| `parse` | `xml_text` | Opaque document handle from inert UTF-8 XML. |
| `parse_file` | `authorized_path` | Opaque document handle from an authorized Session file. |
| `root` | `document` | Opaque root node handle. |
| `describe` | `document, node` | Struct: `id`, `name`, `namespace`, `prefix`, `text`; `children` list/cell; `attributes` map/struct; integer `node_type`. |
| `append` | `document, parent, name, ?text?` | Opaque new child element handle. |
| `insert` | `document, before, name, ?text?` | Opaque preceding-sibling element handle; `before` needs an element parent. |
| `text` | `document, node, ?value?` | Content string when omitted; empty string after replacement. |
| `add_text` | `document, parent, text` | Opaque retained text node handle; adjacent text may merge. |
| `attribute` | `document, node, name, ?value?` | Ordinary attribute string when omitted; empty string after writing/removal/namespace declaration. |
| `remove` | `document, node` | Empty string; removed subtree handles invalidated. |
| `move` | `document, node, parent` | Empty string; unmerged nodes retain their handle; a merged source-text handle becomes stale. |
| `query` | `document, node, tag` | Ordered list/cell of matching element handles in that subtree. |
| `serialize` | `document, ?indent?` | UTF-8 XML string; default indentation 0. |
| `write` | `document, destination` | Existing create-only File Publication receipt, with its `files` map normalized to language structs. |
| `release` | `document` | Empty string; document and all its node handles become invalid. |

The optional `attribute` value has a conditional requirement: `xmlns` and
`xmlns:prefix` declarations require the URI value. Ordinary attributes can be
read by omitting value or removed by supplying the existing `--remove` sentinel.
Omitting `append`/`insert` text creates no text child. Text replacement invalidates
previous child handles. The public documented indentation values are 0/1; the
existing native owner enables indentation for exact `1`.

These are supported argument contracts. Some historical native branches do not
reject every excess trailing operand; consumers must not treat that tolerance
as another supported operation signature. Script metadata does not grant new
filesystem access or bypass native document/namespace/lifetime validation.

```python
from gxtxt import gxtxt_api_call
api = "XML_DOCUMENT_API_v1"
document = gxtxt_api_call(api, "create", ["article"])
try:
    root = gxtxt_api_call(api, "root", [document])
    node = gxtxt_api_call(api, "append", [document, root, "title", "Observation"])
    content = gxtxt_api_call(api, "text", [document, node])
finally:
    gxtxt_api_call(api, "release", [document])
```

The example requires an already active managed Script Bridge. GNU Octave uses
the same positional operands in cells, such as
`gxtxt_api_call(api, 'root', {document})`. It does not start a Bridge, publish a
Dataset or establish installed acceptance merely by being shown in API Browser.

Parsing refuses DTD/entity declarations and expansion, uses NONET, and reports
line/column errors. Limits: 4 MiB parse/text input, depth 64, 50,000 nodes,
64 documents/interpreter, 8 MiB serialized output. These are document-service
limits, not claims of an XML Schema/XPath/XSLT implementation. Release documents
when finished. The native renderer is a separate read-only C presentation path.

Tcl callers explicitly authorize file destinations. Script Bridge write confines
the destination to the exact managed Job output directory; parse_file confines
reads to its Session. Symlink/path escape is refused. Writes delegate to the
existing atomic File Publication owner with create-only policy. No automatic
canonical Dataset is created. Publish explicitly through the existing Dataset
publication APIs if desired. Both language bridges and independent ElementTree
namespace/text/attribute checks passed on Debian in dev106.
