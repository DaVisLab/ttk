# read the ttk.module file and create a list named moduleFileContent from it
# this list can then be parsed using the cmake_parse_arguments method
macro(ttk_parse_module_file moduleFile)
  get_filename_component(moduleRealFile ${moduleFile} REALPATH)
  if(moduleFile MATCHES "ttk.module$")
    # rebuild when ttk.module is changed
    # already done by VTK for vtk.module
    set_property(
      DIRECTORY
        "${CMAKE_CURRENT_SOURCE_DIR}"
      APPEND PROPERTY
      CMAKE_CONFIGURE_DEPENDS
        ${moduleRealFile}
    )
  endif()
  file(READ ${moduleRealFile} moduleFileContent)
  # Replace comments.
  string(REGEX REPLACE "#[^\n]*\n" "\n" moduleFileContent "${moduleFileContent}")
  # Use argument splitting.
  string(REGEX REPLACE "( |\n)+" ";" moduleFileContent "${moduleFileContent}")
endmacro()

# add a new vtk module for with given name.
# This macro assume a ttk.module file is available
# in the current context
# it must have the following syntax:
# NAME: module name
# SOURCES: Specify the list of source files for the module
# HEADERS: Specify the list of header files to install for the module
# DEPENDS: Specify the link dependencies of the module
macro(ttk_add_vtk_module)
  ttk_parse_module_file(${CMAKE_CURRENT_LIST_DIR}/ttk.module)
  cmake_parse_arguments("TTK" "" "NAME" "SOURCES;HEADERS;DEPENDS" ${moduleFileContent})

  if(NOT TARGET ${TTK_NAME})
    vtk_module_add_module(${TTK_NAME}
      SOURCES
        ${TTK_SOURCES}
      HEADERS
        ${TTK_HEADERS}
      )

    vtk_module_compile_options(${TTK_NAME} PRIVATE ${TTK_COMPILER_FLAGS})

    vtk_module_link(${TTK_NAME}
      PUBLIC
        ${TTK_DEPENDS}
      )


    if(TTK_ENABLE_DOUBLE_TEMPLATING)
      vtk_module_definitions(${TTK_NAME} PRIVATE TTK_ENABLE_DOUBLE_TEMPLATING)
    endif()

    if(TTK_REDUCE_TEMPLATE_INSTANTIATIONS)
      vtk_module_definitions(${TTK_NAME} PRIVATE TTK_REDUCE_TEMPLATE_INSTANTIATIONS)
    endif()

    if(TTK_LINKER_FLAGS)
      vtk_module_link_options(${TTK_NAME} PRIVATE ${TTK_LINKER_FLAGS})
    endif()

    install(TARGETS ${TTK_NAME}
      EXPORT TTKVTKTargets
      )
  endif()

  function(ttk_set_paraview_install_name TTK_NAME)
    if(APPLE)
      # On macOS,
      # let the TopologyToolKit.so find this dependency in the subdirectory
      set_target_properties (${TTK_NAME}
        PROPERTIES
          INSTALL_NAME_DIR "@rpath"
      )
    endif(APPLE)
  endfunction(ttk_set_paraview_install_name)

  if(NOT "${TTK_INSTALL_PLUGIN_DIR}" STREQUAL "")
    ttk_set_paraview_install_name(${TTK_NAME})
    install(
      TARGETS
        ${TTK_NAME}
      DESTINATION
        "${TTK_INSTALL_PLUGIN_DIR}/${TTK_PLUGIN_SUBDIR}"
      )
  endif()

  # Fix a race condition in the VTK's CMake:
  # https://discourse.vtk.org/t/building-vtk-modules-with-dependencies-results-in-race-condition-in-make/1711
  if(TARGET ${TTK_NAME}-hierarchy)
    add_dependencies(${TTK_NAME} ${TTK_NAME}-hierarchy)
    foreach(TTK_DEP_TARGET ${TTK_DEPENDS})
      if(TARGET ${TTK_DEP_TARGET}-hierarchy)
        add_dependencies(${TTK_NAME}-hierarchy ${TTK_DEP_TARGET}-hierarchy)
      endif()
    endforeach()
  endif()
endmacro()

# return the target name if target is enabled
# empty otherwise
# Used by the whitelist mechanism to disable target by default:
# - the whitelist mechanism needs to be enables in the cmake command line
#   before the first configure.
# Also check dependencies of each module.
function(ttk_get_target ttk_module ttk_target)
  # default status
  if(${TTK_WHITELIST_MODE})
    # If whitelist mode is ON, no more filters are enabled by default.
    # Filters with default status are switced to DONT_WANT
    if((NOT DEFINED VTK_MODULE_ENABLE_${ttk_module}) OR (${VTK_MODULE_ENABLE_${ttk_module}} STREQUAL "DEFAULT"))
      set(VTK_MODULE_ENABLE_${ttk_module} "DONT_WANT" CACHE STRING "Enable the ${ttk_module} module." FORCE)
      mark_as_advanced(VTK_MODULE_ENABLE_${ttk_module})
    endif()
  endif()

  # dependencies check
  ttk_parse_module_file(${VTKWRAPPER_DIR}/${ttk_module}/vtk.module)
  cmake_parse_arguments("VTK" "" "NAME" "DEPENDS;PRIVATE_DEPENDS" ${moduleFileContent})
  foreach(VTK_DEP_TARGET ${VTK_DEPENDS})
    # Check VTK targets are available (Assume VTK use the VTK namespace)
    string(REGEX MATCH "VTK::.*" TARGET_VTK ${VTK_DEP_TARGET})
    if(NOT "${TARGET_VTK}" STREQUAL "")
      if(NOT TARGET ${TARGET_VTK})
        message(WARNING "Missing dependency ${TARGET_VTK} for module ${ttk_module}.")
        set(VTK_MODULE_ENABLE_${ttk_module} "NO" CACHE STRING "Enable the ${ttk_module} module." FORCE)
      endif()
    endif()
  endforeach()
  foreach(VTK_DEP_TARGET ${VTK_PRIVATE_DEPENDS})
    if(NOT TARGET ${VTK_DEP_TARGET})
      message(WARNING "Missing (private) dependency ${VTK_DEP_TARGET} for module ${ttk_module}.")
      set(VTK_MODULE_ENABLE_${ttk_module} "NO" CACHE STRING "Enable the ${ttk_module} module." FORCE)
    endif()
  endforeach()

  # add the module if enabled
  list(APPEND ACCEPTED_VALUES "YES" "WANT" "DEFAULT")
  if("${VTK_MODULE_ENABLE_${ttk_module}}" IN_LIST ACCEPTED_VALUES)
    set(${ttk_target} ${ttk_module} PARENT_SCOPE)
  else()
    message(STATUS "Disable ttk module: ${ttk_module}")
    set(${ttk_target} "" PARENT_SCOPE)
  endif()
endfunction()
