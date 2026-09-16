cmake_minimum_required(VERSION 3.25)

project(
    cpu
    LANGUAGES CXX
    VERSION 0.0.1
)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

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
)

target_include_directories(
    cpu_lib
    PUBLIC
    include
)

add_executable(
    cpu
    src/main.cpp
    include/emulator/cpu.hpp
)

target_link_libraries(
    cpu
    PRIVATE
    cpu_lib
)

enable_testing()

add_executable(cpu_tests
    tests/cpu_test.cpp
)

include(GoogleTest)

target_link_libraries(
    cpu_tests
    PRIVATE
    cpu_lib
    GTest::gtest_main
)

gtest_discover_tests(cpu_tests)
