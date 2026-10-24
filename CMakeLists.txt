cmake_minimum_required(VERSION 3.24)

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_BINARY_DIR)
    message(FATAL_ERROR "Use an out-of-source build: cmake -S . -B build")
endif()

set(cwhip_sdk_prefix "$ENV{CWHIP_SDK}")
if(cwhip_sdk_prefix STREQUAL "")
    set(cwhip_config_home "$ENV{XDG_CONFIG_HOME}")
    if(cwhip_config_home STREQUAL "" AND NOT "$ENV{HOME}" STREQUAL "")
        set(cwhip_config_home "$ENV{HOME}/.config")
    endif()
    if(NOT cwhip_config_home STREQUAL "")
        if(NOT IS_ABSOLUTE "${cwhip_config_home}")
            message(FATAL_ERROR
                "Cannot discover sdk_prefix: config home '${cwhip_config_home}' is not absolute")
        endif()
        cmake_path(APPEND cwhip_config_home "cwhip"
            OUTPUT_VARIABLE cwhip_settings_directory)
        cmake_path(NORMAL_PATH cwhip_settings_directory)
        set(cwhip_sdk_settings "${cwhip_settings_directory}/sdk.toml")
        set(cwhip_legacy_settings "${cwhip_settings_directory}/settings.toml")
        # Detect entries without opening them so the parser can report read errors.
        file(GLOB cwhip_settings_entries "${cwhip_settings_directory}/*")
        if("${cwhip_sdk_settings}" IN_LIST cwhip_settings_entries)
            set(cwhip_selected_settings "${cwhip_sdk_settings}")
        elseif("${cwhip_legacy_settings}" IN_LIST cwhip_settings_entries)
            set(cwhip_selected_settings "${cwhip_legacy_settings}")
        endif()
        if(DEFINED cwhip_selected_settings)
            find_package(Python3 3.11 REQUIRED COMPONENTS Interpreter)
            execute_process(
                COMMAND "${Python3_EXECUTABLE}"
                    "${CMAKE_CURRENT_SOURCE_DIR}/scripts/sdk-prefix.py"
                    "${cwhip_selected_settings}"
                RESULT_VARIABLE cwhip_settings_result
                OUTPUT_VARIABLE cwhip_sdk_prefix
                ERROR_VARIABLE cwhip_settings_error)
            if(NOT cwhip_settings_result STREQUAL "0")
                message(FATAL_ERROR "${cwhip_settings_error}")
            endif()
        endif()
    endif()
endif()
if(NOT cwhip_sdk_prefix STREQUAL "")
    message(STATUS "Using Cwhip SDK prefix: ${cwhip_sdk_prefix}")
    unset(Cwhip_DIR CACHE)
    unset(Cwhip_DIR)
    find_package(Cwhip 0.0.1 EXACT CONFIG REQUIRED
        PATHS "${cwhip_sdk_prefix}" NO_DEFAULT_PATH)
else()
    find_package(Cwhip 0.0.1 EXACT CONFIG REQUIRED)
endif()
if(NOT COMMAND cwhip_apply_application_defaults)
    message(FATAL_ERROR
        "Selected Cwhip SDK '${Cwhip_PREFIX}' lacks application-defaults support "
        "(cwhip_apply_application_defaults). Rebuild and reinstall an updated "
        "Cwhip SDK with application-defaults support to this prefix, or select "
        "an updated SDK via CWHIP_SDK, then rerun configuration.")
endif()
cwhip_apply_application_defaults()

project(CwhipDebugger VERSION 0.0.1 LANGUAGES C)

include(GNUInstallDirs)

