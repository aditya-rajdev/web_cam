cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "native/phonecam_ipc.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Build PhoneCam Virtual Camera DirectShow Filter DLL
add_library(PhoneCamFilter SHARED
  "native/phonecam_filter.cpp"
  "native/phonecam_filter.def"
  "native/phonecam_ipc.cpp"
)

apply_standard_settings(${BINARY_NAME})
apply_standard_settings(PhoneCamFilter)

target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib" "advapi32.lib" "ole32.lib" "oleaut32.lib" "windowscodecs.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

target_link_libraries(PhoneCamFilter PRIVATE "strmiids.lib" "advapi32.lib" "ole32.lib" "oleaut32.lib" "user32.lib" "gdi32.lib" "windowscodecs.lib")

add_dependencies(${BINARY_NAME} flutter_assemble)

# Automated Code-Signing for all compiled Windows EXEs and DLLs to satisfy Windows Smart App Control
if(WIN32)
  add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND powershell -ExecutionPolicy Bypass -Command "Start-Sleep -Milliseconds 500; Get-ChildItem -Path '${CMAKE_BINARY_DIR}' -Include '*.dll','*.exe' -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $cert = Get-ChildItem Cert:\\LocalMachine\\My | Where-Object { $_.Subject -like '*PhoneCam Local Development*' } | Select-Object -First 1; if ($cert) { Set-AuthenticodeSignature -FilePath $_.FullName -Certificate $cert -ErrorAction SilentlyContinue } }"
    COMMENT "Signing compiled Windows EXE and DLL binaries with Local Development Certificate..."
  )
endif()
