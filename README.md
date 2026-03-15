# YDVoiceTTS: A Chinese Speech synthesis system from Yongde screen reader

## YDVoice TTS 永德音库

> **复活二十年前[永德读屏软件](https://www.wangyongde.com/)的一套基于波形拼接技术实现的中文语音合成引擎**  
> 完全解析 `ydvoiceXX.vl` 私有格式，通过 [FreeBasic](https://sourceforge.net/projects/fbc/) 重构为了一个新的跨平台、离线、轻量级的中文 TTS 引擎。

---

## 项目简介

YDVoice 源自对一款发布于 2000 年前后的闭源中文[读屏程序](https://www.zhihu.com/question/22559984/answer/3046163795) `ydreader.exe` 的深度逆向工程研究。原始程序采用[波形拼接合成技术](https://zhaoshuaijiang.com/2014/03/05/unit_selection_synthesis/)，在极低算力下实现了流畅的中文语音合成，其核心语音数据存储在 `ydvoiceXX.vl` 等私有二进制格式文件中。

本项目完整还原了该语音库的底层数据结构、音素寻址算法及内存优化策略，并基于现代编程语言（C# / FreeBasic / Python）重构了一套**无依赖、跨平台**的离线 TTS 引擎。开发者无需原始程序或二进制字典 `ydmap.mp`，即可直接使用其中的真人录音数据，让这份珍贵的数字遗产得以重获新生。

---

## 核心原理

### 1. 文件格式：`ydvoiceXX.vl` 分析

每个 `.vl` 文件遵循 **“文件头 + 索引表 + 数据区”** 的经典结构，采用小端序存储。

| 区域       | 大小            | 内容                                                                 |
|------------|-----------------|----------------------------------------------------------------------|
| 文件头     | 32 字节         | 元数据：总槽位数（24576）、声道数、采样率（16kHz）、位深（16bit）等 |
| 索引表     | `总槽位数 × 8`  | 每个槽位 8 字节：`[4B 偏移量] + [4B 长度]`，空槽为全 0               |
| 数据区     | 可变            | 连续的 16bit PCM 裸流，无任何压缩或加密                              |

总槽位数 24576 远大于实际有效音节数（约 1500），这是设计者采用的**稀疏数组策略**——以空间换时间，实现 O(1) 直接寻址。

### 2. 拼音 → ID 的三维映射算法

原始引擎不依赖字符串查找，而是将音韵学规律编码为纯数学计算规则，构建了一个 **26 × 26 × 16 的三维物理坐标系**：

```
phonemeId = (声母索引 × 416) + (韵母索引 × 16) + 声调偏移
```

- **Y 轴（声母索引 0~25）**：映射 26 个字母，利用 `I, U, V` 等空缺容纳 `zh, ch, sh` 等多字母声母。
- **X 轴（韵母索引 0~25）**：每个声母块下分配 26 个韵母槽位。
- **Z 轴（变体偏移 0~15）**：每个韵母槽内 `+0~+3` 为四声，`-1` 为轻声，`+7` 为英文字母自身原始发音。

#### 2.1 互斥复用

汉语韵母数量超过 26 个，如何塞进 26 个槽位？设计者运用了音韵学中的**互补分布法则**：若两个韵母永远不会与同一个声母结合，则它们共享同一物理槽位。例如：

- `ia` 与 `ua` 共享槽位：`j/q/x` 只能拼 `ia`，`g/k/h` 只能拼 `ua`，永无冲突。
- `nü/lü` 与 `uai` 共享槽位：`n/l` 无法与 `uai` 结合，该槽位被复用。

### 3. 映射表生成工具

为避免运行时动态解析的复杂，我们采用**表驱动法**：

1. 从拼音语料库提取所有基础拼音（如 `wo`、`jue`）。
2. 根据逆向推导的算法计算出每个拼音的基础 ID。
3. 扩展生成全部带调音节（1~4 声及轻声），并补充英文字母。
4. 输出为 JSON 映射文件，供引擎直接加载。

对应 Python 脚本：
- `build_dict.py`：从 `pinyindata.txt` 生成 `pinyin_to_id_table.py`（Python 字典）或 JSON。
- `json2bin.py`：将 JSON 编译为**固定长度记录（32 字节/条）的二进制映射文件**，支持跨语言二分查找。

---

## 快速开始

### 环境要求

- **语音库文件**：原始的 `ydvoiceXX.vl`
- **映射文件**：可使用我们提供的生成工具从语料库构建，或下载预编译的 `pymap.bin`
- **词典文件**：`phrases.dat` 可在 [mozillazg/phrase-pinyin-data](https://github.com/mozillazg/phrase-pinyin-data) 获得，使用前请按本项目所需的格式进行转换

### C# 调用示例（DLL P/Invoke）

```csharp
using System;
using System.Runtime.InteropServices;

class YDVoice
{
    [DllImport("ydvoice.dll", CallingConvention = CallingConvention.StdCall, CharSet = CharSet.Unicode, ExactSpelling = true)]
    static extern IntPtr Voice_Load([MarshalAs(UnmanagedType.LPWStr)] string pVoicePath);

    [DllImport("ydvoice.dll", CallingConvention = CallingConvention.StdCall, CharSet = CharSet.Unicode, ExactSpelling = true)]
    static extern IntPtr Voice_SynthesisText(IntPtr hVoice,
        [MarshalAs(UnmanagedType.LPWStr)] string pText,
        out int outSize,
        [MarshalAs(UnmanagedType.U1)] bool addWavHeader);

    [DllImport("ydvoice.dll", CallingConvention = CallingConvention.StdCall, ExactSpelling = true)]
    static extern void Voice_FreeBuffer(IntPtr pBuffer);

    [DllImport("ydvoice.dll", CallingConvention = CallingConvention.StdCall, ExactSpelling = true)]
    static extern void Voice_Release(IntPtr hVoice);

    public static void Main()
    {
        IntPtr hVoice = Voice_Load(@".\ydvoice00.vl");
        if (hVoice != IntPtr.Zero)
        {
            int size;
            IntPtr pcm = Voice_SynthesisText(hVoice, "你好，世界", out size, true);
            if (pcm != IntPtr.Zero)
            {
                // 保存或播放 pcm 数据（size 字节）
                Voice_FreeBuffer(pcm);
            }
            Voice_Release(hVoice);
        }
    }
}
```

---

## 附录："YDVoice*.vl" 文件头

| 文件名 | 大小 (字节) | 前 32 字节 (Hex) |
| :--- | :--- | :--- |
| ydvoice00.vl | 13250650 | 0060000001000100803e0000007d000002001000000000000000000000000000 |
| ydvoice01.vl | 13634166 | 0060000001000100803e0000007d000002001000000000000000000000000000 |
| ydvoice02.vl | 4561476 | 0060000001000100803e0000007d0000020010000000000018000300160e0000 |
| ydvoice03.vl | 11900442 | 0060000001000100803e0000007d0000020010000000000018000300a20c0000 |
| ydvoice04.vl | 9817706 | 0060000001000100803e0000007d0000020010000000000018000300fc1e0000 |

---

## 参考

* [《YDVoice TTS 语音合成系统逆向工程研究分析报告》 - 张赐荣](https://blog.csdn.net/zcr_59186/article/details/158570454)

---

## **免责声明**

本项目及附带代码、二进制文件等仅供学习与研究使用。如有侵权，请联系删除（需提供版权、著作权等相关证明材料）。
