"""Script-safe operations owned by CORE public service providers.

Each entry binds a named public operation to a fixed public Tcl procedure.
Research scripts never provide a procedure name or filesystem implementation path.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
from gxtxt_script_bridge_server import BridgeError


def _api(api_id, version, provider, documentation, operations):
    return {"api_id": api_id, "api_version": version, "provider_kind": "core",
            "provider_id": provider, "documentation_ref": documentation,
            "operations": {name: {"name": name, "summary": summary,
                                  "arguments": arguments, "result_contract": result,
                                  "argument_convention": ", ".join(a["name"] for a in arguments) or "no arguments",
                                  "result_convention": result}
                           for name, (summary, arguments, result, *_rest) in operations.items()}}


def _arg(name, kind, required=True):
    return {"name": name, "kind": kind, "required": required}


# Operation tuples: summary, argument schema, result, public command, conversion.
SERVICES = {
    "OBJECT_ORIGIN_API_v1": (1, "object_origin", "docs/api/OBJECT_ORIGIN_API_v1.md", {
        "document": ("Read scientific document creator", [_arg("document_id", "string")], "origin dictionary", "::GX::documentOriginRead", "origin"),
        "dataset": ("Read Dataset publication creator", [_arg("dataset_id", "string")], "origin dictionary", "::GX::datasetOriginRead", "origin"),
        "resource": ("Read managed resource declared creator", [_arg("resource", "struct")], "origin dictionary", "::GX::resourceOriginRead", "origin"),
        "session": ("Read current Session/Experiment declared creator and lineage", [], "origin dictionary with ordered import events", "::GX::sessionOriginRead", "origin"),
        "project": ("Read Project declared creator and lineage", [_arg("project_id", "string")], "origin dictionary", "::GX::projectOriginRead", "origin"),
    }),
    "INSTALLATION_IDENTITY_API_v1": (1, "installation_identity", "docs/api/INSTALLATION_IDENTITY_API_v1.md", {
        "info": ("Read CORE installation identity, authority and recovery diagnostics", [], "identity dictionary; history serialized as Tcl list", "::GX::installationIdentityInfo", "dict"),
        "current": ("Read current installation serial", [], "installation serial", "::GX::installationIdentityCurrent", "string"),
        "history": ("Read retained local installation serial history", [], "ordered history dictionaries", "::GX::installationIdentityHistory", "identity_history"),
    }),
    "EXPERIMENT_DUPLICATION_POLICY_API_v1": (1, "experiment_duplication_policy", "docs/api/EXPERIMENT_DUPLICATION_POLICY_API_v1.md", {
        "info": ("Inspect optional declarative duplication capabilities", [], "capability dictionary", "::GX::experimentDuplicationPolicyInfo", "dict"),
        "module": ("Inspect a module optional policy and conservative fallback", [_arg("module_id", "string")], "policy validation dictionary", "::GX::experimentDuplicationPolicyModule", "dict"),
        "validate": ("Validate an optional flat INI descriptor", [_arg("descriptor", "struct")], "validation dictionary", "::GX::experimentDuplicationPolicyValidate", "dict"),
    }),
    "SESSION_EXPERIMENT_API_v1": (1, "session_experiment", "docs/api/SESSION_EXPERIMENT_API_v1.md", {
        "preparation": ("Read reusable unbound Experiment preparation", [], "preparation dictionary with serialized nested definitions", "::GX::sessionExperimentPreparationRead", "dict"),
    }),
    "SCIENTIFIC_RECIPE_API_v1": (1, "scientific_recipe", "docs/api/SCIENTIFIC_RECIPE_API_v1.md", {
        "data_decode": ("Decode a bounded inert versioned recipe envelope without executing or validating its owner's scientific payload", [_arg("encoded", "string"), _arg("expected_format", "string")], "dictionary with owner-specific nested data serialized", "::GX::scientificRecipeDataDecode", "dict"),
        "inspect": ("Inspect an inert recorded scientific recipe", [_arg("encoded", "string")], "recipe descriptor", "::GX::scientificRecipeInspect", "dict"),
        "validate": ("Validate required APIs, plugins, sources and complete geometry", [_arg("encoded", "string")], "validation receipt", "::GX::scientificRecipeValidate", "dict"),
        "proposal": ("Prepare a validated transactional Workbench replay proposal", [_arg("encoded", "string")], "structured action proposal", "::GX::scientificRecipeProposal", "recipe_proposal"),
    }),
    "TEMPORAL_SET_API_v1": (1, "temporal_set", "docs/api/TEMPORAL_SET_API_v1.md", {
        "create": ("Create a persistent Temporal Set", [_arg("definition", "struct")], "Set ID", "::GX::temporalSetCreate", "string"),
        "list": ("List Temporal Sets", [_arg("dataset_id", "string", False)], "cell of Set descriptors", "::GX::temporalSetList", "dict_list"),
        "read": ("Read a Temporal Set definition", [_arg("set_id", "string")], "Set struct", "::GX::temporalSetRead", "dict"),
        "resolve_info": ("Inspect resolved window count and source", [_arg("set_id", "string")], "resolution struct", "::GX::temporalSetResolveInfo", "dict"),
        "resolve_member": ("Resolve one window or segment", [_arg("set_id", "string"), _arg("index", "integer")], "member struct", "::GX::temporalSetResolveMember", "dict"),
        "update": ("Update a persistent Temporal Set", [_arg("set_id", "string"), _arg("changes", "struct")], "Set struct", "::GX::temporalSetUpdate", "dict"),
        "delete": ("Delete a Temporal Set", [_arg("set_id", "string")], "Set ID", "::GX::temporalSetDelete", "string"),
        "resolve": ("Resolve all Temporal Set members", [_arg("set_id", "string")], "resolution struct", "::GX::temporalSetResolve", "dict"),
    }),
    "VIEWER_PROVIDER_API_v1": (1, "viewer_provider", "docs/api/VIEWER_PROVIDER_API_v1.md", {
        "providers": ("List enabled Viewer providers", [], "cell of provider structs", "::GX::viewerProviderList", "dict_list"),
        "scene_set": ("Set persistent scene presentation", [_arg("module_id", "string"), _arg("viewer_id", "string"), _arg("fields", "struct")], "scene struct", "::GX::viewerSceneSet", "dict"),
        "scene_get": ("Read persistent scene presentation", [_arg("module_id", "string"), _arg("viewer_id", "string")], "scene struct", "::GX::viewerSceneGet", "dict"),
        "layer_set": ("Set a persistent scientific layer", [_arg("module_id", "string"), _arg("viewer_id", "string"), _arg("layer_id", "string"), _arg("fields", "struct")], "layer struct", "::GX::viewerLayerSet", "dict"),
        "layer_get": ("Read a persistent scientific layer", [_arg("module_id", "string"), _arg("viewer_id", "string"), _arg("layer_id", "string")], "layer struct", "::GX::viewerLayerGet", "dict"),
        "layer_ids": ("List scene layer IDs", [_arg("module_id", "string"), _arg("viewer_id", "string")], "cell of IDs", "::GX::viewerLayerIds", "list"),
    }),
    "SESSION_INSPECTION_API_v1": (1, "session_inspection", "docs/api/SESSION_INSPECTION_API_v1.md", {
        "summary": ("Inspect current Session", [], "summary struct", "::GX::sessionInspectionSummary", "dict"),
        "dataset_ids": ("List current Session Dataset IDs", [], "cell of IDs", "::GX::sessionInspectionDatasetIds", "list"),
        "dataset": ("Inspect one Dataset identity and provenance", [_arg("dataset_id", "string")], "Dataset identity struct", "::GX::sessionInspectionDataset", "safe_dataset"),
        "dataset_location": ("Inspect guarded Dataset availability without reading payload bytes", [_arg("dataset_id", "string")], "availability struct without absolute storage path", "::GX::sessionInspectionDatasetLocation", "safe_dataset_location"),
        "selection_ids": ("List current Session Selection IDs", [], "cell of IDs", "::GX::sessionInspectionSelectionIds", "list"),
    }),
    "SESSION_PERSISTENCE_API_v1": (1, "session_persistence", "docs/api/SESSION_PERSISTENCE_API_v1.md", {
        "commit": ("Commit framework-owned current Session state", [], "commit struct without storage path", "::GX::sessionPersistenceCommit", "safe_commit"),
    }),
    "PARALLEL_EXECUTION_API_v1": (1, "parallel_execution", "docs/api/PARALLEL_EXECUTION_API_v1.md", {
        "api_info": ("Inspect parallel resource and ordering policy", [], "policy struct", "::GX::parallelExecutionApiInfo", "dict"),
        "resources": ("Read allowed parallel resource policy", [], "policy struct", "::GX::parallelExecutionConfigure", "dict"),
    }),
    "PROGRESS_API_v1": (1, "progress", "docs/api/PROGRESS_API_v1.md", {
        "publish": ("Publish a structured progress event", [_arg("event", "struct")], "event struct", "::GX::progressPublish", "dict"),
    }),
    "INTERACTIVE_DOCUMENT_API_v1": (1, "interactive_document", "docs/api/INTERACTIVE_DOCUMENT_API_v1.md", {
        "list": ("List persistent Interactive Documents", [], "cell of document structs", "::GX::interactiveDocumentList", "dict_list"),
        "read": ("Read a persistent Interactive Document", [_arg("document_id", "string")], "document struct", "::GX::interactiveDocumentRead", "dict"),
    }),
    "PROJECT_API_v1": (1, "project", "docs/api/PROJECT_API_v1.md", {
        "list": ("List Project IDs", [], "cell of IDs", "::GX::projectIds", "list"),
        "get": ("Read Project metadata", [_arg("project_id", "string")], "Project struct without storage path", "::GX::projectGet", "safe_project"),
    }),
    "SEMANTIC_REGISTRY_API_v1": (1, "semantic_registry", "docs/api/SEMANTIC_REGISTRY_API_v1.md", {
        "list": ("List public semantic IDs", [], "cell of IDs", "::GX::semanticRegistryList", "list"),
        "definition": ("Read public semantic definition", [_arg("semantic_id", "string")], "semantic struct", "::GX::semanticRegistryDefinition", "dict"),
    }),
    "DOCUMENTATION_BROWSER_API_v1": (1, "documentation_browser", "docs/api/DOCUMENTATION_BROWSER_API_v1.md", {
        "list": ("Discover public documentation entries", [_arg("query", "string", False)], "cell of document descriptors without paths", "::GX::documentationBrowserList", "safe_doc_list"),
        "read": ("Read public documentation", [_arg("document_id", "string")], "UTF-8 text", "::GX::documentationBrowserRead", "string"),
    }),
    "MODULE_API_v1": (1, "module", "docs/api/MODULE_API_v1.md", {
        "operational_class": ("Read operational module class independently of package protection", [_arg("module_id", "string")], "operational class", "::GX::moduleOperationalClass", "string"),
        "operational_info": ("Inspect availability, analysis eligibility and package protection", [_arg("module_id", "string")], "typed module classification", "::GX::moduleOperationalInfo", "module_info"),
        "public_api_ids": ("Discover module-declared public API IDs", [_arg("module_id", "string")], "cell of API IDs", "::GX::modulePublicApiIds", "list"),
    }),
    "GRAPH_SERIES_API_v1": (1, "graph_series", "docs/api/GRAPH_SERIES_API_v1.md", {
        "set": ("Set persistent graph series", [_arg("module_id", "string"), _arg("graph_id", "string"), _arg("series_id", "string"), _arg("fields", "struct"), _arg("variant_id", "string", False)], "series struct", "::GX::graphSeriesSet", "safe_series"),
        "list": ("List persistent graph series", [_arg("module_id", "string"), _arg("graph_id", "string"), _arg("variant_id", "string", False), _arg("include_disabled", "integer", False)], "cell of series structs", "::GX::graphSeriesList", "safe_series_list"),
        "resolve": ("Resolve graph series", [_arg("module_id", "string"), _arg("graph_id", "string"), _arg("series_id", "string"), _arg("variant_id", "string", False)], "series struct", "::GX::graphSeriesResolve", "safe_series"),
        "remove": ("Remove graph series", [_arg("module_id", "string"), _arg("graph_id", "string"), _arg("series_id", "string"), _arg("variant_id", "string", False)], "empty", "::GX::graphSeriesRemove", "empty"),
        "ids": ("List series IDs", [_arg("module_id", "string"), _arg("graph_id", "string"), _arg("variant_id", "string", False)], "cell of IDs", "::GX::graphSeriesIds", "list"),
        "move": ("Move series order", [_arg("module_id", "string"), _arg("graph_id", "string"), _arg("series_id", "string"), _arg("delta", "integer"), _arg("variant_id", "string", False)], "cell of IDs", "::GX::graphSeriesMove", "list"),
        "snapshot": ("Read persistent series state", [_arg("module_id", "string"), _arg("graph_id", "string"), _arg("series_id", "string"), _arg("variant_id", "string", False)], "series struct", "::GX::graphSeriesSnapshot", "safe_series"),
        "expand_groups": ("Create grouped graph series", [_arg("module_id", "string"), _arg("graph_id", "string"), _arg("dataset_id", "string"), _arg("x_variable_id", "string"), _arg("y_variable_id", "string"), _arg("group_variable_id", "string"), _arg("options", "struct", False), _arg("variant_id", "string", False)], "cell of member structs", "::GX::graphSeriesExpandGroups", "dict_list"),
    }),
    "GRAPH_WORKFLOW_API_v1": (1, "graph_workflow", "docs/api/GRAPH_WORKFLOW_API_v1.md", {
        "axis_snapshot": ("Read axis state", [_arg("module_id", "string"), _arg("graph_id", "string"), _arg("variant_id", "string", False)], "axis struct", "::GX::graphAxisConfigSnapshot", "dict"),
        "presentation_set": ("Set graph aspect/background presentation", [_arg("module_id", "string"), _arg("graph_id", "string"), _arg("variant_id", "string"), _arg("changes", "struct")], "axis struct", "::GX::graphAxisPresentationSet", "dict"),
        "use_get": ("Read graph USE state", [_arg("module_id", "string"), _arg("graph_id", "string"), _arg("variant_id", "string", False)], "boolean", "::GX::graphUseStateGet", "integer"),
        "use_set": ("Set graph USE state", [_arg("module_id", "string"), _arg("graph_id", "string"), _arg("variant_id", "string"), _arg("value", "integer")], "boolean", "::GX::graphUseStateSet", "integer"),
        "scheduled_graph_ids": ("List scheduled graph IDs", [_arg("module_id", "string")], "cell of IDs", "::GX::scheduledModuleGraphIds", "list"),
    }),
    "PLOT_ANNOTATION_API_v1": (1, "plot_annotation", "docs/api/PLOT_ANNOTATION_API_v1.md", {
        "info": ("Read graph annotation capability", [_arg("module_id", "string"), _arg("graph_id", "string"), _arg("variant_id", "string", False)], "capability struct", "::GX::plotAnnotationInfo", "dict"),
        "read": ("Read graph annotation document", [_arg("module_id", "string"), _arg("graph_id", "string"), _arg("variant_id", "string", False)], "annotation document", "::GX::plotAnnotationRead", "dict"),
        "validate": ("Validate annotation objects", [_arg("module_id", "string"), _arg("graph_id", "string"), _arg("variant_id", "string"), _arg("objects", "list")], "normalized objects", "::GX::plotAnnotationValidate", "dict_list"),
        "add": ("Add one annotation", [_arg("module_id", "string"), _arg("graph_id", "string"), _arg("variant_id", "string"), _arg("object", "struct")], "annotation document", "::GX::plotAnnotationAdd", "dict"),
        "update": ("Update annotation by ID", [_arg("module_id", "string"), _arg("graph_id", "string"), _arg("variant_id", "string"), _arg("annotation_id", "string"), _arg("changes", "struct")], "annotation document", "::GX::plotAnnotationUpdate", "dict"),
        "remove": ("Remove annotation by ID", [_arg("module_id", "string"), _arg("graph_id", "string"), _arg("variant_id", "string"), _arg("annotation_id", "string")], "annotation document", "::GX::plotAnnotationRemove", "dict"),
        "replace": ("Replace annotation objects atomically", [_arg("module_id", "string"), _arg("graph_id", "string"), _arg("variant_id", "string"), _arg("objects", "list")], "annotation document", "::GX::plotAnnotationReplace", "dict"),
        "clear": ("Clear graph annotations", [_arg("module_id", "string"), _arg("graph_id", "string"), _arg("variant_id", "string", False)], "annotation document", "::GX::plotAnnotationClear", "dict"),
        "set_enabled": ("Enable or disable annotation layer", [_arg("module_id", "string"), _arg("graph_id", "string"), _arg("variant_id", "string"), _arg("enabled", "integer")], "annotation document", "::GX::plotAnnotationSetEnabled", "dict"),
    }),
    "GRAPH_NOTES_API_v1": (1, "graph_notes", "docs/api/GRAPH_NOTES_API_v1.md", {
        "info": ("Inspect one graph note", [_arg("graph_ref", "struct")], "note info", "::GX::graphNotesInfo", "dict"),
        "exists": ("Check graph note existence", [_arg("graph_ref", "struct")], "boolean", "::GX::graphNotesExists", "integer"),
        "read": ("Read graph Markdown note", [_arg("graph_ref", "struct")], "UTF-8 Markdown", "::GX::graphNotesRead", "string"),
        "write": ("Write graph Markdown note", [_arg("graph_ref", "struct"), _arg("markdown", "string")], "note info", "::GX::graphNotesWrite", "dict"),
        "clear": ("Remove graph Markdown note", [_arg("graph_ref", "struct")], "note info", "::GX::graphNotesClear", "dict"),
    }),
    "GRAPH_METADATA_API_v1": (1, "graph_metadata", "docs/api/GRAPH_METADATA_API_v1.md", {
        "info": ("Inspect graph metadata resource", [_arg("graph_ref", "struct")], "metadata info", "::GX::graphMetadataInfo", "dict"),
        "read": ("Read graph metadata", [_arg("graph_ref", "struct")], "metadata struct", "::GX::graphMetadataRead", "dict"),
        "write": ("Replace graph metadata", [_arg("graph_ref", "struct"), _arg("metadata", "struct")], "metadata struct", "::GX::graphMetadataWrite", "dict"),
        "update": ("Merge graph metadata", [_arg("graph_ref", "struct"), _arg("changes", "struct")], "metadata struct", "::GX::graphMetadataUpdate", "dict"),
        "unset": ("Remove graph metadata keys", [_arg("graph_ref", "struct"), _arg("keys", "list")], "metadata struct", "::GX::graphMetadataUnset", "dict"),
    }),
    "LEVEL_SCALE_API_v1": (1, "level_scale", "docs/api/LEVEL_SCALE_API_v1.md", {
        "get": ("Read level scale presentation", [_arg("graph_id", "string"), _arg("axis", "string")], "level scale struct", "::GX::levelScaleGet", "dict"),
        "set": ("Set level scale presentation", [_arg("graph_id", "string"), _arg("axis", "string"), _arg("fields", "struct")], "level scale struct", "::GX::levelScaleSet", "dict"),
    }),
    "CONTRACT_REGISTRY_API_v1": (1, "contract_registry", "docs/api/CONTRACT_REGISTRY_API_v1.md", {
        "list": ("List contract IDs", [], "cell of IDs", "::GX::contractRegistryIds", "list"),
        "known": ("Check a contract ID", [_arg("contract_id", "string")], "boolean", "::GX::contractRegistryKnown", "integer"),
        "field": ("Read a contract field", [_arg("contract_id", "string"), _arg("field", "string"), _arg("default", "string", False)], "field value", "::GX::contractRegistryField", "string"),
        "choices": ("List contract choices", [], "cell of choices", "::GX::contractRegistryChoices", "list"),
        "satisfies": ("Check contract specialization", [_arg("actual", "string"), _arg("expected", "string")], "boolean", "::GX::contractSatisfies", "integer"),
        "satisfies_any": ("Check any expected contract", [_arg("actual", "string"), _arg("expected", "list")], "boolean", "::GX::contractSatisfiesAny", "integer"),
    }),
    "PLOT_MODULE_API_v1": (1, "plot_module", "docs/api/PLOT_MODULE_API_v1.md", {
        "supports": ("Check variant support", [_arg("module_id", "string"), _arg("graph_id", "string")], "boolean", "::GX::plotVariantSupports", "integer"),
        "variant_ids": ("List persistent Variant IDs", [_arg("module_id", "string"), _arg("graph_id", "string")], "cell of IDs", "::GX::plotVariantIds", "list"),
        "variant_field": ("Read public Variant field", [_arg("module_id", "string"), _arg("graph_id", "string"), _arg("variant_id", "string"), _arg("field", "string"), _arg("default", "string", False)], "field value", "::GX::plotVariantField", "string"),
        "variant_artifact": ("Read Variant artifact path", [_arg("module_id", "string"), _arg("graph_id", "string"), _arg("variant_id", "string")], "artifact path", "::GX::plotVariantArtifact", "string"),
    }),
}

REGISTRATIONS = [_api(api_id, version, provider, doc, operations)
                 for api_id, (version, provider, doc, operations) in SERVICES.items()]


def _origin_record(host, value, depth=0):
    if depth > 64:
        raise BridgeError("GXTXT:ScriptBridge:RemoteError", "Origin chain exceeds inspection depth")
    row = host.as_dict(value)
    parent = host.as_dict(row.get("parent", ""))
    if parent.get("origin_snapshot"):
        parent["origin_snapshot"] = _origin_record(host, parent["origin_snapshot"], depth + 1)
    row["parent"] = parent
    row["events"] = [host.as_dict(item) for item in host.as_list(row.get("events", ""))]
    return row


def invoke_api(host, api_id, operation, args):
    definition = SERVICES.get(api_id)
    if definition is None or operation not in definition[3]:
        raise BridgeError("GXTXT:ScriptBridge:UnknownOperation", f"{api_id}/{operation} is unavailable")
    _, schema, _, command, conversion = definition[3][operation]
    minimum = sum(a["required"] for a in schema)
    if not minimum <= len(args) <= len(schema):
        raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"{api_id}/{operation} expects {minimum} to {len(schema)} arguments")
    for value, arg in zip(args, schema):
        kind = arg["kind"]
        if kind == "string" and not isinstance(value, str) or kind == "struct" and not isinstance(value, dict) or kind == "list" and not isinstance(value, (list, tuple)):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"{api_id}/{operation}: {arg['name']} must be {kind}")
        if kind == "integer" and (not isinstance(value, (int, float)) or int(value) != value):
            raise BridgeError("GXTXT:ScriptBridge:InvalidArguments", f"{api_id}/{operation}: {arg['name']} must be integer")
    result = host.call(command, *args)
    if conversion == "origin":
        return _origin_record(host, result)
    if conversion == "identity_history":
        return [host.as_dict(item) for item in host.as_list(result)]
    if conversion == "recipe_proposal":
        result = host.as_dict(result)
        result["operations"] = [host.as_dict(item) for item in host.as_list(result["operations"])]
        result["warnings"] = host.as_list(result["warnings"])
        result["provenance"] = host.as_dict(result["provenance"])
        return result
    if (api_id == "GRAPH_SERIES_API_v1" and operation in {"set", "remove", "move", "expand_groups"} or
        api_id == "GRAPH_WORKFLOW_API_v1" and operation in {"use_set", "presentation_set"} or
        api_id == "PLOT_ANNOTATION_API_v1" and operation in {"add", "update", "remove", "replace", "clear", "set_enabled"} or
        api_id == "GRAPH_NOTES_API_v1" and operation in {"write", "clear"} or
        api_id == "GRAPH_METADATA_API_v1" and operation in {"write", "update", "unset"} or
        api_id == "LEVEL_SCALE_API_v1" and operation == "set"):
        host.persist_manifest(f"{api_id}/{operation}")
    if conversion == "module_info":
        result = host.as_dict(result)
        for key in ("core_protected", "always_available", "analysis_enableable", "run_eligible", "enabled"):
            result[key] = bool(int(result[key]))
        return result
    if conversion == "integer":
        return int(result)
    if conversion == "empty":
        return ""
    if conversion == "list":
        return host.as_list(result)
    if conversion == "dict_list":
        return [host.normalize(item) for item in host.as_list(result)]
    if conversion == "safe_doc_list":
        entries = [host.as_dict(item) for item in host.as_list(result)]
        for entry in entries:
            entry.pop("path", None)
        return entries
    if conversion == "safe_series_list":
        rows = [host.normalize(item) for item in host.as_list(result)]
        for row in rows:
            row.pop("path", None)
        return rows
    if conversion == "safe_series":
        row = host.normalize(result)
        row.pop("path", None)
        return row
    if conversion == "safe_commit":
        result = host.as_dict(result)
        result.pop("session", None)
        result.pop("manifest_path", None)
        return result
    if conversion == "safe_dataset_location":
        details = host.as_dict(result)
        details.pop("path", None)
        return details
    if conversion == "safe_dataset":
        details = host.as_dict(result)
        return {key: details.get(key, "") for key in ("id", "kind", "format", "row_count", "canonical_sha256", "source_sha256", "source_module", "created_at")}
    if conversion == "safe_project":
        details = host.as_dict(result)
        details.pop("storage_path", None)
        return details
    if conversion == "string":
        return str(result)
    return host.normalize(result)
