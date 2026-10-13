// SPDX-License-Identifier: GPL-3.0-or-later
// XDE import and assembly transfer lookup cache. The OCCT 7.8.1 override is
// conservatively ported from the frozen viewer worker, not reimplemented.
#include "occt_step_backend.hpp"
#include <IFSelect_ReturnStatus.hxx>
#include <STEPCAFControl_Reader.hxx>
#include <TCollection_AsciiString.hxx>
#include <TDataStd_Name.hxx>
#include <TDF_LabelSequence.hxx>
#include <TDF_Tool.hxx>
#include <TDocStd_Document.hxx>
#include <TopLoc_Location.hxx>
#include <TopoDS_Shape.hxx>
#include <XCAFApp_Application.hxx>
#include <XCAFDoc_DocumentTool.hxx>
#include <XCAFDoc_ShapeTool.hxx>
#include <gp_Trsf.hxx>

#include <algorithm>
#include <exception>
#include <functional>
#include <limits>
#include <map>
#include <mutex>
#include <stdexcept>
#include <utility>
#include <STEPControl_ActorRead.hxx>
#include <Standard_Version.hxx>
#include <STEPConstruct_Assembly.hxx>
#include <Interface_Graph.hxx>
#include <Interface_EntityIterator.hxx>
#include <StepShape_ContextDependentShapeRepresentation.hxx>
#include <StepShape_ShapeDefinitionRepresentation.hxx>
#include <StepRepr_NextAssemblyUsageOccurrence.hxx>
#include <StepRepr_ShapeRepresentationRelationship.hxx>
#include <StepRepr_ProductDefinitionShape.hxx>
#include <StepRepr_Representation.hxx>
#include <StepBasic_ProductDefinition.hxx>
#include <Transfer_TransientProcess.hxx>
#include <TransferBRep.hxx>
#include <TransferBRep_ShapeBinder.hxx>
#include <TopLoc_Location.hxx>
#include <Message_ProgressScope.hxx>
#include <unordered_map>

#if OCC_VERSION_HEX == (7 << 16 | 8 << 8 | 1)
namespace {
void ApplyTransformation(TopoDS_Shape& shape, const gp_Trsf& transform) {
    if (transform.Form() != gp_Identity) shape.Move(TopLoc_Location(transform));
}
struct RepLinks {
    Handle(StepBasic_ProductDefinition) product;
    Handle(StepBasic_ProductDefinition) sdr_product;
    Handle(StepRepr_ShapeRepresentationRelationship) relationship;
};
thread_local const Interface_Graph* cached_graph = nullptr;
thread_local std::unordered_map<const StepRepr_Representation*, RepLinks> rep_links;
RepLinks links_for(const Interface_Graph& graph, const Handle(StepRepr_Representation)& rep) {
    if (cached_graph != &graph) { rep_links.clear(); cached_graph = &graph; }
    auto found = rep_links.find(rep.get());
    if (found != rep_links.end()) return found->second;
    RepLinks links;
    auto shared = graph.Sharings(rep);
    for (shared.Start(); shared.More(); shared.Next()) {
        const auto& item = shared.Value();
        auto sdr = Handle(StepShape_ShapeDefinitionRepresentation)::DownCast(item);
        if (!sdr.IsNull()) {
            if (links.sdr_product.IsNull() && sdr->UsedRepresentation() == rep)
                links.sdr_product = sdr->Definition().PropertyDefinition()->Definition().ProductDefinition();
            auto pds = Handle(StepRepr_ProductDefinitionShape)::DownCast(sdr->Definition().PropertyDefinition());
            if (pds.IsNull()) continue;
            auto children = graph.Shareds(pds);
            for (children.Start(); links.product.IsNull() && children.More(); children.Next())
                links.product = Handle(StepBasic_ProductDefinition)::DownCast(children.Value());
        } else if (item->IsKind(STANDARD_TYPE(StepRepr_ShapeRepresentationRelationship))) {
            links.relationship = Handle(StepRepr_ShapeRepresentationRelationship)::DownCast(item);
        }
    }
    rep_links.emplace(rep.get(), links);
    return links;
}
void reset_step_transfer_cache() {
    // A later import can reuse the previous graph's address. Clearing here
    // also releases product handles retained by the thread-local lookup.
    rep_links.clear();
    cached_graph=nullptr;
}
}

