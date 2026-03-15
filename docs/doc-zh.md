# YDVoice 中文语音合成引擎简明使用指南

---

## 1. 简介

YDVoice 是一款轻量级、离线的中文语音合成引擎，基于波形拼接技术，源自对 2000 年前后广受视障人士欢迎的永德读屏语音库。

本引擎提供简单的 C 语言接口（导出为动态链接库），可在 Windows上快速集成，适用于辅助工具、嵌入式/脱机语音播报等场景。

**核心特点**：
- 无网络依赖，无需深度学习框架
- 内存占用极小（< 10 MB），运行效率非常高
- 支持直接读取原始 `ydvoiceXX.vl` 语音库
- 提供标准 C 接口，易于多种语言调用

---

## 2. 必需文件

在使用 YDVoice 前，请确保以下文件位于**同一目录**：

| 文件名          | 说明 |
|----------------|------|
| `ydvoiceXX.vl` | 原始语音库文件（例如 `ydvoice00.vl` ～ `ydvoice04.vl`），包含所有音频数据。 |
| `ydvoice.dll`  | YDVoice 动态链接库（Windows DLL）。 |
| `pymap.bin`    | 拼音→ID 映射表（二进制格式），引擎运行时用于快速查找音频位置。 |
| `phrases.dat`  | 短语拼音读音修正文件，提升同音字选择场景下的处理能力。 |

将这些文件放在应用程序同一目录下，即可调用 YDVoice TTS API 进行高清晰、高性能的中文语音合成。

---

## 3. API 参考

所有函数均以 `__stdcall` 约定导出（Windows），头文件声明如下：

```c
typedef void* HVOICE;   // 引擎句柄

#ifdef _WIN32
#define YDV_API __declspec(dllexport) __stdcall
#else
#define YDV_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

// 加载语音库，返回句柄
YDV_API HVOICE Voice_Load(const wchar_t* pVoicePath);

// 合成文本，返回音频数据缓冲区指针
YDV_API void* Voice_SynthesisText(HVOICE hVoice, const wchar_t* pText, int* pOutSize, int bAddWavHeader);

// 释放合成返回的缓冲区
YDV_API void Voice_FreeBuffer(void* pBuffer);

// 释放引擎句柄
YDV_API void Voice_Release(HVOICE hVoice);

#ifdef __cplusplus
}
#endif
```

### 3.1 `Voice_Load`

- **功能**：加载语音库文件，初始化引擎。
- **参数**：
  - `pVoicePath`：语音库文件路径（宽字符，Unicode），必须指定具体文件（如 `L"ydvoice00.vl"`）。
- **返回值**：成功返回非零句柄，失败返回 `NULL`。

### 3.2 `Voice_SynthesisText`

- **功能**：合成文本，返回音频数据。
- **参数**：
  - `hVoice`：`Voice_Load` 返回的有效句柄。
  - `pText`：要合成的文本（Unicode 字符串），支持汉字、英文字母、数字。
  - `pOutSize`：输出参数，接收返回数据的大小（字节数）。
  - `bAddWavHeader`：若为非零，返回的数据包含完整的 WAV 文件头（可直接保存为 `.wav`）；若为零，返回纯 PCM 裸流。
- **返回值**：成功返回指向音频数据缓冲区的指针，失败返回 `NULL`。 **必须使用 `Voice_FreeBuffer` 释放**。

### 3.3 `Voice_FreeBuffer`

- **功能**：释放由 `Voice_SynthesisText` 分配的缓冲区。
- **参数**：`pBuffer` – 要释放的缓冲区指针。
- **返回值**：无。

### 3.4 `Voice_Release`

- **功能**：释放引擎句柄，清理资源。
- **参数**：`hVoice` – 要释放的句柄。
- **返回值**：无。

---

## 4. 示例代码

```csharp
using System;
using System.IO;
using System.Runtime.InteropServices;

namespace ConsoleApplication
{
	static class Program
	{
		const string LibName = @"ydvoice_x86.dll";

		// 导入 ydvoice.dll 中的函数
		[DllImport(dllName: LibName, CallingConvention = CallingConvention.StdCall, CharSet = CharSet.Unicode, ExactSpelling = true)]
		static extern IntPtr Voice_Load([MarshalAs(UnmanagedType.LPWStr)] string pVoicePath);

		[DllImport(LibName, CallingConvention = CallingConvention.StdCall, CharSet = CharSet.Unicode, ExactSpelling = true)]
		static extern IntPtr Voice_SynthesisText(IntPtr hVoice,
		[MarshalAs(UnmanagedType.LPWStr)] string pText,
		out int outSize,
		[MarshalAs(UnmanagedType.U1)] bool addWavHeader);

		[DllImport(LibName, CallingConvention = CallingConvention.StdCall, ExactSpelling = true)]
		static extern void Voice_FreeBuffer(IntPtr pBuffer);

		[DllImport(LibName, CallingConvention = CallingConvention.StdCall, ExactSpelling = true)]
		static extern void Voice_Release(IntPtr hVoice);

		static void Main(string[] args)
		{
			try
			{
				// 检查必需的辅助文件是否存在
				string[] auxFiles = { "pymap.bin", "phrases.dat" };
				foreach (var aux in auxFiles)
				{
					if (!File.Exists(aux))
						Console.WriteLine($"提示：辅助文件 {aux} 未找到，引擎可能无法正常工作。");
				}
				string baseText = "欢迎使用永德TTS，我是永德语音库";
				string exeDir = AppDomain.CurrentDomain.BaseDirectory;
				// 依次处理 ydvoice00.vl ~ ydvoice04.vl
				for (int i = 0; i < 5; i++)
				{
					string voiceFile = Path.Combine(exeDir, $"ydvoice{i:00}.vl");
					if (!File.Exists(voiceFile))
					{
						Console.WriteLine($"警告：文件不存在，跳过：{voiceFile}");
						continue;
					}
					Console.WriteLine($"正在加载语音库：{voiceFile}");
					IntPtr hVoice = Voice_Load(voiceFile);
					if (hVoice == IntPtr.Zero)
					{
						Console.WriteLine("加载失败，请检查语音库文件是否完整。");
						continue;
					}
					// 构造完整文本，加上编号
					string fullText = $"{baseText}{i:00}。";
					Console.WriteLine($"合成文本：{fullText}");
					int size;
					IntPtr pcmData = Voice_SynthesisText(hVoice, fullText, out size, true);
					if (pcmData != IntPtr.Zero && size > 0)
					{
						// 将数据复制到托管数组并保存
						byte[] buffer = new byte[size];
						Marshal.Copy(pcmData, buffer, 0, size);
						string outputWav = Path.Combine(exeDir, $"sample_YDVoice{i:00}.wav");
						File.WriteAllBytes(outputWav, buffer);
						Console.WriteLine($"合成成功，已保存：{outputWav} ({size} 字节)");
						// 释放合成缓冲区
						Voice_FreeBuffer(pcmData);
					}
					else
					{
						Console.WriteLine("合成失败！");
					}
					// 释放语音库句柄
					Voice_Release(hVoice);
					Console.WriteLine("---");
				}
				Console.WriteLine("所有任务完成。");
			}
			catch (Exception ex)
			{
				Console.WriteLine(ex.Message);
			}
		}
	}
}
```

---

## 5. 注意事项

- 语音库文件 `ydvoiceXX.vl` 的版权归原作者所有，请确保合法使用。
- `pymap.bin` 可从提供的 Python 工具生成。
- `phrases.dat` 为短语读音修正文件。
- 所有文件必须放置在**同一目录**。

---

*—— 让历史的声音在新时代回响……*
