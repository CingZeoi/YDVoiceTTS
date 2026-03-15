# YDVoice Chinese Speech Synthesis Engine User Guide

---

## 1. Introduction

YDVoice is a lightweight, offline Chinese speech synthesis engine based on waveform concatenation technology. It originates from the Yongde Screen Reader voice library, which was widely embraced by visually impaired users around the year 2000.

This engine provides a simple C language interface (exported as a dynamic link library) for rapid integration on Windows platforms. It is well-suited for assistive technologies, embedded systems, and offline speech playback scenarios.

**Key Features**:
- No network dependency; no deep learning framework required
- Extremely low memory footprint (< 10 MB) with high runtime efficiency
- Direct support for reading raw `ydvoiceXX.vl` voice library files
- Standard C interface for easy invocation from multiple programming languages

---

## 2. Required Files

Before using YDVoice, please ensure the following files are located in the **same directory**:

| Filename         | Description |
|------------------|-------------|
| `ydvoiceXX.vl`   | Raw voice library file (e.g., `ydvoice00.vl` ~ `ydvoice04.vl`), containing all audio data. |
| `ydvoice.dll`    | YDVoice dynamic link library (Windows DLL). |
| `pymap.bin`      | Pinyin-to-ID mapping table (binary format), used by the engine for fast audio segment lookup at runtime. |
| `phrases.dat`    | Phrase pronunciation correction file, enhancing disambiguation capabilities for homophone selection scenarios. |

Place all four files in the same directory as your application to enable high-clarity, high-efficiency Chinese speech synthesis via the provided API.

---

## 3. API Reference

All functions are exported using the `__stdcall` calling convention (Windows). Header file declarations are as follows:

```c
typedef void* HVOICE;   // Engine handle

#ifdef _WIN32
#define YDV_API __declspec(dllexport) __stdcall
#else
#define YDV_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Load voice library and return engine handle
YDV_API HVOICE Voice_Load(const wchar_t* pVoicePath);

// Synthesize text and return pointer to audio data buffer
YDV_API void* Voice_SynthesisText(HVOICE hVoice, const wchar_t* pText, int* pOutSize, int bAddWavHeader);

// Free buffer returned by synthesis function
YDV_API void Voice_FreeBuffer(void* pBuffer);

// Release engine handle and clean up resources
YDV_API void Voice_Release(HVOICE hVoice);

#ifdef __cplusplus
}
#endif
```

### 3.1 `Voice_Load`

- **Purpose**: Load the voice library file and initialize the synthesis engine.
- **Parameters**:
  - `pVoicePath`: Path to the voice library file (wide-character string, Unicode). Must specify the exact filename (e.g., `L"ydvoice00.vl"`).
- **Return Value**: Returns a non-zero handle on success; returns `NULL` on failure.

### 3.2 `Voice_SynthesisText`

- **Purpose**: Synthesize input text and return the resulting audio data.
- **Parameters**:
  - `hVoice`: Valid handle returned by `Voice_Load`.
  - `pText`: Text to synthesize (Unicode string). Supports Chinese characters, English letters, and numerals.
  - `pOutSize`: Output parameter that receives the size (in bytes) of the returned audio data.
  - `bAddWavHeader`: If non-zero, the returned data includes a complete WAV file header (can be directly saved as a `.wav` file); if zero, returns raw PCM data only.
- **Return Value**: Returns a pointer to the audio data buffer on success; returns `NULL` on failure. **The returned buffer must be freed using `Voice_FreeBuffer`**.

### 3.3 `Voice_FreeBuffer`

- **Purpose**: Release the memory buffer allocated by `Voice_SynthesisText`.
- **Parameters**: `pBuffer` – Pointer to the buffer to be freed.
- **Return Value**: None.

### 3.4 `Voice_Release`

- **Purpose**: Release the engine handle and clean up associated resources.
- **Parameters**: `hVoice` – Handle to be released.
- **Return Value**: None.

---

## 4. Example Code

```csharp
using System;
using System.IO;
using System.Runtime.InteropServices;

namespace ConsoleApplication
{
	static class Program
	{
		const string LibName = @"ydvoice_x64.dll";

		//Import functions from ydvoice.dll
		[DllImport(dllName: LibName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode, ExactSpelling = true)]
		static extern IntPtr Voice_Load([MarshalAs(UnmanagedType.LPWStr)] string pVoicePath);

		[DllImport(LibName, CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Unicode, ExactSpelling = true)]
		static extern IntPtr Voice_SynthesisText(IntPtr hVoice,
		[MarshalAs(UnmanagedType.LPWStr)] string pText,
		out int outSize,
		[MarshalAs(UnmanagedType.U1)] bool addWavHeader);

		[DllImport(LibName, CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
		static extern void Voice_FreeBuffer(IntPtr pBuffer);

		[DllImport(LibName, CallingConvention = CallingConvention.Cdecl, ExactSpelling = true)]
		static extern void Voice_Release(IntPtr hVoice);

		static void Main(string[] args)
		{
			try
			{
				// Check for required auxiliary files
				string[] auxFiles = { "pymap.bin", "phrases.dat" };
				foreach (var aux in auxFiles)
				{
					if (!File.Exists(aux))
						Console.WriteLine($"Notice: Auxiliary file {aux} not found. Engine may not function correctly.");
				}
				string baseText = "Welcome to Yongde TTS. I am the Yongde voice library.";
				string exeDir = AppDomain.CurrentDomain.BaseDirectory;
				
				// Process ydvoice00.vl ~ ydvoice04.vl sequentially
				for (int i = 0; i < 5; i++)
				{
					string voiceFile = Path.Combine(exeDir, $"ydvoice{i:00}.vl");
					if (!File.Exists(voiceFile))
					{
						Console.WriteLine($"Warning: File not found, skipping: {voiceFile}");
						continue;
					}
					Console.WriteLine($"Loading voice library: {voiceFile}");
					IntPtr hVoice = Voice_Load(voiceFile);
					if (hVoice == IntPtr.Zero)
					{
						Console.WriteLine("Load failed. Please verify the voice library file is complete.");
						continue;
					}
					// Construct full text with index suffix
					string fullText = $"{baseText}{i:00}.";
					Console.WriteLine($"Synthesizing text: {fullText}");
					int size;
					IntPtr pcmData = Voice_SynthesisText(hVoice, fullText, out size, true);
					if (pcmData != IntPtr.Zero && size > 0)
					{
						// Copy data to managed array and save to file
						byte[] buffer = new byte[size];
						Marshal.Copy(pcmData, buffer, 0, size);
						string outputWav = Path.Combine(exeDir, $"sample_YDVoice{i:00}.wav");
						File.WriteAllBytes(outputWav, buffer);
						Console.WriteLine($"Synthesis successful. Saved to: {outputWav} ({size} bytes)");
						// Free synthesis buffer
						Voice_FreeBuffer(pcmData);
					}
					else
					{
						Console.WriteLine("Synthesis failed!");
					}
					// Release voice library handle
					Voice_Release(hVoice);
					Console.WriteLine("---");
				}
				Console.WriteLine("All tasks completed.");
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

## 5. Important Notes

- Copyright of the voice library files `ydvoiceXX.vl` remains with the original rights holders. Please ensure lawful usage in compliance with applicable licenses.
- The `pymap.bin` file can be generated using the provided Python utility tool.
- The `phrases.dat` file serves as a pronunciation correction dictionary for multi-syllable phrases and context-sensitive homophones.
- **All required files must be placed in the same directory** for the engine to function correctly.

---

*—— Let the voices of history resonate in the new era...*