// OCCT 7.8.1 calls this lookup for every occurrence. A representation shared
// by many occurrences has the same SDR/product links throughout one import.
Standard_Boolean STEPConstruct_Assembly::CheckSRRReversesNAUO(
    const Interface_Graph& graph,
    const Handle(StepShape_ContextDependentShapeRepresentation)& cdsr) {
    auto nauo = Handle(StepRepr_NextAssemblyUsageOccurrence)::DownCast(
        cdsr->RepresentedProductRelation()->Definition().ProductDefinitionRelationship());
    if (nauo.IsNull()) return Standard_False;
    auto rep1 = cdsr->RepresentationRelation()->Rep1();
    auto rep2 = cdsr->RepresentationRelation()->Rep2();
    if (rep1.IsNull() || rep2.IsNull()) return Standard_False;
    const auto pd1 = links_for(graph, rep1).sdr_product;
    const auto pd2 = links_for(graph, rep2).sdr_product;
    if (pd1 == nauo->RelatedProductDefinition() && pd2 == nauo->RelatingProductDefinition())
        return Standard_False;
    if (pd2 == nauo->RelatedProductDefinition() && pd1 == nauo->RelatingProductDefinition())
        return Standard_True;
    return pd2 == nauo->RelatedProductDefinition() || pd1 == nauo->RelatingProductDefinition();
}

Handle(TransferBRep_ShapeBinder) STEPControl_ActorRead::TransferEntity(
    const Handle(StepRepr_NextAssemblyUsageOccurrence)& nauo,
    const Handle(Transfer_TransientProcess)& process,
    const StepData_Factors& factors,
    const Message_ProgressRange& progress) {
    Handle(TransferBRep_ShapeBinder) result;
    Handle(StepBasic_ProductDefinition) product;
    const auto& graph = process->Graph();
    gp_Trsf transform;
    Standard_Boolean has_transform = Standard_False;
    Standard_Boolean reversed = Standard_False;
    Standard_Boolean dependent = Standard_False;
    Handle(StepRepr_ShapeRepresentationRelationship) relationship;
    auto first = graph.Sharings(nauo);
    for (first.Start(); first.More(); first.Next()) {
        auto pds = Handle(StepRepr_ProductDefinitionShape)::DownCast(first.Value());
        if (pds.IsNull()) continue;
        auto second = graph.Sharings(pds);
        for (second.Start(); second.More(); second.Next()) {
            auto cdsr = Handle(StepShape_ContextDependentShapeRepresentation)::DownCast(second.Value());
            if (cdsr.IsNull()) continue;
            dependent = Standard_True;
            auto rr = cdsr->RepresentationRelation();
            if (rr.IsNull()) continue;
            reversed = STEPConstruct_Assembly::CheckSRRReversesNAUO(graph, cdsr);
            auto rep = reversed ? rr->Rep2() : rr->Rep1();
            if (rep.IsNull()) continue;
            has_transform = ComputeSRRWT(rr, process, transform, factors);
            auto links = links_for(graph, rep);
            if (product.IsNull()) product = links.product;
            if (!links.relationship.IsNull()) relationship = links.relationship;
        }
    }
    Handle(Transfer_Binder) binder;
    TopoDS_Shape shape;
    if (dependent) {
        Message_ProgressScope scope(progress, nullptr, 2);
        if (!product.IsNull()) {
            binder = process->Find(product);
            if (binder.IsNull()) binder = TransferEntity(product, process, factors, Standard_False, scope.Next());
            shape = TransferBRep::ShapeResult(binder);
            if (!shape.IsNull()) {
                if (has_transform) {
                    if (reversed) ApplyTransformation(shape, transform.Inverted());
                    else ApplyTransformation(shape, transform);
                }
                result = new TransferBRep_ShapeBinder(shape);
            }
        }
        if (shape.IsNull() && !relationship.IsNull()) {
            binder = process->Find(relationship);
            if (binder.IsNull()) {
                binder = TransferEntity(relationship, process, factors, 0, Standard_False, scope.Next());
                shape = TransferBRep::ShapeResult(binder);
                if (!shape.IsNull()) result = new TransferBRep_ShapeBinder(shape);
            }
        }
    }
    process->Bind(nauo, result);
    return result;
}
#endif

