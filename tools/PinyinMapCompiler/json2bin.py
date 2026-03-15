#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
pymap 二进制编译器

功能: 将 pymap.json 转换为固定32字节记录的二进制格式
"""

import json
import struct
import os
import sys
import traceback

ENTRY_SIZE = 32           # 每条记录固定32字节
KEY_CHAR_COUNT = 14       # Key最多14个UTF-16字符
KEY_BYTES = KEY_CHAR_COUNT * 2          # Key字段: 28字节
KEY_CONTENT_BYTES = (KEY_CHAR_COUNT - 1) * 2  # 有效内容: 26字节(留2字节给null)
ID_SIZE = 4               # ID字段: 4字节uint32
UTF16_NULL = b'\x00\x00'  # UTF-16LE空终止符
ID_STRUCT_FORMAT = '<I'   # 小端序uint32

def _encode_key(key: str) -> bytes:
    """
    将字符串key编码为固定28字节的UTF-16LE格式
    编码规则:
    1. UTF-16LE编码 (小端序, 每字符2字节)
    2. 最多保留13个字符(26字节), 预留2字节给null终止符
    3. 添加 \\x00\\x00 终止符
    4. 零填充至28字节
    返回: 固定28字节的bytes对象
    """
    # UTF-16LE编码
    key_bytes = key.encode('utf-16-le')
    # 截断: 确保不超过有效内容长度(为null终止符留空间)
    if len(key_bytes) > KEY_CONTENT_BYTES:
        key_bytes = key_bytes[:KEY_CONTENT_BYTES]
    # 添加null终止符 + 零填充至固定长度
    return (key_bytes + UTF16_NULL).ljust(KEY_BYTES, b'\x00')

def compile_pymap(json_path: str, output_path: str) -> bool:
    """
    核心编译函数: JSON 到 bin
    参数:
        json_path: 输入JSON文件路径
        output_path: 输出二进制文件路径
    返回:
        True: 成功
        False: 失败

    处理流程:
        1. 读取JSON → Dict[str, int]
        2. 按Unicode码点序(Ordinal)排序key
        3. 逐条编码: [28B UTF-16LE key] + [4B uint32 LE id]
        4. 写入二进制文件
    """
    try:
        # 步骤1: 读取JSON
        if not os.path.isfile(json_path):
            raise FileNotFoundError(f"输入文件不存在: '{json_path}'")
        with open(json_path, 'r', encoding='utf-8') as f:
            raw_dict = json.load(f)
        # 步骤2: 按Ordinal顺序排序 (二分查找必需)
        # Python默认字符串排序为 Unicode码点序
        sorted_items = sorted(raw_dict.items(), key=lambda x: x[0])
        # 步骤3: 编码并写入二进制
        with open(output_path, 'wb') as out_file:
            for key, value in sorted_items:
                # 编码Key: 28字节固定长度
                key_field = _encode_key(key)
                # 编码ID: 4字节小端序uint32
                # 检查数值范围
                if not (0 <= value <= 0xFFFFFFFF):
                    raise ValueError(f"ID值超出uint32范围: {value} (key='{key}')")
                id_field = struct.pack(ID_STRUCT_FORMAT, value)
                # 写入完整记录 (32字节)
                out_file.write(key_field + id_field)
        return True
    except json.JSONDecodeError as e:
        print(f"❌ JSON解析错误: {e.msg}", file=sys.stderr)
        print(f"   位置: 行{e.lineno}, 列{e.colno}", file=sys.stderr)
        print(f"   文件: {json_path}", file=sys.stderr)
        return False
    except UnicodeEncodeError as e:
        print(f"❌ 字符编码错误: 无法用UTF-16LE编码", file=sys.stderr)
        print(f"   详情: {e}", file=sys.stderr)
        return False
    except struct.error as e:
        print(f"❌ 二进制打包错误", file=sys.stderr)
        print(f"   详情: {e}", file=sys.stderr)
        print(f"   提示: 检查ID值是否为0~4294967295的整数", file=sys.stderr)
        return False
    except PermissionError as e:
        print(f"❌ 文件权限错误", file=sys.stderr)
        print(f"   详情: {e}", file=sys.stderr)
        return False
    except Exception as e:
        # 捕获未预期的异常, 输出完整堆栈便于调试
        print(f"❌ 未预期错误: {type(e).__name__}: {e}", file=sys.stderr)
        print("\n--- 详细堆栈信息 ---", file=sys.stderr)
        traceback.print_exc(file=sys.stderr)
        print('---------------------', file=sys.stderr)
        return False


def main():
    """主入口: 参数解析 + 执行 + 简洁输出"""
    # 默认路径
    json_path = sys.argv[1] if len(sys.argv) > 1 else 'pymap.json'
    output_path = sys.argv[2] if len(sys.argv) > 2 else 'pymap.bin'
    # 执行编译
    success = compile_pymap(json_path, output_path)
    if success:
        print("✓ 转换成功")
        sys.exit(0)
    else:
        sys.exit(1)

if __name__ == '__main__':
    main()
