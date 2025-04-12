# Include custom standard package
list(PREPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_LIST_DIR}/../Modules)
include(FindPackageStandard)

# Load using standard package finder
find_package_standard(
  NAMES curl
  HEADERS "curl/curl.h"
  PATHS ${LIBCURL} $ENV{LIBCURL}
)