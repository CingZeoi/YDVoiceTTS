#include once "include/pinyin.bi"

'' <- 全局静态变量 ->
Dim Shared As WString * MAX_PATH g_PinyinDllDir
Dim Shared As WString Ptr g_PhraseBuffer = NULL
Dim Shared As PhraseEntry Ptr g_PhraseDict = NULL
Dim Shared As Integer g_PhraseCount = 0
Dim Shared As Integer g_MaxPhraseLen = 0

'' 线程安全锁：0=未初始化, 1=正在初始化, 2=初始化完毕
Dim Shared As Long g_PinyinInitState = 0

'' <- DLL 自动初始化 ->
Private Sub AutoInit_PinyinDLL() Constructor
    Dim As WString * MAX_PATH dllPath
    GetModuleFileNameW(GetModuleHandleW("ydvoice.dll"), @dllPath, MAX_PATH)
    Dim As Integer lastSlash = -1
    For i As Integer = 0 To Len(dllPath) - 1
        If dllPath[i] = Asc("\") Or dllPath[i] = Asc("/") Then lastSlash = i
    Next
    If lastSlash <> -1 Then
        MemCpy(@g_PinyinDllDir, @dllPath, (lastSlash + 1) * 2)
        g_PinyinDllDir[lastSlash + 1] = 0
    Else
        g_PinyinDllDir = ".\"
    End If
End Sub

Private Function ComparePhrase Cdecl (ByVal p1 As Const Any Ptr, ByVal p2 As Const Any Ptr) As Long
    Dim As Const PhraseEntry Ptr e1 = Cast(Const PhraseEntry Ptr, p1)
    Dim As Const PhraseEntry Ptr e2 = Cast(Const PhraseEntry Ptr, p2)
    Return wcscmp(e1->pKey, e2->pKey)
End Function

Private Function Internal_FindPhrase(ByVal pKey As WString Ptr) As WString Ptr
    If g_PhraseCount = 0 OrElse g_PhraseDict = NULL Then Return NULL
    Dim As PhraseEntry target
    target.pKey = pKey
    Dim As PhraseEntry Ptr pFound = Cast(PhraseEntry Ptr, bsearch(@target, g_PhraseDict, g_PhraseCount, SizeOf(PhraseEntry), @ComparePhrase))
    If pFound <> NULL Then Return pFound->pPinyin
    Return NULL
End Function

Function Internal_LoadPhrasesDict() As Boolean
    If g_PinyinInitState = 2 Then Return True
    
    '' 轻量级自旋锁：拦截并发
    While InterlockedCompareExchange(@g_PinyinInitState, 1, 0) <> 0
        If g_PinyinInitState = 2 Then Return True
        Sleep 1, 1 '' 主动让出 CPU 时间片
    Wend
    
    '' 获得锁后二次检查
    If g_PhraseBuffer <> NULL Then
        InterlockedExchange(@g_PinyinInitState, 2)
        Return True
    End If
    
    Dim As WString * MAX_PATH dictPath = g_PinyinDllDir & "phrases.dat"
    Dim As HANDLE hFile = CreateFileW(@dictPath, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL)
    If hFile = INVALID_HANDLE_VALUE Then 
        InterlockedExchange(@g_PinyinInitState, 0)
        Return False
    End If
    
    Dim As LARGE_INTEGER fs
    GetFileSizeEx(hFile, @fs)
    Dim As Integer fileSize = fs.QuadPart
    If fileSize <= 0 Then 
        CloseHandle(hFile)
        InterlockedExchange(@g_PinyinInitState, 0)
        Return False
    End If
    
    Dim As UByte Ptr utf8Buf = Allocate(fileSize)
    If utf8Buf = NULL Then
        CloseHandle(hFile)
        InterlockedExchange(@g_PinyinInitState, 0)
        Return False
    End If
    
    Dim As ULong bytesRead
    ReadFile(hFile, utf8Buf, fileSize, @bytesRead, NULL)
    CloseHandle(hFile)
    
    Dim As Integer offset = 0
    If fileSize >= 3 AndAlso utf8Buf[0] = &hEF AndAlso utf8Buf[1] = &hBB AndAlso utf8Buf[2] = &hBF Then offset = 3
    
    Dim As Integer wcharsNeeded = MultiByteToWideChar(CP_UTF8, 0, Cast(LPCSTR, utf8Buf + offset), fileSize - offset, NULL, 0)
    g_PhraseBuffer = Allocate((wcharsNeeded + 1) * SizeOf(WString))
    
    If g_PhraseBuffer = NULL Then
        Deallocate(utf8Buf)
        InterlockedExchange(@g_PinyinInitState, 0)
        Return False
    End If
    
    MultiByteToWideChar(CP_UTF8, 0, Cast(LPCSTR, utf8Buf + offset), fileSize - offset, g_PhraseBuffer, wcharsNeeded)
    g_PhraseBuffer[wcharsNeeded] = 0
    Deallocate(utf8Buf)
    
    Dim As Integer lineCount = 0
    For i As Integer = 0 To wcharsNeeded - 1
        If g_PhraseBuffer[i] = Asc(WStr("|")) Then lineCount += 1
    Next
    
    g_PhraseDict = Allocate(lineCount * SizeOf(PhraseEntry))
    If g_PhraseDict = NULL Then
        Deallocate(g_PhraseBuffer) : g_PhraseBuffer = NULL
        InterlockedExchange(@g_PinyinInitState, 0)
        Return False
    End If
    
    Dim As WString Ptr pScan = g_PhraseBuffer
    Dim As WString Ptr pEnd = g_PhraseBuffer + wcharsNeeded
    Dim As WString Ptr pKey = pScan
    Dim As WString Ptr pVal = NULL
    
    While pScan < pEnd
        If *pScan = Asc(WStr("|")) Then
            *pScan = 0
            pVal = pScan + 1
        ElseIf *pScan = 13 OrElse *pScan = 10 Then
            *pScan = 0
            If pKey <> NULL AndAlso pVal <> NULL AndAlso Len(*pKey) > 0 Then
                g_PhraseDict[g_PhraseCount].pKey = pKey
                g_PhraseDict[g_PhraseCount].pPinyin = pVal
                g_PhraseCount += 1
                Dim As Integer kLen = Len(*pKey)
                If kLen > g_MaxPhraseLen Then g_MaxPhraseLen = kLen
            End If
            pKey = pScan + 1
            pVal = NULL
        End If
        pScan += 1
    Wend
    If pKey <> NULL AndAlso pVal <> NULL AndAlso Len(*pKey) > 0 Then
        g_PhraseDict[g_PhraseCount].pKey = pKey
        g_PhraseDict[g_PhraseCount].pPinyin = pVal
        g_PhraseCount += 1
        Dim As Integer kLen = Len(*pKey)
        If kLen > g_MaxPhraseLen Then g_MaxPhraseLen = kLen
    End If
    
    If g_MaxPhraseLen < 1 Then g_MaxPhraseLen = 1
    If g_PhraseCount > 0 Then qsort(g_PhraseDict, g_PhraseCount, SizeOf(PhraseEntry), @ComparePhrase)
    
    InterlockedExchange(@g_PinyinInitState, 2) '' 标记初始化完成
    Return True
End Function

Private Sub Cleanup_PhrasesDict() Destructor
    If g_PhraseDict <> NULL Then Deallocate(g_PhraseDict): g_PhraseDict = NULL
    If g_PhraseBuffer <> NULL Then Deallocate(g_PhraseBuffer): g_PhraseBuffer = NULL
End Sub

'' <- 动态追加元素到数组 ->
Private Sub ArrayPush(ByRef arr As WStringArray, ByVal pStr As WString Ptr, ByVal cLen As Integer)
    If arr.count >= arr.capacity Then
        Dim As Integer newCap = IIf(arr.capacity = 0, 16, arr.capacity * 2)
        '' 使用临时指针，防止分配失败丢失原有数组内存
        Dim As Any Ptr pTmp = Reallocate(arr.items, newCap * SizeOf(WString Ptr))
        If pTmp = NULL Then Return '' 内存不足，丢弃本次追加
        arr.items = Cast(WString Ptr Ptr, pTmp)
        arr.capacity = newCap
    End If
    
    Dim As WString Ptr newVal = Allocate((cLen + 1) * SizeOf(WString))
    If newVal = NULL Then Return '' 内存不足，丢弃本次追加
    MemCpy(newVal, pStr, cLen * SizeOf(WString))
    newVal[cLen] = 0
    arr.items[arr.count] = newVal
    arr.count += 1
End Sub

Private Sub SplitAndPush(ByRef arr As WStringArray, ByVal pStr As WString Ptr)
    Dim As WString Ptr pStart = pStr
    Dim As WString Ptr pScan = pStr
    While *pScan <> 0
        If *pScan = Asc(WStr(" ")) Then
            If pScan > pStart Then ArrayPush(arr, pStart, pScan - pStart)
            pStart = pScan + 1
        End If
        pScan += 1
    Wend
    If pScan > pStart Then ArrayPush(arr, pStart, pScan - pStart)
End Sub

Sub Internal_FreeWStringArray(ByRef arr As WStringArray)
    If arr.items <> NULL Then
        For i As Integer = 0 To arr.count - 1
            If arr.items[i] <> NULL Then Deallocate(arr.items[i])
        Next
        Deallocate(arr.items)
        arr.items = NULL
    End If
    arr.count = 0
    arr.capacity = 0
End Sub

Private Function ForwardSegment(ByVal pText As WString Ptr) As WStringArray
    Dim As WStringArray res = Type(NULL, 0, 0)
    Dim As Integer textLen = Len(*pText)
    If textLen = 0 Then Return res
    
    res.capacity = textLen
    res.items = Allocate(res.capacity * SizeOf(WString Ptr))
    If res.items = NULL Then res.capacity = 0 : Return res
    
    Dim As WString Ptr tempBuf = Allocate((g_MaxPhraseLen + 1) * SizeOf(WString))
    If tempBuf = NULL Then 
        Deallocate(res.items) : res.items = NULL : res.capacity = 0
        Return res
    End If
    
    Dim As Integer pos_idx = 0
    While pos_idx < textLen
        Dim As Integer matchLen = g_MaxPhraseLen
        If textLen - pos_idx < matchLen Then matchLen = textLen - pos_idx
        
        While matchLen > 0
            MemCpy(tempBuf, pText + pos_idx, matchLen * SizeOf(WString))
            tempBuf[matchLen] = 0
            
            If matchLen = 1 OrElse Internal_FindPhrase(tempBuf) <> NULL Then
                Dim As WString Ptr savedStr = Allocate((matchLen + 1) * SizeOf(WString))
                If savedStr <> NULL Then
                    MemCpy(savedStr, tempBuf, (matchLen + 1) * SizeOf(WString))
                    res.items[res.count] = savedStr
                    res.count += 1
                End If
                pos_idx += matchLen
                Exit While
            End If
            matchLen -= 1
        Wend
    Wend
    Deallocate(tempBuf)
    Return res
End Function

Private Function BackwardSegment(ByVal pText As WString Ptr) As WStringArray
    Dim As WStringArray res = Type(NULL, 0, 0)
    Dim As Integer textLen = Len(*pText)
    If textLen = 0 Then Return res
    
    res.capacity = textLen
    res.items = Allocate(res.capacity * SizeOf(WString Ptr))
    If res.items = NULL Then res.capacity = 0 : Return res
    
    Dim As WString Ptr tempBuf = Allocate((g_MaxPhraseLen + 1) * SizeOf(WString))
    If tempBuf = NULL Then 
        Deallocate(res.items) : res.items = NULL : res.capacity = 0
        Return res
    End If
    
    Dim As Integer pos_idx = textLen
    While pos_idx > 0
        Dim As Integer matchLen = g_MaxPhraseLen
        If pos_idx < matchLen Then matchLen = pos_idx
        
        While matchLen > 0
            MemCpy(tempBuf, pText + pos_idx - matchLen, matchLen * SizeOf(WString))
            tempBuf[matchLen] = 0
            
            If matchLen = 1 OrElse Internal_FindPhrase(tempBuf) <> NULL Then
                Dim As WString Ptr savedStr = Allocate((matchLen + 1) * SizeOf(WString))
                If savedStr <> NULL Then
                    MemCpy(savedStr, tempBuf, (matchLen + 1) * SizeOf(WString))
                    res.items[res.count] = savedStr
                    res.count += 1
                End If
                pos_idx -= matchLen
                Exit While
            End If
            matchLen -= 1
        Wend
    Wend
    Deallocate(tempBuf)
    
    Dim As Integer half = res.count \ 2
    For i As Integer = 0 To half - 1
        Swap res.items[i], res.items[res.count - 1 - i]
    Next
    Return res
End Function

Function Internal_PinyinConvert(ByVal pText As WString Ptr) As WStringArray
    Dim As WStringArray result = Type(NULL, 0, 0)
    If pText = NULL OrElse Len(*pText) = 0 Then Return result
    If Internal_LoadPhrasesDict() = False Then Return result
    
    Dim As WStringArray forwardArr = ForwardSegment(pText)
    Dim As WStringArray backwardArr = BackwardSegment(pText)
    
    Dim As WStringArray finalTokens
    If forwardArr.count <= backwardArr.count Then
        finalTokens = forwardArr
        Internal_FreeWStringArray(backwardArr)
    Else
        finalTokens = backwardArr
        Internal_FreeWStringArray(forwardArr)
    End If
    
    For i As Integer = 0 To finalTokens.count - 1
        Dim As WString Ptr pVal = Internal_FindPhrase(finalTokens.items[i])
        If pVal <> NULL Then
            SplitAndPush(result, pVal)
        Else
            ArrayPush(result, finalTokens.items[i], Len(*(finalTokens.items[i])))
        End If
    Next
    
    Internal_FreeWStringArray(finalTokens)
    Return result
End Function