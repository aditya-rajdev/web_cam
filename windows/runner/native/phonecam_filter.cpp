#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <unknwn.h>
#include <strmif.h>
#include <uuids.h>
#include <vfwmsgs.h>
#include <stdint.h>

#ifndef VFW_E_NOT_CONNECTED
#define VFW_E_NOT_CONNECTED ((HRESULT)0x80040209L)
#endif

#ifndef E_PROP_SET_UNSUPPORTED
#define E_PROP_SET_UNSUPPORTED ((HRESULT)0x80070490L)
#endif

typedef struct tagRECT_CAM {
    LONG left;
    LONG top;
    LONG right;
    LONG bottom;
} RECT_CAM;

typedef struct tagBITMAPINFOHEADER_CAM {
    DWORD biSize;
    LONG biWidth;
    LONG biHeight;
    WORD biPlanes;
    WORD biBitCount;
    DWORD biCompression;
    DWORD biSizeImage;
    LONG biXPelsPerMeter;
    LONG biYPelsPerMeter;
    DWORD biClrUsed;
    DWORD biClrImportant;
} BITMAPINFOHEADER_CAM;

typedef struct tagVIDEOINFOHEADER_CAM {
    RECT_CAM rcSource;
    RECT_CAM rcTarget;
    DWORD dwBitRate;
    DWORD dwBitErrorRate;
    REFERENCE_TIME AvgTimePerFrame;
    BITMAPINFOHEADER_CAM bmiHeader;
} VIDEOINFOHEADER_CAM;

// DirectShow GUIDs
// CLSID_PhoneCamFilter: {B98E711A-4C23-400A-9B3B-8F0E4632F1A2}
static const GUID CLSID_PhoneCamFilter =
{ 0xb98e711a, 0x4c23, 0x400a, { 0x9b, 0x3b, 0x8f, 0x0e, 0x46, 0x32, 0xf1, 0xa2 } };

#define FILTER_NAME L"PhoneCam"
#define CLSID_STRING L"{B98E711A-4C23-400A-9B3B-8F0E4632F1A2}"

#define PHONECAM_MAGIC 0x5043414D
#define PHONECAM_SHM_NAME L"Local\\PhoneCamSharedMem"
#define PHONECAM_MUTEX_NAME L"Local\\PhoneCamFrameMutex"
#define PHONECAM_MAX_BUF_SIZE (1920 * 1080 * 3 + 1024)

#pragma pack(push, 1)
struct PhoneCamFrameHeader {
    uint32_t magic;
    uint32_t width;
    uint32_t height;
    uint32_t format;
    uint32_t sequenceNumber;
    uint64_t timestampMs;
    uint32_t payloadSize;
    uint32_t isConnected;
};
#pragma pack(pop)

static LONG g_cRefModule = 0;
static HINSTANCE g_hModule = NULL;

BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID lpReserved) {
    if (ul_reason_for_call == DLL_PROCESS_ATTACH) {
        g_hModule = hModule;
        DisableThreadLibraryCalls(hModule);
    }
    return TRUE;
}

class CPhoneCamFilter;

