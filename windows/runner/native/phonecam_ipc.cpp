#include "phonecam_ipc.h"
#include <wincodec.h>
#include <iostream>

#pragma comment(lib, "windowscodecs.lib")

static HANDLE g_hSharedMem = NULL;
static PhoneCamFrameHeader* g_pHeader = NULL;
static uint8_t* g_pFrameData = NULL;
static HANDLE g_hMutex = NULL;
static IWICImagingFactory* g_pWicFactory = NULL;

static bool InitializeIPC() {
    if (g_pHeader != NULL) return true;

    g_hMutex = CreateMutexW(NULL, FALSE, PHONECAM_MUTEX_NAME);

    g_hSharedMem = CreateFileMappingW(
        INVALID_HANDLE_VALUE,
        NULL,
        PAGE_READWRITE,
        0,
        PHONECAM_MAX_BUF_SIZE,
        PHONECAM_SHM_NAME
    );

    if (g_hSharedMem == NULL) {
        return false;
    }

    void* pBuffer = MapViewOfFile(g_hSharedMem, FILE_MAP_ALL_ACCESS, 0, 0, PHONECAM_MAX_BUF_SIZE);
    if (pBuffer == NULL) {
        CloseHandle(g_hSharedMem);
        g_hSharedMem = NULL;
        return false;
    }

    g_pHeader = (PhoneCamFrameHeader*)pBuffer;
    g_pFrameData = (uint8_t*)pBuffer + sizeof(PhoneCamFrameHeader);

    g_pHeader->magic = PHONECAM_MAGIC;
    g_pHeader->width = 1280;
    g_pHeader->height = 720;
    g_pHeader->format = 0;
    g_pHeader->sequenceNumber = 0;
    g_pHeader->timestampMs = 0;
    g_pHeader->payloadSize = 0;
    g_pHeader->isConnected = 0;

    CoInitialize(NULL);
    CoCreateInstance(
        CLSID_WICImagingFactory,
        NULL,
        CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&g_pWicFactory)
    );

    return true;
}

static bool DecodeJpegToRgb24(const uint8_t* jpegData, uint32_t jpegSize, uint32_t* outWidth, uint32_t* outHeight) {
    if (!g_pWicFactory || !jpegData || jpegSize == 0) return false;

    IWICStream* pStream = NULL;
    HRESULT hr = g_pWicFactory->CreateStream(&pStream);
    if (FAILED(hr)) return false;

    hr = pStream->InitializeFromMemory((BYTE*)jpegData, jpegSize);
    if (FAILED(hr)) {
        pStream->Release();
        return false;
    }

    IWICBitmapDecoder* pDecoder = NULL;
    hr = g_pWicFactory->CreateDecoderFromStream(pStream, NULL, WICDecodeMetadataCacheOnDemand, &pDecoder);
    if (FAILED(hr)) {
        pStream->Release();
        return false;
    }

    IWICBitmapFrameDecode* pFrame = NULL;
    hr = pDecoder->GetFrame(0, &pFrame);
    if (FAILED(hr)) {
        pDecoder->Release();
        pStream->Release();
        return false;
    }

    UINT w = 0, h = 0;
    pFrame->GetSize(&w, &h);
    if (outWidth) *outWidth = w;
    if (outHeight) *outHeight = h;

    IWICFormatConverter* pConverter = NULL;
    hr = g_pWicFactory->CreateFormatConverter(&pConverter);
    if (SUCCEEDED(hr)) {
        hr = pConverter->Initialize(
            pFrame,
            GUID_WICPixelFormat24bppBGR,
            WICBitmapDitherTypeNone,
            NULL,
            0.0,
            WICBitmapPaletteTypeCustom
        );

        if (SUCCEEDED(hr)) {
            UINT stride = w * 3;
            UINT bufSize = stride * h;
            if (bufSize <= (PHONECAM_MAX_BUF_SIZE - sizeof(PhoneCamFrameHeader))) {
                pConverter->CopyPixels(NULL, stride, bufSize, g_pFrameData);
            }
        }
        pConverter->Release();
    }

    pFrame->Release();
    pDecoder->Release();
    pStream->Release();

    return SUCCEEDED(hr);
}