set(CWHIP_BIN_DIR "${CMAKE_CURRENT_SOURCE_DIR}/bin" CACHE PATH "Application executable directory")
set(CWHIP_LIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/lib" CACHE PATH "Native library directory")
get_filename_component(CWHIP_BIN_DIR "${CWHIP_BIN_DIR}" ABSOLUTE BASE_DIR "${CMAKE_BINARY_DIR}")
get_filename_component(CWHIP_LIB_DIR "${CWHIP_LIB_DIR}" ABSOLUTE BASE_DIR "${CMAKE_BINARY_DIR}")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CWHIP_BIN_DIR}")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CWHIP_LIB_DIR}")
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CWHIP_LIB_DIR}")
if(NOT Cwhip_APPLICATION_OUTPUT_DIRECTORIES)
    message(FATAL_ERROR "Install a Cwhip SDK with application output-directory support")
endif()
get_filename_component(CDBG_OUTPUT_PREFIX "${CWHIP_BIN_DIR}" DIRECTORY)
cwhip_require_sourceview(RESOURCE_DIRECTORY
    "${CDBG_OUTPUT_PREFIX}/share/cwhip/modules/sourceview/0.1.0/language-specs")

find_package(Python3 REQUIRED COMPONENTS Interpreter)

set(CDBG_GENERATED_VALUES "${CMAKE_CURRENT_BINARY_DIR}/values.h")
add_custom_command(
    OUTPUT "${CDBG_GENERATED_VALUES}"
    COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/src/embed_values.py"
            "${CMAKE_CURRENT_SOURCE_DIR}/src/values.py" "${CDBG_GENERATED_VALUES}"
    DEPENDS src/embed_values.py src/values.py
    VERBATIM)

add_custom_target(cdbg_values_header DEPENDS "${CDBG_GENERATED_VALUES}")
add_library(cdbg_native OBJECT src/terminal.c)
set_target_properties(cdbg_native PROPERTIES C_STANDARD 11 C_STANDARD_REQUIRED YES)
add_dependencies(cdbg_native cdbg_values_header)
target_include_directories(cdbg_native PRIVATE "${Cwhip_INCLUDE_DIR}" "${CMAKE_CURRENT_BINARY_DIR}")

cwhip_add_program(cdbg
    SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/src/cdbg.cw"
    OUTPUT_DIRECTORY "${CWHIP_BIN_DIR}"
    OBJECTS $<TARGET_OBJECTS:cdbg_native>
    DEPENDS cdbg_native cdbg_values_header)
get_target_property(CDBG_EXECUTABLE cdbg CWHIP_EXECUTABLE)

install(PROGRAMS "${CDBG_EXECUTABLE}" DESTINATION "${CMAKE_INSTALL_BINDIR}")

