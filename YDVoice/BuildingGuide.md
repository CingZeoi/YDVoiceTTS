# 中文语音合成系统 YDVoice TTS 编译指南（Windows DLL）

本文档说明如何从源代码构建 YDVoice TTS 引擎，生成 `ydvoice.dll` （Windows 动态链接库）。

## 1. 环境准备：安装 FreeBasic 编译器

本语音合成引擎使用 [FreeBasic](https://sf.net/projects/fbc/) 语言编写。请按以下步骤安装并配置编译环境：

1. **下载编译器**  
   访问 [FreeBasic 项目页面](https://sf.net/projects/fbc/)，下载适用于 Windows 的版本（本项目采用**FreeBASIC-1.10.1-winlibs-gcc-9.3.0**构建发行版）。

2. **解压安装**  
   将压缩包解压到一个**不含空格和中文**的路径，例如 `c:\software\FreeBasic`。

3. **配置环境变量**  
   将 `fbc32.exe` / `fbc64.exe` 所在的目录添加到系统的 `PATH` 环境变量中，以便在命令行中直接调用：
   - 右键“此电脑” → “属性” → “高级系统设置” → “环境变量”。
   - 在“系统变量”或“用户变量”中找到 `Path` 变量，点击“编辑” → “新建”，添加路径（例如 `c:\software\FreeBasic`）。
   - 点击“确定”保存所有窗口。

4. **验证安装**  
   打开一个新的命令提示符（cmd）或 PowerShell，输入：
   ```bash
   fbc32 --version
   fbc64 --version
   ```

   显示出版本信息（如 `FreeBASIC Compiler - Version 1.10.1 (2023-12-24), built for win32 (32bit)` 或 `FreeBASIC Compiler - Version 1.10.1 (2023-12-24), built for win64 (64bit)`），则安装成功。

## 2. 编译 YDVoice DLL

1. **获取源代码**  
   克隆本项目，进入 `YDVoiceTTS` 目录。

2. **执行编译脚本**  
   根据要编译的目标平台，**双击运行**对应的批处理文件：
   - 若要生成 **64位** DLL，运行 `compile_x64.bat`
   - 若要生成 **32位** DLL，运行 `compile_x86.bat`

3. **编译结果**  
   成功后，当前目录下会生成 `bin_x64` / `bin_x86` 文件夹，编译后的 dll 会存放在对应平台的目录中。

## 3. 注意事项

- **位数匹配**：编译的 DLL 位数必须与调用它的应用程序一致（例如 64位应用需使用 64位 DLL）。请根据你的使用场景选择正确的编译脚本。
- **环境变量**：如果运行脚本时提示 `'fbc' 不是内部或外部命令`，说明环境变量未配置正确，请检查 `PATH` 设置并重新进入cmd。
- **依赖文件**：生成的 `ydvoice.dll` 运行时需要与 `ydvoiceXX.vl`、`pymap.bin`、`phrases.dat` 等文件放在同一目录。
