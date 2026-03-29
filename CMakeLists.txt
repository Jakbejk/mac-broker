cmake_minimum_required(VERSION 4.2)
project(mac_broker C)

set(CMAKE_C_STANDARD 11)

include_directories(native/src/headers)

add_executable(mac_broker
        native/src/headers/MacBrokerBridge.h
        native/src/MacBrokerBridge.m)