class CPhoneCamEnumMediaTypes : public IEnumMediaTypes {
    LONG m_cRef;
    ULONG m_iIndex;
public:
    CPhoneCamEnumMediaTypes() : m_cRef(1), m_iIndex(0) {}
    virtual ~CPhoneCamEnumMediaTypes() {}

    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) {
        if (!ppv) return E_POINTER;
        if (riid == IID_IUnknown || riid == IID_IEnumMediaTypes) {
            *ppv = static_cast<IEnumMediaTypes*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = NULL;
        return E_NOINTERFACE;
    }

    STDMETHODIMP_(ULONG) AddRef() { return InterlockedIncrement(&m_cRef); }
    STDMETHODIMP_(ULONG) Release() {
        ULONG res = InterlockedDecrement(&m_cRef);
        if (res == 0) delete this;
        return res;
    }

    STDMETHODIMP Next(ULONG cMediaTypes, AM_MEDIA_TYPE** ppMediaTypes, ULONG* pcFetched) {
        if (!ppMediaTypes) return E_POINTER;
        if (m_iIndex > 0) {
            if (pcFetched) *pcFetched = 0;
            return S_FALSE;
        }

        AM_MEDIA_TYPE* pmt = (AM_MEDIA_TYPE*)CoTaskMemAlloc(sizeof(AM_MEDIA_TYPE));
        ZeroMemory(pmt, sizeof(AM_MEDIA_TYPE));
        pmt->majortype = MEDIATYPE_Video;
        pmt->subtype = MEDIASUBTYPE_RGB24;
        pmt->bFixedSizeSamples = TRUE;
        pmt->bTemporalCompression = FALSE;
        pmt->lSampleSize = 1280 * 720 * 3;
        pmt->formattype = FORMAT_VideoInfo;

        VIDEOINFOHEADER_CAM* pvih = (VIDEOINFOHEADER_CAM*)CoTaskMemAlloc(sizeof(VIDEOINFOHEADER_CAM));
        ZeroMemory(pvih, sizeof(VIDEOINFOHEADER_CAM));
        pvih->AvgTimePerFrame = 333333; // 30 FPS
        pvih->bmiHeader.biSize = sizeof(BITMAPINFOHEADER_CAM);
        pvih->bmiHeader.biWidth = 1280;
        pvih->bmiHeader.biHeight = 720;
        pvih->bmiHeader.biPlanes = 1;
        pvih->bmiHeader.biBitCount = 24;
        pvih->bmiHeader.biCompression = BI_RGB;
        pvih->bmiHeader.biSizeImage = 1280 * 720 * 3;

        pmt->cbFormat = sizeof(VIDEOINFOHEADER_CAM);
        pmt->pbFormat = (BYTE*)pvih;

        ppMediaTypes[0] = pmt;
        m_iIndex++;
        if (pcFetched) *pcFetched = 1;
        return S_OK;
    }

    STDMETHODIMP Skip(ULONG cMediaTypes) {
        m_iIndex += cMediaTypes;
        return (m_iIndex <= 1) ? S_OK : S_FALSE;
    }

    STDMETHODIMP Reset() {
        m_iIndex = 0;
        return S_OK;
    }

    STDMETHODIMP Clone(IEnumMediaTypes** ppEnum) { return E_NOTIMPL; }
};

class CPhoneCamOutputPin : public IPin, public IAMStreamConfig, public IKsPropertySet {
    LONG m_cRef;
    CPhoneCamFilter* m_pFilter;
    IPin* m_pConnectedPin;
    IMemInputPin* m_pConnectedMemInput;
    IMemAllocator* m_pAllocator;
    HANDLE m_hStreamThread;
    bool m_bStreaming;
    uint64_t m_frameCount;
public:
    CPhoneCamOutputPin(CPhoneCamFilter* pFilter);
    virtual ~CPhoneCamOutputPin();

