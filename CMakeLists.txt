cmake_minimum_required(VERSION 4.2)
project(mac_broker LANGUAGES C Swift)

set(CMAKE_C_STANDARD 11)

include_directories(native/src/headers)

add_library(MacBrokerBridge SHARED
        native/src/headers/MacBrokerBridge.h
        native/src/MacBrokerBridge.swift)

target_compile_options(MacBrokerBridge PRIVATE
        "-import-objc-header" "${CMAKE_SOURCE_DIR}/native/src/headers/MacBrokerBridge.h")

target_link_libraries(MacBrokerBridge PRIVATE
        "-framework Foundation"
        "-framework Security"
        "-framework AppKit"
        "-framework WebKit")
