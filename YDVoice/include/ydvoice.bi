#pragma once
#include once "windows.bi"
#include once "crt/string.bi"
#include once "crt/wchar.bi"

#define VOICE_MAGIC &h564F4943 

'' 字典条目
Type DictEntry Field = 1
    As WString * 14 key
    As ULong value
End Type

'' WAV 头部结构
Type WavHeader Field = 1
    As ULong riffId, fileSize, waveId, fmtId, fmtSize
    As UShort audioFormat, channels
    As ULong sampleRate, byteRate
    As UShort blockAlign, bitsPerSample
    As ULong dataId, dataSize
End Type

'' 语音库索引项
Type IndexEntry Field = 1
    As ULong Offset
    As ULong Size
End Type

'' 语音库上下文
Type VoiceContext
    As ULong Magic
    As HANDLE hFile
    As HANDLE hMap
    As Any Ptr pBase
    
    As LongInt FileSize
    
    As ULong TotalIds
    As IndexEntry Ptr pIndexTable
    
    As UShort Channels
    As ULong SampleRate
    As UShort BitsPerSample
    
    Declare Constructor()
    Declare Destructor()
End Type

Constructor VoiceContext()
    This.Magic = VOICE_MAGIC
    This.hFile = INVALID_HANDLE_VALUE
    This.hMap = NULL
    This.pBase = NULL
    This.FileSize = 0
    This.pIndexTable = NULL
End Constructor

Destructor VoiceContext()
    This.Magic = 0
    If This.pBase Then UnmapViewOfFile(This.pBase)
    If This.hMap  Then CloseHandle(This.hMap)
    If This.hFile <> INVALID_HANDLE_VALUE Then CloseHandle(This.hFile)
End Destructor
