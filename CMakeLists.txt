cmake_minimum_required(VERSION 3.16)

project(MJCom VERSION 0.1 LANGUAGES CXX)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

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
  Charts
  DataVisualization
  REQUIRED)

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(MJCom
    main.cpp
)

target_link_libraries(MJCom PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::SerialPort
    Qt6::Charts
    Qt6::DataVisualization
    ${LUA_LIBRARY}
)

qt_add_qml_module(MJCom
    URI MJCom
    VERSION 1.0
    QML_FILES
        RESOURCES MJCom.qrc
)

# Qt for iOS sets MACOSX_BUNDLE_GUI_IDENTIFIER automatically since Qt 6.1.
# If you are developing for iOS or macOS you should consider setting an
# explicit, fixed bundle identifier manually though.
set_target_properties(MJCom PROPERTIES
#    MACOSX_BUNDLE_GUI_IDENTIFIER com.example.MJCom
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)


include(GNUInstallDirs)
install(TARGETS MJCom
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

if(WIN32)
    get_target_property(_qmake_executable Qt6::qmake IMPORTED_LOCATION)
    get_filename_component(_qt_bin_dir "${_qmake_executable}" DIRECTORY)
    find_program(WINDEPLOYQT_EXECUTABLE windeployqt HINTS "${_qt_bin_dir}")

    if(WINDEPLOYQT_EXECUTABLE)
      add_custom_command(TARGET MJCom POST_BUILD
          COMMAND "${WINDEPLOYQT_EXECUTABLE}"
                  --no-translations          # 不部署翻译文件
                  --no-system-d3d-compiler   # 不部署 D3D 编译器
                  --no-virtualkeyboard       # 不部署虚拟键盘
                  --no-opengl-sw             # 不部署软件 OpenGL
                  --no-svg                   # 如果不使用 SVG，可以移除
                  --compiler-runtime         # 只部署必要的编译器运行时
                  --qmldir "${CMAKE_CURRENT_SOURCE_DIR}"  # 指定 QML 目录以便只部署所需的 QML 模块
                  --release                  # 指定发布版本，减少调试信息
                  "$<TARGET_FILE:MJCom>"
          WORKING_DIRECTORY "$<TARGET_FILE_DIR:MJCom>"
          COMMENT "Deploying minimal Qt dependencies for MJCom..."
      )
    endif()
endif()
