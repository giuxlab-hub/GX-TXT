#!/usr/bin/env python3
"""CORE structural-transform worker; canonical input only through public APIs.

SQLite provides disk-backed row/key ordering. Neither a source reader nor a
Dataset publication implementation lives here. Private hex-row transport keeps
arbitrary UTF-8/text/newlines distinct without evaluating generated Tcl code.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
from __future__ import annotations
import base64
from collections import OrderedDict
import itertools
import math
import re
from pathlib import Path
import sqlite3
import struct
import sys
from gxtxt_script_bridge_server import Host
from gxtxt_unit_program_v1 import compile_formula

OPERATIONS = {"project_variables", "subset_rows", "concat_rows", "merge_columns",
              "join_by_key", "rename_reorder", "curve_bundle", "build_family",
              "extract_family_member", "split_family", "convert_units", "calibrate_variables",
              "transform_xy", "reverse_rows", "reverse_range", "reverse_sequence", "combine_selection", "sort_rows", "baseline_correct", "log_variables", "smooth_curve"}


def require(test, message):
    if not test:
        raise ValueError(message)


class Transform:
    def __init__(self, runtime, request, directory):
        self.host = Host(Path(runtime))
        self.directory = Path(directory)
        self.request = self.dictionary(Path(request).read_text(encoding="utf-8"))
        self.op = self.request["operation"]
        self.effective_op = self.op
        self.compatibility_conflicts = []
        require(self.op in OPERATIONS, f"Unknown transform operation '{self.op}'")
        self.options = self.dictionary(self.request.get("options", ""))
        self.output = self.dictionary(self.request.get("output", ""))
        self.sources = [self.dictionary(s) for s in self.sequence(self.request["sources"])]
        require(self.sources, "A transform requires at least one source")
        self.db = sqlite3.connect(self.directory / "rows.sqlite3")
        self.db.execute("PRAGMA cache_size=-4096")
        self.db.execute("PRAGMA temp_store=FILE")
        self.conversions = []
        self.calibrations = []
        self.coordinate_calibration = self.dictionary(self.request.get("_coordinate_calibration", ""))
        require(self.op == "calibrate_variables" or not self.coordinate_calibration, "Unexpected calibration envelope")
        self.unit_assumptions = []
        self.schema = []
        self.tables = []
        self.output_map = []
        self.family_coordinates = {}
        self.family_parts = {}
        self.part_handles = OrderedDict()
        self.member_descriptors = []
        self.input_chunks = 0;self.max_input_chunk = 0;self.binary_columns = 0
        self.bundle_auxiliary_mapping = []

    def dictionary(self, value):
        return {str(k): v for k, v in self.host.as_dict(value).items()}

    def sequence(self, value):
        return self.host.as_list(value)

    def string(self, value):
        return str(value)

    def option(self, name, default=None):
        return self.options.get(name, default)

    def typed(self, value, spec):
        if spec["dtype"] == "string": return str(value)
        # Canonical numeric CSV cells may be missing Tcl empty objects. Keep
        # them null in the existing view, rather than converting them to zero.
        if value is None or str(value) == "": return None
        if spec["dtype"] == "bool": return int(str(value).lower() in ("1", "true"))
        if str(spec["dtype"]).startswith(("int", "uint")): return int(value)
        return float(value)

    def numeric_unit(self, symbol):
        return self.dictionary(self.host.call("::GX::unitRegistryDefinition", symbol))

    def converter(self, spec, target):
        source = spec.get("unit", "")
        if source == target: return lambda value: value
        override = {field: spec[field] for field in ("canonical_unit", "to_canonical", "from_canonical")} if spec.get("canonical_unit") else {}
        plan = self.dictionary(self.host.call("::GX::unitRegistryConversionPlan", source, target, override))
        require(spec["dtype"] != "string", "Unit conversion requires numeric variables")
        self.conversions.append(dict(plan, variable_id=spec["variable_id"]))
        target_definition = self.dictionary(plan["target_definition"])
        spec["unit"] = target
        spec["dtype"] = "float64"
        for field in ("canonical_unit", "to_canonical", "from_canonical"):
            spec[field] = target_definition[field]
        forward = compile_formula(self.host, plan["source_to_canonical"])
        inverse = compile_formula(self.host, plan["target_from_canonical"])
        ratio = float(plan["base_scale_ratio"])
        def convert(value):
            if value is None:
                return None
            canonical = forward(value) * ratio
            require(not math.isfinite(float(value)) or math.isfinite(canonical), "Unit conversion exceeds the finite numeric range")
            return inverse(canonical)
        return convert

    def calibrator(self, spec, settings):
        settings = self.dictionary(settings)
        factor, origin, output = (float(settings[key]) for key in ("calibration_factor", "input_origin", "output_origin"))
        require(all(math.isfinite(v) for v in (factor, origin, output)) and factor > 0, "Invalid calibration coefficients")
        require(spec["dtype"] in ("float32", "float64", "int8", "int16", "int32", "int64", "uint8", "uint16", "uint32", "uint64"), "Calibration requires a real numeric Variable")
        identity = factor == 1 and origin == output
        self.calibrations.append(dict(variable_id=spec["variable_id"], source_dtype=spec["dtype"], unit=spec.get("unit", ""),
            factor=factor, input_origin=origin, output_origin=output, identity=int(identity),
            coordinate_revision=int(self.option("expected_coordinate_revision"))))
        if identity:
            return lambda value: value
        spec["dtype"] = "float64"
        def convert(value):
            if value is None:
                return None
            if isinstance(value, int):
                require(int(float(value)) == value, "Calibration would lose input integer precision; select an exactly representable Variable")
            value = float(value)
            if not math.isfinite(value):
                return value
            result = output + factor * (value - origin)
            require(math.isfinite(result), "Calibration exceeds the finite binary64 range")
            return result
        return convert

    def matches(self, values, source, ordinal, filters, chosen):
        if "rows" in source:
            included = ordinal in chosen
            if (source.get("row_operation", "keep") == "keep") != included: return False
        start = int(source.get("start", self.option("start", 0)))
        count = int(source.get("count", self.option("count", -1)))
        if ordinal < start or (count >= 0 and ordinal >= start + count): return False
        for item in filters:
            identifier = item["filter_variable_id"]
            require(identifier in values, f"Filter variable '{identifier}' is absent")
            spec = self.variables[source["member_id"]][identifier]
            value = values[identifier]
            predicate = item["predicate"]
            numeric = spec["dtype"] != "string"
            integral = str(spec["dtype"]).startswith(("int", "uint")) or spec["dtype"] == "bool"
            def scalar(item):
                if not numeric: return str(item)
                if item is None: return math.nan
                if integral:
                    try: return int(item)
                    except ValueError: return float(item)
                return float(item)
            number = scalar(value)
            if numeric and not math.isfinite(number) and predicate != "is_nonfinite": return False
            if predicate == "is_finite": accepted = numeric and math.isfinite(number)
            elif predicate == "is_nonfinite": accepted = numeric and not math.isfinite(number)
            else:
                target = item.get("value", "")
                target = scalar(target) if numeric and target != "" else str(target)
                if predicate == "exact_equal": accepted = number == target
                elif predicate == "not_equal": accepted = number != target
                elif predicate == "less_than": accepted = number < target
                elif predicate == "less_equal": accepted = number <= target
                elif predicate == "greater_than": accepted = number > target
                elif predicate == "greater_equal": accepted = number >= target
                elif predicate == "between_inclusive": accepted = scalar(item["lower"]) <= number <= scalar(item["upper"])
                elif predicate == "in_set": accepted = number in [scalar(v) for v in self.sequence(item["values"])]
                elif predicate == "contains": accepted = str(item["value"]) in str(number)
                elif predicate == "like":
                    expression = "".join(".*" if c == "%" else "." if c == "_" else re.escape(c) for c in str(item["value"]))
                    accepted = re.fullmatch(expression, str(number), flags=re.DOTALL) is not None
                else: raise ValueError(f"Unsupported safe row predicate '{predicate}'")
            if not accepted: return False
        if "selection_filters" in source:
            inside = self.matches(values, {"member_id": source["member_id"]}, ordinal,
                                  [self.dictionary(v) for v in self.sequence(source["selection_filters"])], set())
            require(source.get("selection_operation", "keep") in ("keep", "exclude"), "Invalid selection operation")
            return inside if source.get("selection_operation", "keep") == "keep" else not inside
        return True

    def load(self):
        self.variables = {}
        member_ids = set()
        for index, source in enumerate(self.sources):
            member = source.get("member_id", f"member{index+1}")
            require(member not in member_ids, f"Duplicate member ID '{member}'")
            source["member_id"] = member;member_ids.add(member)
            if not source.get("dataset_id"):
                continue
            handle = self.host.call("::GX::datasetAccessOpen", self.host.session, source["dataset_id"])
            try:
                metadata = self.dictionary(self.host.call("::GX::datasetAccessMetadata", handle))
                variables = [self.dictionary(v) for v in self.sequence(metadata["variables"])]
            finally:
                self.host.call("::GX::datasetAccessClose", handle)
            variables = [v for v in variables if str(v.get("enabled", 1)) != "0" and int(v["rank"]) == 1]
            self.variables[member] = {v["variable_id"]: v for v in variables}
            for identifier, assumed in self.dictionary(source.get("assume_units", "")).items():
                require(identifier in self.variables[member], f"Unknown assumed-unit variable '{identifier}'")
                variable = self.variables[member][identifier]
                require(not variable.get("unit"), f"Cannot assume a unit for already declared '{identifier}'")
                require(variable["dtype"] != "string" and variable.get("value_kind", "number") == "number", "Unit assumptions require numeric variables")
                require(not any(variable.get(field) for field in ("canonical_unit", "to_canonical", "from_canonical")), "Normalize calibrated variables explicitly before a unit assumption")
                require(str(assumed).strip(), "An explicit assumed unit is required")
                self.numeric_unit(assumed)
                variable["unit"] = assumed
                self.unit_assumptions.append(dict(source_dataset_id=source["dataset_id"], member_id=member, variable_id=identifier, assumed_unit=assumed, original_unit="", source_schema_mutated=0))
            source["contract"] = metadata["contract"]
            source["sha256"] = str(self.host.call("::GX::datasetField", source["dataset_id"], "canonical_sha256", ""))
            selected = self.sequence(source.get("variable_ids", self.option("variable_ids", "")))
            if not selected: selected = list(self.variables[member])
            require(len(set(selected)) == len(selected), "Duplicate selected Variable IDs")
            require(all(v in self.variables[member] for v in selected), f"Unknown or non-table variable in '{source['dataset_id']}'")
            filters = [self.dictionary(v) for v in self.sequence(source.get("row_filters", ""))]
            if self.op == "extract_family_member":
                members = self.sequence(self.option("members", ""))
                require(members, "Select explicit family members")
                filters.append({"filter_variable_id": self.option("member_variable_id", "member_id"), "predicate": "in_set", "values": self.host.tcl_arg(members)})
            read_ids = list(dict.fromkeys(selected + [f["filter_variable_id"] for f in filters + [self.dictionary(v) for v in self.sequence(source.get("selection_filters", ""))]]))
            chosen = {int(v) for v in self.sequence(source.get("rows", ""))}
            require(all(v >= 0 for v in chosen), "Selected row indices must be nonnegative")
            count = int(metadata["row_count"])
            require(count < 0 or all(v < count for v in chosen), "Selected row is outside the source Dataset")
            require(int(source.get("start", self.option("start", 0))) >= 0 and int(source.get("count", self.option("count", -1))) >= -1, "Invalid row slice")
            require(source.get("row_operation", "keep") in ("keep", "exclude"), "Invalid row subset operation")
            aliases = self.dictionary(source.get("variable_map", self.option("rename", "")))
            labels = self.dictionary(self.option("display_labels", ""))
            conversions = self.dictionary(source.get("convert_units", self.option("target_units", "")))
            schema = []
            converters = []
            inherited_axes = {}
            if self.op == "extract_family_member":
                metadata_fields = self.dictionary(self.host.call("::GX::datasetMetadataRead", self.host.session, source["dataset_id"]))
                effective = self.dictionary(metadata_fields.get("transform.effective", ""))
                members = self.sequence(self.option("members", ""))
                if len(members) == 1:
                    for descriptor in self.sequence(effective.get("member_descriptors", "")):
                        descriptor = self.dictionary(descriptor)
                        if descriptor["member_id"] != members[0]: continue
                        for axis in ("x", "y"):
                            inherited_axes[descriptor.get(f"bundle_{axis}_variable_id", axis)] = self.dictionary(descriptor[f"{axis}_descriptor"])
            for identifier in selected:
                variable = dict(self.variables[member][identifier])
                if identifier in inherited_axes:
                    for field in ("unit", "display_label", "semantic_role", "value_kind", "value_format", "canonical_unit", "to_canonical", "from_canonical", "time_origin", "time_reference"):
                        variable[field] = inherited_axes[identifier].get(field, variable.get(field, ""))
                if self.op == "calibrate_variables" and identifier in self.coordinate_calibration:
                    converter = self.calibrator(variable, self.coordinate_calibration[identifier])
                else:
                    converter = self.converter(variable, conversions[identifier]) if identifier in conversions else lambda value: value
                converters.append(converter)
                variable["variable_id"] = aliases.get(identifier, identifier)
                if identifier in aliases: variable["name"] = variable["canonical"] = aliases[identifier]
                self.host.call("::GX::datasetPublicationV2ValidateId", "variable", variable["variable_id"])
                if identifier in labels: variable["display_label"] = labels[identifier]
                coordinate_ids = ""
                if self.op in ("project_variables", "rename_reorder"):
                    # Projection keeps only requested Variables, including their
                    # relationships when the referenced source is also selected.
                    related_ids = (item.strip() for item in str(variable.get("coordinate_variable_ids", "")).replace(",", ";").split(";"))
                    coordinate_ids = ";".join(aliases.get(related, related) for related in related_ids if related in selected)
                variable.update(rank=1, dimension_ids="row", axis_kind="explicit", shape="", maxshape="*", coordinate_variable_ids=coordinate_ids)
                schema.append(variable)
            names = [v["variable_id"] for v in schema]
            require(len(names) == len(set(names)), "Renamed variable IDs collide")
            table = f"source{index}"
            # Calibration uses complete tuple order, with no SQL numerical
            # comparisons. Store floating cells as round-trip text so SQLite
            # cannot normalize -0.0 or collapse NaN into SQL NULL.
            exact_float_text = self.op in ("calibrate_variables", "baseline_correct", "log_variables", "smooth_curve")
            columns = ",".join(f"c{i} " + ("TEXT" if v["dtype"] in ("string", "uint64") or (exact_float_text and str(v["dtype"]).startswith("float")) else "REAL" if str(v["dtype"]).startswith("float") else "INTEGER") for i, v in enumerate(schema))
            self.db.execute(f"CREATE TABLE {table} (seq INTEGER PRIMARY KEY, source_row INTEGER, {columns})")
            stream = self.host.call("::GX::tableStreamOpenDataset", self.host.session, source["dataset_id"], read_ids, 65536, {"numeric_transport": "auto"})
            try:
                position = 0
                while True:
                    chunk = self.dictionary(self.host.call("::GX::tableStreamNext", stream))
                    self.input_chunks += 1;self.max_input_chunk = max(self.max_input_chunk, int(chunk["nrows"]))
                    values = {}
                    for item in self.sequence(chunk["columns"]):
                        column = self.dictionary(item);identifier = column["variable_id"]
                        if "binary_block" in column:
                            self.binary_columns += 1
                            block = self.dictionary(column["binary_block"])
                            formats = {"bool": "?", "int8": "b", "uint8": "B", "int16": "h", "uint16": "H", "int32": "i", "uint32": "I", "int64": "q", "uint64": "Q", "float16": "e", "float32": "f", "float64": "d"}
                            require(block["dtype"] in formats, "Unsupported typed canonical sort/transform column")
                            require(block["endian"] in ("little", "big"), "Unsupported canonical byte order")
                            fmt = ("<" if block["endian"] == "little" else ">") + formats[block["dtype"]]
                            raw = base64.b64decode(block["base64"], validate=True)
                            require(len(raw) == int(chunk["nrows"])*struct.calcsize(fmt), "Canonical binary chunk shape mismatch")
                            values[identifier] = [value[0] for value in struct.iter_unpack(fmt, raw)]
                        else: values[identifier] = self.sequence(column["values"])
                    batch = []
                    for row in range(int(chunk["nrows"])):
                        ordinal = int(chunk["offset"]) + row
                        data = {v: values[v][row] for v in read_ids}
                        if not self.matches(data, source, ordinal, filters, chosen): continue
                        data = [convert(self.typed(data[v], self.variables[member][v])) for v, convert in zip(selected, converters)]
                        data = [str(v) if v is not None and (spec["dtype"] == "uint64" or (exact_float_text and str(spec["dtype"]).startswith("float"))) else v for v,spec in zip(data,schema)]
                        batch.append((position, ordinal, *data));position += 1
                    if batch: self.db.executemany(f"INSERT INTO {table} VALUES ({','.join('?' for _ in range(len(schema)+2))})", batch)
                    if int(chunk["eof"]): break
                self.db.commit()
            finally:
                self.host.call("::GX::tableStreamClose", stream)
            source.update(selected_variable_ids=selected, schema=schema, table=table, row_count=position)
            self.tables.append(table)
        if any("native_geometry" in source for source in self.sources):
            self.load_geometry()

    def load_geometry(self):
        """Materialize owned XY resources with exact source-row tuple lookup.

        Auxiliary integer/string types stay exact. Unbound rows have explicit
        validity=0 and inert zero/empty placeholders, never invented readings.
        """
        templates = [s for s in self.sources if s.get("dataset_id")]
        prefix = self.option("lineage_prefix", "selection_")
        validity_id, gap_id = prefix+"auxiliary_valid", prefix+"break_before"
        base_template = templates[0] if templates else None
        for index, source in enumerate(self.sources):
            geometry = self.dictionary(source.get("native_geometry", ""))
            if not geometry:
                schema = source["schema"]
                require(not {validity_id,gap_id}.intersection(v["variable_id"] for v in schema), "Geometry validity/gap columns collide")
                self.db.execute(f"ALTER TABLE {source['table']} ADD COLUMN c{len(schema)} INTEGER DEFAULT 1")
                self.db.execute(f"ALTER TABLE {source['table']} ADD COLUMN c{len(schema)+1} INTEGER DEFAULT 0")
                schema.extend([self.field(validity_id,"bool"),self.field(gap_id,"bool")])
                source["selected_variable_ids"].extend([validity_id,gap_id])
                continue
            template = source if source.get("dataset_id") else base_template
            if template:
                # A preceding Dataset already augmented above is still a
                # template only for original scientific variables.
                schema = [dict(v) for v in template["schema"] if v["variable_id"] not in (validity_id,gap_id)]
                identifiers = [v for v in template["selected_variable_ids"] if v not in (validity_id,gap_id)]
                x_id, y_id = template["x_variable_id"], template["y_variable_id"]
            else:
                schema = [self.dictionary(geometry[axis+"_variable"]) for axis in ("x","y")]
                identifiers = [v["variable_id"] for v in schema]
                x_id,y_id = identifiers
            require(x_id in identifiers and y_id in identifiers and x_id!=y_id, "Native XY bindings must be distinct selected variables")
            xi,yi = identifiers.index(x_id),identifiers.index(y_id)
            for axis,axis_index in (("x",xi),("y",yi)):
                descriptor = self.dictionary(geometry[axis+"_variable"])
                require(descriptor.get("unit","")==schema[axis_index].get("unit",""), "Native/Dataset coordinate units differ; convert explicitly")
                require(schema[axis_index]["dtype"]=="float64", "Mixed Native materialization requires explicit float64 coordinate schema")
            require(not {validity_id,gap_id}.intersection(v["variable_id"] for v in schema), "Geometry validity/gap columns collide")
            table = f"geometry{index}"
            columns = ",".join(f"c{i} "+("TEXT" if v["dtype"] in ("string","uint64") else "REAL" if v["dtype"].startswith("float") else "INTEGER") for i,v in enumerate(schema))
            self.db.execute(f"CREATE TABLE {table} (seq INTEGER PRIMARY KEY,source_row INTEGER,{columns},c{len(schema)} INTEGER,c{len(schema)+1} INTEGER)")
            old_table = source.get("table")
            if old_table: self.db.execute(f"CREATE INDEX {old_table}_row ON {old_table}(source_row)")
            readers = []
            try:
                xy = open(source["_xy_resource_file"],"rb");readers.append(xy)
                row_reader = open(source["_row_resource_file"],"rb") if "_row_resource_file" in source else None
                gap_reader = open(source["_gap_resource_file"],"rb") if "_gap_resource_file" in source else None
                readers.extend(r for r in (row_reader,gap_reader) if r is not None)
                count = 0
                while True:
                    raw = xy.read(16*8192)
                    if not raw: break
                    require(len(raw)%16==0,"Truncated owned XY geometry")
                    n = len(raw)//16
                    row_data = row_reader.read(n*8) if row_reader else b""
                    gaps = gap_reader.read(n) if gap_reader else bytes(n)
                    require(len(gaps)==n and (not row_reader or len(row_data)==n*8),"Geometry lineage/gap shape mismatch")
                    rows = [r[0] for r in struct.iter_unpack("<Q",row_data)] if row_reader else [2**64-1]*n
                    batch = []
                    for offset,((x,y),ordinal,gap) in enumerate(zip(struct.iter_unpack("<dd",raw),rows,gaps)):
                        require(math.isfinite(x) and math.isfinite(y),"Native materialization requires finite XY")
                        if ordinal==2**64-1: ordinal=-1
                        original = self.db.execute(f"SELECT * FROM {old_table} WHERE source_row=?",(ordinal,)).fetchone() if old_table and ordinal>=0 else None
                        require(not (old_table and ordinal>=0 and original is None),"Native lineage row is absent from the captured Dataset source")
                        values = list(original[2:2+len(schema)]) if original else ["" if v["dtype"]=="string" else 0 for v in schema]
                        values[xi],values[yi] = x,y
                        batch.append((count+offset,ordinal,*values,int(original is not None),int(bool(gap))))
                    self.db.executemany(f"INSERT INTO {table} VALUES ({','.join('?' for _ in range(len(schema)+4))})",batch)
                    count += n
                    self.input_chunks += 1;self.max_input_chunk=max(self.max_input_chunk,n)
                require(count>0,"Owned Native geometry contains no rows")
            finally:
                for reader in readers: reader.close()
            schema.extend([self.field(validity_id,"bool"),self.field(gap_id,"bool")])
            identifiers.extend([validity_id,gap_id])
            source.update(schema=schema,selected_variable_ids=identifiers,table=table,row_count=count,x_variable_id=x_id,y_variable_id=y_id)
            source.setdefault("dataset_id","");source.setdefault("sha256","");source.setdefault("contract","table.generic")
        self.db.commit()
        self.options["native_auxiliary_policy"] = "auxiliary_valid=0 means all non-XY source variables are absent; zero/empty placeholders are not scientific values"

    def compatible(self, a, b):
        fields = ("variable_id", "dtype", "unit", "semantic_role", "value_kind", "coordinate_role", "rank")
        require(len(a) == len(b), "Concat sources have different ordered variables")
        for left, right in zip(a, b):
            for field in fields:
                require(str(left.get(field, "")) == str(right.get(field, "")), f"Concat incompatibility: {left['variable_id']} {field}")

    def source_rows(self, source):
        reverse = str(source.get("reverse", "0")).lower()
        require(reverse in ("0", "1", "false", "true", "no", "yes"), "Source reverse must be a boolean")
        reverse = reverse in ("1", "true", "yes")
        scope = self.sequence(self.option("source_member_ids", ""))
        if self.option("member_id") is not None: scope = [self.option("member_id")]
        require(not scope or set(scope).issubset({s["member_id"] for s in self.sources}), "Unknown source member scope")
        applies = not scope or source["member_id"] in scope
        if self.op == "reverse_sequence":
            require(not self.option("members", ""), "reverse_sequence uses complete source rows; member-partition steps are not supported")
            steps = [self.sequence(step) for step in self.sequence(self.option("steps", ""))]
            require(steps and len(steps) <= 65536, "reverse_sequence requires 1..65536 explicit ordered start/count steps")
            normalized = []
            for step in steps:
                require(len(step) == 2, "A reverse step is {start count}")
                require(all(re.fullmatch(r"[0-9]+", str(value)) for value in step), "Reverse step bounds must be nonnegative integers")
                start, count = map(int, step)
                require(count >= 1 and start + count <= source["row_count"], "Reverse step is outside complete source rows")
                normalized.append((start, count))
            # Reuse ordinary source ordering/reversal before the explicit steps.
            # Only a disk-indexed permutation is built, never a full row list.
            original_operation = self.op
            try:
                self.op = "concat_rows"
                base = self.source_rows(source)
            finally:
                self.op = original_operation
            if not applies: return base
            permutation = source["table"] + "_reverse_sequence"
            self.db.execute(f"CREATE TEMP TABLE {permutation}(seq INTEGER PRIMARY KEY,pos INTEGER NOT NULL)")
            self.db.executemany(f"INSERT INTO {permutation} VALUES (?,?)", ((row[0], position) for position, row in enumerate(base)))
            for start, count in normalized:
                self.db.execute(f"UPDATE {permutation} SET pos=?-pos WHERE pos>=? AND pos<?", (2*start+count-1, start, start+count))
            self.db.commit()
            return self.db.execute(f"SELECT t.* FROM {source['table']} t JOIN {permutation} p ON p.seq=t.seq ORDER BY p.pos")
        if reverse or source.get("order_variable_ids", ""):
            require(self.op != "reverse_range", "Ordered/reversed source preprocessing cannot be combined with reverse_range")
            require(not self.option("members", ""), "Source ordering/reversal cannot be combined with member-scoped reverse; use separate explicit transformations")
        if self.op == "sort_rows" or source.get("order_variable_ids", ""):
            require(self.op != "reverse_range", "Ordered source preprocessing cannot be combined with reverse_range")
            identifiers = source["selected_variable_ids"]
            keys = self.sequence(source.get("order_variable_ids", self.option("order_variable_ids", "")))
            require(keys and len(set(keys)) == len(keys), "Sort requires distinct explicit order Variable IDs")
            require(all(key in identifiers for key in keys), "Sort key must be included in the selected complete tuple")
            descending = str(self.option("descending", "0")).lower()
            require(descending in ("0", "1", "false", "true", "no", "yes"), "Sort descending must be a boolean")
            direction = "DESC" if descending in ("1", "true", "yes") else "ASC"
            if self.op == "reverse_rows" and applies: reverse = not reverse
            if reverse: direction = "ASC" if direction == "DESC" else "DESC"
            ordering = []
            for key in keys:
                index = identifiers.index(key);column = f"c{index}";dtype = source["schema"][index]["dtype"]
                if dtype != "string":
                    predicate = f"{column} IS NULL"
                    if str(dtype).startswith("float"): predicate += f" OR ABS({column})>1.7976931348623157e308"
                    require(self.db.execute(f"SELECT 1 FROM {source['table']} WHERE {predicate} LIMIT 1").fetchone() is None, "Sort keys must be finite/non-null")
                if dtype == "uint64": ordering.append(f"LENGTH({column}) {direction}")
                ordering.append(f"{column} {direction}")
            ordering.append("seq DESC" if reverse else "seq ASC")
            return self.db.execute(f"SELECT * FROM {source['table']} ORDER BY {','.join(ordering)}")
        if self.op in ("reverse_rows", "reverse_range") and self.option("members", ""):
            identifiers = source["selected_variable_ids"]
            variable = self.option("member_variable_id", "member_id")
            require(variable in identifiers, "Member-scoped reverse requires a selected member identity variable")
            column = f"c{identifiers.index(variable)}"
            members = [str(v) for v in self.sequence(self.option("members"))]
            marks = ",".join("?" for _ in members)
            counts = dict(self.db.execute(f"SELECT {column},COUNT(*) FROM {source['table']} WHERE {column} IN ({marks}) GROUP BY {column}", members))
            require(set(counts) == set(members), "Requested reverse member is absent")
            ordering = "p.n+1-p.rn"
            if self.op == "reverse_range":
                ranges = [self.sequence(r) for r in self.sequence(self.option("ranges", ""))]
                require(ranges, "Member reverse_range requires start/count ranges")
                occupied = [];parts = []
                for item in ranges:
                    require(len(item) == 2, "A reverse range is {start count}")
                    start,count = map(int,item)
                    require(start >= 0 and count >= 1 and all(start+count<=n for n in counts.values()), "Reverse range is outside a selected member")
                    require(all(start+count<=a or start>=b for a,b in occupied), "Reverse ranges overlap")
                    occupied.append((start,start+count))
                    parts.append(f"WHEN p.rn>{start} AND p.rn<={start+count} THEN {2*start+count+1}-p.rn")
                ordering = f"CASE {' '.join(parts)} ELSE p.rn END"
            query = f"""WITH positioned AS (
                SELECT seq,{column} member,ROW_NUMBER() OVER(PARTITION BY {column} ORDER BY seq) rn,COUNT(*) OVER(PARTITION BY {column}) n FROM {source['table']}),
                permutation AS (SELECT p.seq target_seq,q.seq source_seq FROM positioned p JOIN positioned q ON p.member=q.member AND q.rn={ordering} WHERE p.member IN ({marks}))
                SELECT t.* FROM {source['table']} t LEFT JOIN permutation p ON t.seq=p.source_seq ORDER BY COALESCE(p.target_seq,t.seq)"""
            return self.db.execute(query,members)
        query = f"SELECT * FROM {source['table']} ORDER BY seq"
        if (self.op == "reverse_rows" and applies) != reverse:
            query += " DESC"
        elif self.op == "reverse_range" and applies:
            ranges = [self.sequence(r) for r in self.sequence(self.option("ranges", ""))]
            require(ranges, "reverse_range requires explicit start/count ranges")
            occupied = []
            parts = []
            for item in ranges:
                require(len(item) == 2, "A reverse range is {start count}")
                start, count = map(int, item)
                require(start >= 0 and count >= 1 and start + count <= source["row_count"], "Reverse range is outside member rows")
                require(all(start + count <= a or start >= b for a, b in occupied), "Reverse ranges overlap")
                occupied.append((start, start + count))
                parts.append(f"WHEN seq >= {start} AND seq < {start+count} THEN {2*start+count-1}-seq")
            query = f"SELECT * FROM {source['table']} ORDER BY CASE {' '.join(parts)} ELSE seq END"
        return self.db.execute(query)

    @staticmethod
    def field(identifier, dtype="string", unit="", role="auxiliary"):
        return {"variable_id": identifier, "name": identifier, "display_label": identifier.replace("_", " "),
                "dtype": dtype, "unit": unit, "semantic_role": role, "coordinate_role": "coordinate" if role == "coordinate" else "auxiliary" if role == "auxiliary" else "data",
                "value_kind": "text" if dtype == "string" else "number", "rank": 1, "dimension_ids": "row", "axis_kind": "explicit"}

    def bundle(self):
        representation = self.option("representation", "long")
        require(representation in ("wide", "long", "family"), "Curve bundle representation must be wide or long/family")
        positions = []
        for source in self.sources:
            ids = source["selected_variable_ids"]
            require(source.get("x_variable_id") in ids and source.get("y_variable_id") in ids, "Curve sources require explicit X/Y Variable IDs")
            positions.append((ids.index(source["x_variable_id"]), ids.index(source["y_variable_id"])))
        preserve=str(self.option("preserve_auxiliary","0")).lower() in ("1","true","yes") or any("native_geometry" in source for source in self.sources)
        auxiliary=[]
        if preserve:
            for source,(x,y) in zip(self.sources,positions):
                for i,specification in enumerate(source["schema"]):
                    if i in (x,y): continue
                    specification=dict(specification);old=specification["variable_id"]
                    specification["variable_id"]=source["member_id"]+"_"+old
                    specification["name"]=specification["canonical"]=specification["variable_id"]
                    self.host.call("::GX::datasetPublicationV2ValidateId","variable",specification["variable_id"])
                    auxiliary.append((source,i,specification))
                    self.bundle_auxiliary_mapping.append({"source_dataset_id":source["dataset_id"],"source_variable_id":source["selected_variable_ids"][i],"member_id":source["member_id"],"output_variable_id":specification["variable_id"]})
        if representation == "wide":
            first = self.sources[0];x, _ = positions[0]
            x_spec = dict(first["schema"][x]);x_spec["variable_id"] = "x"
            self.schema = [x_spec]
            for source, (x, y) in zip(self.sources, positions):
                require(source["row_count"] == first["row_count"], "Wide curves have different point counts")
                require(source["schema"][x].get("unit", "") == x_spec.get("unit", ""), "Wide X units differ; request explicit conversion")
                spec = dict(source["schema"][y]);spec["variable_id"] = f"y_{source['member_id']}"
                self.host.call("::GX::datasetPublicationV2ValidateId", "variable", spec["variable_id"])
                self.schema.append(spec)
            if preserve:
                self.schema.extend(dict(spec) for _,_,spec in auxiliary)
                self.schema.extend(self.field("source_row_"+source["member_id"],"int64") for source in self.sources)
            cursors = [self.bundle_rows(source) for source in self.sources]
            tolerance = float(self.option("x_tolerance", 0))
            require(math.isfinite(tolerance) and tolerance >= 0, "Invalid explicit X tolerance")
            for rows in zip(*cursors):
                xs = [row[2+x] for row, (x, _) in zip(rows, positions)]
                require(all(x is not None and math.isfinite(x) and abs(x-xs[0]) <= tolerance for x in xs), "Wide X coordinates do not match; interpolation is not performed")
                values={source["member_id"]:row for source,row in zip(self.sources,rows)}
                extra=([values[source["member_id"]][2+i] for source,i,_ in auxiliary]+[row[1] for row in rows]) if preserve else []
                yield [xs[0]] + [row[2+y] for row, (_, y) in zip(rows, positions)] + extra
            return
        lineage = [self.field("member_id"), self.field("source_dataset_id"), self.field("source_sha256"),
                   self.field("source_row_ordinal", "int64"), self.field("source_x_variable_id"),
                   self.field("source_y_variable_id"), self.field("x_unit"), self.field("y_unit")]
        axes = []
        for axis, position in (("x",0),("y",1)):
            specs = [source["schema"][xy[position]] for source,xy in zip(self.sources,positions)]
            units = {spec.get("unit", "") for spec in specs}
            spec = dict(specs[0]);spec.update(variable_id=axis, name=axis, canonical=axis, dtype="float64", coordinate_role="coordinate" if axis=="x" else "data")
            if len(units)>1:
                spec.update(unit="", canonical_unit="", to_canonical="", from_canonical="", value_kind="number", value_format="")
            if len({v.get("display_label", "") for v in specs})>1: spec["display_label"] = axis.upper()
            axes.append(spec)
        self.schema = axes + lineage
        family_axes = self.sequence(self.option("family_axes", "")) if self.op == "build_family" else []
        if self.op == "build_family":
            require(len(family_axes) in (1, 2) and len(set(family_axes)) == len(family_axes), "Family requires one or two distinct coordinate axes")
            keys = set();coordinates = {axis: set() for axis in family_axes}
            for source in self.sources:
                params = self.dictionary(source.get("family_coordinates", ""))
                require(set(params) == set(family_axes), "Missing or unknown family coordinates")
                key = tuple(float(params[axis]) for axis in family_axes)
                require(all(math.isfinite(v) for v in key), "Family coordinates must be finite")
                require(key not in keys, "Duplicate family coordinate combination")
                keys.add(key)
                for axis, value in zip(family_axes, key): coordinates[axis].add(value)
            require(len(family_axes) == 1 or len(keys) == math.prod(len(v) for v in coordinates.values()), "Incomplete rectangular two-dimensional family")
            self.family_coordinates = {axis: sorted(values) for axis, values in coordinates.items()}
            units = self.dictionary(self.option("family_units", ""))
            for axis in family_axes:
                self.host.call("::GX::datasetPublicationV2ValidateId", "variable", axis)
                require(axis not in [v["variable_id"] for v in self.schema], "Family axis conflicts with a lineage variable")
                self.schema.append(self.field(axis, "float64", units.get(axis, "1"), "coordinate"))
        if preserve:
            self.schema.extend(dict(spec) for _,_,spec in auxiliary)
            self.schema.extend(self.field("member_present_"+source["member_id"],"bool") for source in self.sources)
            self.options["family_auxiliary_policy"]="Per-member original dtypes/descriptors; member_present=0 means its zero/empty placeholders are absent. Native auxiliary_valid additionally marks unbound source values."
        for source, (x, y) in zip(self.sources, positions):
            units = [source["schema"][x].get("unit", ""), source["schema"][y].get("unit", "")]
            params = self.dictionary(source.get("family_coordinates", ""))
            for row in self.bundle_rows(source):
                extra=([row[2+i] if owner is source else "" if spec["dtype"]=="string" else 0 for owner,i,spec in auxiliary]+[int(owner is source) for owner in self.sources]) if preserve else []
                yield [row[2+x], row[2+y], source["member_id"], source["dataset_id"], source["sha256"], row[1], source["x_variable_id"], source["y_variable_id"], *units] + [float(params[axis]) for axis in family_axes] + extra

    def bundle_rows(self, source):
        """A gap belongs to an edge; reversing a member moves it to that edge's new end."""
        gap = next((i for i, v in enumerate(source["schema"])
                    if v["variable_id"] == self.option("lineage_prefix", "selection_")+"break_before"), None)
        reverse = str(source.get("reverse", "0")).lower() in ("1", "true", "yes")
        first = True
        for record in self.source_rows(source):
            if gap is not None:
                record = list(record)
                if first:
                    record[2+gap] = 0
                elif reverse:
                    following = self.db.execute(f"SELECT c{gap} FROM {source['table']} WHERE seq=?", (record[0]+1,)).fetchone()
                    record[2+gap] = int(bool(following and following[0]))
            first = False
            yield record

    def merged(self):
        require(len(self.sources) >= 2, "Merge requires at least two sources")
        self.schema = [dict(v) for source in self.sources for v in source["schema"]]
        names = [v["variable_id"] for v in self.schema]
        require(len(set(names)) == len(names), "Merge Variable IDs collide; supply explicit variable_map per source")
        mode = self.option("mode", "row_index")
        if mode == "row_index":
            require(len({s["row_count"] for s in self.sources}) == 1, "Row-index merge requires identical row counts")
            for rows in zip(*(self.source_rows(s) for s in self.sources)):
                yield list(itertools.chain.from_iterable(row[2:] for row in rows))
            return
        require(mode == "exact_key" or self.op == "join_by_key", "Unsupported merge mode")
        require(len(self.sources) == 2, "Exact key join requires two sources")
        keys = [self.sequence(k) for k in self.sequence(self.option("keys", ""))]
        require(keys and all(len(k) == 2 for k in keys), "Join keys must be explicit left/right Variable ID pairs")
        a, b = self.sources
        indices = [(a["selected_variable_ids"].index(left), b["selected_variable_ids"].index(right)) for left, right in keys]
        for left, right in indices:
            av, bv = a["schema"][left], b["schema"][right]
            require(av["dtype"] == bv["dtype"] and av.get("unit", "") == bv.get("unit", ""), "Exact keys have incompatible dtype/units")
        policy = self.option("duplicate_policy", "error")
        require(policy in ("error", "all"), "Duplicate policy must be error or explicit all")
        require(self.op != "merge_columns" or policy == "error", "Exact-key merge requires unique keys")
        for source, side in ((a, 0), (b, 1)):
            fields = [f"c{pair[side]}" for pair in indices]
            if policy == "error":
                duplicate = self.db.execute(f"SELECT 1 FROM {source['table']} GROUP BY {','.join(fields)} HAVING COUNT(*)>1 LIMIT 1").fetchone()
                require(duplicate is None, f"Duplicate join key in Dataset '{source['dataset_id']}'")
            require(self.db.execute(f"SELECT 1 FROM {source['table']} WHERE {' OR '.join(f'{f} IS NULL' for f in fields)} LIMIT 1").fetchone() is None, "Null/nonfinite join keys are not valid exact keys")
            self.db.execute(f"CREATE INDEX keys_{source['table']} ON {source['table']} ({','.join(fields)})")
        join = self.option("join", "inner")
        require(join in ("inner", "left"), "Join must be inner or left")
        condition = " AND ".join(f"a.c{left}=b.c{right}" for left, right in indices)
        if self.op == "merge_columns":
            matches = self.db.execute(f"SELECT COUNT(*) FROM {a['table']} a JOIN {b['table']} b ON {condition}").fetchone()[0]
            require(matches == a["row_count"] == b["row_count"], "Exact-key merge requires complete equal key sets")
        columns = [f"a.c{i}" for i in range(len(a["schema"]))] + [f"b.c{i}" for i in range(len(b["schema"]))]
        query = f"SELECT {','.join(columns)} FROM {a['table']} a {'LEFT JOIN' if join=='left' else 'JOIN'} {b['table']} b ON {condition} ORDER BY a.seq,b.seq"
        if join == "left":
            for spec in self.schema[len(a["schema"]):]:
                if spec["dtype"] != "string": spec["dtype"] = "float64"
        for row in self.db.execute(query):
            if join == "left":
                for value, spec in zip(row[len(a["schema"]):], b["schema"]):
                    if value is not None and str(spec["dtype"]).startswith(("int", "uint")):
                        require(abs(int(value)) <= 2**53, "Left-join NaN representation would lose integer precision")
            yield list(row)

    def transformed(self):
        if self.op == "smooth_curve":
            from dataset_transform_smoothing_v1 import rows
            yield from rows(self)
            return
        if self.op == "log_variables":
            from dataset_transform_log_v1 import rows
            yield from rows(self)
            return
        if self.op == "baseline_correct":
            from dataset_transform_baseline_v1 import rows
            yield from rows(self)
            return
        if self.op == "combine_selection":
            require(all(s.get("x_variable_id") and s.get("y_variable_id") for s in self.sources), "Selection members require explicit X/Y bindings")
            try:
                for source in self.sources[1:]: self.compatible(self.sources[0]["schema"],source["schema"])
                require(len({s["contract"] for s in self.sources})==1, "Source contracts differ")
                compatible = True
            except ValueError as conflict:
                compatible = False;self.compatibility_conflicts.append(str(conflict))
            if compatible:
                self.effective_op = "concat_rows"
                self.options["include_lineage"] = "1"
                self.options.setdefault("lineage_prefix", "selection_")
                self.op = "concat_rows"
                try: yield from self.transformed()
                finally: self.op = "combine_selection"
            else:
                self.effective_op = "curve_bundle"
                self.options["representation"] = "long"
                yield from self.bundle()
            return
        if self.op in ("curve_bundle", "build_family"):
            yield from self.bundle();return
        if self.op in ("merge_columns", "join_by_key"):
            if self.op == "join_by_key": self.options["mode"] = "exact_key"
            yield from self.merged();return
        self.schema = [dict(v) for v in self.sources[0]["schema"]]
        if len(self.sources) > 1:
            require(self.op in ("concat_rows", "reverse_rows", "reverse_range"), "Operation requires one source")
            for source in self.sources[1:]: self.compatible(self.schema, source["schema"])
            if self.op == "concat_rows" and self.output.get("contract", "auto") != "table.generic":
                require(len({str(s["contract"]) for s in self.sources}) == 1, "Concat contracts differ; explicitly request table.generic")
        reorder = self.sequence(self.option("reorder", ""))
        indices = list(range(len(self.schema)))
        if reorder:
            require(len(reorder) == len(self.schema) and set(reorder) == {v["variable_id"] for v in self.schema}, "Reorder must contain every output Variable ID exactly once")
            indices = [[v["variable_id"] for v in self.schema].index(v) for v in reorder]
            self.schema = [self.schema[i] for i in indices]
        family_indices = None
        if self.op == "split_family":
            member_variable = self.option("member_variable_id", "member_id")
            identifiers = [v["variable_id"] for v in self.schema]
            require(member_variable in identifiers, "Family member identity variable is absent")
            family_indices = identifiers.index(member_variable)
            outputs = self.dictionary(self.output.get("member_outputs", ""))
            members = set(self.sequence(self.option("members", ""))) or set(outputs)
            require(members, "Select explicit family members")
            require(members == set(outputs), "Every split member requires an explicit output Dataset ID")
        matrix = None
        if self.op == "transform_xy":
            matrix = [float(v) for v in self.sequence(self.option("matrix", ""))]
            require(len(matrix) == 6 and all(math.isfinite(v) for v in matrix), "Affine XY matrix requires six finite values {a b c d tx ty}")
            identifiers = [v["variable_id"] for v in self.schema]
            xi, yi = identifiers.index(self.option("x_variable_id")), identifiers.index(self.option("y_variable_id"))
            require(self.schema[xi]["dtype"] != "string" and self.schema[yi]["dtype"] != "string", "Affine coordinates must be numeric")
            require((matrix[1] == 0 and matrix[2] == 0) or self.schema[xi].get("unit", "") == self.schema[yi].get("unit", ""), "Mixed-axis affine transformation requires equal units or explicit conversion")
            self.schema[xi]["dtype"] = self.schema[yi]["dtype"] = "float64"
        include_lineage = str(self.option("include_lineage", "0")).lower() in ("1", "true", "yes")
        prefix = self.option("lineage_prefix", "selection_")
        if include_lineage:
            generated = [self.field(prefix+"member_id"), self.field(prefix+"source_dataset_id"), self.field(prefix+"source_sha256"), self.field(prefix+"source_row_ordinal", "int64"), self.field(prefix+"source_x_variable_id"), self.field(prefix+"source_y_variable_id")]
            require(not {v["variable_id"] for v in generated}.intersection(v["variable_id"] for v in self.schema), "Generated lineage columns collide; choose an explicit lineage_prefix")
            for spec in generated: self.host.call("::GX::datasetPublicationV2ValidateId", "variable", spec["variable_id"])
            self.schema.extend(generated)
        for source in self.sources:
            geometry_gap = None
            if any("native_geometry" in s for s in self.sources):
                gap_identifier = prefix+"break_before"
                geometry_gap = [v["variable_id"] for v in source["schema"]].index(gap_identifier)
            first_output = True
            for record in self.source_rows(source):
                row = [record[2+i] for i in indices]
                if geometry_gap is not None:
                    output_gap = indices.index(geometry_gap)
                    reversed_source = str(source.get("reverse","0")).lower() in ("1","true","yes")
                    if first_output:
                        row[output_gap] = int(source is not self.sources[0])
                    elif reversed_source:
                        following = self.db.execute(f"SELECT c{geometry_gap} FROM {source['table']} WHERE seq=?",(record[0]+1,)).fetchone()
                        row[output_gap] = int(bool(following and following[0]))
                    first_output = False
                if family_indices is not None and str(row[family_indices]) not in members: continue
                if matrix is not None:
                    x, y = row[xi], row[yi];a,b,c,d,tx,ty = matrix
                    row[xi],row[yi] = a*x+b*y+tx,c*x+d*y+ty
                if include_lineage:
                    row += [source["member_id"],source["dataset_id"],source["sha256"],record[1],source.get("x_variable_id", ""),source.get("y_variable_id", "")]
                yield row

    def output_rows(self):
        iterator=iter(self.transformed())
        first=next(iterator,None)
        if first is None: return
        polar=self.dictionary(self.option("polar_output",""))
        if not polar:
            yield first;yield from iterator;return
        require(set(polar).issubset({"representation","frame","x_variable_id","y_variable_id","theta_variable_id","radius_variable_id","angle_defined_variable_id"}),"Unknown polar output option")
        representation=polar.get("representation","both")
        require(representation in ("cartesian","polar","both"),"Polar output representation must be cartesian, polar or both")
        if representation=="cartesian":
            yield first;yield from iterator;return
        identifiers=[v["variable_id"] for v in self.schema]
        xi,yi=identifiers.index(polar["x_variable_id"]),identifiers.index(polar["y_variable_id"])
        require(xi!=yi and self.schema[xi].get("unit","")==self.schema[yi].get("unit",""),"Polar publication requires distinct X/Y with explicit matching units")
        require(self.schema[xi].get("unit",""),"Polar radius needs a declared working unit")
        frame=self.dictionary(polar.get("frame",""))
        theta_id=polar.get("theta_variable_id","theta");radius_id=polar.get("radius_variable_id","r");valid_id=polar.get("angle_defined_variable_id","theta_defined")
        require(len({theta_id,radius_id,valid_id})==3 and not {theta_id,radius_id,valid_id}.intersection(identifiers),"Polar output Variable IDs collide; choose explicit distinct names")
        kept=[i for i in range(len(identifiers)) if representation=="both" or i not in (xi,yi)]
        unit=self.schema[xi]["unit"]
        angle_unit="deg" if str(frame.get("degrees","0")).lower() in ("1","true","yes") else "rad"
        theta=self.field(theta_id,"float64",angle_unit,"coordinate");theta["display_label"]="Polar angle"
        radius=self.field(radius_id,"float64",unit,"data");radius["display_label"]="Polar radius"
        valid=self.field(valid_id,"bool");valid["display_label"]="Angle defined (false at origin)"
        self.schema=[self.schema[i] for i in kept]+[theta,radius,valid]
        pending=[first]
        while pending:
            pending.extend(itertools.islice(iterator,8192-len(pending)))
            coordinates=[(float(row[xi]),float(row[yi])) for row in pending]
            require(all(math.isfinite(x) and math.isfinite(y) for x,y in coordinates),"Polar publication requires finite complete XY rows; select valid rows explicitly")
            encoded=base64.b64encode(b"".join(struct.pack("<dd",x,y) for x,y in coordinates)).decode("ascii")
            result=self.dictionary(self.host.call("::GX::native2DGeometryPolarBulk",frame,encoded))
            values=list(struct.iter_unpack("<dd",base64.b64decode(result["theta_r_base64"],validate=True)))
            defined=base64.b64decode(result["angle_defined_base64"],validate=True)
            require(len(values)==len(pending)==len(defined),"Native polar result shape differs")
            for row,(theta_value,radius_value),flag in zip(pending,values,defined): yield [row[i] for i in kept]+[theta_value,radius_value,int(flag)]
            self.options["polar_scientific_policy"]={key:result[key] for key in ("frame","policy","origin_angle_policy","normalization")}
            pending=list(itertools.islice(iterator,1))

    def run(self):
        try:
            self.load()
            count = 0
            split_outputs = self.dictionary(self.output.get("member_outputs", "")) if self.op == "split_family" else {}
            split_indices = {member:index for index,member in enumerate(split_outputs)}
            with (self.directory / "values.hexrows").open("w", encoding="ascii") as out:
                for row in self.output_rows():
                    encoded = []
                    for value, spec in zip(row, self.schema):
                        if value is None: value = "" if spec["dtype"] == "string" else "NaN"
                        if isinstance(value, float): value = format(value, ".17g")
                        encoded.append(str(value).encode("utf-8").hex())
                    line = "\t".join(encoded) + "\n"
                    out.write(line);count += 1
                    if split_outputs:
                        member_column = [v["variable_id"] for v in self.schema].index(self.option("member_variable_id", "member_id"))
                        member = str(row[member_column])
                        if member not in self.part_handles:
                            if len(self.part_handles) >= 32:
                                _, handle = self.part_handles.popitem(last=False);handle.close()
                            self.part_handles[member] = (self.directory / f"part_{split_indices[member]:06d}.hexrows").open("a", encoding="ascii")
                        self.part_handles[member].write(line)
                        self.part_handles.move_to_end(member)
                        self.family_parts[member] = self.family_parts.get(member,0)+1
            require(count > 0, "Transform selects no output rows")
            require(not split_outputs or set(self.family_parts) == set(split_outputs), "Requested split family member is absent")
            names = [s["variable_id"] for s in self.schema]
            require(len(set(names)) == len(names), "Output Variable IDs collide")
            contract = self.output.get("contract", "auto")
            if contract == "auto":
                contract = "table.generic" if self.op in ("extract_family_member", "split_family") else "curve_family.table" if self.effective_op in ("curve_bundle", "build_family") and self.option("representation", "long") != "wide" else self.sources[0]["contract"] if len(self.sources) == 1 else "table.generic"
            allowed = {"variable_id", "name", "canonical", "display_label", "dtype", "rank", "dimension_ids", "coordinate_variable_ids", "coordinate_role", "axis_kind", "unit", "semantic_role", "value_kind", "semantic_source", "semantic_reason", "value_format", "decimal_separator", "canonical_unit", "to_canonical", "from_canonical", "time_origin", "time_reference", "instrument_id", "instrument_channel"}
            if self.op in ("project_variables", "rename_reorder"):
                for variable in self.schema:
                    if variable.get("coordinate_variable_ids"):
                        variable["coordinate_variable_ids"] = ";".join(related for related in variable["coordinate_variable_ids"].split(";") if related in names)
                self.options["coordinate_reference_policy"] = "Preserve selected coordinate references under explicit ID maps; omit references to excluded output Variables without adding columns."
            self.schema = [{k:v for k,v in variable.items() if k in allowed} for variable in self.schema]
            for variable in self.schema: variable.update(shape=str(count), maxshape="*", axis_count=str(count))
            mapping = []
            for source in self.sources:
                if self.effective_op in ("curve_bundle", "build_family"):
                    pairs = [(source["x_variable_id"], "x"), (source["y_variable_id"], f"y_{source['member_id']}" if self.option("representation", "long") == "wide" else "y")]
                else:
                    pairs = [(identifier,spec["variable_id"]) for identifier,spec in zip(source["selected_variable_ids"],source["schema"])]
                for identifier, output in pairs:
                    if output not in names: continue
                    mapping.append({"source_dataset_id": source["dataset_id"], "source_variable_id": identifier, "member_id": source["member_id"], "output_variable_id": output})
                if self.effective_op in ("curve_bundle", "build_family") or (self.op=="combine_selection" and source.get("x_variable_id")):
                    descriptor = {"member_id": source["member_id"], "source_dataset_id": source["dataset_id"], "source_sha256": source["sha256"], "row_count": source["row_count"]}
                    for axis in ("x", "y"):
                        identifier = source[f"{axis}_variable_id"]
                        index = source["selected_variable_ids"].index(identifier)
                        descriptor[f"bundle_{axis}_variable_id"] = source["schema"][index]["variable_id"] if self.effective_op=="concat_rows" else "x" if axis=="x" else f"y_{source['member_id']}" if self.option("representation", "long") == "wide" else "y"
                        descriptor[f"{axis}_variable_id"] = identifier
                        descriptor[f"{axis}_descriptor"] = {k:v for k,v in source["schema"][index].items() if k in allowed}
                    self.member_descriptors.append(descriptor)
            report = {"api_version": 1, "operation": self.op, "effective_operation": self.effective_op, "effective_options": self.options, "compatibility_conflicts": self.compatibility_conflicts, "member_variable_id": self.option("lineage_prefix", "selection_")+"member_id" if self.effective_op=="concat_rows" and self.op=="combine_selection" else "member_id", "row_count": count,
                      "variables": self.schema, "contract": contract,
                      "source_fingerprints": [{"dataset_id": s["dataset_id"], "member_id": s["member_id"], "sha256": s["sha256"], "variable_ids": s["selected_variable_ids"], "row_count": s["row_count"]} for s in self.sources],
                      "conversions": self.conversions, "calibrations": self.calibrations, "unit_assumptions": self.unit_assumptions, "family_coordinates": self.family_coordinates, "family_parts": self.family_parts, "variable_mapping": mapping + self.bundle_auxiliary_mapping, "member_descriptors": self.member_descriptors,
                      "ordering": "explicit stable tuple sort; ties retain original row order" if self.op == "sort_rows" else "explicit source/member order; original row order unless reverse operation",
                      "interpolation": "none", "max_input_chunk_rows": self.max_input_chunk, "input_chunk_limit": 65536, "input_chunks": self.input_chunks, "binary_columns_returned": self.binary_columns, "sqlite_cache_bytes": 4194304}
            if hasattr(self, 'smoothing_receipt'):
                report['smoothing_receipt'] = self.smoothing_receipt
            if hasattr(self, 'baseline_receipt'):
                report['baseline_receipt'] = self.baseline_receipt
            if hasattr(self, 'logarithm_receipt'):
                report['logarithm_receipt'] = self.logarithm_receipt
            print(self.host.tcl.call("format", "%s", self.host.tcl_arg(report)))
        finally:
            for handle in self.part_handles.values(): handle.close()
            self.db.close();self.host.cleanup()


if __name__ == "__main__":
    try:
        require(len(sys.argv) == 4, "usage: dataset_transform_worker_v1.py RUNTIME REQUEST PRIVATE_DIRECTORY")
        Transform(*sys.argv[1:]).run()
    except Exception as exc:
        print(f"Dataset Transform: {exc}", file=sys.stderr)
        sys.exit(1)