    void StartStreaming();
    void StopStreaming();
    static DWORD WINAPI StreamThreadProc(LPVOID lpParam);
    void DoStreamLoop();

    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) {
        if (!ppv) return E_POINTER;
        if (riid == IID_IUnknown || riid == IID_IPin) {
            *ppv = static_cast<IPin*>(this);
            AddRef();
            return S_OK;
        }
        if (riid == IID_IAMStreamConfig) {
            *ppv = static_cast<IAMStreamConfig*>(this);
            AddRef();
            return S_OK;
        }
        if (riid == IID_IKsPropertySet) {
            *ppv = static_cast<IKsPropertySet*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = NULL;
        return E_NOINTERFACE;
    }

    STDMETHODIMP_(ULONG) AddRef() { return InterlockedIncrement(&m_cRef); }
    STDMETHODIMP_(ULONG) Release() {
        ULONG res = InterlockedDecrement(&m_cRef);
        if (res == 0) delete this;
        return res;
    }

    // IPin Methods
    STDMETHODIMP Connect(IPin* pReceivePin, const AM_MEDIA_TYPE* pmt) {
        if (!pReceivePin) return E_POINTER;
        m_pConnectedPin = pReceivePin;
        m_pConnectedPin->AddRef();

        pReceivePin->QueryInterface(IID_IMemInputPin, (void**)&m_pConnectedMemInput);
        if (m_pConnectedMemInput) {
            m_pConnectedMemInput->GetAllocator(&m_pAllocator);
            if (m_pAllocator) {
                ALLOCATOR_PROPERTIES prop = { 0 };
                prop.cBuffers = 2;
                prop.cbBuffer = 1280 * 720 * 3;
                prop.cbAlign = 1;
                ALLOCATOR_PROPERTIES actual = { 0 };
                m_pAllocator->SetProperties(&prop, &actual);
                m_pConnectedMemInput->NotifyAllocator(m_pAllocator, FALSE);
                m_pAllocator->Commit();
            }
        }
        return S_OK;
    }

    STDMETHODIMP ReceiveConnection(IPin* pConnector, const AM_MEDIA_TYPE* pmt) { return E_NOTIMPL; }
    STDMETHODIMP Disconnect() {
        StopStreaming();
        if (m_pAllocator) {
            m_pAllocator->Decommit();
            m_pAllocator->Release();
            m_pAllocator = NULL;
        }
        if (m_pConnectedMemInput) {
            m_pConnectedMemInput->Release();
            m_pConnectedMemInput = NULL;
        }
        if (m_pConnectedPin) {
            m_pConnectedPin->Release();
            m_pConnectedPin = NULL;
        }
        return S_OK;
    }

    STDMETHODIMP ConnectedTo(IPin** ppPin) {
        if (!ppPin) return E_POINTER;
        if (!m_pConnectedPin) return VFW_E_NOT_CONNECTED;
        *ppPin = m_pConnectedPin;
        m_pConnectedPin->AddRef();
        return S_OK;
    }

    STDMETHODIMP ConnectionMediaType(AM_MEDIA_TYPE* pmt) {
        if (!pmt) return E_POINTER;
        pmt->majortype = MEDIATYPE_Video;
        pmt->subtype = MEDIASUBTYPE_RGB24;
        pmt->formattype = FORMAT_VideoInfo;
        return S_OK;
    }

    STDMETHODIMP QueryPinInfo(PIN_INFO* pInfo) {
        if (!pInfo) return E_POINTER;
        pInfo->pFilter = (IBaseFilter*)m_pFilter;
        if (pInfo->pFilter) pInfo->pFilter->AddRef();
        pInfo->dir = PINDIR_OUTPUT;
        lstrcpyW(pInfo->achName, L"Capture");
        return S_OK;
    }

    STDMETHODIMP QueryDirection(PIN_DIRECTION* pPinDir) {
        if (!pPinDir) return E_POINTER;
        *pPinDir = PINDIR_OUTPUT;
        return S_OK;
    }

    STDMETHODIMP QueryId(LPWSTR* Id) {
        if (!Id) return E_POINTER;
        *Id = (LPWSTR)CoTaskMemAlloc(sizeof(L"Capture"));
        lstrcpyW(*Id, L"Capture");
        return S_OK;
    }

    STDMETHODIMP QueryAccept(const AM_MEDIA_TYPE* pmt) { return S_OK; }
    STDMETHODIMP EnumMediaTypes(IEnumMediaTypes** ppEnum) {
        if (!ppEnum) return E_POINTER;
        *ppEnum = new CPhoneCamEnumMediaTypes();
        return S_OK;
    }

    STDMETHODIMP QueryInternalConnections(IPin** apPin, ULONG* nPin) { return E_NOTIMPL; }
    STDMETHODIMP EndOfStream() { return S_OK; }
    STDMETHODIMP BeginFlush() { return S_OK; }
    STDMETHODIMP EndFlush() { return S_OK; }
    STDMETHODIMP NewSegment(REFERENCE_TIME tStart, REFERENCE_TIME tStop, double dRate) { return S_OK; }

    // IAMStreamConfig Methods
    STDMETHODIMP SetFormat(AM_MEDIA_TYPE *pmt) { return S_OK; }
    STDMETHODIMP GetFormat(AM_MEDIA_TYPE **ppmt) {
        if (!ppmt) return E_POINTER;
        AM_MEDIA_TYPE* pmt = (AM_MEDIA_TYPE*)CoTaskMemAlloc(sizeof(AM_MEDIA_TYPE));
        ZeroMemory(pmt, sizeof(AM_MEDIA_TYPE));
        pmt->majortype = MEDIATYPE_Video;
        pmt->subtype = MEDIASUBTYPE_RGB24;
        pmt->bFixedSizeSamples = TRUE;
        pmt->bTemporalCompression = FALSE;
        pmt->lSampleSize = 1280 * 720 * 3;
        pmt->formattype = FORMAT_VideoInfo;

        VIDEOINFOHEADER_CAM* pvih = (VIDEOINFOHEADER_CAM*)CoTaskMemAlloc(sizeof(VIDEOINFOHEADER_CAM));
        ZeroMemory(pvih, sizeof(VIDEOINFOHEADER_CAM));
        pvih->AvgTimePerFrame = 333333; // 30 FPS
        pvih->bmiHeader.biSize = sizeof(BITMAPINFOHEADER_CAM);
        pvih->bmiHeader.biWidth = 1280;
        pvih->bmiHeader.biHeight = 720;
        pvih->bmiHeader.biPlanes = 1;
        pvih->bmiHeader.biBitCount = 24;
        pvih->bmiHeader.biCompression = BI_RGB;
        pvih->bmiHeader.biSizeImage = 1280 * 720 * 3;

        pmt->cbFormat = sizeof(VIDEOINFOHEADER_CAM);
        pmt->pbFormat = (BYTE*)pvih;

        *ppmt = pmt;
        return S_OK;
    }

    STDMETHODIMP GetNumberOfCapabilities(int *piCount, int *piSize) {
        if (!piCount || !piSize) return E_POINTER;
        *piCount = 1;
        *piSize = sizeof(VIDEO_STREAM_CONFIG_CAPS);
        return S_OK;
    }

    STDMETHODIMP GetStreamCaps(int iIndex, AM_MEDIA_TYPE **ppmt, BYTE *pSCC) {
        if (iIndex != 0) return E_INVALIDARG;
        if (!ppmt || !pSCC) return E_POINTER;

        AM_MEDIA_TYPE* pmt = (AM_MEDIA_TYPE*)CoTaskMemAlloc(sizeof(AM_MEDIA_TYPE));
        ZeroMemory(pmt, sizeof(AM_MEDIA_TYPE));
        pmt->majortype = MEDIATYPE_Video;
        pmt->subtype = MEDIASUBTYPE_RGB24;
        pmt->bFixedSizeSamples = TRUE;
        pmt->bTemporalCompression = FALSE;
        pmt->lSampleSize = 1280 * 720 * 3;
        pmt->formattype = FORMAT_VideoInfo;

        VIDEOINFOHEADER_CAM* pvih = (VIDEOINFOHEADER_CAM*)CoTaskMemAlloc(sizeof(VIDEOINFOHEADER_CAM));
        ZeroMemory(pvih, sizeof(VIDEOINFOHEADER_CAM));
        pvih->AvgTimePerFrame = 333333; // 30 FPS
        pvih->bmiHeader.biSize = sizeof(BITMAPINFOHEADER_CAM);
        pvih->bmiHeader.biWidth = 1280;
        pvih->bmiHeader.biHeight = 720;
        pvih->bmiHeader.biPlanes = 1;
        pvih->bmiHeader.biBitCount = 24;
        pvih->bmiHeader.biCompression = BI_RGB;
        pvih->bmiHeader.biSizeImage = 1280 * 720 * 3;

        pmt->cbFormat = sizeof(VIDEOINFOHEADER_CAM);
        pmt->pbFormat = (BYTE*)pvih;

        *ppmt = pmt;

        VIDEO_STREAM_CONFIG_CAPS* pCaps = (VIDEO_STREAM_CONFIG_CAPS*)pSCC;
        ZeroMemory(pCaps, sizeof(VIDEO_STREAM_CONFIG_CAPS));
        pCaps->guid = MEDIATYPE_Video;
        pCaps->VideoStandard = 0;
        pCaps->InputSize.cx = 1280;
        pCaps->InputSize.cy = 720;
        pCaps->MinCroppingSize.cx = 1280;
        pCaps->MinCroppingSize.cy = 720;
        pCaps->MaxCroppingSize.cx = 1280;
        pCaps->MaxCroppingSize.cy = 720;
        pCaps->MinOutputSize.cx = 1280;
        pCaps->MinOutputSize.cy = 720;
        pCaps->MaxOutputSize.cx = 1280;
        pCaps->MaxOutputSize.cy = 720;
        pCaps->MinFrameInterval = 333333;
        pCaps->MaxFrameInterval = 333333;
        pCaps->MinBitsPerSecond = 1280 * 720 * 24 * 30;
        pCaps->MaxBitsPerSecond = 1280 * 720 * 24 * 30;

        return S_OK;
    }

    // IKsPropertySet Methods
    STDMETHODIMP Set(REFGUID guidPropSet, DWORD dwPropID, LPVOID pInstanceData, DWORD cbInstanceData, LPVOID pPropData, DWORD cbPropData) {
        return E_NOTIMPL;
    }

    STDMETHODIMP Get(REFGUID guidPropSet, DWORD dwPropID, LPVOID pInstanceData, DWORD cbInstanceData, LPVOID pPropData, DWORD cbPropData, DWORD *pcbReturned) {
        if (guidPropSet == AMPROPSETID_Pin) {
            if (dwPropID == 0) { // AMPROPERTY_PIN_CATEGORY
                if (pPropData == NULL || cbPropData < sizeof(GUID)) return E_INVALIDARG;
                *(GUID*)pPropData = PIN_CATEGORY_CAPTURE;
                if (pcbReturned) *pcbReturned = sizeof(GUID);
                return S_OK;
            }
        }
        return E_PROP_SET_UNSUPPORTED;
    }

    STDMETHODIMP QuerySupported(REFGUID guidPropSet, DWORD dwPropID, DWORD *pTypeSupport) {
        if (guidPropSet == AMPROPSETID_Pin && dwPropID == 0) {
            if (pTypeSupport) *pTypeSupport = 1; // KSPROPERTY_SUPPORT_GET
            return S_OK;
        }
        return E_PROP_SET_UNSUPPORTED;
    }
};

