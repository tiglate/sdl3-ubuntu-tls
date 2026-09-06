# A consumer exactly like a real one: finds every packaged library through its
# installed CMake config and links the imported targets. If the -dev packages
# are wrong -- missing config files, a broken find_dependency(SDL3), headers in
# the wrong place -- this fails to configure or link.
cmake_minimum_required(VERSION 3.16)
project(sdl3_consumer C)

foreach(pkg SDL3 SDL3_image SDL3_mixer SDL3_net SDL3_ttf)
    find_package(${pkg} REQUIRED CONFIG)
endforeach()

add_executable(sdl3_consumer main.c)
target_link_libraries(sdl3_consumer PRIVATE
    SDL3::SDL3
    SDL3_image::SDL3_image
    SDL3_mixer::SDL3_mixer
    SDL3_net::SDL3_net
    SDL3_ttf::SDL3_ttf)
