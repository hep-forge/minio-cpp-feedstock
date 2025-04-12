function(factorize_paths input_string)
    # Split the input string by ';' into a list
    string(REPLACE ";" ";" input_string "${input_string}")
    string(REPLACE ";" " " input_string)
    separate_arguments(library_paths UNIX_COMMAND "${input_string}")

    # Find the common prefix of all paths
    list(GET library_paths 0 common_prefix)
    foreach(path IN LISTS library_paths)
        string(FIND "${path}" "${common_prefix}" common_len)
        while(NOT common_len EQUAL 0)
            string(SUBSTRING "${common_prefix}" 0 ${common_len} common_prefix)
            string(FIND "${path}" "${common_prefix}" common_len)
        endwhile()
    endforeach()

    # Extract library names and construct the final output
    set(library_names "")
    foreach(path IN LISTS library_paths)
        string(REPLACE "${common_prefix}" "" library_name "${path}")
        string(REGEX REPLACE "^lib|\\.dylib$" "" library_name "${library_name}")
        list(APPEND library_names "${library_name}")
    endforeach()

    # Join library names with commas and construct the final string
    string(REPLACE ";" " " library_names_str "${library_names}")
    string(REPLACE " " "," library_names_str "${library_names_str}")
    set(final_string "${common_prefix}[${library_names_str}].dylib")

    # Print the final string
    message("${final_string}")
endfunction()

# Function 1: parse_component_suffix
function(parse_component_suffix input_string component_name_var suffix_var)
    # Check if the input string contains a "/"
    string(FIND "${input_string}" "/" slash_position)

    if(slash_position EQUAL -1)
        # No suffix found, handle as a single component
        set(${component_name_var} "${input_string}" PARENT_SCOPE)
        set(${suffix_var} "" PARENT_SCOPE)
    else()
        # Extract component name after the suffix "/"
        string(SUBSTRING "${input_string}" 0 ${slash_position} suffix)
        math(EXPR component_start "${slash_position} + 1")
        string(SUBSTRING "${input_string}" ${component_start} -1 component_name)

        set(${component_name_var} "${component_name}" PARENT_SCOPE)
        set(${suffix_var} "${suffix}" PARENT_SCOPE)
    endif()

endfunction()

# Function 2: parse_component_alternatives
function(parse_component_alternatives input_string component_name_var component_list_var)
    # Check if the input string contains a colon (for alternatives)
    string(FIND "${input_string}" ":" colon_position)

    if(colon_position EQUAL -1)
        # No alternatives found, handle as a single component
        set(${component_name_var} "${input_string}" PARENT_SCOPE)
        set(${component_list_var} "" PARENT_SCOPE)
    else()
        # Extract component name before the colon
        string(SUBSTRING "${input_string}" 0 ${colon_position} component_name)

        # Extract alternatives after the colon
        math(EXPR alternatives_start "${colon_position} + 1")
        string(SUBSTRING "${input_string}" ${alternatives_start} -1 alternatives_string)

        # Split alternatives by commas
        string(REPLACE "," ";" alternatives_list "${alternatives_string}")

        set(${component_name_var} "${component_name}" PARENT_SCOPE)
        set(${component_list_var} "${alternatives_list}" PARENT_SCOPE)
    endif()

endfunction()

function(find_custom_path LIBRARY _INCLUDE_PATHS_NAME)

    if (${_INCLUDE_PATHS_NAME})
        set(_INCLUDE_PATHS "${${_INCLUDE_PATHS_NAME}}")
    endif()

    if(${LIBRARY}_INCLUDE_DIR AND NOT "${${LIBRARY}_INCLUDE_DIR}" STREQUAL "TRUE")
        list(PREPEND ${${LIBRARY}_INCLUDE_DIR})
    endif()

    foreach(LIBRARY_PATH IN LISTS ${LIBRARY}_LIBRARIES)
        get_filename_component(LIBRARY_DIRNAME ${LIBRARY_PATH} DIRECTORY)
        list(APPEND _INCLUDE_PATHS ${LIBRARY_DIRNAME}/../include)
    endforeach()

    foreach(LIBRARY_INCLUDE_DIR IN LISTS _LIBRARY_INCLUDE_PATHS)
        list(APPEND _INCLUDE_PATHS ${LIBRARY_INCLUDE_DIR})
    endforeach()
    
    list(REMOVE_DUPLICATES _INCLUDE_PATHS)
    find_path(${LIBRARY}_INCLUDE_DIRS
        NAMES
            ${LIBRARY_HEADERS}
        PATHS
            ${_INCLUDE_PATHS}
        HINTS 
            ${LIBRARY_HINTS}
        NO_DEFAULT_PATH
    )
    if(NOT ${LIBRARY}_INCLUDE_PATHS)

        find_path(${LIBRARY}_INCLUDE_DIRS
            NAMES
                ${LIBRARY_HEADERS}
            PATHS
                ${_INCLUDE_PATHS}
            HINTS 
                ${LIBRARY_HINTS}
        )

    endif()

endfunction()