class CPhoneCamEnumPins : public IEnumPins {
    LONG m_cRef;
    ULONG m_iIndex;
    CPhoneCamFilter* m_pFilter;
public:
    CPhoneCamEnumPins(CPhoneCamFilter* pFilter);
    virtual ~CPhoneCamEnumPins() {}

    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) {
        if (!ppv) return E_POINTER;
        if (riid == IID_IUnknown || riid == IID_IEnumPins) {
            *ppv = static_cast<IEnumPins*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = NULL;
        return E_NOINTERFACE;
    }

    STDMETHODIMP_(ULONG) AddRef() { return InterlockedIncrement(&m_cRef); }
    STDMETHODIMP_(ULONG) Release() {
        ULONG res = InterlockedDecrement(&m_cRef);
        if (res == 0) delete this;
        return res;
    }

    STDMETHODIMP Next(ULONG cPins, IPin** ppPins, ULONG* pcFetched);
    STDMETHODIMP Skip(ULONG cPins) { m_iIndex += cPins; return (m_iIndex <= 1) ? S_OK : S_FALSE; }
    STDMETHODIMP Reset() { m_iIndex = 0; return S_OK; }
    STDMETHODIMP Clone(IEnumPins** ppEnum) { return E_NOTIMPL; }
};

class CPhoneCamFilter : public IBaseFilter {
    LONG m_cRef;
    FILTER_STATE m_state;
    IFilterGraph* m_pGraph;
    CPhoneCamOutputPin* m_pOutputPin;
public:
    CPhoneCamFilter() : m_cRef(1), m_state(State_Stopped), m_pGraph(NULL) {
        InterlockedIncrement(&g_cRefModule);
        m_pOutputPin = new CPhoneCamOutputPin(this);
    }