#if OCC_VERSION_HEX != (7 << 16 | 8 << 8 | 1)
namespace { void reset_step_transfer_cache() {} }
#endif

namespace gx3de_backend {

namespace {
std::mutex step_import_mutex;

std::string label_id(const TDF_Label& label) {
    TCollection_AsciiString entry;
    TDF_Tool::Entry(label,entry);
    return entry.ToCString();
}

std::string label_name(const TDF_Label& label) {
    Handle(TDataStd_Name) attribute;
    if (!label.FindAttribute(TDataStd_Name::GetID(),attribute)) return {};
    const auto& value=attribute->Get();
    std::vector<char> utf8(value.LengthOfCString()+1,'\0');
    Standard_PCharacter pointer=utf8.data();
    value.ToUTF8CString(pointer);
    return utf8.data();
}

gx3de_mat4 as_matrix(const gp_Trsf& transform) {
    gx3de_mat4 matrix{};
    for (int row=0;row<3;++row)
        for (int column=0;column<4;++column)
            matrix.m[column*4+row]=transform.Value(row+1,column+1);
    matrix.m[15]=1.0;
    return matrix;
}

void close_document(Handle(TDocStd_Document)& document) {
    if (document.IsNull()) return;
    XCAFApp_Application::GetApplication()->Close(document);
    document.Nullify();
}
} // namespace

struct StepDocument {
    Handle(TDocStd_Document) xde;
    std::vector<StepNode> nodes;
    std::vector<StepPrototype> prototypes;
    std::vector<TopoDS_Shape> shapes;
    StepImportStats stats;

