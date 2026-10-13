// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <vtkCell.h>
#include <vtkCellArray.h>
#include <vtkMath.h>
#include <vtkNew.h>
#include <vtkPoints.h>
#include <vtkPolyData.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <map>
#include <numeric>
#include <stdexcept>
#include <vector>

namespace gx3d_repeat {
struct Match {
    std::array<double,3> center{};
    std::array<double,4> quaternion{};
    std::vector<vtkIdType> cells;
};
struct Proposal {
    vtkSmartPointer<vtkPolyData> prototype;
    std::vector<Match> matches;
    std::vector<uint8_t> matched_cells;
    vtkIdType source_cell{-1};
    vtkIdType source_triangles{0};
};
using Matrix = std::array<std::array<int,3>,3>;
using Triangle = std::array<int64_t,9>;

inline std::vector<Matrix> rotations() {
    std::vector<Matrix> result;
    std::array<int,3> permutation{0,1,2};
    do {
        const int parity = ((permutation[0] > permutation[1]) +
            (permutation[0] > permutation[2]) +
            (permutation[1] > permutation[2])) % 2 ? -1 : 1;
        for (int sx : {-1,1}) for (int sy : {-1,1}) for (int sz : {-1,1}) {
            if (parity*sx*sy*sz != 1) continue;
            Matrix rotation{};
            rotation[0][permutation[0]] = sx;
            rotation[1][permutation[1]] = sy;
            rotation[2][permutation[2]] = sz;
            result.push_back(rotation);
        }
    } while (std::next_permutation(permutation.begin(),permutation.end()));
    return result;
}

inline std::array<double,3> centroid(vtkPolyData* mesh,
                                     const std::vector<vtkIdType>& cells) {
    std::array<double,3> center{};
    for (const auto cell_id : cells) {
        vtkCell* cell = mesh->GetCell(cell_id);
        if (!cell || cell->GetNumberOfPoints() != 3)
            throw std::runtime_error("repeat detection requires triangle cells");
        for (int vertex=0; vertex<3; ++vertex) {
            double point[3]{};
            mesh->GetPoint(cell->GetPointId(vertex),point);
            for (int axis=0; axis<3; ++axis) center[axis] += point[axis];
        }
    }
    const double divisor = static_cast<double>(cells.size())*3.0;
    for (double& value : center) value /= divisor;
    return center;
}

inline std::vector<Triangle> signature(vtkPolyData* mesh,
    const std::vector<vtkIdType>& cells, const std::array<double,3>& center,
    const Matrix& rotation, double tolerance) {
    std::vector<Triangle> triangles;
    triangles.reserve(cells.size());
    for (const auto cell_id : cells) {
        vtkCell* cell = mesh->GetCell(cell_id);
        std::array<std::array<int64_t,3>,3> vertices{};
        for (int vertex=0; vertex<3; ++vertex) {
            double point[3]{};
            mesh->GetPoint(cell->GetPointId(vertex),point);
            for (int axis=0; axis<3; ++axis) {
                double coordinate = 0;
                for (int source=0; source<3; ++source)
                    coordinate += rotation[source][axis]*(point[source]-center[source]);
                if (!std::isfinite(coordinate) || std::abs(coordinate/tolerance) > 1e15)
                    throw std::runtime_error("repeat geometry is outside the supported precision range");
                vertices[vertex][axis] = static_cast<int64_t>(std::llround(coordinate/tolerance));
            }
        }
        std::sort(vertices.begin(),vertices.end());
        Triangle flattened{};
        for (int vertex=0; vertex<3; ++vertex)
            for (int axis=0; axis<3; ++axis)
                flattened[vertex*3+axis] = vertices[vertex][axis];
        triangles.push_back(flattened);
    }
    std::sort(triangles.begin(),triangles.end());
    return triangles;
}

inline Proposal discover(vtkPolyData* mesh, vtkIdType selected) {
    if (!mesh || selected < 0 || selected >= mesh->GetNumberOfCells())
        throw std::runtime_error("select an available mesh cell for repeat matching");
    const vtkIdType cell_count = mesh->GetNumberOfCells();
    const vtkIdType point_count = mesh->GetNumberOfPoints();
    if (cell_count > 1000000 || point_count > 3000000)
        throw std::runtime_error("repeat matching exceeds its bounded mesh scan limit");
    std::vector<vtkIdType> parent(static_cast<size_t>(cell_count));
    std::iota(parent.begin(),parent.end(),vtkIdType{0});
    std::vector<vtkIdType> first(static_cast<size_t>(point_count),-1);
    auto root = [&](vtkIdType cell) {
        while (parent[static_cast<size_t>(cell)] != cell) {
            parent[static_cast<size_t>(cell)] = parent[static_cast<size_t>(parent[static_cast<size_t>(cell)])];
            cell = parent[static_cast<size_t>(cell)];
        }
        return cell;
    };
    for (vtkIdType cell_id=0; cell_id<cell_count; ++cell_id) {
        vtkCell* cell = mesh->GetCell(cell_id);
        if (!cell || cell->GetNumberOfPoints() != 3)
            throw std::runtime_error("repeat matching requires triangle cells");
        for (int vertex=0; vertex<3; ++vertex) {
            const auto point = cell->GetPointId(vertex);
            auto& prior = first[static_cast<size_t>(point)];
            if (prior >= 0) parent[static_cast<size_t>(root(cell_id))] = root(prior);
            else prior = cell_id;
        }
    }
    std::map<vtkIdType,std::vector<vtkIdType>> groups;
    for (vtkIdType cell_id=0; cell_id<cell_count; ++cell_id)
        groups[root(cell_id)].push_back(cell_id);
    const auto selected_root = root(selected);
    const auto chosen = groups.find(selected_root);
    if (chosen == groups.end() || chosen->second.empty() || chosen->second.size() > 100000)
        throw std::runtime_error("selected component is empty or over the repeat limit");
    const auto source_center = centroid(mesh,chosen->second);
    double bounds[6]{}; mesh->GetBounds(bounds);
    const double span = std::max({bounds[1]-bounds[0],bounds[3]-bounds[2],bounds[5]-bounds[4]});
    // The binary display cache stores float coordinates; allow their rounding
    // error after large translations without merging visibly different parts.
    const double tolerance = std::max(1e-6,span*1e-5);
    const Matrix identity{{{{1,0,0}},{{0,1,0}},{{0,0,1}}}};
    const auto reference = signature(mesh,chosen->second,source_center,identity,tolerance);
    Proposal proposal;
    proposal.source_cell = selected;
    proposal.source_triangles = static_cast<vtkIdType>(chosen->second.size());
    proposal.matched_cells.assign(static_cast<size_t>(cell_count),0);
    const auto orientations = rotations();
    for (const auto& entry : groups) {
        if (entry.second.size() != chosen->second.size()) continue;
        const auto center = centroid(mesh,entry.second);
        for (const auto& rotation : orientations) {
            if (signature(mesh,entry.second,center,rotation,tolerance) != reference) continue;
            double matrix[3][3]{};
            for (int row=0; row<3; ++row) for (int column=0; column<3; ++column)
                matrix[row][column] = rotation[row][column];
            double quaternion[4]{};
            vtkMath::Matrix3x3ToQuaternion(matrix,quaternion);
            Match match;
            match.center = center;
            match.quaternion = {quaternion[0],quaternion[1],quaternion[2],quaternion[3]};
            match.cells = entry.second;
            for (const auto cell_id : match.cells)
                proposal.matched_cells[static_cast<size_t>(cell_id)] = 1;
            proposal.matches.push_back(std::move(match));
            break;
        }
    }
    if (proposal.matches.size() < 2)
        throw std::runtime_error("no matching disconnected components were found");
    vtkNew<vtkPoints> points;
    vtkNew<vtkCellArray> cells;
    for (const auto cell_id : chosen->second) {
        vtkCell* cell = mesh->GetCell(cell_id);
        vtkIdType ids[3]{};
        for (int vertex=0; vertex<3; ++vertex) {
            double position[3]{};
            mesh->GetPoint(cell->GetPointId(vertex),position);
            ids[vertex] = points->InsertNextPoint(position[0]-source_center[0],
                position[1]-source_center[1],position[2]-source_center[2]);
        }
        cells->InsertNextCell(3,ids);
    }
    proposal.prototype = vtkSmartPointer<vtkPolyData>::New();
    proposal.prototype->SetPoints(points);
    proposal.prototype->SetPolys(cells);
    return proposal;
}

inline vtkSmartPointer<vtkPolyData> remainder(vtkPolyData* mesh, const Proposal& proposal) {
    vtkNew<vtkPoints> points;
    vtkNew<vtkCellArray> cells;
    std::map<vtkIdType,vtkIdType> remap;
    for (vtkIdType cell_id=0; cell_id<mesh->GetNumberOfCells(); ++cell_id) {
        if (proposal.matched_cells[static_cast<size_t>(cell_id)]) continue;
        vtkCell* cell = mesh->GetCell(cell_id);
        vtkIdType ids[3]{};
        for (int vertex=0; vertex<3; ++vertex) {
            const auto source = cell->GetPointId(vertex);
            const auto found = remap.find(source);
            if (found != remap.end()) ids[vertex] = found->second;
            else {
                double position[3]{}; mesh->GetPoint(source,position);
                ids[vertex] = points->InsertNextPoint(position);
                remap.emplace(source,ids[vertex]);
            }
        }
        cells->InsertNextCell(3,ids);
    }
    auto output = vtkSmartPointer<vtkPolyData>::New();
    output->SetPoints(points); output->SetPolys(cells);
    return output;
}
} // namespace gx3d_repeat