    ~CPhoneCamFilter() {
        if (m_pOutputPin) {
            m_pOutputPin->Release();
            m_pOutputPin = NULL;
        }
        InterlockedDecrement(&g_cRefModule);
    }

    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) {
        if (!ppv) return E_POINTER;
        if (riid == IID_IUnknown || riid == IID_IPersist || riid == IID_IMediaFilter || riid == IID_IBaseFilter) {
            *ppv = static_cast<IBaseFilter*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = NULL;
        return E_NOINTERFACE;
    }

    STDMETHODIMP_(ULONG) AddRef() { return InterlockedIncrement(&m_cRef); }
    STDMETHODIMP_(ULONG) Release() {
        ULONG res = InterlockedDecrement(&m_cRef);
        if (res == 0) delete this;
        return res;
    }

    STDMETHODIMP GetClassID(CLSID* pClassID) {
        if (!pClassID) return E_POINTER;
        *pClassID = CLSID_PhoneCamFilter;
        return S_OK;
    }

    STDMETHODIMP Stop() {
        m_state = State_Stopped;
        if (m_pOutputPin) m_pOutputPin->StopStreaming();
        return S_OK;
    }

    STDMETHODIMP Pause() {
        m_state = State_Paused;
        return S_OK;
    }

    STDMETHODIMP Run(REFERENCE_TIME tStart) {
        m_state = State_Running;
        if (m_pOutputPin) m_pOutputPin->StartStreaming();
        return S_OK;
    }

    STDMETHODIMP GetState(DWORD dwMilliSecsTimeout, FILTER_STATE* State) {
        if (!State) return E_POINTER;
        *State = m_state;
        return S_OK;
    }

    STDMETHODIMP SetSyncSource(IReferenceClock* pClock) { return S_OK; }
    STDMETHODIMP GetSyncSource(IReferenceClock** ppClock) { if (ppClock) *ppClock = NULL; return S_OK; }

    STDMETHODIMP EnumPins(IEnumPins** ppEnum) {
        if (!ppEnum) return E_POINTER;
        *ppEnum = new CPhoneCamEnumPins(this);
        return S_OK;
    }

    STDMETHODIMP FindPin(LPCWSTR Id, IPin** ppPin) {
        if (!ppPin) return E_POINTER;
        *ppPin = m_pOutputPin;
        m_pOutputPin->AddRef();
        return S_OK;
    }

    STDMETHODIMP QueryFilterInfo(FILTER_INFO* pInfo) {
        if (!pInfo) return E_POINTER;
        lstrcpyW(pInfo->achName, FILTER_NAME);
        pInfo->pGraph = m_pGraph;
        if (m_pGraph) m_pGraph->AddRef();
        return S_OK;
    }

    STDMETHODIMP JoinFilterGraph(IFilterGraph* pGraph, LPCWSTR pName) {
        m_pGraph = pGraph;
        return S_OK;
    }

    STDMETHODIMP QueryVendorInfo(LPWSTR* pVendorInfo) { return E_NOTIMPL; }

    CPhoneCamOutputPin* GetPin() { return m_pOutputPin; }
};

