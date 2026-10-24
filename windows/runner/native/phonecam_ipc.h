#ifndef PHONECAM_IPC_H
#define PHONECAM_IPC_H

#include <windows.h>
#include <stdint.h>

#define PHONECAM_MAGIC 0x5043414D // 'PCAM'
#define PHONECAM_SHM_NAME L"Local\\PhoneCamSharedMem"
#define PHONECAM_MUTEX_NAME L"Local\\PhoneCamFrameMutex"
#define PHONECAM_EVENT_NAME L"Local\\PhoneCamFrameEvent"
#define PHONECAM_MAX_BUF_SIZE (1920 * 1080 * 3 + 1024)

#pragma pack(push, 1)
struct PhoneCamFrameHeader {
    uint32_t magic;           // PHONECAM_MAGIC
    uint32_t width;           // e.g. 1280
    uint32_t height;          // e.g. 720
    uint32_t format;          // 0 = RGB24
    uint32_t sequenceNumber;
    uint64_t timestampMs;
    uint32_t payloadSize;     // width * height * 3
    uint32_t isConnected;     // 1 if streaming, 0 if idle/disconnected
};
#pragma pack(pop)

#ifdef __cplusplus
extern "C" {
#endif

__declspec(dllexport) bool PhoneCam_WriteFrame(uint32_t width, uint32_t height, const uint8_t* rgbData, uint32_t dataSize, uint32_t isConnected);
__declspec(dllexport) bool PhoneCam_IsFilterRegistered();
__declspec(dllexport) bool PhoneCam_RegisterFilter(const wchar_t* dllPath);
__declspec(dllexport) bool PhoneCam_UnregisterFilter(const wchar_t* dllPath);

#ifdef __cplusplus
}
#endif

#endif // PHONECAM_IPC_H
