cmake_minimum_required(VERSION 3.20)
project(RlfcMemoryBridge LANGUAGES CXX)

add_library(RlfcMemoryBridge SHARED
   src/RlfcMemoryBridge.cpp
   include/RlfcMemoryBridge.h
)

target_compile_features(RlfcMemoryBridge PRIVATE cxx_std_17)
target_include_directories(RlfcMemoryBridge PRIVATE include)
target_compile_definitions(RlfcMemoryBridge PRIVATE
   UNICODE
   _UNICODE
   WIN32_LEAN_AND_MEAN
   NOMINMAX
)

if(MSVC)
   target_compile_options(RlfcMemoryBridge PRIVATE /W4 /O2 /permissive-)
else()
   target_compile_options(RlfcMemoryBridge PRIVATE -Wall -Wextra -Wpedantic -O2)
endif()

set_target_properties(RlfcMemoryBridge PROPERTIES
   OUTPUT_NAME "RlfcMemoryBridge"
   PREFIX ""
)

enable_testing()
add_executable(RlfcMemoryBridgeSmoke tests/bridge_smoke.cpp)
target_compile_features(RlfcMemoryBridgeSmoke PRIVATE cxx_std_17)
target_include_directories(RlfcMemoryBridgeSmoke PRIVATE include)
target_link_libraries(RlfcMemoryBridgeSmoke PRIVATE RlfcMemoryBridge)
add_test(NAME RlfcMemoryBridgeSmoke COMMAND RlfcMemoryBridgeSmoke)
