# Additional clean files
cmake_minimum_required(VERSION 3.16)

if("${CONFIG}" STREQUAL "" OR "${CONFIG}" STREQUAL "Debug")
  file(REMOVE_RECURSE
  "CMakeFiles\\appQT_uart_autogen.dir\\AutogenUsed.txt"
  "CMakeFiles\\appQT_uart_autogen.dir\\ParseCache.txt"
  "appQT_uart_autogen"
  )
endif()
