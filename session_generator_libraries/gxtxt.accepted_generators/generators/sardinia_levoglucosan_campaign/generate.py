#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate the deterministic synthetic Sardinia levoglucosan campaign."""

from __future__ import annotations

import argparse
import csv
import hashlib
import math
import random
import shutil
from dataclasses import dataclass
from datetime import date, timedelta
from pathlib import Path

SEED = 20250923
YEAR = 2025
LOD_PPM = 0.010
LOQ_PPM = 0.030
SAMPLED_AIR_VOLUME_M3 = 24.0
EXTRACT_VOLUME_ML = 10.0
RELATIVE_ANALYTICAL_RSD = 0.040
ABSOLUTE_ANALYTICAL_SIGMA_PPM = 0.004
FIRE_DISTANCE_DECAY_KM = 65.0
FIRE_CONTRIBUTION_SCALE_PPM = 6.5
GENERATOR_VERSION = "1.1.1"
SOURCE_DATASET_ID = "demo.environmental.levoglucosan.source"
SOURCE_DATASET_FILE = "datasets/demo.environmental.levoglucosan.source.csv"


@dataclass(frozen=True)
class Site:
    site_id: int
    site_key: str
    site_name: str
    zone: str
    latitude_deg: float
    longitude_deg: float
    elevation_m: float
    environment_class: str
    summer_baseline_ppm: float
    winter_amplitude_ppm: float


@dataclass(frozen=True)
class FireEvent:
    fire_event_id: int
    event_key: str
    name: str
    start_date: date
    end_date: date
    centroid_latitude: float
    centroid_longitude: float
    severity_index: float
    synthetic_burned_area_ha: float


SITES = (
    Site(1, "CAG", "Cagliari metropolitan reference", "South", 39.2236, 9.1181, 6.0,
         "urban_coastal", 0.045, 1.55),
    Site(2, "GON", "Gonnostramatza / Marmilla reference", "Central-West", 39.682833, 8.833833, 96.0,
         "rural_inland", 0.035, 4.95),
    Site(3, "NUO", "Nuoro / Barbagia reference", "Central Inland", 40.3199, 9.3257, 549.0,
         "mountain_inland", 0.040, 3.20),
    Site(4, "OLB", "Olbia / Gallura reference", "North-East", 40.9234, 9.4980, 15.0,
         "coastal_northeast", 0.030, 1.85),
)

FIRE_EVENTS = (
    FireEvent(1, "SOUTH_2025_01", "Synthetic South Sardinia early-summer fire", date(2025, 6, 28), date(2025, 7, 1),
              39.2900, 9.0600, 0.45, 1600.0),
    FireEvent(2, "GALLURA_2025_01", "Synthetic Gallura wildfire", date(2025, 7, 6), date(2025, 7, 10),
              40.9300, 9.3500, 0.70, 3600.0),
    FireEvent(3, "CENTRAL_WEST_2025_01", "Synthetic Central-West Montiferru-scale wildfire", date(2025, 7, 23), date(2025, 7, 30),
              39.9800, 8.6400, 1.00, 12000.0),
    FireEvent(4, "BARBAGIA_2025_01", "Synthetic Barbagia wildfire", date(2025, 8, 13), date(2025, 8, 18),
              40.1700, 9.1600, 0.80, 5200.0),
)


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371.0088
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2.0) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2.0) ** 2
    return 2.0 * r * math.asin(math.sqrt(a))


def season_name(d: date) -> str:
    if d.month in (12, 1, 2):
        return "winter"
    if d.month in (3, 4, 5):
        return "spring"
    if d.month in (6, 7, 8):
        return "summer"
    return "autumn"


def heating_factor(day_of_year: int) -> float:
    # Smooth annual envelope: maximum in mid-January, minimum in mid-July.
    phase = 2.0 * math.pi * (day_of_year - 15.0) / 365.0
    raw = 0.5 * (1.0 + math.cos(phase))
    scaled = max(0.0, (raw - 0.18) / 0.82)
    return scaled ** 1.65


def event_profile(d: date, event: FireEvent) -> float:
    if d < event.start_date or d > event.end_date:
        return 0.0
    span = (event.end_date - event.start_date).days
    if span <= 0:
        return 1.0
    position = (d - event.start_date).days / span
    # Raised-sine evolution gives zero-ish shoulders and a smooth event peak.
    return 0.20 + 0.80 * math.sin(math.pi * position) ** 1.5