CPhoneCamOutputPin::CPhoneCamOutputPin(CPhoneCamFilter* pFilter)
    : m_cRef(1), m_pFilter(pFilter), m_pConnectedPin(NULL), m_pConnectedMemInput(NULL),
      m_pAllocator(NULL), m_hStreamThread(NULL), m_bStreaming(false), m_frameCount(0) {}

CPhoneCamOutputPin::~CPhoneCamOutputPin() {
    StopStreaming();
}

void CPhoneCamOutputPin::StartStreaming() {
    if (m_bStreaming) return;
    m_bStreaming = true;
    m_frameCount = 0;
    m_hStreamThread = CreateThread(NULL, 0, StreamThreadProc, this, 0, NULL);
}

void CPhoneCamOutputPin::StopStreaming() {
    if (!m_bStreaming) return;
    m_bStreaming = false;
    if (m_hStreamThread) {
        WaitForSingleObject(m_hStreamThread, 1000);
        CloseHandle(m_hStreamThread);
        m_hStreamThread = NULL;
    }
}

DWORD WINAPI CPhoneCamOutputPin::StreamThreadProc(LPVOID lpParam) {
    CPhoneCamOutputPin* pPin = (CPhoneCamOutputPin*)lpParam;
    if (pPin) pPin->DoStreamLoop();
    return 0;
}

void CPhoneCamOutputPin::DoStreamLoop() {
    HANDLE hSharedMem = OpenFileMappingW(FILE_MAP_READ, FALSE, PHONECAM_SHM_NAME);
    HANDLE hMutex = OpenMutexW(SYNCHRONIZE, FALSE, PHONECAM_MUTEX_NAME);

    void* pBuffer = NULL;
    if (hSharedMem) {
        pBuffer = MapViewOfFile(hSharedMem, FILE_MAP_READ, 0, 0, PHONECAM_MAX_BUF_SIZE);
    }

    PhoneCamFrameHeader* pHeader = (PhoneCamFrameHeader*)pBuffer;
    uint8_t* pFrameData = pBuffer ? ((uint8_t*)pBuffer + sizeof(PhoneCamFrameHeader)) : NULL;

    const ULONG frameSize = 1280 * 720 * 3;

    while (m_bStreaming) {
        if (!m_pAllocator || !m_pConnectedMemInput) {
            Sleep(33);
            continue;
        }

        IMediaSample* pSample = NULL;
        HRESULT hr = m_pAllocator->GetBuffer(&pSample, NULL, NULL, 0);
        if (SUCCEEDED(hr) && pSample) {
            BYTE* pData = NULL;
            pSample->GetPointer(&pData);

            if (pData) {
                bool hasFrame = false;
                if (hMutex) WaitForSingleObject(hMutex, 50);

                if (pHeader && pHeader->magic == PHONECAM_MAGIC && pHeader->isConnected == 1 && pHeader->payloadSize > 0 && pFrameData) {
                    ULONG copyBytes = pHeader->payloadSize < frameSize ? pHeader->payloadSize : frameSize;
                    memcpy(pData, pFrameData, copyBytes);
                    hasFrame = true;
                }

                if (hMutex) ReleaseMutex(hMutex);

                if (!hasFrame) {
                    // Fill dark standby background pattern
                    for (ULONG i = 0; i < frameSize; i += 3) {
                        pData[i] = 40;     // B
                        pData[i + 1] = 20; // G
                        pData[i + 2] = 15; // R
                    }
                }
            }

            REFERENCE_TIME tStart = m_frameCount * 333333;
            REFERENCE_TIME tStop = tStart + 333333;
            pSample->SetTime(&tStart, &tStop);
            pSample->SetSyncPoint(TRUE);

            m_pConnectedMemInput->Receive(pSample);
            pSample->Release();
            m_frameCount++;
        }

        Sleep(33); // 30 FPS pacing
    }

    if (pBuffer) UnmapViewOfFile(pBuffer);
    if (hSharedMem) CloseHandle(hSharedMem);
    if (hMutex) CloseHandle(hMutex);
}

