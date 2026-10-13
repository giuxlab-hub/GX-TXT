// SPDX-License-Identifier: GPL-3.0-or-later
// Linux OCCT 7.8 STEP assembly transfer lookup cache.
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
