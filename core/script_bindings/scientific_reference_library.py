"""Read and candidate-analysis binding owned by Scientific Reference Library API."""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError, NumericArray

_OPERATIONS = {
    "list_libraries": ("List installed reference library IDs", [], "cell of library IDs"),
    "library_info": ("Read versioned library metadata", [("library_id", "string")], "library struct"),
    "list_entities": ("List library entity IDs", [("library_id", "string")], "cell of entity IDs"),
    "entity_info": ("Read entity metadata", [("library_id", "string"), ("entity_id", "string")], "entity struct"),
    "list_spectra": ("List library spectrum IDs", [("library_id", "string"), ("entity_id", "optional string")], "cell of spectrum IDs"),
    "spectrum_info": ("Read spectrum metadata", [("library_id", "string"), ("spectrum_id", "string")], "spectrum struct"),
    "read_spectrum": ("Read stable scientific X/Y arrays", [("library_id", "string"), ("spectrum_id", "string")], "spectrum struct with numeric vectors"),
    "search": ("Search reference identifiers and metadata", [("library_id", "string"), ("query", "string")], "cell of spectrum IDs"),
    "bulk_rank": ("Prescreen reference spectra against processed data", [("library_id", "string"), ("experimental", "spectrum struct"), ("options", "struct")], "candidate ranking struct"),
}
REGISTRATION = {
    "api_id": "SCIENTIFIC_REFERENCE_LIBRARY_API_v1", "api_version": 1,
    "provider_kind": "core", "provider_id": "scientific_reference_library",
    "documentation_ref": "docs/api/SCIENTIFIC_REFERENCE_LIBRARY_API_v1.md",
    "operations": {name: {"name": name, "summary": summary,
                          "arguments": [{"name": label, "kind": kind, "required": not kind.startswith("optional")}
                                        for label, kind in arguments],
                          "result_contract": result,
                          "argument_convention": ", ".join(label for label, _ in arguments) or "no arguments",
                          "result_convention": result}
                   for name, (summary, arguments, result) in _OPERATIONS.items()},
}


def invoke(host, operation, args):
    schema = _OPERATIONS.get(operation)
    if schema is None:
        raise BridgeError("GXTXT:ScriptBridge:UnknownOperation", f"unknown reference operation {operation}")
    arguments = schema[1]
    if not sum(not kind.startswith("optional") for _, kind in arguments) <= len(args) <= len(arguments):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"{operation} has invalid argument count")
    prefix = "::GX::ReferenceLibraryAPIv1::"
    commands = {"list_libraries": "listLibraries", "library_info": "libraryInfo",
                "list_entities": "listEntities", "entity_info": "entityInfo",
                "list_spectra": "listSpectra", "spectrum_info": "spectrumInfo",
                "read_spectrum": "readSpectrum", "search": "search", "bulk_rank": "bulkRank"}
    result = host.call(prefix + commands[operation], *args)
    if operation in ("list_libraries", "list_entities", "list_spectra", "search"):
        return host.as_list(result)
    item = host.as_dict(result)
    item.pop("path", None)
    if operation == "read_spectrum":
        for field in ("x", "y"):
            item[field] = NumericArray(host.as_list(item[field]))
        for field in ("metadata", "provenance"):
            item[field] = host.as_dict(item.get(field, ""))
    if operation == "bulk_rank" and "candidates" in item:
        item["candidates"] = [host.as_dict(value) for value in host.as_list(item["candidates"])]
    return item