extern "C" __declspec(dllexport) bool PhoneCam_WriteFrame(
    uint32_t width,
    uint32_t height,
    const uint8_t* frameData,
    uint32_t dataSize,
    uint32_t isConnected
) {
    if (!InitializeIPC()) return false;

    if (g_hMutex != NULL) {
        WaitForSingleObject(g_hMutex, INFINITE);
    }

    g_pHeader->magic = PHONECAM_MAGIC;
    g_pHeader->sequenceNumber++;
    g_pHeader->timestampMs = GetTickCount64();
    g_pHeader->isConnected = isConnected;

    if (isConnected && frameData != NULL && dataSize > 0) {
        uint32_t decodedW = width;
        uint32_t decodedH = height;

        // Detect JPEG magic header (0xFF 0xD8)
        if (dataSize >= 2 && frameData[0] == 0xFF && frameData[1] == 0xD8) {
            if (DecodeJpegToRgb24(frameData, dataSize, &decodedW, &decodedH)) {
                g_pHeader->width = decodedW;
                g_pHeader->height = decodedH;
                g_pHeader->payloadSize = decodedW * decodedH * 3;
            } else {
                g_pHeader->width = width;
                g_pHeader->height = height;
                g_pHeader->payloadSize = width * height * 3;
            }
        } else {
            // Raw RGB24 copy
            g_pHeader->width = width;
            g_pHeader->height = height;
            g_pHeader->payloadSize = dataSize;
            if (dataSize <= (PHONECAM_MAX_BUF_SIZE - sizeof(PhoneCamFrameHeader))) {
                memcpy(g_pFrameData, frameData, dataSize);
            }
        }
    } else {
        g_pHeader->payloadSize = 0;
    }

    if (g_hMutex != NULL) {
        ReleaseMutex(g_hMutex);
    }

    return true;
}

extern "C" __declspec(dllexport) bool PhoneCam_IsFilterRegistered() {
    HKEY hKey = NULL;
    // 1. Check HKCR
    const wchar_t* subKeyHKCR = L"CLSID\\{860BB310-5D01-11d0-BD3B-00A0C911CE86}\\Instance\\{B98E711A-4C23-400A-9B3B-8F0E4632F1A2}";
    LONG result = RegOpenKeyExW(HKEY_CLASSES_ROOT, subKeyHKCR, 0, KEY_READ, &hKey);
    if (result == ERROR_SUCCESS) {
        RegCloseKey(hKey);
        return true;
    }

    // 2. Check HKCU
    const wchar_t* subKeyHKCU = L"Software\\Classes\\CLSID\\{860BB310-5D01-11d0-BD3B-00A0C911CE86}\\Instance\\{B98E711A-4C23-400A-9B3B-8F0E4632F1A2}";
    result = RegOpenKeyExW(HKEY_CURRENT_USER, subKeyHKCU, 0, KEY_READ, &hKey);
    if (result == ERROR_SUCCESS) {
        RegCloseKey(hKey);
        return true;
    }

    return false;
}

extern "C" __declspec(dllexport) bool PhoneCam_RegisterFilter(const wchar_t* dllPath) {
    HMODULE hDll = LoadLibraryW(dllPath);
    if (hDll == NULL) return false;

    typedef HRESULT(STDAPICALLTYPE * DllRegisterServerFn)();
    DllRegisterServerFn pfnRegister = (DllRegisterServerFn)GetProcAddress(hDll, "DllRegisterServer");

    bool success = false;
    if (pfnRegister != NULL) {
        HRESULT hr = pfnRegister();
        success = SUCCEEDED(hr);
    }

    FreeLibrary(hDll);
    return success;
}

extern "C" __declspec(dllexport) bool PhoneCam_UnregisterFilter(const wchar_t* dllPath) {
    HMODULE hDll = LoadLibraryW(dllPath);
    if (hDll == NULL) return false;

    typedef HRESULT(STDAPICALLTYPE * DllUnregisterServerFn)();
    DllUnregisterServerFn pfnUnregister = (DllUnregisterServerFn)GetProcAddress(hDll, "DllUnregisterServer");

    bool success = false;
    if (pfnUnregister != NULL) {
        HRESULT hr = pfnUnregister();
        success = SUCCEEDED(hr);
    }

    FreeLibrary(hDll);
    return success;
}
