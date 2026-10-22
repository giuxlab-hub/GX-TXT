/* SPDX-License-Identifier: GPL-3.0-or-later
 * TASK210 UNWIRED DEVELOPMENT CANDIDATE -- NOT AN ADOPTED PUBLIC ABI.
 * Revision v2, ABI-major candidate1 / minor0, LP64 x86_64 Linux little-endian.
 * Value declarations copied from the exact v2 review artifact; no provider export.
 *
 * All value records below (including nested records/typed arrays) are FROZEN:
 * sizeof/alignment/offset/type changes require a new versioned record/ABI major.
 * struct_bytes validates exact ABI1 size; it DOES NOT allow appended value fields.
 * Only CoreApi/ProviderApi tails may grow under negotiated minor/table bytes.
 * Required table-prefix coverage AND nonnull callbacks precede every call.
 * Unknown table tails/capabilities are never read/called as known fields.
 *
 * Input records require exact struct_bytes and all reserved fields zero. Output
 * record callers initialize exact struct_bytes and zero remaining fields;
 * callees validate size BEFORE writing, never write beyond that frozen size,
 * and return invalid without writing an incorrectly sized output/Diagnostic.
 * Handle/token outputs are initialized to0/null and remain so on failure except
 * open may return an owned partial ProviderHandle requiring exactly one close.
 * Output views/counts are valid only on ok/done, never after an error status.
 *
 * ABI calls stay on one worker owner thread, synchronous and nonreentrant.
 * seal may sort/sample synchronously. There is NO step/work-unit/time guarantee.
 * Cancellation between calls uses cancel; in-call cancellation/timeout uses the
 * existing managed worker/process-group owner. No concurrent close/cancel/view.
 * Exceptions must be contained inside each noexcept callback. A violating crash
 * is a managed-worker failure, never a partial successful result.
 *
 * No allocators, Tcl objects, paths, STL storage, virtual classes or C++ exception
 * ownership cross this boundary. Native packages remain trusted extensions.
 */
#ifndef GXTXT_PREVIEW_PROVIDER_V1_H
#define GXTXT_PREVIEW_PROVIDER_V1_H
#include <cstddef>
#include <cstdint>
#include <limits>
#include <type_traits>
#if !defined(__linux__) || !defined(__x86_64__) || !defined(__BYTE_ORDER__) || __BYTE_ORDER__ != __ORDER_LITTLE_ENDIAN__
#error "Preview ABI1 candidate requires the declared x86_64 Linux little-endian profile"
#endif