    ~StepDocument() {
        std::lock_guard<std::mutex> lock(step_import_mutex);
        close_document(xde);
    }
};

bool step_read(const std::string& source_path, const StepImportOptions& options,
               std::shared_ptr<StepDocument>& out, std::string& error) {
    out.reset(); error.clear();
    if (source_path.empty() || options.max_nodes==0) {
        error="STEP path is empty or node budget is zero"; return false;
    }
    std::lock_guard<std::mutex> lock(step_import_mutex);
    Handle(TDocStd_Document) xde;
    try {
        if (options.cancelled && options.cancelled()) {
            error="STEP import cancelled"; return false;
        }
        // Preserve the viewer's XDE reader modes and transfer behavior.
        STEPCAFControl_Reader reader;
        reader.SetNameMode(Standard_True);
        reader.SetColorMode(Standard_True);
        reset_step_transfer_cache();
        if (reader.ReadFile(source_path.c_str())!=IFSelect_RetDone)
            throw std::runtime_error("STEP parse failed");
        if (options.cancelled && options.cancelled())
            throw std::runtime_error("STEP import cancelled");
        XCAFApp_Application::GetApplication()->NewDocument("BinXCAF",xde);
        if (xde.IsNull() || !reader.Transfer(xde))
            throw std::runtime_error("STEP XDE transfer failed");
        reset_step_transfer_cache();
        if (options.cancelled && options.cancelled())
            throw std::runtime_error("STEP import cancelled");
        const Handle(XCAFDoc_ShapeTool) shapes=XCAFDoc_DocumentTool::ShapeTool(xde->Main());
        if (shapes.IsNull()) throw std::runtime_error("STEP XDE shape tool missing");
        TDF_LabelSequence roots;
        shapes->GetFreeShapes(roots);
        if (roots.Length()<1) throw std::runtime_error("STEP has no transferable roots");

        // Keep the document private until all referenced definitions and
        // occurrence transforms have been validated.
        std::vector<StepNode> nodes;
        std::vector<StepPrototype> prototypes;
        std::vector<TopoDS_Shape> prototype_shapes;
        std::map<std::string,uint64_t> prototype_indices;
        std::vector<std::string> active_assemblies;
        StepImportStats stats{};
        stats.root_count=static_cast<uint64_t>(roots.Length());
        const gp_Trsf identity;
        std::function<void(const TDF_Label&,uint64_t,const gp_Trsf&,unsigned)> inspect;
        inspect=[&](const TDF_Label& label, uint64_t parent,
                     const gp_Trsf& parent_world, unsigned depth) {
            if (depth>128) throw std::runtime_error("STEP assembly nesting exceeds safety limit");
            if (nodes.size()>=options.max_nodes)
                throw std::runtime_error("STEP assembly exceeds node budget");
            if (options.cancelled && options.cancelled())
                throw std::runtime_error("STEP import cancelled");
            const bool reference=XCAFDoc_ShapeTool::IsReference(label);
            TDF_Label definition=label;
            if (reference && !XCAFDoc_ShapeTool::GetReferredShape(label,definition))
                throw std::runtime_error("STEP occurrence has no definition");
            const bool assembly=XCAFDoc_ShapeTool::IsAssembly(definition);
            const bool part=XCAFDoc_ShapeTool::IsSimpleShape(definition);
            if (!assembly && !part)
                throw std::runtime_error("STEP contains unsupported XDE shape kind");
            gp_Trsf local;
            if (reference) local=XCAFDoc_ShapeTool::GetLocation(label).Transformation();
            gp_Trsf world=parent_world;
            world.Multiply(local);
            StepNode node;
            node.id=label_id(label);
            node.name=label_name(label);
            node.definition_id=label_id(definition);
            node.parent_index=parent;
            node.kind=assembly ? StepNodeKind::assembly : StepNodeKind::part;
            node.is_reference=reference;
            node.local_transform=as_matrix(local);
            node.world_transform=as_matrix(world);
            const uint64_t self=static_cast<uint64_t>(nodes.size());
            if (assembly) {
                ++stats.assembly_nodes;
            } else {
                ++stats.part_occurrences;
                auto found=prototype_indices.find(node.definition_id);
                if (found==prototype_indices.end()) {
                    TopoDS_Shape native=XCAFDoc_ShapeTool::GetShape(definition);
                    if (native.IsNull())
                        throw std::runtime_error("STEP part definition has no shape");
                    const uint64_t index=static_cast<uint64_t>(prototypes.size());
                    prototypes.push_back({node.definition_id,label_name(definition)});
                    prototype_shapes.push_back(std::move(native));
                    prototype_indices.emplace(node.definition_id,index);
                    node.prototype_index=index;
                } else node.prototype_index=found->second;
            }
            if (reference) ++stats.reference_nodes;
            nodes.push_back(std::move(node));
            if (!assembly) return;
            const std::string definition_id=label_id(definition);
            if (std::find(active_assemblies.begin(),active_assemblies.end(),definition_id)!=active_assemblies.end())
                throw std::runtime_error("STEP assembly contains a definition cycle");
            active_assemblies.push_back(definition_id);
            TDF_LabelSequence children;
            XCAFDoc_ShapeTool::GetComponents(definition,children);
            for (int i=1;i<=children.Length();++i)
                inspect(children.Value(i),self,world,depth+1);
            active_assemblies.pop_back();
        };
        for (int i=1;i<=roots.Length();++i)
            inspect(roots.Value(i),UINT64_MAX,identity,0);
        if (options.cancelled && options.cancelled())
            throw std::runtime_error("STEP import cancelled");
        stats.unique_parts=static_cast<uint64_t>(prototypes.size());
        auto result=std::make_shared<StepDocument>();
        result->xde=xde;
        xde.Nullify();
        result->nodes=std::move(nodes);
        result->prototypes=std::move(prototypes);
        result->shapes=std::move(prototype_shapes);
        result->stats=stats;
        out=std::move(result);
        return true;
    } catch (const Standard_Failure& e) {
        error=e.GetMessageString() ? e.GetMessageString() : "OCCT STEP import failed";
    } catch (const std::exception& e) {
        error=e.what();
    }
    reset_step_transfer_cache();
    close_document(xde);
    return false;
}

const std::vector<StepNode>& step_nodes(const StepDocument& document) {
    return document.nodes;
}
const std::vector<StepPrototype>& step_prototypes(const StepDocument& document) {
    return document.prototypes;
}
StepImportStats step_stats(const StepDocument& document) { return document.stats; }
bool step_prototype_shape(const StepDocument& document, uint64_t index,
                          TopoDS_Shape& out) {
    out.Nullify();
    if (index>=document.shapes.size()) return false;
    out=document.shapes[static_cast<size_t>(index)];
    return !out.IsNull();
}

} // namespace gx3de_backend