function(find_library_component LIBRARY COMPONENT_NAME COMPONENT PATH_SUFFIX)
    string(REGEX REPLACE "^lib" "" COMPONENT_STRIPPED "${COMPONENT}")

    string(TOLOWER ${COMPONENT_STRIPPED} COMPONENT_LOWER_STRIPPED)
    string(TOUPPER ${COMPONENT_STRIPPED} COMPONENT_UPPER_STRIPPED)
    
    string(TOLOWER ${COMPONENT} COMPONENT_LOWER)
    string(TOUPPER ${COMPONENT} COMPONENT_UPPER)

    if(TARGET ${${LIBRARY}_${COMPONENT_NAME}_LIBRARY})
        set(${LIBRARY}_${COMPONENT_NAME}_LIBRARY ${CMAKE_BINARY_DIR}/lib/lib${COMPONENT}.so)
        if(APPLE)
            set(${LIBRARY}_${COMPONENT_NAME}_LIBRARY ${CMAKE_BINARY_DIR}/lib/lib${COMPONENT}.dylib)
        endif()
    else()

        find_library(
            ${LIBRARY}_${COMPONENT_NAME}_LIBRARY
            NAMES ${COMPONENT}          ${COMPONENT_LOWER}          ${COMPONENT_UPPER} 
                  ${COMPONENT_STRIPPED} ${COMPONENT_LOWER_STRIPPED} ${COMPONENT_UPPER_STRIPPED}
            PATHS ${_LIBRARY_PATHS}
            HINTS 
                 ${LIBRARY_HINTS}
            PATH_SUFFIXES lib/${PATH_SUFFIX} lib64/${PATH_SUFFIX}
            NO_DEFAULT_PATH
        )

        # If not found, try to find the library with default path
        if(NOT ${LIBRARY}_${COMPONENT_NAME}_LIBRARY)
                
            find_library(
                ${LIBRARY}_${COMPONENT_NAME}_LIBRARY
                NAMES ${COMPONENT}          ${COMPONENT_LOWER}          ${COMPONENT_UPPER} 
                    ${COMPONENT_STRIPPED} ${COMPONENT_LOWER_STRIPPED} ${COMPONENT_UPPER_STRIPPED}
                PATHS ${_LIBRARY_PATHS}
                HINTS 
                    ${LIBRARY_HINTS}
                PATH_SUFFIXES lib/${PATH_SUFFIX} lib64/${PATH_SUFFIX}
            )

        endif()

    endif()
endfunction()

function(find_multiarch_triplet OUT_VAR)
  execute_process(
    COMMAND ${CMAKE_C_COMPILER} -print-multiarch
    OUTPUT_VARIABLE _triplet
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
  )

  if(NOT _triplet OR _triplet STREQUAL "")
    string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" _arch)
    set(_triplet "${_arch}-linux-gnu")
  endif()

  set(${OUT_VAR} "${_triplet}" PARENT_SCOPE)
endfunction()

