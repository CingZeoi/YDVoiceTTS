#include once "include/ydvoice.bi"
#include once "include/pinyin.bi"
#include once "crt/wchar.bi"

'' <- 全局变量与单例字典控制 ->
Dim Shared As WString * MAX_PATH g_DllDir
Dim Shared As HANDLE g_hDictFile = INVALID_HANDLE_VALUE
Dim Shared As HANDLE g_hDictMap = NULL
Dim Shared As DictEntry Ptr g_pDictBase = NULL
Dim Shared As ULong g_DictCount = 0

'' 二进制字典的安全锁状态
Dim Shared As Long g_DictInitState = 0

Private Function Internal_LoadSharedDict() As Boolean
    If g_DictInitState = 2 Then Return True
    
    '' 轻量级自旋锁
    While InterlockedCompareExchange(@g_DictInitState, 1, 0) <> 0
        If g_DictInitState = 2 Then Return True
        Sleep 1, 1
    Wend
    
    If g_pDictBase <> NULL Then
        InterlockedExchange(@g_DictInitState, 2)
        Return True
    End If

    Dim As WString * MAX_PATH dictPath = g_DllDir & "pymap.bin"
    g_hDictFile = CreateFileW(@dictPath, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL)
    If g_hDictFile = INVALID_HANDLE_VALUE Then 
        InterlockedExchange(@g_DictInitState, 0)
        Return False
    End If

    Dim As LARGE_INTEGER fsDict
    If GetFileSizeEx(g_hDictFile, @fsDict) = 0 Then
        CloseHandle(g_hDictFile): g_hDictFile = INVALID_HANDLE_VALUE
        InterlockedExchange(@g_DictInitState, 0)
        Return False
    End If
    g_DictCount = fsDict.QuadPart \ SizeOf(DictEntry)

    g_hDictMap = CreateFileMapping(g_hDictFile, NULL, PAGE_READONLY, 0, 0, NULL)
    If g_hDictMap = NULL Then
        CloseHandle(g_hDictFile): g_hDictFile = INVALID_HANDLE_VALUE
        InterlockedExchange(@g_DictInitState, 0)
        Return False
    End If

    g_pDictBase = Cast(DictEntry Ptr, MapViewOfFile(g_hDictMap, FILE_MAP_READ, 0, 0, 0))
    If g_pDictBase = NULL Then
        CloseHandle(g_hDictMap): g_hDictMap = NULL
        CloseHandle(g_hDictFile): g_hDictFile = INVALID_HANDLE_VALUE
        InterlockedExchange(@g_DictInitState, 0)
        Return False
    End If
    
    InterlockedExchange(@g_DictInitState, 2)
    Return True
End Function

Private Sub Cleanup_SharedDict() Destructor
    If g_pDictBase Then UnmapViewOfFile(g_pDictBase)
    If g_hDictMap Then CloseHandle(g_hDictMap)
    If g_hDictFile <> INVALID_HANDLE_VALUE Then CloseHandle(g_hDictFile)
End Sub

