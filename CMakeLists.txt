cmake_minimum_required(VERSION 3.25)

project(
    cpu
    LANGUAGES CXX
    VERSION 0.0.1
)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

include(FetchContent)

FetchContent_Declare(
    googletest
    URL https://github.com/google/googletest/archive/refs/tags/v1.17.0.zip
    DOWNLOAD_EXTRACT_TIMESTAMP ON
)

FetchContent_MakeAvailable(googletest)

add_library(
    cpu_lib
    src/cpu.cpp
        include/emulator/alu.h
        include/emulator/instruction.h
)

target_include_directories(
    cpu_lib
    PUBLIC
    include
)

add_executable(
    cpu
    src/
        include/emulator/cpu.h
        include/emulator/control_unit.h
        include/emulator/alu.h
        include/emulator/instruction.h
)

target_link_libraries(
    cpu
    PRIVATE
    cpu_lib
)

enable_testing()

add_executable(cpu_tests
    tests/cpu_test.cpp
        include/emulator/alu.h
        include/emulator/instruction.h
)

include(GoogleTest)

target_link_libraries(
    cpu_tests
    PRIVATE
    cpu_lib
    GTest::gtest_main
)

gtest_discover_tests(cpu_tests)

target_compile_options(
    cpu_lib
    PRIVATE
    -Wall
    -Wextra
    -Wpedantic
    -Wconversion
    -Wshadow
)