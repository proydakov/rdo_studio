#==============================================================================
# Copyright (c) 2012 Evgeny Proydakov <lord.tiran@gmail.com>
#==============================================================================

FILE(GLOB_RECURSE SOURCE_FILES RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} *.cpp)
ADD_BOOST_TEST(test_utils_real_format ${SOURCE_FILES})

ADD_DEPENDENCIES(test_utils_real_format rdo_utils)
TARGET_LINK_LIBRARIES(test_utils_real_format rdo_utils)
