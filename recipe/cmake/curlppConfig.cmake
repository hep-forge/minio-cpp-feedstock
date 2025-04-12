# Include custom standard package
list(PREPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_LIST_DIR})
include(FindPackageStandard)

# Load using standard package finder
find_package_standard(
  NAMES curlpp
  HEADERS "curlpp/Easy.hpp"
  PATHS ${LIBCURLPP} $ENV{LIBCURLPP}
)

if(curlpp_FOUND)

  find_package(curl REQUIRED)

  get_filename_component(FILE_NAME ${CMAKE_CURRENT_LIST_FILE} NAME_WE)
  if(${FILE_NAME} MATCHES "^Find(.+)$")
    set(FINDER ${CMAKE_MATCH_1})
  elseif(${FILE_NAME} MATCHES "^(.+)Config$")
    set(FINDER ${CMAKE_MATCH_1})
  elseif(${FILE_NAME} MATCHES "^(.+)-config$")
    set(FINDER ${CMAKE_MATCH_1})
  endif()

  if(FINDER AND ${FINDER}_FOUND)
        set(${FINDER}_INCLUDE_DIRS "${${FINDER}_INCLUDE_DIRS}" "${curl_INCLUDE_DIRS}")
        set(${FINDER}_LIBRARIES "${${FINDER}_LIBRARIES}" "${curl_LIBRARIES}")
  endif()
endif()
