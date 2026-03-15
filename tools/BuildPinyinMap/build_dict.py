import os
import re

# 核心底层物理坐标系
Y_MAP = {
    'a':0, 'b':1, 'c':2, 'd':3, 'e':4, 'f':5, 'g':6, 'h':7, 'sh':8, 'j':9, 'k':10,
    'l':11, 'm':12, 'n':13, 'o':14, 'p':15, 'q':16, 'r':17, 's':18, 't':19,
    'zh':20, 'ch':21, 'w':22, 'x':23, 'y':24, 'z':25
}

X_MAP = {
    'a':0,   'ui':1,  'ian':2, 'an':3,  'e':4,   'eng':5, 'en':6,  'ing':7,
    'i':8,   'in':9,  'ong':10,'iao':11,'iang':12,'uan':13,'uo':14, 'ou':15,
    'ia':16, 'ei':17, 'ang':18,'ie':19, 'u':20,  'uai':21,'ao':22, 'ai':23,
    'iu':24, 'un':25
}

def resolve_base_pinyin_to_id(base_py):
    """
    将无声调的基础拼音 (如 dia, wo, jue) 转换为基础 ID
    """
    base_py = base_py.lower().replace('ü', 'v')
    
    # 拆分声母
    initial = ""
    for init in['zh', 'ch', 'sh', 'b', 'p', 'm', 'f', 'd', 't', 'n', 'l', 'g', 'k', 'h', 'j', 'q', 'x', 'r', 'z', 'c', 's', 'y', 'w']:
        if base_py.startswith(init):
            initial = init
            break
            
    if not initial:
        if base_py[0] in ['a', 'e', 'o']: initial = base_py[0]
        else: return None
        
    rime = base_py[len(initial):]
    if initial in ['a', 'e', 'o']:
        rime = base_py # 零声母时，韵母等于全拼
        
    x_coord = -1
    
    # 引擎“褪糖” (寻找真实的 X 坐标)
    if initial in ['a', 'e', 'o']:
        zero_desugar = {'a':0, 'an':3, 'ang':18, 'ao':22, 'ai':23, 'e':4, 'ei':17, 'eng':5, 'en':6, 'er':15, 'o':14, 'ou':15}
        x_coord = zero_desugar.get(rime, -1)
    elif initial == 'y':
        y_desugar = {'a':0, 'e':4, 'an':3, 'ue':1, 'ing':7, 'i':8, 'in':9, 'ong':10, 'uan':13, 'o':14, 'ou':15, 'ang':18, 'u':20, 'ao':22, 'un':25}
        x_coord = y_desugar.get(rime, -1)
    elif initial == 'w':
        w_desugar = {'a':0, 'an':3, 'eng':5, 'en':6, 'o':14, 'ei':17, 'ang':18, 'u':20, 'ai':23}
        x_coord = w_desugar.get(rime, -1)
    else:
        # 处理互斥复用
        if initial in['j', 'q', 'x']:
            if rime == 'u': rime = 'v'
            elif rime == 'ue': rime = 'ui'
            elif rime == 'iong': rime = 'ong'
        elif initial in ['n', 'l']:
            if rime == 'v': rime = 'uai'
            elif rime in ['ue', 've']: rime = 'ui'
        elif initial in ['g', 'k', 'h', 'zh', 'ch', 'sh']:
            if rime == 'uang': rime = 'iang'
            elif rime == 'ua': rime = 'ia'
        elif initial == 'd' and rime == 'er':
            rime = 'e'
        elif rime == 'o' and initial in['b', 'p', 'm', 'f', 'l']:
            rime = 'uo'
            
        if rime == 'v': rime = 'u'
        x_coord = X_MAP.get(rime, -1)

    if x_coord == -1: return None
    
    y_coord = Y_MAP[initial]
    return (y_coord * 416) + (x_coord * 16)

def build_dict_from_corpus(data_file):
    if not os.path.exists(data_file):
        print(f"找不到文件: {data_file}。请确保文件在同目录下。")
        return

    unique_bases = set()
    
    print(f"[*] 正在读取 {data_file} 提取拼音...")
    # 提取正则：忽略开头的汉字，只抓取 a-z 或 ü v，忽略数字声调
    py_pattern = re.compile(r'[a-zA-Züv]+')
    
    with open(data_file, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line: continue
            
            match = py_pattern.search(line)
            if match:
                base_py = match.group(0).lower()
                unique_bases.add(base_py)

    print(f"[*] 成功提取了 {len(unique_bases)} 种独立的基础发音（如 dia, wo, nv）。")
    
    # 开始生成
    final_dict = {}
    error_list =[]
    
    for base_py in unique_bases:
        base_id = resolve_base_pinyin_to_id(base_py)
        
        if base_id is None:
            error_list.append(base_py)
            continue
        # 1-4声 (偏移 0-3)
        for tone in range(1, 5):
            final_dict[f"{base_py}{tone}"] = base_id + (tone - 1)
        
        # 轻声 (用数字 5 代表轻声，同时支持无数字直接调用)
        final_dict[f"{base_py}5"] = base_id - 1
        final_dict[base_py] = base_id - 1

    # 补充英文字母发音
    for char in "abcdefghijklmnopqrstuvwxyz":
        idx = ord(char) - ord('a')
        final_dict[char] = (idx * 416) + 7

    # 导出文件

    # 导出成功的字典
    with open("pinyin_to_id_table.py", "w", encoding="utf-8") as f:
        f.write("# 自动生成的映射表（基于真实语料库扩展 1~5 声）\n")
        f.write("PINYIN_ID_MAP = {\n")
        for k, v in sorted(final_dict.items()):
            f.write(f"    '{k}': {v},\n")
        f.write("}\n")
        
    print(f"成功生成全量字典 pinyin_to_id_table.py (包含 {len(final_dict)} 个项)!")

    # 记录错误/无法识别的拼音
    if error_list:
        with open("unmapped_pinyin_error.log", "w", encoding="utf-8") as f:
            f.write("以下基础拼音无法被引擎公式解析，请人工核查是否是生僻拼写或提取错误：\n\n")
            for err in sorted(error_list):
                f.write(f"{err}\n")
        print(f"发现 {len(error_list)} 个无法解析的拼音，已记录到 unmapped_pinyin_error.log。")
    else:
        print("语料库中所有的拼音都被引擎公式成功解析，没有遇到任何死角！")

if __name__ == "__main__":
    build_dict_from_corpus("pinyindata.txt")
