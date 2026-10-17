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
Query selects descendants by local name. Serialize takes optional indent 0/1.
Remove invalidates the subtree's handles; move preserves handles and rejects
cycles/cross-document references. Release invalidates every document handle.

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