def fire_terms(d: date, site: Site) -> tuple[int, float, float, float]:
    exposure = 0.0
    contribution = 0.0
    active: list[tuple[float, FireEvent, float]] = []
    for event in FIRE_EVENTS:
        profile = event_profile(d, event)
        if profile <= 0.0:
            continue
        distance = haversine_km(site.latitude_deg, site.longitude_deg,
                                event.centroid_latitude, event.centroid_longitude)
        decay = math.exp(-distance / FIRE_DISTANCE_DECAY_KM)
        component = event.severity_index * profile * decay
        exposure += component
        contribution += FIRE_CONTRIBUTION_SCALE_PPM * component
        active.append((distance, event, component))
    if not active:
        return 0, 0.0, math.nan, 0.0
    nearest = min(active, key=lambda item: item[0])
    strongest = max(active, key=lambda item: item[2])
    return strongest[1].fire_event_id, exposure, nearest[0], contribution


def regional_variation(day_of_year: int, heating: float) -> float:
    slow = 0.070 * heating * math.sin(2.0 * math.pi * (day_of_year + 17.0) / 31.0)
    synoptic = 0.025 * (0.25 + heating) * math.sin(2.0 * math.pi * (day_of_year + 3.0) / 9.0)
    return slow + synoptic


def ambient_from_extract_ppm(ppm: float) -> float:
    # 1 ppm = 1 ug/mL. Mass = ppm * extract_volume_mL [ug].
    # Convert ug to ng and divide by sampled air volume [m3].
    return ppm * EXTRACT_VOLUME_ML * 1000.0 / SAMPLED_AIR_VOLUME_M3


