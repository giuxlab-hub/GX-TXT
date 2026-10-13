/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef GX3DE_OCCT_STEP_BACKEND_HPP
#define GX3DE_OCCT_STEP_BACKEND_HPP

#include "native_3d_engine_api_v1.h"
#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <vector>

class TopoDS_Shape;

namespace gx3de_backend {

struct StepDocument;

enum class StepNodeKind : uint32_t { assembly=1, part=2 };

/* One logical XDE assembly/part occurrence per node, in preorder. A reference
 * node carries its own XDE label/name and a separate definition_id. Repeated
 * part occurrences share a prototype_index. The matrices are column-major;
 * parent_index and prototype_index use UINT64_MAX when absent. */
struct StepNode {
    std::string id;
    std::string name;
    std::string definition_id;
    uint64_t parent_index=UINT64_MAX;
    uint64_t prototype_index=UINT64_MAX;
    StepNodeKind kind=StepNodeKind::part;
    bool is_reference=false;
    gx3de_mat4 local_transform{};
    gx3de_mat4 world_transform{};
};

struct StepPrototype {
    std::string id;
    std::string name;
};

struct StepImportStats {
    uint64_t root_count=0;
    uint64_t assembly_nodes=0;
    uint64_t reference_nodes=0;
    uint64_t part_occurrences=0;
    uint64_t unique_parts=0;
};

struct StepImportOptions {
    /* A true result cancels traversal. OCCT ReadFile/Transfer themselves are
     * blocking; cancellation cannot interrupt those calls in this version. */
    std::function<bool()> cancelled;
    uint64_t max_nodes=1000000;
};

/* Reads STEP/XDE without tessellating or flattening assembly occurrences.
 * Output is assigned only after complete transfer/traversal. Import calls are
 * serialized around OCCT's application/transfer state; returned documents are
 * independent and retain their own XDE document and immutable prototypes.
 */
bool step_read(const std::string& source_path, const StepImportOptions& options,
               std::shared_ptr<StepDocument>& out, std::string& error);
const std::vector<StepNode>& step_nodes(const StepDocument& document);
const std::vector<StepPrototype>& step_prototypes(const StepDocument& document);
StepImportStats step_stats(const StepDocument& document);

/* Internal native shape bridge for a later C API import wrapper. The returned
 * OCCT shape is the untransformed, shared definition, never an occurrence
 * compound. Caller applies StepNode::world_transform for each occurrence. */
bool step_prototype_shape(const StepDocument& document, uint64_t index,
                          TopoDS_Shape& out);

} // namespace gx3de_backend
#endif