CPhoneCamEnumPins::CPhoneCamEnumPins(CPhoneCamFilter* pFilter)
    : m_cRef(1), m_iIndex(0), m_pFilter(pFilter) {}

STDMETHODIMP CPhoneCamEnumPins::Next(ULONG cPins, IPin** ppPins, ULONG* pcFetched) {
    if (!ppPins) return E_POINTER;
    if (m_iIndex > 0) {
        if (pcFetched) *pcFetched = 0;
        return S_FALSE;
    }
    ppPins[0] = m_pFilter->GetPin();
    ppPins[0]->AddRef();
    m_iIndex++;
    if (pcFetched) *pcFetched = 1;
    return S_OK;
}

class CPhoneCamClassFactory : public IClassFactory {
    LONG m_cRef;
public:
    CPhoneCamClassFactory() : m_cRef(1) { InterlockedIncrement(&g_cRefModule); }
    ~CPhoneCamClassFactory() { InterlockedDecrement(&g_cRefModule); }

    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) {
        if (!ppv) return E_POINTER;
        if (riid == IID_IUnknown || riid == IID_IClassFactory) {
            *ppv = static_cast<IClassFactory*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = NULL;
        return E_NOINTERFACE;
    }

    STDMETHODIMP_(ULONG) AddRef() { return InterlockedIncrement(&m_cRef); }
    STDMETHODIMP_(ULONG) Release() {
        ULONG res = InterlockedDecrement(&m_cRef);
        if (res == 0) delete this;
        return res;
    }

    STDMETHODIMP CreateInstance(IUnknown* pUnkOuter, REFIID riid, void** ppv) {
        if (pUnkOuter != NULL) return CLASS_E_NOAGGREGATION;
        CPhoneCamFilter* pFilter = new CPhoneCamFilter();
        HRESULT hr = pFilter->QueryInterface(riid, ppv);
        pFilter->Release();
        return hr;
    }

    STDMETHODIMP LockServer(BOOL fLock) {
        if (fLock) InterlockedIncrement(&g_cRefModule);
        else InterlockedDecrement(&g_cRefModule);
        return S_OK;
    }
};

static bool RegisterKey(HKEY rootKey, const wchar_t* subKey, const wchar_t* valueName, const wchar_t* data) {
    HKEY hKey = NULL;
    if (RegCreateKeyExW(rootKey, subKey, 0, NULL, 0, KEY_WRITE, NULL, &hKey, NULL) == ERROR_SUCCESS) {
        if (data != NULL) {
            RegSetValueExW(hKey, valueName, 0, REG_SZ, (BYTE*)data, (lstrlenW(data) + 1) * sizeof(wchar_t));
        }
        RegCloseKey(hKey);
        return true;
    }
    return false;
}

static bool RegisterBinaryKey(HKEY rootKey, const wchar_t* subKey, const wchar_t* valueName, const BYTE* pData, DWORD cbData) {
    HKEY hKey = NULL;
    if (RegCreateKeyExW(rootKey, subKey, 0, NULL, 0, KEY_WRITE, NULL, &hKey, NULL) == ERROR_SUCCESS) {
        RegSetValueExW(hKey, valueName, 0, REG_BINARY, pData, cbData);
        RegCloseKey(hKey);
        return true;
    }
    return false;
}

static bool DeleteKey(HKEY rootKey, const wchar_t* subKey) {
    return RegDeleteKeyW(rootKey, subKey) == ERROR_SUCCESS;
}

