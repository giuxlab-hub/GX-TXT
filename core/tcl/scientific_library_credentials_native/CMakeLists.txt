cmake_minimum_required(VERSION 3.12)
project(gxtxt_library_credentials_native VERSION 1.0 LANGUAGES C)

# Private Library source leaf only. MAIN owns matching normal builds/staging.
if(NOT CMAKE_SYSTEM_NAME STREQUAL "Linux")
  message(FATAL_ERROR "Native Library submit requires the reviewed Linux host")
endif()
find_package(TCL REQUIRED)
add_library(gxtxt_library_credentials_native MODULE ../scientific_library_credentials_native_v1.c)
target_compile_features(gxtxt_library_credentials_native PRIVATE c_std_99)
target_include_directories(gxtxt_library_credentials_native PRIVATE ${TCL_INCLUDE_PATH})
target_link_libraries(gxtxt_library_credentials_native PRIVATE ${TCL_LIBRARY})
set_target_properties(gxtxt_library_credentials_native PROPERTIES
  PREFIX "" OUTPUT_NAME "gxtxt_library_credentials_native")
# No central add_subdirectory, auto-loader, configure execution or tests.
install(TARGETS gxtxt_library_credentials_native
  LIBRARY DESTINATION core/tcl/bin
  RUNTIME DESTINATION core/tcl/bin)