def format_optional(value: float, digits: int = 6) -> str:
    if not math.isfinite(value):
        return ""
    return f"{value:.{digits}f}"


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def write_ini(path: Path, sections: list[tuple[str, list[tuple[str, str]]]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as f:
        for index, (name, items) in enumerate(sections):
            if index:
                f.write("\n")
            f.write(f"[{name}]\n")
            for key, value in items:
                f.write(f"{key}={value}\n")


def variable_schema() -> list[dict[str, str]]:
    # Stable source identities and semantic roles for the ready-to-run demo Session.
    # Text variables remain available for inspection; numerical analysis bindings use
    # explicit semantic roles so no post-generation schema editing is required.
    rows = [
        ("date", "", "generic", "text", "string", "data"),
        ("day_of_year", "day", "independent", "number", "float64", "coordinate"),
        ("month", "", "independent", "number", "float64", "auxiliary"),
        ("season", "", "generic", "text", "string", "auxiliary"),
        ("site_id", "", "group", "number", "float64", "auxiliary"),
        ("site_key", "", "generic", "text", "string", "auxiliary"),
        ("site_name", "", "generic", "text", "string", "auxiliary"),
        ("zone", "", "generic", "text", "string", "auxiliary"),
        ("latitude_deg", "deg", "coordinate", "number", "float64", "auxiliary"),
        ("longitude_deg", "deg", "coordinate", "number", "float64", "auxiliary"),
        ("elevation_m", "m", "coordinate", "number", "float64", "auxiliary"),
        ("environment_class", "", "generic", "text", "string", "auxiliary"),
        ("sample_id", "", "generic", "text", "string", "auxiliary"),
        ("replicate_id", "", "group", "number", "float64", "auxiliary"),
        ("fire_event_id", "", "group", "number", "float64", "auxiliary"),
        ("fire_exposure_index", "", "independent", "number", "float64", "auxiliary"),
        ("nearest_fire_distance_km", "km", "independent", "number", "float64", "auxiliary"),
        ("sampled_air_volume_m3", "", "generic", "number", "float64", "auxiliary"),
        ("extract_volume_mL", "", "generic", "number", "float64", "auxiliary"),
        ("levoglucosan_ppm", "ppm", "concentration", "number", "float64", "data"),
        ("levoglucosan_ng_m3", "", "concentration", "number", "float64", "data"),
        ("below_lod", "", "generic", "number", "float64", "auxiliary"),
        ("below_loq", "", "generic", "number", "float64", "auxiliary"),
        ("qc_flag", "", "generic", "text", "string", "auxiliary"),
    ]
    return [dict(canonical=n, unit=u, semantic_role=r, value_kind=k, dtype=d, coordinate_role=c)
            for n, u, r, k, d, c in rows]


def write_ready_to_run_session(target: Path, main_fields: list[str], metadata: list[tuple[str, str]]) -> None:
    raw_rel = "raw/sardinia_levoglucosan_ic.csv"
    raw_path = target / raw_rel
    canonical_path = target / SOURCE_DATASET_FILE
    canonical_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(raw_path, canonical_path)
    raw_hash = sha256_file(raw_path)
    canonical_hash = sha256_file(canonical_path)
    if raw_hash != canonical_hash:
        raise RuntimeError("canonical Dataset copy differs from generated RAW CSV")

    schema = variable_schema()
    if [v["canonical"] for v in schema] != main_fields:
        raise RuntimeError("Variable Schema order does not match the generated primary CSV")

    registry_sections: list[tuple[str, list[tuple[str, str]]]] = [
        ("registry", [
            ("api_version", "1"),
            ("access_api_version", "2"),
            ("inspection_api_version", "1"),
            ("session_mode", "analysis_only"),
            ("count", "1"),
        ])
    ]
    dataset_items = [
        ("id", SOURCE_DATASET_ID),
        ("kind", "table.generic"),
        ("contract", "table.generic"),
        ("format", "csv"),
        ("storage_kind", "text"),
        ("media_type", "text/csv"),
        ("path", SOURCE_DATASET_FILE),
        ("columns", ";".join(main_fields)),
        ("variables", ";".join(main_fields)),
        ("units", ";".join(v["unit"] for v in schema)),
        ("semantic_roles", ";".join(v["semantic_role"] for v in schema)),
        ("source_module", "session_generator.sardinia_levoglucosan_campaign"),
        ("source_raw", raw_rel),
        ("source_sha256", raw_hash),
        ("canonical_sha256", canonical_hash),
        ("sha256", canonical_hash),
        ("row_count", "4380"),
        ("sample_count", "4380"),
        ("var_count", str(len(schema))),
        ("variable_schema_api_version", "3"),
        ("canonical_access_api_version", "2"),
        ("canonical_delimiter", "comma"),
        ("source_delimiter", "comma"),
        ("source_header_rows", "1"),
        ("structured_metadata_file", f"metadata/datasets/{SOURCE_DATASET_ID}.ini"),
        ("structured_metadata_api_version", "1"),
        ("immutable", "0"),
        ("notes", "Ready-to-run canonical Dataset generated with the synthetic campaign Session."),
    ]
    for i, v in enumerate(schema, start=1):
        prefix = f"var{i}_"
        dataset_items.extend([
            (prefix + "variable_id", v["canonical"]),
            (prefix + "enabled", "1"),
            (prefix + "source_column", str(i)),
            (prefix + "canonical_position", str(i)),
            (prefix + "original_header", v["canonical"]),
            (prefix + "canonical", v["canonical"]),
            (prefix + "unit", v["unit"]),
            (prefix + "semantic_role", v["semantic_role"]),
            (prefix + "semantic_source", "generator"),
            (prefix + "semantic_reason", "Declared by the deterministic Sardinia levoglucosan Session Generator"),
            (prefix + "value_kind", v["value_kind"]),
            (prefix + "dtype", v["dtype"]),
            (prefix + "rank", "1"),
            (prefix + "shape", "4380"),
            (prefix + "dimension_ids", "row"),
            (prefix + "coordinate_variable_ids", "" if v["canonical"] == "day_of_year" else "day_of_year"),
            (prefix + "coordinate_role", v["coordinate_role"]),
            (prefix + "axis_kind", "explicit" if v["canonical"] == "day_of_year" else "none"),
            (prefix + "axis_origin", ""),
            (prefix + "axis_step", ""),
            (prefix + "axis_count", ""),
            (prefix + "component_ids", ""),
            (prefix + "group_id", "campaign"),
        ])
    registry_sections.append((f"dataset.{SOURCE_DATASET_ID}", dataset_items))
    write_ini(target / "metadata" / "datasets.ini", registry_sections)

    metadata_sections = [("dataset_metadata", [
        ("api_version", "1"),
        ("dataset_id", SOURCE_DATASET_ID),
        ("updated_at", "2025-01-01T00:00:00+0000"),
        ("count", str(len(metadata))),
    ]), ("metadata", metadata)]
    write_ini(target / "metadata" / "datasets" / f"{SOURCE_DATASET_ID}.ini", metadata_sections)

    binding_map = [
        ("day_of_year", "day_of_year"),
        ("month", "month"),
        ("site_id", "site_id"),
        ("replicate_id", "replicate_id"),
        ("levoglucosan", "levoglucosan_ppm"),
        ("fire_event_id", "fire_event_id"),
        ("fire_exposure", "fire_exposure_index"),
        ("fire_distance", "nearest_fire_distance_km"),
        ("latitude", "latitude_deg"),
        ("longitude", "longitude_deg"),
        ("elevation", "elevation_m"),
        ("below_lod", "below_lod"),
        ("below_loq", "below_loq"),
    ]
    manifest_sections: list[tuple[str, list[tuple[str, str]]]] = [
        ("pipeline", [("format", "2"), ("module_api_version", "1")]),
        ("session", [("mode", "analysis_only")]),
        ("experiment", [
            ("name", "Synthetic Sardinia levoglucosan campaign 2025"),
            ("project", "GX-TXT Environmental Chemistry Demonstrations"),
            ("date", "2025"),
            ("notes", "All campaign measurements are deterministic synthetic data."),
        ]),
        ("source_variables", [("count", str(len(schema)))]),
    ]
    for i, v in enumerate(schema, start=1):
        manifest_sections.append((f"source_variable.{i}", [
            ("enabled", "1"), ("source_column", str(i)), ("source_channel", ""),
            ("original_header", v["canonical"]), ("canonical", v["canonical"]),
            ("unit", v["unit"]), ("semantic_role", v["semantic_role"]),
            ("instrument_id", ""), ("instrument_channel", ""),
        ]))
    manifest_sections.extend([
        ("module_state", [
            ("enabled", "demo.environmental.levoglucosan_campaign"),
            ("run", "demo.environmental.levoglucosan_campaign"),
        ]),
        ("analysis_source_map_api", [("version", "1")]),
        ("module_analysis_sources.demo.environmental.levoglucosan_campaign", [("ids", "primary")]),
        ("module_analysis_source.demo.environmental.levoglucosan_campaign.primary", [("dataset_id", SOURCE_DATASET_ID)]),
        ("module_binding.demo.environmental.levoglucosan_campaign", [(role, f"primary.{var}") for role, var in binding_map]),
        ("dataset_variable_schema_api", [("version", "3")]),
        ("module_binding_variable_id.demo.environmental.levoglucosan_campaign", [
            (role, f"primary|{SOURCE_DATASET_ID}|{var}") for role, var in binding_map
        ]),
    ])
    write_ini(target / "metadata" / "manifest.ini", manifest_sections)



def generate(target: Path) -> None:
    rng_environment = random.Random(SEED)
    rng_analytical = random.Random(SEED + 1)
    (target / "raw").mkdir(parents=True, exist_ok=True)
    (target / "metadata").mkdir(parents=True, exist_ok=True)
    (target / "reference").mkdir(parents=True, exist_ok=True)
    (target / "datasets").mkdir(parents=True, exist_ok=True)

    with (target / "raw" / "sites.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["site_id", "site_key", "site_name", "zone", "latitude_deg", "longitude_deg", "elevation_m", "environment_class"])
        for s in SITES:
            w.writerow([s.site_id, s.site_key, s.site_name, s.zone, f"{s.latitude_deg:.4f}", f"{s.longitude_deg:.4f}", f"{s.elevation_m:.1f}", s.environment_class])

    with (target / "raw" / "fire_events.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["fire_event_id", "event_key", "event_name", "start_date", "end_date", "centroid_latitude", "centroid_longitude", "severity_index", "synthetic_burned_area_ha"])
        for e in FIRE_EVENTS:
            w.writerow([e.fire_event_id, e.event_key, e.name, e.start_date.isoformat(), e.end_date.isoformat(),
                        f"{e.centroid_latitude:.4f}", f"{e.centroid_longitude:.4f}", f"{e.severity_index:.3f}", f"{e.synthetic_burned_area_ha:.1f}"])

    main_fields = [
        "date", "day_of_year", "month", "season",
        "site_id", "site_key", "site_name", "zone", "latitude_deg", "longitude_deg", "elevation_m", "environment_class",
        "sample_id", "replicate_id",
        "fire_event_id", "fire_exposure_index", "nearest_fire_distance_km",
        "sampled_air_volume_m3", "extract_volume_mL",
        "levoglucosan_ppm", "levoglucosan_ng_m3",
        "below_lod", "below_loq", "qc_flag",
    ]
    truth_fields = [
        "date", "day_of_year", "month", "site_id", "site_key",
        "latent_levoglucosan_ppm", "summer_baseline_ppm", "winter_component_ppm",
        "regional_component_ppm", "environmental_component_ppm", "wildfire_component_ppm",
        "fire_event_id", "fire_exposure_index", "nearest_fire_distance_km",
    ]

    start = date(YEAR, 1, 1)
    with (target / "raw" / "sardinia_levoglucosan_ic.csv").open("w", newline="", encoding="utf-8") as main_f, \
         (target / "reference" / "synthetic_truth.csv").open("w", newline="", encoding="utf-8") as truth_f:
        main = csv.DictWriter(main_f, fieldnames=main_fields, lineterminator="\n")
        truth = csv.DictWriter(truth_f, fieldnames=truth_fields, lineterminator="\n")
        main.writeheader()
        truth.writeheader()
        for offset in range(365):
            d = start + timedelta(days=offset)
            doy = offset + 1
            heat = heating_factor(doy)
            regional = regional_variation(doy, heat)
            for site in SITES:
                fire_event_id, fire_exposure, nearest_distance, fire_component = fire_terms(d, site)
                winter_component = site.winter_amplitude_ppm * heat
                pre_env = site.summer_baseline_ppm + winter_component + regional + fire_component
                env_sigma = 0.010 + 0.045 * max(0.05, site.summer_baseline_ppm + winter_component)
                environmental = rng_environment.gauss(0.0, env_sigma)
                latent = max(0.002, pre_env + environmental)
                sample_id = f"SYN-{YEAR}-{doy:03d}-S{site.site_id}"
                truth.writerow({
                    "date": d.isoformat(), "day_of_year": doy, "month": d.month,
                    "site_id": site.site_id, "site_key": site.site_key,
                    "latent_levoglucosan_ppm": f"{latent:.8f}",
                    "summer_baseline_ppm": f"{site.summer_baseline_ppm:.8f}",
                    "winter_component_ppm": f"{winter_component:.8f}",
                    "regional_component_ppm": f"{regional:.8f}",
                    "environmental_component_ppm": f"{environmental:.8f}",
                    "wildfire_component_ppm": f"{fire_component:.8f}",
                    "fire_event_id": fire_event_id,
                    "fire_exposure_index": f"{fire_exposure:.8f}",
                    "nearest_fire_distance_km": format_optional(nearest_distance, 4),
                })
                analytical_sigma = math.sqrt((RELATIVE_ANALYTICAL_RSD * latent) ** 2 + ABSOLUTE_ANALYTICAL_SIGMA_PPM ** 2)
                for replicate in range(1, 4):
                    measured = max(0.0001, latent + rng_analytical.gauss(0.0, analytical_sigma))
                    below_lod = int(measured < LOD_PPM)
                    below_loq = int(measured < LOQ_PPM)
                    qc_flag = "below_lod" if below_lod else ("below_loq" if below_loq else "quantified")
                    main.writerow({
                        "date": d.isoformat(), "day_of_year": doy, "month": d.month, "season": season_name(d),
                        "site_id": site.site_id, "site_key": site.site_key, "site_name": site.site_name, "zone": site.zone,
                        "latitude_deg": f"{site.latitude_deg:.4f}", "longitude_deg": f"{site.longitude_deg:.4f}",
                        "elevation_m": f"{site.elevation_m:.1f}", "environment_class": site.environment_class,
                        "sample_id": sample_id, "replicate_id": replicate,
                        "fire_event_id": fire_event_id, "fire_exposure_index": f"{fire_exposure:.8f}",
                        "nearest_fire_distance_km": format_optional(nearest_distance, 4),
                        "sampled_air_volume_m3": f"{SAMPLED_AIR_VOLUME_M3:.1f}", "extract_volume_mL": f"{EXTRACT_VOLUME_ML:.1f}",
                        "levoglucosan_ppm": f"{measured:.8f}", "levoglucosan_ng_m3": f"{ambient_from_extract_ppm(measured):.6f}",
                        "below_lod": below_lod, "below_loq": below_loq, "qc_flag": qc_flag,
                    })

    metadata = [
        ("data.synthetic", "true"),
        ("campaign.synthetic", "true"),
        ("campaign.region", "Sardinia, Italy"),
        ("campaign.year", str(YEAR)),
        ("campaign.sampling_frequency", "daily"),
        ("campaign.duration_days", "365"),
        ("campaign.site_count", "4"),
        ("campaign.technical_replicates", "3"),
        ("campaign.measurement_rows", "4380"),
        ("analyte.name", "levoglucosan"),
        ("analyte.role", "biomass-burning marker"),
        ("sample.matrix", "PM aerosol filter aqueous extract"),
        ("sample.sampled_air_volume_m3", f"{SAMPLED_AIR_VOLUME_M3:g}"),
        ("sample.extract_volume_mL", f"{EXTRACT_VOLUME_ML:g}"),
        ("analysis.method", "HPAEC-PAD / IC-PAD synthetic analytical model"),
        ("analysis.reported_unit", "ppm in aqueous filter extract"),
        ("analysis.ppm_definition", "1 ppm = 1 mg/L = 1 ug/mL levoglucosan in the aqueous extract"),
        ("analysis.ambient_conversion", "levoglucosan_ng_m3 = levoglucosan_ppm * extract_volume_mL * 1000 / sampled_air_volume_m3"),
        ("analysis.replicates", "3"),
        ("analysis.relative_analytical_rsd", f"{RELATIVE_ANALYTICAL_RSD:g}"),
        ("analysis.absolute_noise_floor_sigma_ppm", f"{ABSOLUTE_ANALYTICAL_SIGMA_PPM:g}"),
        ("analysis.lod_ppm", f"{LOD_PPM:g}"),
        ("analysis.loq_ppm", f"{LOQ_PPM:g}"),
        ("analysis.below_lod_policy", "Retain the measured value; set below_lod=1; never replace with zero"),
        ("analysis.below_loq_policy", "Retain the measured value; set below_loq=1; qc_flag identifies below_lod, below_loq, or quantified"),
        ("model.seasonality", "Winter residential biomass-burning envelope; spring decrease; low summer background; autumn return"),
        ("model.wildfire", "Synthetic event severity multiplied by temporal profile and exponential distance decay"),
        ("model.fire_distance_decay_km", f"{FIRE_DISTANCE_DECAY_KM:g}"),
        ("model.fire_contribution_scale_ppm", f"{FIRE_CONTRIBUTION_SCALE_PPM:g}"),
        ("generator.seed", str(SEED)),
        ("generator.version", GENERATOR_VERSION),
        ("generator.library_id", "org.giuxlab.gxtxt.numerical_examples"),
        ("generator.generator_id", "sardinia_levoglucosan_campaign"),
        ("literature.informed", "true"),
        ("literature.caseiro_2007_doi", "10.1016/j.chroma.2007.09.038"),
        ("literature.piazzalunga_2010_doi", "10.1080/03067310903023619"),
        ("literature.sardinia_pm25_pubmed", "30557803"),
        ("literature.fire_context", "ISPRA Montiferru 24-30 July 2021 monitoring used only as broad scale/geography inspiration"),
        ("geography.reference", "Regione Autonoma della Sardegna Geoportale; WGS84 geographic EPSG:4326 reference convention"),
        ("geography.monitoring_status", "Reference locations for a synthetic campaign; not claims of real monitoring stations"),
    ]
    with (target / "metadata" / "campaign.metadata.txt").open("w", encoding="utf-8", newline="\n") as f:
        f.write("# GX-TXT Dataset Metadata import file\n")
        f.write("# Synthetic Sardinia levoglucosan campaign; values below LOD/LOQ are retained and flagged.\n")
        for key, value in metadata:
            f.write(f"{key}={value}\n")

    write_ready_to_run_session(target, main_fields, metadata)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--target-session", required=True)
    p.add_argument("--library-id")
    p.add_argument("--generator-id")
    args = p.parse_args()
    target = Path(args.target_session)
    generate(target)
    print("Generated deterministic synthetic Sardinia levoglucosan campaign: 365 days x 4 sites x 3 IC replicates = 4380 rows.")


if __name__ == "__main__":
    main()
