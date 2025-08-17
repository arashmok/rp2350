cmake_minimum_required(VERSION 3.13)

# Use the SDK from your environment (set PICO_SDK_PATH before running CMake)
include(${PICO_SDK_PATH}/external/pico_sdk_import.cmake)

project(riscv_blinky C CXX ASM)
pico_sdk_init()

add_executable(riscv_blinky
    main.c
)

target_link_libraries(riscv_blinky
    pico_stdlib
)

# Optional: USB stdio on, UART off
pico_enable_stdio_usb(riscv_blinky 1)
pico_enable_stdio_uart(riscv_blinky 0)

# Create .uf2/.bin/.elf
pico_add_extra_outputs(riscv_blinky)