Private Sub AutoInit_DLL() Constructor
    Dim As WString * MAX_PATH dllPath
    GetModuleFileNameW(GetModuleHandleW("ydvoice.dll"), @dllPath, MAX_PATH)
    Dim As Integer lastSlash = -1
    For i As Integer = 0 To Len(dllPath) - 1
        If dllPath[i] = Asc("\") Or dllPath[i] = Asc("/") Then lastSlash = i
    Next
    If lastSlash <> -1 Then
        MemCpy(@g_DllDir, @dllPath, (lastSlash + 1) * 2)
        g_DllDir[lastSlash + 1] = 0
    Else
        g_DllDir = ".\"
    End If
End Sub

Private Function Internal_GetIdByPinyin(ByVal pKey As WString Ptr) As ULong
    If g_pDictBase = NULL Or g_DictCount = 0 Then Return 23
    Dim As Integer low_idx = 0
    Dim As Integer high_idx = g_DictCount - 1
    Dim As Integer mid_idx, res
    While low_idx <= high_idx
        mid_idx = low_idx + (high_idx - low_idx) \ 2
        Dim As DictEntry Ptr entry = g_pDictBase + mid_idx
        res = wcscmp(@entry->key, pKey)
        If res = 0 Then Return entry->value
        If res < 0 Then low_idx = mid_idx + 1 Else high_idx = mid_idx - 1
    Wend
    Return 23
End Function

Extern "Windows-MS"

Function Voice_Load(ByVal pVoicePath As WString Ptr) As Any Ptr Export
    If pVoicePath = NULL Then Return NULL
    If Internal_LoadSharedDict() = False Then Return NULL
    If Internal_LoadPhrasesDict() = False Then Return NULL
    
    Dim As VoiceContext Ptr ctx = New VoiceContext()
    If ctx = NULL Then Return NULL
    
    ctx->hFile = CreateFileW(pVoicePath, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL)
    If ctx->hFile = INVALID_HANDLE_VALUE Then Delete ctx : Return NULL
    
    ctx->hMap = CreateFileMapping(ctx->hFile, NULL, PAGE_READONLY, 0, 0, NULL)
    If ctx->hMap = NULL Then Delete ctx : Return NULL
    
    ctx->pBase = MapViewOfFile(ctx->hMap, FILE_MAP_READ, 0, 0, 0)
    If ctx->pBase = NULL Then Delete ctx : Return NULL
    
    Dim As LARGE_INTEGER fs
    GetFileSizeEx(ctx->hFile, @fs)
    ctx->FileSize = fs.QuadPart '' 记录实际物理文件大小
    
    ctx->TotalIds = *Cast(ULong Ptr, ctx->pBase)
    If (32 + Cast(LongInt, ctx->TotalIds) * 8) > ctx->FileSize Then Delete ctx : Return NULL
    
    ctx->Channels = *Cast(UShort Ptr, ctx->pBase + &h04)
    ctx->SampleRate = *Cast(ULong Ptr, ctx->pBase + &h08)
    ctx->BitsPerSample = *Cast(UShort Ptr, ctx->pBase + &h12)
    ctx->pIndexTable = Cast(IndexEntry Ptr, ctx->pBase + 32)
    Return ctx
End Function

End Extern

'' 底层合成逻辑
Private Function Voice_GetPcmData(ByVal hVoice As Any Ptr, ByVal pIds As ULong Ptr, ByVal count As Long, ByRef outSize As Long, ByVal addWavHeader As Boolean) As Byte Ptr
    outSize = 0
    If hVoice = NULL OrElse pIds = NULL OrElse count <= 0 Then Return NULL
    Dim As VoiceContext Ptr ctx = Cast(VoiceContext Ptr, hVoice)
    If ctx->Magic <> VOICE_MAGIC Then Return NULL
    
    Dim As LongInt pcmBytes = 0
    Dim As Boolean lastWasInvalid = False
    Dim As ULong FALLBACK_ID = 23
    
    '' 第一遍扫描：计算总大小
    For i As Integer = 0 To count - 1
        Dim As IndexEntry Ptr entry = NULL
        If pIds[i] < ctx->TotalIds Then entry = ctx->pIndexTable + pIds[i]
        
        Dim As Boolean isValid = False
        If entry <> NULL AndAlso entry->Size > 0 Then
            '' 绝对防御：越界大小校验
            If (Cast(LongInt, entry->Offset) + Cast(LongInt, entry->Size)) <= ctx->FileSize Then isValid = True
        End If
        
        If isValid Then
            pcmBytes += entry->Size : lastWasInvalid = False
        ElseIf lastWasInvalid = False Then
            If FALLBACK_ID < ctx->TotalIds Then '' 判断兜底ID是否有效
                Dim As IndexEntry Ptr fb = ctx->pIndexTable + FALLBACK_ID
                If fb->Size > 0 AndAlso (Cast(LongInt, fb->Offset) + Cast(LongInt, fb->Size)) <= ctx->FileSize Then
                    pcmBytes += fb->Size
                End If
            End If
            lastWasInvalid = True
        End If
    Next
    
    If pcmBytes <= 0 Then Return NULL
    Dim As Long headerSize = IIf(addWavHeader, SizeOf(WavHeader), 0)
    
    Dim As Byte Ptr pBuf = Allocate(headerSize + pcmBytes)
    If pBuf = NULL Then Return NULL '' 拦截超大合成引发的 OOM
    
    If addWavHeader Then
        Dim As WavHeader Ptr hw = Cast(WavHeader Ptr, pBuf)
        hw->riffId = &h46464952 : hw->waveId = &h45564157
        hw->fmtId = &h20746D66 : hw->dataId = &h61746164
        hw->fmtSize = 16 : hw->audioFormat = 1
        hw->channels = ctx->Channels : hw->sampleRate = ctx->SampleRate : hw->bitsPerSample = ctx->BitsPerSample
        hw->dataSize = Cast(ULong, pcmBytes) : hw->fileSize = Cast(ULong, pcmBytes + 36)
        hw->byteRate = (ctx->SampleRate * ctx->Channels * ctx->BitsPerSample) \ 8
        hw->blockAlign = (ctx->Channels * ctx->BitsPerSample) \ 8
    End If
    
    '' 第二遍扫描：拷贝数据
    Dim As Byte Ptr pWrite = pBuf + headerSize
    lastWasInvalid = False
    For i As Integer = 0 To count - 1
        Dim As IndexEntry Ptr entry = NULL
        If pIds[i] < ctx->TotalIds Then entry = ctx->pIndexTable + pIds[i]
        
        Dim As Boolean isValid = False
        If entry <> NULL AndAlso entry->Size > 0 Then
            If (Cast(LongInt, entry->Offset) + Cast(LongInt, entry->Size)) <= ctx->FileSize Then isValid = True
        End If
        
        If isValid Then
            MemCpy(pWrite, ctx->pBase + entry->Offset, entry->Size)
            pWrite += entry->Size : lastWasInvalid = False
        ElseIf lastWasInvalid = False Then
            If FALLBACK_ID < ctx->TotalIds Then
                Dim As IndexEntry Ptr fb = ctx->pIndexTable + FALLBACK_ID
                If fb->Size > 0 AndAlso (Cast(LongInt, fb->Offset) + Cast(LongInt, fb->Size)) <= ctx->FileSize Then
                    MemCpy(pWrite, ctx->pBase + fb->Offset, fb->Size)
                    pWrite += fb->Size
                End If
            End If
            lastWasInvalid = True
        End If
    Next
    
    outSize = headerSize + pcmBytes
    Return pBuf
End Function

Private Function Voice_Synthesis(ByVal hVoice As Any Ptr, ByVal ppTextArray As WString Ptr Ptr, ByVal arrayCount As Long, ByRef outSize As Long, ByVal addWavHeader As Boolean) As Byte Ptr
    outSize = 0
    If hVoice = NULL OrElse ppTextArray = NULL OrElse arrayCount <= 0 Then Return NULL
    Dim As VoiceContext Ptr ctx = Cast(VoiceContext Ptr, hVoice)
    If ctx->Magic <> VOICE_MAGIC Then Return NULL
    Dim As ULong Ptr pIds = Allocate(arrayCount * SizeOf(ULong))
    If pIds = NULL Then Return NULL
    For i As Integer = 0 To arrayCount - 1
        pIds[i] = Internal_GetIdByPinyin(ppTextArray[i])
    Next
    Dim As Byte Ptr pResult = Voice_GetPcmData(hVoice, pIds, arrayCount, outSize, addWavHeader)
    Deallocate(pIds)
    Return pResult
End Function

Extern "Windows-MS"

Function Voice_SynthesisText(ByVal hVoice As Any Ptr, _
                             ByVal pText As WString Ptr, _
                             ByRef outSize As Long, _
                             ByVal addWavHeader As Boolean) As Byte Ptr Export
                             
    outSize = 0
    If hVoice = NULL OrElse pText = NULL OrElse Len(*pText) = 0 Then Return NULL
    Dim As VoiceContext Ptr ctx = Cast(VoiceContext Ptr, hVoice)
    If ctx->Magic <> VOICE_MAGIC Then Return NULL
    
    Dim As WStringArray pinyinArr = Internal_PinyinConvert(pText)
    If pinyinArr.count = 0 Then Return NULL
    
    Dim As ULong Ptr pIds = Allocate(pinyinArr.count * SizeOf(ULong))
    If pIds = NULL Then 
        Internal_FreeWStringArray(pinyinArr)
        Return NULL
    End If
    
    Dim As Integer validIdCount = 0
    Dim As ULong lastId = &hFFFFFFFFul

    '' 查 ID 并去除内部连续的 23 （静音）
    For i As Integer = 0 To pinyinArr.count - 1
        Dim As ULong currentId = Internal_GetIdByPinyin(pinyinArr.items[i])
        If currentId = 23 AndAlso lastId = 23 Then Continue For
        pIds[validIdCount] = currentId
        validIdCount += 1
        lastId = currentId
    Next
    
    '' 首尾静音(23号)双向剥离修剪
    Dim As Integer startIdx = 0
    While startIdx < validIdCount AndAlso pIds[startIdx] = 23
        startIdx += 1
    Wend
    
    Dim As Integer endIdx = validIdCount - 1
    While endIdx >= startIdx AndAlso pIds[endIdx] = 23
        endIdx -= 1
    Wend
    
    Dim As Integer finalCount = endIdx - startIdx + 1
    Dim As Byte Ptr pResult = NULL
    
    '' 执行音频生成 (传入修剪后的切片起始地址与实际长度)
    If finalCount > 0 Then
        pResult = Voice_GetPcmData(hVoice, pIds + startIdx, finalCount, outSize, addWavHeader)
    End If
    
    Deallocate(pIds)
    Internal_FreeWStringArray(pinyinArr)
    
    Return pResult
End Function

Sub Voice_FreeBuffer(ByVal pBuffer As Any Ptr) Export
    If pBuffer <> NULL Then Deallocate(pBuffer)
End Sub

Sub Voice_Release(ByVal hVoice As Any Ptr) Export
    If hVoice <> NULL Then
        Dim As VoiceContext Ptr ctx = Cast(VoiceContext Ptr, hVoice)
        If ctx->Magic = VOICE_MAGIC Then Delete ctx
    End If
End Sub

End Extern