function(find_package_standard)

    # Parse expected arguments and extract expected library headers 
    set(options "HEADER_FILE_ONLY")
    set(oneValueArgs "")
    set(multiValueArgs NAMES HEADERS HINTS PATHS PATH_SUFFIXES OPTIONALS LIBRARY_PATHS INCLUDE_PATHS)
    cmake_parse_arguments(LIBRARY "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    # Extract package name from basename
    list(LENGTH LIBRARY_UNPARSED_ARGUMENTS ARGC)
    if(ARGC GREATER 0)
        list(GET LIBRARY_UNPARSED_ARGUMENTS 0 LIBRARY)
    else()
        get_filename_component(FILE_NAME ${CMAKE_CURRENT_LIST_FILE} NAME_WE)
        if(${FILE_NAME} MATCHES "^Find(.+)$")
            set(LIBRARY ${CMAKE_MATCH_1})
        elseif(${FILE_NAME} MATCHES "^(.+)-config$")
            set(LIBRARY ${CMAKE_MATCH_1})
        elseif(${FILE_NAME} MATCHES "^(.+)Config$")
            set(LIBRARY ${CMAKE_MATCH_1})
        else()
            message(WARNING "Library name cannot be extracted from `${CMAKE_CURRENT_LIST_FILE}`.")
        endif()
    endif()

    if(NOT LIBRARY)
        message(FATAL_ERROR "Unable to extract LIBRARY variable name")
    endif()

    if (${LIBRARY}_FOUND)
        return()
    endif()

    # Prepare include and library file location variables    
    set(_LIBRARY_PATHS)
    set(_INCLUDE_PATHS)

    find_multiarch_triplet(MULTIARCH)
    if(DEFINED ENV{CMAKE_PREFIX_PATH})
        string(REPLACE ":" ";" CMAKE_PREFIX_PATH_LIST "$ENV{CMAKE_PREFIX_PATH}")
        foreach(PATH IN LISTS CMAKE_PREFIX_PATH_LIST)
            list(APPEND _LIBRARY_PATHS "${PATH}/lib" "${PATH}/lib64")
            list(APPEND _INCLUDE_PATHS "${PATH}/include")
        endforeach()
    endif()

    foreach(PATH ${PATHS})
        list(APPEND _LIBRARY_PATHS "${PATH}/lib" "${PATH}/lib64")
        list(APPEND _INCLUDE_PATHS "${PATH}/include")
    endforeach()

    foreach(HINT ${HINTS})
        list(APPEND _LIBRARY_PATHS "${HINT}/lib" "${HINT}/lib64" "${HINT}")
        list(APPEND _INCLUDE_PATHS "${HINT}/include" "${HINT}")
    endforeach()

    list(APPEND _LIBRARY_PATHS ${LIBRARY_PATHS})
    list(APPEND _INCLUDE_PATHS ${INCLUDE_PATHS})

    # Append paths based on root library directory information
    list(APPEND LIBRARY_DIR "${LIBRARY_NAMES}" "${LIBRARY}")
    foreach(_PATH IN LISTS _LIBRARY_PATHS)
        if(EXISTS "${_PATH}/${MULTIARCH}")
            list(APPEND _LIBRARY_PATHS "${_PATH}/${MULTIARCH}")
        endif()
    endforeach()

    foreach(LIBRARY_NAME IN LISTS LIBRARY_DIR)

        if(NOT LIBRARY_NAME)
            CONTINUE()
        endif()

        string(TOUPPER ${LIBRARY_NAME} LIBRARY_NAME_UPPER)
        string(TOLOWER ${LIBRARY_NAME} LIBRARY_NAME_LOWER)

        # Initialize the list with the required paths for both LIBRARY (lowercase, original, and uppercase)
        list(APPEND _PATHS 
            "${${LIBRARY_NAME}_DIR}"        "$ENV{${LIBRARY_NAME}_DIR}"
            "${${LIBRARY_NAME}}"            "$ENV{${LIBRARY_NAME}}"
            "${${LIBRARY_NAME_UPPER}_DIR}"  "$ENV{${LIBRARY_NAME_UPPER}_DIR}"
            "${${LIBRARY_NAME_UPPER}}"      "$ENV{${LIBRARY_NAME_UPPER}}"    
            "${${LIBRARY_NAME_LOWER}_DIR}"  "$ENV{${LIBRARY_NAME_LOWER}_DIR}"
            "${${LIBRARY_NAME_LOWER}}"      "$ENV{${LIBRARY_NAME_LOWER}}"    
        )
    endforeach()

    if(CMAKE_BUILD_WITH_INSTALL_RPATH)
        foreach(RPATH IN LISTS CMAKE_BUILD_RPATH)
            list(APPEND _PATHS "${RPATH}")
        endforeach()
    endif()

    list(REMOVE_ITEM _PATHS "")
    list(REMOVE_DUPLICATES _PATHS)

    # Loop over LD_LIBRARY_PATH or DYLD_LIBRARY_PATH and add ../ paths
    if(APPLE)
        if(DEFINED ENV{DYLD_LIBRARY_PATH})
            string(REPLACE ":" ";" DYLD_LIBRARY_PATH_LIST "$ENV{DYLD_LIBRARY_PATH}")
            foreach(DYLD_PATH IN LISTS DYLD_LIBRARY_PATH_LIST)
                list(APPEND _PATHS "${DYLD_PATH}/../")
            endforeach()
        endif()
    else()
        if(DEFINED ENV{LD_LIBRARY_PATH})
            string(REPLACE ":" ";" LD_LIBRARY_PATH_LIST "$ENV{LD_LIBRARY_PATH}")
            foreach(LD_PATH IN LISTS LD_LIBRARY_PATH_LIST)
                list(APPEND _PATHS "${LD_PATH}/../")
            endforeach()
        endif()
    endif()

    # Iterate over the existing LIBRARY_PATHS list
    foreach(_PATH ${_PATHS})
        
        get_filename_component(RESOLVED_PATH "${_PATH}/lib" REALPATH)
        if(EXISTS "${RESOLVED_PATH}")
            list(APPEND _LIBRARY_PATHS "${RESOLVED_PATH}")
        endif()
        
        get_filename_component(RESOLVED_PATH "${_PATH}/../lib" REALPATH)
        if(EXISTS "${RESOLVED_PATH}")
            list(APPEND _LIBRARY_PATHS "${RESOLVED_PATH}")
        endif()

        get_filename_component(RESOLVED_PATH "${_PATH}/../lib64" REALPATH)
        if(EXISTS "${RESOLVED_PATH}")
            list(APPEND _LIBRARY_PATHS "${RESOLVED_PATH}")
        endif()
    endforeach()

    # Merge with LD_LIBRARY_PATH and DYLD_LIBRARY_PATH (lower priority)
    if (APPLE)
        set(_LIBRARY_PATH $ENV{DYLD_LIBRARY_PATH} ${DYLD_LIBRARY_PATH})
    else()
        set(_LIBRARY_PATH $ENV{LD_LIBRARY_PATH} ${LD_LIBRARY_PATH})
    endif()

    string(REPLACE ":" ";" _LIBRARY_PATH_LIST "${_LIBRARY_PATH}")
    list(APPEND _LIBRARY_PATHS ${_LIBRARY_PATH_LIST})
    foreach(PATH ${_LIBRARY_PATHS})
        get_filename_component(ABS_PATH "${PATH}" REALPATH)
        list(APPEND RESOLVED_PATHS "${ABS_PATH}")
    endforeach()
    set(_LIBRARY_PATHS ${RESOLVED_PATHS})
    list(REMOVE_ITEM _LIBRARY_PATHS "")
    list(REMOVE_DUPLICATES _LIBRARY_PATHS)

    foreach(LIBRARY_PATH ${_LIBRARY_PATHS})
        if(NOT "${LIBRARY_PATH}/include" MATCHES "/lib/include$" AND NOT "${LIBRARY_PATH}/include" MATCHES "/lib64/include$")
            list(APPEND _INCLUDE_PATHS "${LIBRARY_PATH}/include")
        endif()
        if(NOT "${LIBRARY_PATH}" MATCHES "/lib$" AND NOT "${LIBRARY_PATH}" MATCHES "/lib64$")
            list(APPEND _INCLUDE_PATHS "${LIBRARY_PATH}")
        endif()
        if(NOT "${LIBRARY_PATH}/../include" MATCHES "/include/../include$")
            list(APPEND _INCLUDE_PATHS "${LIBRARY_PATH}/../include")
        endif()
    endforeach()
    
    set(RESOLVED_PATHS)
    foreach(PATH ${_INCLUDE_PATHS})
        get_filename_component(ABS_PATH "${PATH}" REALPATH)
        list(APPEND RESOLVED_PATHS "${ABS_PATH}")
    endforeach()

    set(_INCLUDE_PATHS ${RESOLVED_PATHS})
    list(REMOVE_ITEM _INCLUDE_PATHS "")
    list(REMOVE_DUPLICATES _INCLUDE_PATHS)

    # Looking for library headers
    if(LIBRARY_HEADERS)
        find_custom_path(${LIBRARY} _INCLUDE_PATHS)
    endif()

    # Looking for library version
    set(${LIBRARY}_VERSION "0.0.0")
    foreach(LIBRARY_HEADER ${LIBRARY_HEADERS})

        if("${${LIBRARY}_VERSION}" STREQUAL "0.0.0" AND EXISTS ${LIBRARY_HEADER})

            file(READ "${LIBRARY_HEADER}" LIBRARY_HEADER_CONTENTS)

            string(REGEX MATCH "#define [^ ]*VERSION_MAJOR ([0-9]+)" VERSION_MAJOR_MATCH "${LIBRARY_HEADER_CONTENTS}")
            if(VERSION_MAJOR_MATCH)
                set(${LIBRARY}_VERSION_MAJOR ${CMAKE_MATCH_1})
            else()
                set(${LIBRARY}_VERSION_MAJOR 0)
            endif()

            string(REGEX MATCH "#define [^ ]*VERSION_MINOR ([0-9]+)" VERSION_MINOR_MATCH "${LIBRARY_HEADER_CONTENTS}")
            if(VERSION_MINOR_MATCH)
                set(${LIBRARY}_VERSION_MINOR ${CMAKE_MATCH_1})
            else()
                set(${LIBRARY}_VERSION_MINOR 0)
            endif()
            
            string(REGEX MATCH "#define [^ ]*VERSION_PATCH ([0-9]+)" VERSION_PATCH_MATCH "${LIBRARY_HEADER_CONTENTS}")
            if(VERSION_PATCH_MATCH)
                set(${LIBRARY}_VERSION_PATCH ${CMAKE_MATCH_1})
            else()
                set(${LIBRARY}_VERSION_PATCH 0)
            endif()

            string(REGEX MATCH "#define [^ ]*VERSION_TWEAK ([0-9]+)" VERSION_TWEAK_MATCH "${LIBRARY_HEADER_CONTENTS}")
            if(VERSION_TWEAK_MATCH)
                set(${LIBRARY}_VERSION_TWEAK ${CMAKE_MATCH_1})
            else()
                set(${LIBRARY}_VERSION_TWEAK 0)
            endif()

            string(REGEX MATCH "#define [^ ]*VERSION_COUNT([0-9]+)" VERSION_COUNT_MATCH "${LIBRARY_HEADER_CONTENTS}")
            if(VERSION_COUNT_MATCH)
                set(${LIBRARY}_VERSION_COUNT ${CMAKE_MATCH_1})
            else()
                set(${LIBRARY}_VERSION_COUNT 0)
            endif()
            if(${LIBRARY}_VERSION_COUNT GREATER 4)
                set(${LIBRARY}_VERSION_COUNT 4)
            endif()

            string(REGEX MATCH "#define [^ ]*VERSION ([0-9]+)" VERSION_MATCH "${LIBRARY_HEADER_CONTENTS}")
            if(VERSION_MATCH)
                set(${LIBRARY}_VERSION ${CMAKE_MATCH_1})
            else()
                set(${LIBRARY}_VERSION "${${LIBRARY}_VERSION_MAJOR}.${${LIBRARY}_VERSION_MINOR}.${${LIBRARY}_VERSION_PATCH}")
            endif()

        endif()

    endforeach()

    if("${${LIBRARY}_VERSION}" STREQUAL "0.0.0")
        set(${LIBRARY}_VERSION "")
    endif()

    # Look for libraries
    if(NOT LIBRARY_HEADER_FILE_ONLY)

        set(COMPONENTS)
        if(NOT DEFINED ${LIBRARY}_LIBRARIES)

            foreach(COMPONENT IN LISTS LIBRARY_NAMES)

                parse_component_suffix(${COMPONENT} _COMPONENT_NAME COMPONENT_SUFFIX_PATH)
                parse_component_alternatives(${_COMPONENT_NAME} _COMPONENT_NAME _ALTERNATIVES)

                if(NOT DEFINED ${_COMPONENT_NAME}_ALTERNATIVES)
                    set(${_COMPONENT_NAME}_ALTERNATIVES)
                endif()
                foreach(ALTERNATIVE IN LISTS _ALTERNATIVES)
                    list(APPEND ${_COMPONENT_NAME}_ALTERNATIVES ${ALTERNATIVE})
                endforeach()
                list(REMOVE_DUPLICATES ${_COMPONENT_NAME}_ALTERNATIVES)

                find_library_component(${LIBRARY} ${_COMPONENT_NAME} ${COMPONENT} "${COMPONENT_SUFFIX_PATH}")
                list(APPEND ${LIBRARY}_LIBRARIES ${${LIBRARY}_${_COMPONENT_NAME}_LIBRARY})
            endforeach()

            foreach(COMPONENT IN LISTS LIBRARY_OPTIONALS)

                parse_component_suffix(${COMPONENT} _COMPONENT_NAME COMPONENT_SUFFIX_PATH)
                parse_component_alternatives(${_COMPONENT_NAME} _COMPONENT_NAME ${_COMPONENT_NAME}_ALTERNATIVES)
                foreach(ALTERNATIVE IN LISTS ${_COMPONENT_NAME}_ALTERNATIVES)
                    find_library_component(${LIBRARY} ${_COMPONENT_NAME} ${ALTERNATIVE} "${COMPONENT_SUFFIX_PATH}")
                    if(${LIBRARY}_${_COMPONENT_NAME}_LIBRARY)
                        break() # If found, stop looking for alternatives
                    endif()
                endforeach()

                if(NOT ${LIBRARY}_${_COMPONENT_NAME}_LIBRARY)
                    find_library_component(${LIBRARY} ${_COMPONENT_NAME} ${_COMPONENT_NAME} "${COMPONENT_SUFFIX_PATH}")
                endif()
                unset(${_COMPONENT_NAME}_ALTERNATIVES)
                
                set(${LIBRARY}_${_COMPONENT_NAME}_FOUND TRUE PARENT_SCOPE)
                set(${LIBRARY}_${_COMPONENT_NAME}_LIBRARY ${${LIBRARY}_${_COMPONENT_NAME}_LIBRARY} PARENT_SCOPE)

                if(${LIBRARY}_${_COMPONENT_NAME}_LIBRARY)
                    list(APPEND ${LIBRARY}_LIBRARIES ${${LIBRARY}_${_COMPONENT_NAME}_LIBRARY})
                else()
                    unset(${LIBRARY}_${_COMPONENT_NAME}_FOUND PARENT_SCOPE)
                    if(${LIBRARY}_FIND_REQUIRED_${_COMPONENT_NAME} OR (NOT IN_LIST ${LIBRARY}_FIND_COMPONENTS AND NOT ${_COMPONENT_NAME} IN_LIST LIBRARY_OPTIONALS))
                        message(FATAL_ERROR "Component `${_COMPONENT_NAME}` required, but not found for ${LIBRARY}.")
                    endif()
                endif()
            endforeach()

            # Fallback include, in case it was not found in the first place, knowing now subcomponents
            if(NOT ${LIBRARY}_INCLUDE_DIRS AND DEFINED ${LIBRARY}_LIBRARIES)
                find_custom_path(${LIBRARY} _INCLUDE_PATHS)
            endif()

            if(TARGET ${LIBRARY})

                set(${LIBRARY}_FOUND TRUE)
                set(${LIBRARY}_INCLUDE_DIR ${CMAKE_BINARY_DIR}/include)
                set(${LIBRARY}_INCLUDE_DIRS ${CMAKE_BINARY_DIR}/include)

            elseif(NOT DEFINED ${LIBRARY}_FOUND)

                # Provide information about how to use the library
                include(FindPackageHandleStandardArgs)
                if(NOT ${LIBRARY}_VERSION)
                    find_package_handle_standard_args(${LIBRARY}
                        FOUND_VAR ${LIBRARY}_FOUND
                        REQUIRED_VARS ${LIBRARY}_LIBRARIES ${LIBRARY}_INCLUDE_DIRS
                    )
                else()
                    find_package_handle_standard_args(${LIBRARY}
                        FOUND_VAR ${LIBRARY}_FOUND
                        REQUIRED_VARS ${LIBRARY}_LIBRARIES ${LIBRARY}_INCLUDE_DIRS
                        VERSION_VAR "${LIBRARY}_VERSION"
                        HANDLE_VERSION_RANGE
                    )
                endif()

                if (NOT ${LIBRARY}_FOUND)
                    set(${LIBRARY}_FOUND FALSE CACHE BOOL "Library found with header only")
                endif()
            endif()
        endif()

    elseif(${LIBRARY}_INCLUDE_DIRS)

        if (NOT DEFINED ${LIBRARY}_FOUND AND NOT ${LIBRARY}_FOUND)
            set(${LIBRARY}_FOUND TRUE CACHE BOOL "Library found with header only")
            message(STATUS "FOUND ${LIBRARY}: ${${LIBRARY}_INCLUDE_DIRS} (header only)")
        endif()

    else()

        if (NOT DEFINED ${LIBRARY}_FOUND AND NOT ${LIBRARY}_FOUND)
            set(${LIBRARY}_FOUND FALSE CACHE BOOL "Library found with header only")
            message(STATUS "Could NOT find ${LIBRARY} (missing: ${LIBRARY}_INCLUDE_DIRS; header only)")
        endif()

    endif()

    # Pass the variables back to the parent scope
    if(${LIBRARY}_FOUND)
        set(${LIBRARY}_FOUND ${${LIBRARY}_FOUND} PARENT_SCOPE)
    elseif(MY_REQUIRED)

        set(${LIBRARY}_STATUS "")
        if(NOT ${LIBRARY}_INCLUDE_DIRS)
            set(${LIBRARY}_STATUS "${${LIBRARY}_STATUS}${LIBRARY}_INCLUDE_DIRS ")
        endif()
        if(NOT ${LIBRARY}_LIBRARIES AND NOT LIBRARY_HEADER_FILE_ONLY)
            set(${LIBRARY}_STATUS "${${LIBRARY}_STATUS} ${LIBRARY}_LIBRARIES")
        endif()
        
        if(${LIBRARY}_STATUS)
            set(${LIBRARY}_STATUS "Missing variable(s): ${${LIBRARY}_STATUS}")
        endif()
        
        message(FATAL_ERROR "Library ${LIBRARY} is required, but not found; ${${LIBRARY}_STATUS}")
    endif()

    list(LENGTH ${LIBRARY}_LIBRARIES ${LIBRARY}_LIBRARIES_LENGTH)
    if(${LIBRARY}_LIBRARIES_LENGTH EQUAL 0)

        # Use ${LIBRARY}_INCLUDE_DIRS to determine ${LIBRARY}_DIR
        if(${LIBRARY}_INCLUDE_DIRS)
            list(GET ${LIBRARY}_INCLUDE_DIRS 0 ${LIBRARY}_INCLUDE_DIR)
            get_filename_component(${LIBRARY}_DIR "${${LIBRARY}_INCLUDE_DIR}" PATH)
        endif()

    else()

        list(GET ${LIBRARY}_LIBRARIES 0 ${LIBRARY}_LIBRARY)

        get_filename_component(${LIBRARY}_LIBRARY_PATH "${${LIBRARY}_LIBRARY}" PATH)
        get_filename_component(${LIBRARY}_LIBRARY_PARENT_PATH "${${LIBRARY}_LIBRARY_PATH}" PATH)
        if(${LIBRARY}_LIBRARY_PATH MATCHES "lib|lib32|lib64")
            set(${LIBRARY}_DIR "${${LIBRARY}_LIBRARY_PARENT_PATH}")
        endif()
    endif()

    list(REMOVE_DUPLICATES ${LIBRARY}_LIBRARIES)
    set(${LIBRARY}_LIBRARY ${${LIBRARY}_LIBRARY} PARENT_SCOPE)
    set(${LIBRARY}_INCLUDE_DIR ${${LIBRARY}_INCLUDE_DIR} PARENT_SCOPE)
    set(${LIBRARY}_DIR ${${LIBRARY}_DIR} PARENT_SCOPE)

    set(${LIBRARY}_LIBRARIES    ${${LIBRARY}_LIBRARIES} PARENT_SCOPE)
    set(${LIBRARY}_INCLUDE_DIR  ${${LIBRARY}_INCLUDE_DIR} PARENT_SCOPE)
    set(${LIBRARY}_INCLUDE_DIRS ${${LIBRARY}_INCLUDE_DIRS} PARENT_SCOPE)
    set(${LIBRARY}_VERSION ${${LIBRARY}_VERSION} PARENT_SCOPE)
    set(${LIBRARY}_VERSION_MAJOR ${${LIBRARY}_VERSION_MAJOR} PARENT_SCOPE)
    set(${LIBRARY}_VERSION_MINOR ${${LIBRARY}_VERSION_MINOR} PARENT_SCOPE)
    set(${LIBRARY}_VERSION_PATCH ${${LIBRARY}_VERSION_PATCH} PARENT_SCOPE)
    set(${LIBRARY}_VERSION_TWEAK ${${LIBRARY}_VERSION_TWEAK} PARENT_SCOPE)
    set(${LIBRARY}_VERSION_COUNT ${${LIBRARY}_VERSION_COUNT} PARENT_SCOPE)

    # Remove cache variables
    if(DEFINED ${LIBRARY}_DIR)
        unset(${LIBRARY}_DIR CACHE)
    endif()

    if(DEFINED ${LIBRARY}_LIBRARY)
        unset(${LIBRARY}_LIBRARY CACHE)
    endif()

    if(DEFINED ${LIBRARY}_LIBRARIES)
        unset(${LIBRARY}_LIBRARIES CACHE)
    endif()

    if(DEFINED ${LIBRARY}_INCLUDE_DIR)
        unset(${LIBRARY}_INCLUDE_DIR CACHE)
    endif()
    
    if(DEFINED ${LIBRARY}_INCLUDE_DIRS)
        unset(${LIBRARY}_INCLUDE_DIRS CACHE)
    endif()

endfunction()

macro(target_link_package)

    # Parse expected arguments
    set(options EXACT QUIET REQUIRED CONFIG NO_MODULE GLOBAL NO_POLICY_SCOPE BYPASS_PROVIDER
                NO_DEFAULT_PATH NO_PACKAGE_ROOT_PATH NO_CMAKE_PATH NO_CMAKE_ENVIRONMENT_PATH
                NO_SYSTEM_ENVIRONMENT_PATH NO_CMAKE_PACKAGE_REGISTRY NO_CMAKE_BUILDS_PATH
                NO_CMAKE_SYSTEM_PATH NO_CMAKE_INSTALL_PREFIX NO_CMAKE_SYSTEM_PACKAGE_REGISTRY
                CMAKE_FIND_ROOT_PATH_BOTH ONLY_CMAKE_FIND_ROOT_PATH NO_CMAKE_FIND_ROOT_PATH PRIVATE PUBLIC INTERFACE)

    set(oneValueArgs NAMES REGISTRY_VIEW DESTINATION RENAME)

    set(multiValueArgs COMPONENTS OPTIONAL_COMPONENTS CONFIGS HINTS PATHS PATH_SUFFIXES TARGETS CONFIGURATIONS)

    cmake_parse_arguments(MY "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    # Check mandatory and optional unparsed aguments
    list(LENGTH MY_UNPARSED_ARGUMENTS ARGC)
    if(ARGC LESS 1)
        message(FATAL_ERROR "target_link_package: Please provide at least TARGET_NAME and PACKAGE_NAME.")
    elseif(ARGC LESS 2)
        message(FATAL_ERROR "target_link_package: Please provide PACKAGE_NAME.")
    else()
    
        list(GET MY_UNPARSED_ARGUMENTS 0 MY_TARGET_NAME)
        list(GET MY_UNPARSED_ARGUMENTS 1 MY_PACKAGE_NAME)
        if(ARGC GREATER 2)
            list(GET MY_UNPARSED_ARGUMENTS 2 MY_VERSION)
        endif()
    endif()

    # Prepare find_package arguments
    set(ARGS)
    if(MY_EXACT)
        list(APPEND ARGS EXACT)
    endif()
    if(MY_QUIET)
        list(APPEND ARGS QUIET)
    endif()
    if(MY_REQUIRED)
        list(APPEND ARGS REQUIRED ${ENDIF_MY_REQUIRED})
    endif()
    if(MY_CONFIG)
        list(APPEND ARGS CONFIG ${ENDIF_MY_CONFIG})
    endif()
    if(MY_NO_MODULE)
        list(APPEND ARGS NO_MODULE ${ENDIF_MY_NO_MODULE})
    endif()
    if(MY_GLOBAL)
        list(APPEND ARGS GLOBAL ${ENDIF_MY_GLOBAL})
    endif()
    if(MY_NO_POLICY_SCOPE)
        list(APPEND ARGS NO_POLICY_SCOPE ${ENDIF_MY_NO_POLICY_SCOPE})
    endif()
    if(MY_BYPASS_PROVIDER)
        list(APPEND ARGS BYPASS_PROVIDER ${ENDIF_MY_BYPASS_PROVIDER})
    endif()
    if(MY_NO_DEFAULT_PATH)
        list(APPEND ARGS NO_DEFAULT_PATH ${ENDIF_MY_NO_DEFAULT_PATH})
    endif()
    if(MY_NO_PACKAGE_ROOT_PATH)
        list(APPEND ARGS NO_PACKAGE_ROOT_PATH ${ENDIF_MY_NO_PACKAGE_ROOT_PATH})
    endif()
    if(MY_NO_CMAKE_PATH)
        list(APPEND ARGS NO_CMAKE_PATH ${ENDIF_MY_NO_CMAKE_PATH})
    endif()
    if(MY_NO_CMAKE_ENVIRONMENT_PATH)
        list(APPEND ARGS NO_CMAKE_ENVIRONMENT_PATH ${ENDIF_MY_NO_CMAKE_ENVIRONMENT_PATH})
    endif()
    if(MY_NO_SYSTEM_ENVIRONMENT_PATH)
        list(APPEND ARGS NO_SYSTEM_ENVIRONMENT_PATH ${ENDIF_MY_NO_SYSTEM_ENVIRONMENT_PATH})
    endif()
    if(MY_NO_CMAKE_PACKAGE_REGISTRY)
        list(APPEND ARGS NO_CMAKE_PACKAGE_REGISTRY ${ENDIF_MY_NO_CMAKE_PACKAGE_REGISTRY})
    endif()
    if(MY_NO_CMAKE_BUILDS_PATH)
        list(APPEND ARGS NO_CMAKE_BUILDS_PATH ${ENDIF_MY_NO_CMAKE_BUILDS_PATH})
    endif()
    if(MY_NO_CMAKE_SYSTEM_PATH)
        list(APPEND ARGS NO_CMAKE_SYSTEM_PATH ${ENDIF_MY_NO_CMAKE_SYSTEM_PATH})
    endif()
    if(MY_NO_CMAKE_INSTALL_PREFIX)
        list(APPEND ARGS NO_CMAKE_INSTALL_PREFIX ${ENDIF_MY_NO_CMAKE_INSTALL_PREFIX})
    endif()
    if(MY_NO_CMAKE_SYSTEM_PACKAGE_REGISTRY)
        list(APPEND ARGS NO_CMAKE_SYSTEM_PACKAGE_REGISTRY ${ENDIF_MY_NO_CMAKE_SYSTEM_PACKAGE_REGISTRY})
    endif()
    if(MY_CMAKE_FIND_ROOT_PATH_BOTH)
        list(APPEND ARGS CMAKE_FIND_ROOT_PATH_BOTH ${ENDIF_MY_CMAKE_FIND_ROOT_PATH_BOTH})
    endif()
    if(MY_ONLY_CMAKE_FIND_ROOT_PATH)
        list(APPEND ARGS ONLY_CMAKE_FIND_ROOT_PATH ${ENDIF_MY_ONLY_CMAKE_FIND_ROOT_PATH})
    endif()
    if(MY_NO_CMAKE_FIND_ROOT_PATH)
        list(APPEND ARGS NO_CMAKE_FIND_ROOT_PATH ${ENDIF_MY_NO_CMAKE_FIND_ROOT_PATH})
    endif()

    if(MY_COMPONENTS)
        list(APPEND ARGS COMPONENTS ${MY_COMPONENTS})
    endif()
    if(MY_OPTIONAL_COMPONENTS)
        list(APPEND ARGS OPTIONAL_COMPONENTS ${MY_OPTIONAL_COMPONENTS})
    endif()
    if(MY_CONFIGS)
        list(APPEND ARGS CONFIGS ${MY_CONFIGS})
    endif()
    if(MY_HINTS)
        list(APPEND ARGS HINTS ${MY_HINTS})
    endif()
    if(MY_PATHS)
        list(APPEND ARGS PATHS ${MY_PATHS})
    endif()
    if(MY_PATH_SUFFIXES)
        list(APPEND ARGS PATH_SUFFIXES ${MY_PATH_SUFFIXES})
    endif()
    if(MY_TARGETS)
        list(APPEND ARGS TARGETS ${MY_TARGETS})
    endif()
    if(MY_CONFIGURATIONS)
        list(APPEND ARGS CONFIGURATIONS ${MY_CONFIGURATIONS})
    endif()

    if(NOT "${MY_REGISTRY_VIEW}" STREQUAL "")
        list(APPEND ARGS REGISTRY_VIEW "${MY_REGISTRY_VIEW}")
    endif()
    if(NOT "${MY_DESTINATION}" STREQUAL "")
        list(APPEND ARGS DESTINATION "${MY_DESTINATION}")
    endif()
    if(NOT "${MY_RENAME}" STREQUAL "")
        list(APPEND ARGS RENAME "${MY_RENAME}")
    endif()

    # Call find package
    if(TARGET ${MY_PACKAGE_NAME})
        target_link_libraries(${MY_TARGET_NAME} PUBLIC ${MY_PACKAGE_NAME})
    else()

        # Load library if not found
        if (NOT ${MY_PACKAGE_NAME}_FOUND)
            find_package(${MY_PACKAGE_NAME} ${ARGS})
        endif()

        # Make connection between target and package
        if (${MY_PACKAGE_NAME}_FOUND)
            
            # Create an INTERFACE wrapper then it should hide the warnings
            add_library(${MY_TARGET_NAME}_${MY_PACKAGE_NAME}_WRAPPER INTERFACE)
            target_link_libraries(${MY_TARGET_NAME}_${MY_PACKAGE_NAME}_WRAPPER INTERFACE ${${MY_PACKAGE_NAME}_LIBRARIES})
            target_compile_options(${MY_TARGET_NAME}_${MY_PACKAGE_NAME}_WRAPPER INTERFACE -w) # Hide warnings (this is linked libraries, this is not our responsibility)

            if (MY_PRIVATE)
                set(LINK_TYPE "PRIVATE")
                target_include_directories(${MY_TARGET_NAME}_${MY_PACKAGE_NAME}_WRAPPER INTERFACE ${${MY_PACKAGE_NAME}_INCLUDE_DIRS})
                target_link_libraries(${MY_TARGET_NAME} PRIVATE ${MY_TARGET_NAME}_${MY_PACKAGE_NAME}_WRAPPER)
            elseif (MY_INTERFACE)
                set(LINK_TYPE "INTERFACE")
                target_include_directories(${MY_TARGET_NAME} INTERFACE ${${MY_PACKAGE_NAME}_INCLUDE_DIRS})
                target_link_libraries(${MY_TARGET_NAME} INTERFACE ${MY_TARGET_NAME}_${MY_PACKAGE_NAME}_WRAPPER)
            else()
                set(LINK_TYPE "PUBLIC")
                target_include_directories(${MY_TARGET_NAME} PUBLIC ${${MY_PACKAGE_NAME}_INCLUDE_DIRS})
                target_link_libraries(${MY_TARGET_NAME} PUBLIC ${MY_TARGET_NAME}_${MY_PACKAGE_NAME}_WRAPPER)
            endif()

            # Only print message if LINK_TYPE is changed
            if (NOT DEFINED ${MY_PACKAGE_NAME}_LINK_TYPE)
                set(${MY_PACKAGE_NAME}_LINK_TYPE ${LINK_TYPE} CACHE STRING "Link type for ${MY_PACKAGE_NAME}")
                message(STATUS "Library ${MY_PACKAGE_NAME} will be linked as ${LINK_TYPE} into ${MY_TARGET_NAME}")
            elseif (${MY_PACKAGE_NAME}_LINK_TYPE STREQUAL ${LINK_TYPE})
                # No change, skip the message
            else()
                set(${MY_PACKAGE_NAME}_LINK_TYPE ${LINK_TYPE} CACHE STRING "Link type for ${MY_PACKAGE_NAME}")
                message(STATUS "Library ${MY_PACKAGE_NAME} will be linked as ${LINK_TYPE} into ${MY_TARGET_NAME}")
            endif()

        endif()

    endif()

endmacro()