STDAPI DllRegisterServer() {
    wchar_t szModule[MAX_PATH];
    if (GetModuleFileNameW(g_hModule, szModule, MAX_PATH) == 0) return E_FAIL;

    wchar_t szSubKey[MAX_PATH];

    // Require HKLM System-Wide Administrator Registration
    HKEY rootKey = HKEY_LOCAL_MACHINE;
    HKEY hTestKey = NULL;
    if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Classes\\CLSID", 0, KEY_WRITE, &hTestKey) != ERROR_SUCCESS) {
        // Return E_ACCESSDENIED if process is not running as Administrator
        return E_ACCESSDENIED;
    }
    RegCloseKey(hTestKey);

    // 1. DirectShow CLSID Registration
    wsprintfW(szSubKey, L"SOFTWARE\\Classes\\CLSID\\%s", CLSID_STRING);
    RegisterKey(rootKey, szSubKey, NULL, FILTER_NAME);

    wsprintfW(szSubKey, L"SOFTWARE\\Classes\\CLSID\\%s\\InprocServer32", CLSID_STRING);
    RegisterKey(rootKey, szSubKey, NULL, szModule);
    RegisterKey(rootKey, szSubKey, L"ThreadingModel", L"Both");

    // 2. DirectShow Video Input Device Category (System-Wide with Pin Metadata)
    wsprintfW(szSubKey, L"SOFTWARE\\Classes\\CLSID\\{860BB310-5D01-11d0-BD3B-00A0C911CE86}\\Instance\\%s", CLSID_STRING);
    RegisterKey(rootKey, szSubKey, L"FriendlyName", FILTER_NAME);
    RegisterKey(rootKey, szSubKey, L"CLSID", CLSID_STRING);

    static const BYTE filterData[] = {
        0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x08, 0x00,
        0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x33, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
        0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    };
    RegisterBinaryKey(rootKey, szSubKey, L"FilterData", filterData, sizeof(filterData));

    // 3. Media Foundation Platform Registration (64-bit and 32-bit WOW64)
    wsprintfW(szSubKey, L"SOFTWARE\\Microsoft\\Windows Media Foundation\\Platform\\%s", CLSID_STRING);
    RegisterKey(rootKey, szSubKey, L"FriendlyName", FILTER_NAME);
    RegisterKey(rootKey, szSubKey, L"CLSID", CLSID_STRING);

    wsprintfW(szSubKey, L"SOFTWARE\\WOW6432Node\\Microsoft\\Windows Media Foundation\\Platform\\%s", CLSID_STRING);
    RegisterKey(rootKey, szSubKey, L"FriendlyName", FILTER_NAME);
    RegisterKey(rootKey, szSubKey, L"CLSID", CLSID_STRING);

    return S_OK;
}

STDAPI DllUnregisterServer() {
    wchar_t szSubKey[MAX_PATH];

    HKEY rootKey = HKEY_LOCAL_MACHINE;

    wsprintfW(szSubKey, L"SOFTWARE\\Classes\\CLSID\\{860BB310-5D01-11d0-BD3B-00A0C911CE86}\\Instance\\%s", CLSID_STRING);
    DeleteKey(rootKey, szSubKey);

    wsprintfW(szSubKey, L"SOFTWARE\\Classes\\CLSID\\%s\\InprocServer32", CLSID_STRING);
    DeleteKey(rootKey, szSubKey);

    wsprintfW(szSubKey, L"SOFTWARE\\Classes\\CLSID\\%s", CLSID_STRING);
    DeleteKey(rootKey, szSubKey);

    wsprintfW(szSubKey, L"SOFTWARE\\Microsoft\\Windows Media Foundation\\Platform\\%s", CLSID_STRING);
    DeleteKey(rootKey, szSubKey);

    wsprintfW(szSubKey, L"SOFTWARE\\WOW6432Node\\Microsoft\\Windows Media Foundation\\Platform\\%s", CLSID_STRING);
    DeleteKey(rootKey, szSubKey);

    return S_OK;
}

STDAPI DllCanUnloadNow() {
    return (g_cRefModule == 0) ? S_OK : S_FALSE;
}

STDAPI DllGetClassObject(REFCLSID rclsid, REFIID riid, void** ppv) {
    if (rclsid == CLSID_PhoneCamFilter) {
        CPhoneCamClassFactory* pFactory = new CPhoneCamClassFactory();
        HRESULT hr = pFactory->QueryInterface(riid, ppv);
        pFactory->Release();
        return hr;
    }
    return CLASS_E_CLASSNOTAVAILABLE;
}
