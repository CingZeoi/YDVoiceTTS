@echo off

if not exist bin_x64 mkdir bin_x64

fbc64 -dll -gen gcc -O 3 -strip src\ydvoice.bas src\pinyin.bas res\version.rc -x bin_x64\ydvoice.dll -i include

if %errorlevel% neq 0 (
    echo [错误] 编译失败！
    pause
) else (
    echo [成功] DLL 已生成到 bin 文件夹。
    pause
)