include(CTest)
if(BUILD_TESTING)
    set(CDBG_TEST_WORK "${CMAKE_CURRENT_BINARY_DIR}/test-work")
    add_test(NAME cdbg_project_setup
        COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/test_project_setup.py")
    add_test(NAME cdbg_sdk_discovery
        COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/test_sdk_discovery.py")
    add_test(NAME cdbg_gtk_environment
        COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/test_gtk_support.py")
    add_executable(cdbg_terminal_test tests/test_cdbg_terminal.c src/terminal.c
                   "${CDBG_GENERATED_VALUES}")
    set_target_properties(cdbg_terminal_test PROPERTIES C_STANDARD 11 C_STANDARD_REQUIRED YES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/test-bin")
    target_compile_options(cdbg_terminal_test PRIVATE -UNDEBUG)
    target_include_directories(cdbg_terminal_test PRIVATE
        "${Cwhip_INCLUDE_DIR}" "${CMAKE_CURRENT_BINARY_DIR}")
    add_dependencies(cdbg_terminal_test cdbg_values_header)
    add_test(NAME cdbg_terminal
        COMMAND cdbg_terminal_test "${CMAKE_CURRENT_SOURCE_DIR}/src/values.py")

    add_test(NAME cdbg_parser
        COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/test_cdbg.py"
            --group parser --compiler "${Cwhip_COMPILER}"
            --source "${CMAKE_CURRENT_SOURCE_DIR}/src/cdbg.cw"
            --include "${Cwhip_INCLUDE_DIR}" --work "${CDBG_TEST_WORK}/parser")

    add_test(NAME cdbg_cli
        COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/test_cdbg.py"
            --group cli --compiler "${Cwhip_COMPILER}"
            --source "${CMAKE_CURRENT_SOURCE_DIR}/src/cdbg.cw"
            --include "${Cwhip_INCLUDE_DIR}" --work "${CDBG_TEST_WORK}/cli"
            --executable "${CDBG_EXECUTABLE}")

    find_program(CDBG_GDB_EXECUTABLE NAMES gdb)
    find_program(CDBG_XVFB_EXECUTABLE NAMES Xvfb)
    find_program(CDBG_DBUS_DAEMON_EXECUTABLE NAMES dbus-daemon)
    if(CDBG_GDB_EXECUTABLE AND CDBG_XVFB_EXECUTABLE AND CDBG_DBUS_DAEMON_EXECUTABLE)
        set(CDBG_SESSION_ARGS
            --group session --compiler "${Cwhip_COMPILER}"
            --source "${CMAKE_CURRENT_SOURCE_DIR}/src/cdbg.cw"
            --include "${Cwhip_INCLUDE_DIR}" --work "${CDBG_TEST_WORK}/session"
            --sourceview-languages "${Cwhip_MODULE_DIR}/sourceview/0.1.0/language-specs"
            --executable "${CDBG_EXECUTABLE}" --gdb "${CDBG_GDB_EXECUTABLE}"
            --clang "${Cwhip_CLANG_EXECUTABLE}" --xvfb "${CDBG_XVFB_EXECUTABLE}")
        set(CDBG_RUNTIME_SOURCE "" CACHE FILEPATH
            "Optional compiler RuntimeGc.c source for internal source-line stepping coverage")
        if(CDBG_RUNTIME_SOURCE)
            if(NOT EXISTS "${CDBG_RUNTIME_SOURCE}")
                message(FATAL_ERROR "CDBG_RUNTIME_SOURCE does not exist: ${CDBG_RUNTIME_SOURCE}")
            endif()
            list(APPEND CDBG_SESSION_ARGS --runtime-source "${CDBG_RUNTIME_SOURCE}")
        endif()
        add_test(NAME cdbg_session
            COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/test_cdbg.py"
                ${CDBG_SESSION_ARGS})
        if(NOT CDBG_RUNTIME_SOURCE)
            message(STATUS "cdbg runtime-source stepping excluded (set CDBG_RUNTIME_SOURCE to enable)")
        endif()
    else()
        message(STATUS "cdbg session tests excluded: require gdb, Xvfb, and dbus-daemon")
    endif()

    add_custom_target(check-noop
        COMMAND "${CMAKE_COMMAND}" -E env "PYTHONDONTWRITEBYTECODE=1"
            "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/test_cdbg.py"
            --group noop --compiler "${Cwhip_COMPILER}"
            --source "${CMAKE_CURRENT_SOURCE_DIR}/src/cdbg.cw"
            --include "${Cwhip_INCLUDE_DIR}" --work "${CDBG_TEST_WORK}/noop"
            --executable "${CDBG_EXECUTABLE}" --build "${CMAKE_CURRENT_BINARY_DIR}"
            --cmake "${CMAKE_COMMAND}"
        DEPENDS cdbg
        USES_TERMINAL)
    add_custom_target(test-all
        COMMAND "${CMAKE_CTEST_COMMAND}" --test-dir "${CMAKE_CURRENT_BINARY_DIR}"
            --parallel 1 --output-on-failure
        DEPENDS cdbg cdbg_terminal_test
        USES_TERMINAL)
    get_property(cdbg_tests DIRECTORY PROPERTY TESTS)
    set_tests_properties(${cdbg_tests} PROPERTIES TIMEOUT 600
        ENVIRONMENT "PYTHONDONTWRITEBYTECODE=1")
endif()

set_property(DIRECTORY APPEND PROPERTY ADDITIONAL_CLEAN_FILES
    "${CMAKE_CURRENT_BINARY_DIR}/test-work"
    "${CMAKE_CURRENT_BINARY_DIR}/values.h")
