cmake_minimum_required(VERSION 3.16)

project(Mjcom VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD_REQUIRED ON)


# Lua配置 -------------------------------------------------
set(LUA_DIR "Lua")
include_directories(${LUA_DIR}/include)

# 查找Lua库
find_library(LUA_LIBRARY
    NAMES lua54 lua5.4 lua
    PATHS ${LUA_DIR}
    REQUIRED
)

find_package(Qt6 COMPONENTS
  Core
  Gui
  Qml
  Quick
  QuickControls2
  SerialPort
  REQUIRED)

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(Mjcom
    main.cpp
)

target_link_libraries(Mjcom PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::SerialPort
    ${LUA_LIBRARY}
)

qt_add_qml_module(Mjcom
    URI Mjcom
    VERSION 1.0
    QML_FILES
        Main.qml
)

# Qt for iOS sets MACOSX_BUNDLE_GUI_IDENTIFIER automatically since Qt 6.1.
# If you are developing for iOS or macOS you should consider setting an
# explicit, fixed bundle identifier manually though.
set_target_properties(Mjcom PROPERTIES
#    MACOSX_BUNDLE_GUI_IDENTIFIER com.example.Mjcom
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)


include(GNUInstallDirs)
install(TARGETS Mjcom
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
