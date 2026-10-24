cmake_minimum_required(VERSION 3.12)
project(gxtxt_native2d VERSION 0.9.8 LANGUAGES C CXX)

# Numeric owns shared reductions; Native2D owns matching/projection geometry.
set(GXTXT_NUMERIC_REDUCTION_HEADER "${CMAKE_CURRENT_SOURCE_DIR}/../../plugins/modules/math.numeric/api/c/gxtxt_numeric_reductions_v1.h")
if(NOT EXISTS "${GXTXT_NUMERIC_REDUCTION_HEADER}")
  message(FATAL_ERROR "Native2D requires the public NUMERIC_API_v1 C binding from the matching framework")
endif()
add_library(gx2d gx2d.c "${GXTXT_NUMERIC_REDUCTION_HEADER}")
target_compile_features(gx2d PUBLIC c_std_99)
target_include_directories(gx2d PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
if(WIN32 AND BUILD_SHARED_LIBS)
  target_compile_definitions(gx2d PRIVATE GX2D_BUILD_DLL)
endif()
if(NOT MSVC)
  target_link_libraries(gx2d PUBLIC m)
endif()

# Tcl adapter for viewers. The geometry engine remains a standalone C library.
find_package(TCL QUIET)
option(GXTXT_PREVIEW_PROVIDER_ONLY "Build the optional Preview adapter without rebuilding the GUI viewer" OFF)
if(TCL_FOUND)
  # Existing separate worker adapter; it only needs Tcl and the platform loader.
  if(CMAKE_SYSTEM_NAME STREQUAL "Linux" AND CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|amd64)$")
    add_library(gxpreviewprovider MODULE gx2d_preview_provider_v1.cpp gx2d_preview_provider_loader.cpp)
    target_compile_features(gxpreviewprovider PRIVATE cxx_std_17)
    target_include_directories(gxpreviewprovider PRIVATE ${TCL_INCLUDE_PATH})
    target_compile_definitions(gxpreviewprovider PRIVATE GXTXT_PREVIEW_BRIDGE_BUILD_ID="gxtxt.preview.bridge.dev111.p002.v1")
    target_link_libraries(gxpreviewprovider PRIVATE ${TCL_LIBRARY} ${CMAKE_DL_LIBS})
    set_target_properties(gxpreviewprovider PROPERTIES PREFIX "")
    install(TARGETS gxpreviewprovider LIBRARY DESTINATION core/native2d/bin)
  endif()
  if(GXTXT_PREVIEW_PROVIDER_ONLY)
    return()
  endif()
  # Device presentation is owned by Native2D and shares one painter between
  # virtual grids and native Plot projections. Cairo supplies real clipping,
  # alpha composition, dashed strokes and rotated text on the Tk drawable.
  find_path(GXTXT_CAIRO_INCLUDE cairo.h PATH_SUFFIXES cairo REQUIRED)
  find_library(GXTXT_CAIRO_LIBRARY NAMES cairo libcairo.so.2 REQUIRED)
  find_package(X11 REQUIRED)
  add_library(gx2dtcl MODULE gx2d_tcl.c gx2d.c gx2d_surface.cpp gx2d_presentation_batch.cpp)
  target_sources(gx2dtcl PRIVATE
    gx2d_csv_provider_v1.cpp
    gx2d_preview_categories_v1.cpp
    gx2d_preview_plane_v1.cpp
    gx2d_preview_batch_v1.cpp
    gx2d_preview_overlay_v1.cpp
    gx2d_preview_coordinates_v1.cpp)
  if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    set_source_files_properties(gx2d_preview_coordinates_v1.cpp PROPERTIES
      COMPILE_OPTIONS "-ffp-contract=off")
  elseif(MSVC)
    set_source_files_properties(gx2d_preview_coordinates_v1.cpp PROPERTIES
      COMPILE_OPTIONS "/fp:strict")
  endif()
  if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/gx2d_plot_v4.cpp")
    target_sources(gx2dtcl PRIVATE gx2d_plot_v4.cpp)
    target_compile_definitions(gx2dtcl PRIVATE GXTXT_NATIVE_PLOT_V4=1)
  endif()
  target_include_directories(gx2dtcl PRIVATE ${TCL_INCLUDE_PATH} ${TK_INCLUDE_PATH} ${GXTXT_CAIRO_INCLUDE})
  target_link_libraries(gx2dtcl PRIVATE ${TCL_LIBRARY} ${TK_LIBRARY} ${GXTXT_CAIRO_LIBRARY} X11::X11)
  target_compile_features(gx2dtcl PRIVATE cxx_std_17)
  target_compile_features(gx2dtcl PRIVATE c_std_99)
  if(NOT MSVC)
    target_link_libraries(gx2dtcl PRIVATE m)
  endif()
  set_target_properties(gx2dtcl PROPERTIES PREFIX "" OUTPUT_NAME "gx2dtcl")
  install(TARGETS gx2dtcl LIBRARY DESTINATION core/native2d/bin
                          RUNTIME DESTINATION core/native2d/bin)
endif()

include(CTest)
if(BUILD_TESTING)
  # Packaged validation sources are optional for a standalone CORE checkout.
  set(GXTXT_VALIDATION_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../validation" CACHE PATH "GX-TXT compatibility fixtures")
  set(GXTXT_NATIVE2D_FIXTURES dev054/native_interaction dev054/native_sketch054 dev055/native_construction055 dev056/native_tangents056 dev056/native_scene056 dev057/native_selection057 dev057/native_path057)
  list(APPEND GXTXT_NATIVE2D_FIXTURES curve_local_dev092/native_parts dev059/native_presentation059 dev059/native_selection059 dev059/native_composition059 dev059/native_tangent059)
  list(APPEND GXTXT_NATIVE2D_FIXTURES dev108/native_selection_pointset)
  foreach(family sketch constraints units snap cad gizmo direction identity collections views measurements compare_geometry polar_bulk bridge)
    list(APPEND GXTXT_NATIVE2D_FIXTURES "task9_dev052/native2d_${family}")
  endforeach()
  foreach(fixture IN LISTS GXTXT_NATIVE2D_FIXTURES)
    if(EXISTS "${GXTXT_VALIDATION_ROOT}/${fixture}.c")
      get_filename_component(test_name "${fixture}" NAME)
      add_executable("test_${test_name}" "${GXTXT_VALIDATION_ROOT}/${fixture}.c")
      target_link_libraries("test_${test_name}" PRIVATE gx2d)
      if(MSVC)
        target_compile_options("test_${test_name}" PRIVATE /UNDEBUG)
      else()
        target_compile_options("test_${test_name}" PRIVATE -UNDEBUG)
      endif()
      add_test(NAME "${test_name}" COMMAND "test_${test_name}")
    endif()
  endforeach()
endif()
