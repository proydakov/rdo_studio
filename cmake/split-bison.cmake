#==============================================================================
# Copyright (c) 2013 Alexandrovsky Kirill <k.alexandrovsky@gmail.com>
#==============================================================================

MACRO(RDO_SPLIT_BISON_TARGET INPUT_FILE Y_1 Y_2)

    SET(${INPUT_FILE}_INPUT ${GRAMMA_INPUT_PATH}/rdo${INPUT_FILE}.yx)

    SET(BISON_${FILE_TYPE}_INPUT_1 ${CMAKE_CURRENT_BINARY_DIR}/rdo${Y_1}.y)
    SET(BISON_${FILE_TYPE}_INPUT_2 ${CMAKE_CURRENT_BINARY_DIR}/rdo${Y_2}.y)

    SET(${INPUT_FILE}_PASS1 ${CMAKE_CURRENT_BINARY_DIR}/rdo${Y_1}.y)
    SET(${INPUT_FILE}_PASS2 ${CMAKE_CURRENT_BINARY_DIR}/rdo${Y_2}.y)

    SET(CPP_OUTPUT_FILE_1 ${CMAKE_CURRENT_BINARY_DIR}/rdogram${Y_1}.cpp)
    SET(CPP_OUTPUT_FILE_2 ${CMAKE_CURRENT_BINARY_DIR}/rdogram${Y_2}.cpp)

    IF(MSVC)
        SET_SOURCE_FILES_PROPERTIES(${CMAKE_CURRENT_BINARY_DIR}/rdogram${Y_1}.cpp PROPERTIES COMPILE_FLAGS "/Od")
        SET_SOURCE_FILES_PROPERTIES(${CMAKE_CURRENT_BINARY_DIR}/rdogram${Y_2}.cpp PROPERTIES COMPILE_FLAGS "/Od")
    ENDIF()

    SET(BISON_${INPUT_FILE}_OUTPUTS_1 ${CPP_OUTPUT_FILE_1})
    SET(BISON_${INPUT_FILE}_OUTPUTS_2 ${CPP_OUTPUT_FILE_2})

    SET(OUTPUT_FILE ${CPP_OUTPUT_FILE_1})
    LIST(APPEND OUTPUT_FILE ${CPP_OUTPUT_FILE_2})

    LIST(APPEND OUTPUT_FILE ${CMAKE_CURRENT_BINARY_DIR}/rdogram${Y_1}.dot)
    LIST(APPEND OUTPUT_FILE ${CMAKE_CURRENT_BINARY_DIR}/rdogram${Y_1}.output)

    LIST(APPEND OUTPUT_FILE ${CMAKE_CURRENT_BINARY_DIR}/rdogram${Y_2}.dot)
    LIST(APPEND OUTPUT_FILE ${CMAKE_CURRENT_BINARY_DIR}/rdogram${Y_2}.output)

    SET(BISON_DEFINE)
    SET(BISON_${INPUT_FILE}_OUTPUT_HEADER)
    IF(${ARGC} GREATER 4 OR ${ARGC} EQUAL 4)
        SET(BISON_${INPUT_FILE}_OUTPUT_HEADER ${GRAMMA_H})
        SET(BISON_DEFINES -defines)
        SET(BISON_DEFINE ${BISON_${INPUT_FILE}_OUTPUT_HEADER})
        LIST(APPEND OUTPUT_FILE ${BISON_${INPUT_FILE}_OUTPUT_HEADER})
    ENDIF()

    ADD_CUSTOM_COMMAND(
        OUTPUT ${OUTPUT_FILE}
        COMMAND ${PYTHON_EXECUTABLE} ${PROJECT_SOURCE_DIR}/scripts/python/split-bison.py ARGS ${${INPUT_FILE}_INPUT} -y1 ${BISON_${FILE_TYPE}_INPUT_1} -y2 ${BISON_${FILE_TYPE}_INPUT_2}
        COMMAND ${PYTHON_EXECUTABLE} ${PROJECT_SOURCE_DIR}/scripts/python/run-bison.py ARGS ${${INPUT_FILE}_INPUT} -y1 ${BISON_${FILE_TYPE}_INPUT_1} -y2 ${BISON_${FILE_TYPE}_INPUT_2} -o1 ${CPP_OUTPUT_FILE_1} -o2 ${CPP_OUTPUT_FILE_2} -n1 ${Y_1} -n2 ${Y_2} -bison ${BISON_EXECUTABLE}\ -g\ -v ${BISON_DEFINES} ${BISON_DEFINE}
        DEPENDS ${${INPUT_FILE}_INPUT}
        COMMENT "[BISON][rdo${INPUT_FILE}] Building parser with bison ${BISON_VERSION}"
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})

ENDMACRO(RDO_SPLIT_BISON_TARGET)
