# Include custom standard package
list(PREPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_LIST_DIR})
include(FindPackageStandard)

# Load using standard package finder
find_package_standard(
  NAMES inih INIReader
  HEADERS "ini.h" "INIReader.h"
  PATHS ${LIBINIH} $ENV{LIBINIH}
)