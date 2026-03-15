#pragma once
#include once "windows.bi"
#include once "crt/string.bi"
#include once "crt/wchar.bi"
#include once "crt/stdlib.bi"

'' 拼音词典条目
Type PhraseEntry Field = 1
    As WString Ptr pKey
    As WString Ptr pPinyin
End Type

'' 动态宽字符串数组结构
Type WStringArray
    As WString Ptr Ptr items
    As Integer count
    As Integer capacity
End Type

'' 仅供内部 (ydvoice.bas) 调用的声明
Declare Function Internal_LoadPhrasesDict() As Boolean
Declare Function Internal_PinyinConvert(ByVal pText As WString Ptr) As WStringArray
Declare Sub Internal_FreeWStringArray(ByRef arr As WStringArray)
