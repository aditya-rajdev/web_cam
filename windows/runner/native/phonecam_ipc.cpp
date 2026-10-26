#include "phonecam_ipc.h"
#include <wincodec.h>
#include <shellapi.h>
#include <strmif.h>
#include <uuids.h>
#include <iostream>

#pragma comment(lib, "windowscodecs.lib")
#pragma comment(lib, "strmiids.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "oleaut32.lib")

static HANDLE g_hSharedMem = NULL;
static PhoneCamFrameHeader* g_pHeader = NULL;
static uint8_t* g_pFrameData = NULL;
static HANDLE g_hMutex = NULL;
static IWICImagingFactory* g_pWicFactory = NULL;
static IUnknown* g_pVirtualCameraObj = NULL;

typedef enum _MFVirtualCameraType {
    MFVirtualCameraType_SoftwareCamera = 0
} MFVirtualCameraType;

typedef enum _MFVirtualCameraLifetime {
    MFVirtualCameraLifetime_Session = 0,
    MFVirtualCameraLifetime_System = 1
} MFVirtualCameraLifetime;

typedef enum _MFVirtualCameraAccess {
    MFVirtualCameraAccess_CurrentUser = 0,
    MFVirtualCameraAccess_AllUsers = 1
} MFVirtualCameraAccess;

typedef HRESULT(STDAPICALLTYPE* PFN_MFCreateVirtualCamera)(
    MFVirtualCameraType type,
    MFVirtualCameraLifetime lifetime,
    MFVirtualCameraAccess access,
    LPCWSTR friendlyName,
    LPCWSTR szCLSID,
    LPCWSTR categories,
    IUnknown** ppVirtualCamera
);

static bool RegisterMFVirtualCamera() {
    HMODULE hMfPlat = LoadLibraryW(L"mfplat.dll");
    if (!hMfPlat) return false;

    PFN_MFCreateVirtualCamera pfnCreateVirCam = (PFN_MFCreateVirtualCamera)GetProcAddress(hMfPlat, "MFCreateVirtualCamera");
    if (pfnCreateVirCam != NULL) {
        if (g_pVirtualCameraObj) {
            g_pVirtualCameraObj->Release();
            g_pVirtualCameraObj = NULL;
        }

        HRESULT hr = pfnCreateVirCam(
            MFVirtualCameraType_SoftwareCamera,
            MFVirtualCameraLifetime_System,
            MFVirtualCameraAccess_AllUsers,
            L"PhoneCam",
            L"{B98E711A-4C23-400A-9B3B-8F0E4632F1A2}",
            NULL,
            &g_pVirtualCameraObj
        );

        if (SUCCEEDED(hr) && g_pVirtualCameraObj != NULL) {
            FreeLibrary(hMfPlat);
            return true;
        }
    }

    FreeLibrary(hMfPlat);
    return false;
}

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

    // 1. Check HKCR System-Wide Registration
    const wchar_t* subKeyHKCR = L"CLSID\\{860BB310-5D01-11d0-BD3B-00A0C911CE86}\\Instance\\{B98E711A-4C23-400A-9B3B-8F0E4632F1A2}";
    LONG result = RegOpenKeyExW(HKEY_CLASSES_ROOT, subKeyHKCR, 0, KEY_READ, &hKey);
    if (result == ERROR_SUCCESS) {
        RegCloseKey(hKey);
        return true;
    }

    // 2. Check HKLM System-Wide Registration
    const wchar_t* subKeyHKLM = L"SOFTWARE\\Classes\\CLSID\\{860BB310-5D01-11d0-BD3B-00A0C911CE86}\\Instance\\{B98E711A-4C23-400A-9B3B-8F0E4632F1A2}";
    result = RegOpenKeyExW(HKEY_LOCAL_MACHINE, subKeyHKLM, 0, KEY_READ, &hKey);
    if (result == ERROR_SUCCESS) {
        RegCloseKey(hKey);
        return true;
    }

    return false;
}

