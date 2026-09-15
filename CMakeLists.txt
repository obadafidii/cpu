cmake_minimum_required(VERSION 3.25)

project(
    cpu
    LANGUAGES CXX
    VERSION 0.0.1
)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_executable(
    cpu
    src/main.cpp
    src/cpu.cpp
)

target_include_directories(
    cpu
    PRIVATE
    include
)

target_compile_options(
    cpu
    PRIVATE
    -Wall
    -Wextra
    -Wpedantic
)
