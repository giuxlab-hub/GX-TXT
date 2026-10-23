cmake_minimum_required(VERSION 3.12)
project(gxtxt_script_job_channel VERSION 1.0 LANGUAGES C)

# Private leaf of ScriptJob, not a runner or runtime compiler. This initial
# source contract qualifies native Unix command-pipe drivers only.
if(NOT UNIX)
  message(FATAL_ERROR "The private protected ScriptJob leaf requires a reviewed Unix command-pipe driver")
endif()
find_package(TCL REQUIRED)
add_library(gxtxt_script_job_channel MODULE ../script_job_channel_v1.c)
target_compile_features(gxtxt_script_job_channel PRIVATE c_std_99)
target_include_directories(gxtxt_script_job_channel PRIVATE ${TCL_INCLUDE_PATH})
target_link_libraries(gxtxt_script_job_channel PRIVATE ${TCL_LIBRARY})
set_target_properties(gxtxt_script_job_channel PROPERTIES
  PREFIX "" OUTPUT_NAME "gxtxt_script_job_channel")
# No configure-time execution, tests, auto-loader or product binary staging.
install(TARGETS gxtxt_script_job_channel
  LIBRARY DESTINATION core/tcl/bin
  RUNTIME DESTINATION core/tcl/bin)