extern "C" __declspec(dllexport) bool PhoneCam_DiagnoseDirectShow() {
    CoInitialize(NULL);
    ICreateDevEnum* pDevEnum = NULL;
    HRESULT hr = CoCreateInstance(
        CLSID_SystemDeviceEnum,
        NULL,
        CLSCTX_INPROC_SERVER,
        IID_ICreateDevEnum,
        (void**)&pDevEnum
    );

    if (FAILED(hr) || !pDevEnum) return false;

    IEnumMoniker* pEnum = NULL;
    hr = pDevEnum->CreateClassEnumerator(CLSID_VideoInputDeviceCategory, &pEnum, 0);
    pDevEnum->Release();

    if (hr != S_OK || !pEnum) return false;

    IMoniker* pMoniker = NULL;
    bool found = false;

    while (pEnum->Next(1, &pMoniker, NULL) == S_OK) {
        IPropertyBag* pPropBag = NULL;
        hr = pMoniker->BindToStorage(0, 0, IID_IPropertyBag, (void**)&pPropBag);
        if (SUCCEEDED(hr)) {
            VARIANT var;
            VariantInit(&var);
            hr = pPropBag->Read(L"FriendlyName", &var, 0);
            if (SUCCEEDED(hr) && var.vt == VT_BSTR && var.bstrVal) {
                if (wcsstr(var.bstrVal, L"PhoneCam") != NULL) {
                    // Instantiation Check: BindToObject creates the filter instance
                    IBaseFilter* pFilter = NULL;
                    hr = pMoniker->BindToObject(0, 0, IID_IBaseFilter, (void**)&pFilter);
                    if (SUCCEEDED(hr) && pFilter) {
                        found = true;
                        pFilter->Release();
                    }
                }
            }
            VariantClear(&var);
            pPropBag->Release();
        }
        pMoniker->Release();
        if (found) break;
    }

    pEnum->Release();
    return found;
}

extern "C" __declspec(dllexport) bool PhoneCam_RegisterFilter(const wchar_t* dllPath) {
    if (!dllPath || wcslen(dllPath) == 0) return false;

    // Register Media Foundation Virtual Camera for Windows 11 / Windows 10
    RegisterMFVirtualCamera();

    // 1. Try in-process LoadLibrary DllRegisterServer
    HMODULE hDll = LoadLibraryW(dllPath);
    if (hDll != NULL) {
        typedef HRESULT(STDAPICALLTYPE * DllRegisterServerFn)();
        DllRegisterServerFn pfnRegister = (DllRegisterServerFn)GetProcAddress(hDll, "DllRegisterServer");
        if (pfnRegister != NULL) {
            HRESULT hr = pfnRegister();
            FreeLibrary(hDll);
            if (SUCCEEDED(hr) && PhoneCam_IsFilterRegistered()) {
                return true;
            }
        } else {
            FreeLibrary(hDll);
        }
    }

    // 2. Execute elevated regsvr32 via ShellExecuteW 'runas' for Administrator System Registration
    wchar_t params[MAX_PATH + 20];
    wsprintfW(params, L"/s \"%s\"", dllPath);

    SHELLEXECUTEINFOW sei = { sizeof(sei) };
    sei.cbSize = sizeof(sei);
    sei.lpVerb = L"runas";
    sei.lpFile = L"regsvr32.exe";
    sei.lpParameters = params;
    sei.nShow = SW_HIDE;
    sei.fMask = SEE_MASK_NOCLOSEPROCESS;

    if (ShellExecuteExW(&sei) && sei.hProcess) {
        WaitForSingleObject(sei.hProcess, 10000);
        CloseHandle(sei.hProcess);
    }

    // 3. GENUINELY VERIFY actual registration in system registry!
    return PhoneCam_IsFilterRegistered();
}

extern "C" __declspec(dllexport) bool PhoneCam_UnregisterFilter(const wchar_t* dllPath) {
    if (!dllPath || wcslen(dllPath) == 0) return false;

    HMODULE hDll = LoadLibraryW(dllPath);
    if (hDll != NULL) {
        typedef HRESULT(STDAPICALLTYPE * DllUnregisterServerFn)();
        DllUnregisterServerFn pfnUnregister = (DllUnregisterServerFn)GetProcAddress(hDll, "DllUnregisterServer");
        if (pfnUnregister != NULL) {
            pfnUnregister();
        }
        FreeLibrary(hDll);
    }

    wchar_t params[MAX_PATH + 20];
    wsprintfW(params, L"/u /s \"%s\"", dllPath);

    SHELLEXECUTEINFOW sei = { sizeof(sei) };
    sei.cbSize = sizeof(sei);
    sei.lpVerb = L"runas";
    sei.lpFile = L"regsvr32.exe";
    sei.lpParameters = params;
    sei.nShow = SW_HIDE;
    sei.fMask = SEE_MASK_NOCLOSEPROCESS;

    if (ShellExecuteExW(&sei) && sei.hProcess) {
        WaitForSingleObject(sei.hProcess, 10000);
        CloseHandle(sei.hProcess);
    }

    return !PhoneCam_IsFilterRegistered();
}