namespace gx::preview::v1 {
inline constexpr std::uint32_t kAbiMajor = 1, kAbiMinor = 0;
inline constexpr char kPlatform[] = "x86_64-linux-gnu;64;little";
/* SHA256 of the frozen canonical layout manifest; filled by review layout check. */
inline constexpr char kValueLayoutId[] = "67718a8f35ffc318ec65322f1fa553df16c4ac09ad8bbad8b87c8668520a9e94";
inline constexpr std::uint64_t kCapGroupedCurves = UINT64_C(1) << 0;
inline constexpr std::uint64_t kCapBoundedArrayPlane = UINT64_C(1) << 1;
inline constexpr std::uint64_t kCapRasterOverlay = UINT64_C(1) << 2;
inline constexpr std::uint64_t kKnownCapabilities = kCapGroupedCurves | kCapBoundedArrayPlane | kCapRasterOverlay;
inline constexpr std::uint64_t kCurveChunkRowsMax = 4096, kSelectedRowsMax = 2000000;
inline constexpr std::uint64_t kRetainedRowCapacityMax = 4000000, kSeriesMax = 512;
inline constexpr std::uint64_t kPerSeriesPointsMax = 4096, kTotalPointsMax = 100000;
inline constexpr std::uint64_t kUniqueRasterPointsMax = 65536, kPlaneEdgeMax = 128;
inline constexpr std::uint64_t kPlaneCellsMax = 16384, kPlaneRgbBytesMax = 806400;
inline constexpr std::uint32_t kCoreHandlesPerInvocationMax = 1, kResultsPerInvocationMax = 1;
inline constexpr std::uint32_t kInvocationsPerWorkerMax = 4;

using CoreHandle = std::uint64_t;   // CORE-issued, invocation-scoped;0 invalid
using ResultToken = std::uint64_t;  // CORE-issued, invocation-scoped;0 invalid
struct ProviderOpaque;
using ProviderHandle = ProviderOpaque*; // provider allocation; host NEVER dereferences

enum class Status : std::uint32_t { ok=0, done=1, cancelled=2, unsupported=3, invalid=4, stale=5, limit=6, out_of_memory=7, internal=8, incompatible=9 };
enum class DType : std::uint32_t { boolean=1, i8=2, i16=3, i32=4, i64=5, u8=6, u16=7, u32=8, u64=9, f16=10, f32=11, f64=12, utf8=13 };
enum class ColumnTransport : std::uint32_t { fixed_numeric=1, utf8=2, owner_lexemes=3 };
enum class Endian : std::uint32_t { little=1, big=2 };
enum class FloatFormat : std::uint32_t { ieee754_binary64=1 };
enum class CellState : std::uint32_t { present=1, missing=2 };
enum class PlanMode : std::uint32_t { grouped_curves=1, bounded_array_plane=2 };
enum class PredicateKind : std::uint32_t { exact_equal=1, not_equal=2, less_than=3, less_equal=4, greater_than=5, greater_equal=6, between_inclusive=7, in_set=8, is_finite=9, is_nonfinite=10 };
enum class ContinuityPolicy : std::uint32_t { none=0, source_row_adjacency=1 };
enum class CoordinatePolicy : std::uint32_t { not_applicable=0, canonical_identity=1, canonical_single_scale=2, owner_pointwise=3 };
enum class StorageOrder : std::uint32_t { last_dimension_fastest=1, first_dimension_fastest=2 };
enum class PlanePolicy : std::uint32_t { existing_nearest_cell_rgb_v1=1 };
enum class Stage : std::uint32_t { created=1, ingest=2, seal=3, complete=4, cancelled=5, failed=6 };

/* UTF-8 bytes, no terminator/normalization. Embedded NUL is allowed for source
 * values/labels; IDs obey their existing owner. Null data iff bytes==0 is valid.
 * Nonzero length requires a valid range; ABI does not sandbox native pointers. */
struct Text { const char* data; std::uint64_t bytes; };
struct Bytes { const std::uint8_t* data; std::uint64_t bytes; };
/* LSB-first; either bits=null/bit_count=0 (all present), or bit_count==rows.
 * Padding bits are zero. Present empty UTF-8 differs from missing mask bit0. */
struct Mask { const std::uint8_t* bits; std::uint64_t bit_count; };
struct Scalar {
    std::uint32_t struct_bytes; DType dtype; CellState state; std::uint32_t reserved;
    std::int64_t signed_value; std::uint64_t unsigned_value; double float_value; Text text_value;
};
/* Only the dtype's value field is active; all inactive fields zero. Signed and
 * unsigned integer identities/ranges NEVER pass through double. Float16/32
 * scalar values widen exactly into float_value; raw columns retain original bits.
 * Numeric identity admission/equality remains Graph Series/Graph Selection,
 * including numeric signed-zero coalescing. No provider replacement validator. */
struct Column {
    std::uint32_t struct_bytes; DType dtype; Endian endian; ColumnTransport transport;
    Text variable_id; std::uint64_t row_count; Bytes bytes;
    const std::uint64_t* offsets; std::uint64_t offset_count; Mask present;
};
/* fixed_numeric: bytes==rows*dtype-width, offsets=null/count0. Widths: bool/i8/u8
 * 1; i16/u16/f16 2; i32/u32/f32 4; i64/u64/f64 8. Signed raw integers are two's
 * complement; floats are IEEE binary16/32/64. Bool is one byte,0 false/nonzero
 * true as the canonical typed owner. Scalar bool uses unsigned_value0/1.
 * utf8 requires DType::utf8; owner_lexemes retains the DECLARED numeric dtype
 * plus exact canonical owner's source cell text (including empty/invalid tokens
 * and historical bignums). Both use native uint64 aligned offsets count=rows+1,
 * start0, monotonic, final==bytes.bytes. Owner_lexemes is not a scientific dtype
 * or permission to coerce text; existing CORE authorities alone interpret it.
 * Overlay identity/order/coordinate roles REQUIRE owner_lexemes when their
 * current owner's collision policy is lexical; binary-only input cannot silently
 * replace that receipt. Endian applies only to fixed_numeric bytes (otherwise
 * little). Checked products/bounds precede every access.
 * Column/Scalar array stride is their frozen sizeof, never struct_bytes. */
struct Chunk {
    std::uint32_t struct_bytes; std::uint32_t column_count;
    std::uint64_t source_row_start, row_count; const Column* columns;
};
/* Unique projected IDs; every column has Chunk.row_count. Curves: contiguous
 * canonical source ordinals, starting0, no uint64 wrap, <=4096 rows per push.
 * Plane: exactly one column/one push, linear start0, rows==product(counts)<=16384.
 * Chunk/text/data/offsets/masks are call-borrowed only, released before returning
 * to any event loop; retained copies count against invocation budgets. */
struct Predicate {
    std::uint32_t struct_bytes; PredicateKind kind; Text variable_id;
    const Scalar* operands; std::uint64_t operand_count;
};
/* Existing owner-normalized predicates: finite/nonfinite0 operands, ordinary
 * comparisons1, between2, in_set>=1. Numeric order/range only; exact strings
 * remain byte-exact. Missing/nonfinite ordinary comparisons reject. CORE uses
 * actual existing authorities (possibly per-distinct callbacks), never a cloned
 * provider evaluator. All predicates/IDs are immutable invocation-bound inputs. */
struct Affine {
    std::uint32_t struct_bytes; CoordinatePolicy policy;
    double scale, offset; Text input_unit, output_unit;
};
/* Owner-issued canonical presentation only. identity=(1,0), single_scale=(s,0)
 * only where the existing owner proves the same operation sequence. For
 * owner_pointwise coefficients are zero/unused and CORE invokes its existing
 * captured coordinate owner. Providers never evaluate units/formulas or apply
 * numerical calibration/view factors; the invocation retains full owner context. */
struct Limits {
    std::uint32_t struct_bytes, max_series;
    std::uint64_t max_chunk_rows, max_input_rows, max_selected_rows;
    std::uint64_t max_retained_row_capacity, max_native_bytes;
    std::uint64_t per_series_display_points, total_display_points;
    std::uint64_t max_unique_raster_points, max_text_bytes, max_rgb_bytes;
    std::uint32_t max_core_handles, max_result_tokens;
};
/* Applicable Limits are host-issued budgets, never provider defaults;
 * inapplicable mode-specific fields are zero.
 * Fixed known maxima above constrain applicable fields. max_native_bytes=0 means
 * no additional aggregate allocation budget requested; finite >0 is unsupported
 * BEFORE create until common engines implement actual aggregate reservations.
 * Input/text/RGB budgets and hard row/series/chunk/display/token limits remain
 * enforced. No silent row/group/science truncation. Native-byte progress reports
 * accounted payload/capacity only, or0 when unknown; it is never total RSS. */
struct Range { std::uint64_t start, count; std::uint32_t count_is_bounded, reserved; };
/* count_is_bounded=0 requires count0 and means all remaining;1 permits explicit
 * count (zero is owner-rejected for a nonempty curve request). No signed sentinel
 * cast. Range applies after filtering/grouping/stable order, to EACH group. */
struct RasterRoles {
    std::uint32_t struct_bytes, reserved;
    Text curve_variable_id, curve_label_variable_id, point_order_variable_id;
    Text raster_x_variable_id, raster_y_variable_id;
};
/* Empty roles disable overlay. Nonempty roles require actual owner admission;
 * point_order preserves declared signed/unsigned integer domain, not double. */
struct PlanePlan {
    std::uint32_t struct_bytes, rank; Text dataset_id, variable_id;
    const std::uint64_t* starts; const std::uint64_t* counts;
    StorageOrder storage_order; std::uint32_t reserved;
    std::uint64_t source_width, source_height, max_output_width, max_output_height;
    std::uint64_t max_native_bytes; PlanePolicy policy; std::uint32_t reserved2;
};
/* rank>=2; exact canonical hyperslab starts/counts[rank], leading counts1, last
 * two counts1..128, width=counts[last], height=counts[last-1]. Existing native
 * plane accepts last_dimension_fastest ONLY; first_dimension_fastest is explicit
 * unsupported until canonical-owner conversion exists, never silent transpose.
 * Exact current palette/gray/nearest-cell replication and original dtype range
 * labels/counts remain with common plane owner. Compute current scale first;
 * reject an insufficient output/byte budget rather than change the policy.
 * Source arrays/unit/coordinates are unchanged; no encoder/file/output path. */
struct Plan {
    std::uint32_t struct_bytes; PlanMode mode; std::uint32_t group_count, reserved;
    Text dataset_id, x_variable_id, y_variable_id; const Text* group_variable_ids;
    Text order_variable_id; const Predicate* predicates; std::uint64_t predicate_count;
    Range range; ContinuityPolicy continuity_policy; std::uint32_t reserved2;
    Text continuity_variable_id; RasterRoles raster; Affine x_display, y_display;
    Limits limits; const PlanePlan* plane;
};
/* All Plan records/arrays/text/PlanePlan are borrowed only for open; providers
 * copy their own retained metadata under budget. The host has already captured
 * the actual normalized plan/source/Session/coordinate/continuity receipts in
 * invocation; CORE create accepts NO replacement plan from the provider.
 * Curves: plane=null, <=16 distinct grouping IDs, <=64 normalized predicates;
 * continuity none requires empty role; adjacency requires owner-admitted exact
 * row identity. Operation order: predicates -> grouping -> stable numeric order
 * (ties original ordinal) -> per-group range -> declared continuity -> existing
 * Native2D reducer. Arbitrary ordinal gaps do not imply scientific breaks.
 * Plane: plane!=null, matching dataset_id, unused curve IDs/arrays/raster/affine
 * payloads zero (embedded struct_bytes still exact, policy not_applicable),
 * range all/start0/count0 and continuity none/empty. raster_overlay capability
 * requires grouped_curves mode AND grouped_curves capability; no standalone
 * overlay PlanMode is defined. Mode and
 * capabilities must agree; ignored/unsupported semantics are NEVER approximated.
 * No provider Dataset reader, sampler, scientific renderer or descriptor mint. */
struct Progress {
    std::uint32_t struct_bytes; Stage stage;
    std::uint64_t input_rows, accepted_rows, series, native_bytes, retained_row_capacity, text_bytes;
};
/* Progress.native_bytes=0 when aggregate accounting is unavailable; never RSS. */
struct Point { double x, y; };
struct TraceView {
    std::uint32_t struct_bytes, group_count; const Scalar* group_identity;
    std::uint64_t row_count, finite_rows, display_rows;
    const Point* canonical_points; const Point* display_points;
    const std::uint64_t* source_rows; const std::uint64_t* breaks;
    std::uint64_t break_count; double canonical_bounds[4], display_bounds[4];
};
/* Points/source_rows lengths==display_rows; breaks length==break_count, each
 * index identifies the gap AFTER that displayed point, <display_rows-1. Bounds
 * describe full selected source window via existing owners. Source rows are
 * original canonical uint64 ordinals, never group-local indices. */
struct RasterPoint { Text point_order_lexeme; double x, y; Text x_lexeme, y_lexeme; };
struct RasterView {
    std::uint32_t struct_bytes, reserved; Text curve_identity_lexeme, curve_label;
    const RasterPoint* points; std::uint64_t point_count;
};
/* Raster views are ALREADY collected/deduplicated/collision-checked/sorted by
 * the existing CORE overlay owner. Lexical curve/point/coordinate receipts
 * preserve distinctions such as01 vs1 and1.0 vs1. Historical bignum input
 * lexemes stay intact; current owner sort/range rejection propagates unchanged;
 * x/y are display coordinates only. These lexical presentation receipts do NOT
 * replace canonical Dataset/schema/Curve Source IDs. Original scientific typed
 * identity/metadata remains in canonical input/invocation. Providers never
 * dedupe/sort/coerce these views or infer a new scientific identity from them.
 * Host copies exact receipts along with display derivatives into ordinary cache.
 */
struct PlaneView {
    std::uint32_t struct_bytes, channels; std::uint64_t width, height, row_stride;
    Bytes rgb; Scalar finite_minimum, finite_maximum;
    std::uint64_t finite_count, nonfinite_count, nearest_cell_scale;
};
/* Plane RGB channels3, row_stride=width*3, rgb.bytes=row_stride*height, no padding;
 * exact dtype min/max, finite+nonfinite==source plane cells, gray includes missing.
 * All Trace/Raster/Plane nested storage is immutable CORE-owned, borrowed until
 * host invalidates/destroys invocation. Providers NEVER allocate result views. */
struct Diagnostic { std::uint32_t struct_bytes; Status status; Text code, message; };
struct Probe {
    std::uint32_t struct_bytes, contract_count; const Text* contracts; Text dataset_kind;
    std::uint64_t requested_capabilities; PlanMode requested_mode; std::uint32_t reserved;
};
struct Admission { std::uint32_t struct_bytes, supported; std::uint64_t capabilities; Text reason; };
struct ResultInfo {
    std::uint32_t struct_bytes; PlanMode mode; CoreHandle preparation;
    std::uint64_t trace_count, raster_count; std::uint32_t has_plane, reserved;
    std::uint64_t capabilities;
};
struct AbiIdentity {
    std::uint32_t struct_bytes, abi_major, abi_minor, pointer_bytes;
    Endian native_endian; FloatFormat float_format; std::uint32_t reserved[2];
    Text platform, value_layout_id, build_id;
};
/* value_layout_id is this manifest's lowercase64hex SHA; build_id is a nonempty
 * bounded UTF-8 package build identity, stable until unload. Distinct host and
 * provider build IDs are allowed and both bound in actual admission/cache. */
struct CoreApi {
    std::uint32_t struct_bytes, abi_major, abi_minor, reserved;
    void* invocation; const AbiIdentity* identity; std::uint64_t capabilities;
    Status (*create)(void* invocation, CoreHandle*, Diagnostic*) noexcept;
    Status (*push)(void* invocation, CoreHandle, const Chunk*, Progress*, Diagnostic*) noexcept;
    Status (*seal)(void* invocation, CoreHandle, Progress*, Diagnostic*) noexcept;
    Status (*result)(void* invocation, CoreHandle, ResultToken*, Diagnostic*) noexcept;
    Status (*inspect_result)(void* invocation, ResultToken, ResultInfo*, Diagnostic*) noexcept;
    Status (*trace)(void* invocation, ResultToken, std::uint64_t index, TraceView*, Diagnostic*) noexcept;
    Status (*raster)(void* invocation, ResultToken, std::uint64_t index, RasterView*, Diagnostic*) noexcept;
    Status (*plane)(void* invocation, ResultToken, PlaneView*, Diagnostic*) noexcept;
    Status (*cancel)(void* invocation, CoreHandle, Diagnostic*) noexcept;
};
/* Each callback receives the SAME invocation pointer in this immutable table.
 * Owner registry validates handles/results against invocation before dereference;
 * unknown/foreign/closed/mismatched tokens return invalid. create is at most once
 * and uses the host-captured plan only. No destroy function is provided here.
 * State: created -> ingest -> seal(synchronous) -> done, or failed/cancelled.
 * Failed push/seal freezes whole preparation; no partial result. result only at
 * done; successful repeated result returns same immutable token, never new ones.
 * cancel is idempotent, invalidates access, does NOT free borrowed allocations.
 * create/push success=ok, seal/result success=done, view/inspect success=ok.
 * CoreApi/identity storage stays valid through provider close. Capability-specific
 * view callbacks may be null when not advertised; advertised callbacks required.
 * Scientific authorities may run through this supplied common CORE, not providers.
 */
struct ProviderApi {
    std::uint32_t struct_bytes, abi_major, abi_minor, reserved;
    const AbiIdentity* identity; Text provider_id, provider_version; std::uint64_t capabilities;
    Status (*probe)(const Probe*, Admission*, Diagnostic*) noexcept;
    Status (*open)(const CoreApi*, const Plan*, ProviderHandle*, Diagnostic*) noexcept;
    Status (*push)(ProviderHandle, const Chunk*, Progress*, Diagnostic*) noexcept;
    Status (*seal)(ProviderHandle, Progress*, Diagnostic*) noexcept;
    Status (*result)(ProviderHandle, ResultToken*, Diagnostic*) noexcept;
    Status (*cancel)(ProviderHandle, Diagnostic*) noexcept;
    void (*close)(ProviderHandle) noexcept;
};
/* Providers delegate scientific preparation/result construction to supplied
 * CoreApi and may return only its actual invocation-issued result token. Table,
 * identity and provider-id/version storage live until unload. open/Chunk inputs
 * are call-borrowed; CoreApi pointer stays valid until close, never beyond it.
 * probe Admission/Diagnostic strings live until next API call on the SAME loaded
 * provider (including probe) and host copies immediately. Instance diagnostics
 * live until next call on that instance. Providers release only own allocations.
 *
 * NORMAL HOST LIFETIME (also on failed/partial open):
 * 1 host creates one invocation bound to verified provider + exact owner receipts;
 * 2 provider opens/delegates; host tracks CORE tokens independently of provider;
 * 3 finish/cancel work; on success host validates result token AND source/Session/
 *   plan receipts, consumes/copies ALL borrowed views while CORE stays alive;
 * 4 host calls close exactly once for each returned nonnull ProviderHandle;
 *   close must not revoke/free/alter CORE results or preparation;
 * 5 host INTERNAL owner invalidates/destroys every invocation CORE object once,
 *   even if open failed/returned no token. No provider permission to destroy;
 * 6 unload only after provider handles and related Builder GUI mounts are gone.
 * No borrowed pointer enters durable cache. Abrupt worker kill may skip callbacks;
 * existing process owner invalidates the invocation and reclaims process memory.
 * Provider may not retain asynchronous work after close or fork private readers.
 */

/* Candidate fixed future symbol name is gxtxt_preview_provider_v1. This review
 * defines ONLY its function-pointer type: NO symbol declaration/definition/export.
 * Before loading, existing package/descriptor owner verifies binary/design hashes.
 * Entry validates exact value layout/platform/float/pointer profile and major;
 * table/identity abi_minor advertises that build's supported maximum; effective
 * minor=min(host,provider). Required ABI1 prefix coverage and nonnull fields
 * precede calls; optional future tails require their introduced minor too.
 * Unknown future table tails are ignored. Value structs never negotiate tails.
 * Failure sets table=null. Diagnostic obeys caller capacity rules above. */
extern "C" {
typedef Status (*ProviderEntryV1)(const AbiIdentity* host_identity,
    std::uint32_t host_core_table_bytes, std::uint32_t host_provider_table_bytes,
    const ProviderApi** table, Diagnostic*) noexcept;
}
inline constexpr std::uint32_t kCoreApiV1Bytes = 112;
inline constexpr std::uint32_t kProviderApiV1Bytes = 120;

static_assert(sizeof(void*)==8 && alignof(void*)==8, "ABI1 review profile requires64-bit aligned pointers");
static_assert(sizeof(double)==8 && alignof(double)==8 && std::numeric_limits<double>::is_iec559, "ABI1 requires IEEE754 binary64");
static_assert(sizeof(kValueLayoutId)==65, "Frozen value-layout SHA256 must be64hex");
static_assert(INT64_MIN==(-INT64_MAX-1), "ABI1 raw signed integers require two's complement");
#define GX_PREVIEW_FROZEN_RECORD(type, bytes) \
    static_assert(sizeof(type)==bytes && alignof(type)==8 && std::is_standard_layout<type>::value && std::is_trivially_copyable<type>::value, "Frozen ABI1 layout: " #type)
GX_PREVIEW_FROZEN_RECORD(Text,16); GX_PREVIEW_FROZEN_RECORD(Bytes,16); GX_PREVIEW_FROZEN_RECORD(Mask,16);
GX_PREVIEW_FROZEN_RECORD(Scalar,56); GX_PREVIEW_FROZEN_RECORD(Column,88); GX_PREVIEW_FROZEN_RECORD(Chunk,32);
GX_PREVIEW_FROZEN_RECORD(Predicate,40); GX_PREVIEW_FROZEN_RECORD(Affine,56); GX_PREVIEW_FROZEN_RECORD(Limits,96);
GX_PREVIEW_FROZEN_RECORD(Range,24); GX_PREVIEW_FROZEN_RECORD(RasterRoles,88); GX_PREVIEW_FROZEN_RECORD(PlanePlan,112);
GX_PREVIEW_FROZEN_RECORD(Plan,456); GX_PREVIEW_FROZEN_RECORD(Progress,56); GX_PREVIEW_FROZEN_RECORD(Point,16);
GX_PREVIEW_FROZEN_RECORD(TraceView,144); GX_PREVIEW_FROZEN_RECORD(RasterPoint,64); GX_PREVIEW_FROZEN_RECORD(RasterView,56);
GX_PREVIEW_FROZEN_RECORD(PlaneView,184); GX_PREVIEW_FROZEN_RECORD(Diagnostic,40); GX_PREVIEW_FROZEN_RECORD(Probe,48);
GX_PREVIEW_FROZEN_RECORD(Admission,32); GX_PREVIEW_FROZEN_RECORD(ResultInfo,48); GX_PREVIEW_FROZEN_RECORD(AbiIdentity,80);
#undef GX_PREVIEW_FROZEN_RECORD
/* These are REQUIRED TABLE PREFIX pins, not frozen whole-table sizes. A future
 * reviewed minor header may append a tail, never change these prefix offsets. */
static_assert(offsetof(CoreApi,cancel)+sizeof(CoreApi::cancel)==kCoreApiV1Bytes, "CORE mandatory prefix");
static_assert(offsetof(ProviderApi,close)+sizeof(ProviderApi::close)==kProviderApiV1Bytes, "Provider mandatory prefix");
static_assert(sizeof(CoreApi)>=kCoreApiV1Bytes && std::is_standard_layout<CoreApi>::value && std::is_trivially_copyable<CoreApi>::value, "CORE table prefix layout");
static_assert(sizeof(ProviderApi)>=kProviderApiV1Bytes && std::is_standard_layout<ProviderApi>::value && std::is_trivially_copyable<ProviderApi>::value, "Provider table prefix layout");
} // namespace gx::preview::v1
#endif
