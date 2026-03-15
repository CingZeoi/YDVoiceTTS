import struct
import wave
import os

def extract_voice_library_fixed(vl_filename, output_dir):
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    file_size = os.path.getsize(vl_filename)

    with open(vl_filename, 'rb') as f:
        header_size_data = f.read(4)
        total_ids = struct.unpack('<I', header_size_data)[0]
        print(f"[+] 系统分配的发音 ID 总个数为: {total_ids} (0x{total_ids:X})")
        
        # 跳转到索引区开始 (0x20 = 32字节)
        f.seek(32)
        
        valid_count = 0
        extracted_size = 0
        
        # 遍历所有的 24576 个 ID
        for syllable_id in range(total_ids):
            offset_size_data = f.read(8)
            if len(offset_size_data) < 8:
                break
                
            offset, size = struct.unpack('<II', offset_size_data)
            
            # 如果 offset 或 size 为 0，或者偏离文件大小，则跳过
            if offset == 0 or size == 0 or offset + size > file_size:
                continue
                
            valid_count += 1
            extracted_size += size
            
            # 记录指针
            current_pos = f.tell()
            
            # 提取数据
            f.seek(offset)
            pcm_data = f.read(size)
            
            # 保存为 WAV
            wav_filename = os.path.join(output_dir, f"ID_{syllable_id:04d}.wav")
            with wave.open(wav_filename, 'wb') as wav_file:
                wav_file.setnchannels(1)
                wav_file.setsampwidth(2)
                wav_file.setframerate(16000)
                wav_file.writeframes(pcm_data)
                
            f.seek(current_pos)
            
        print(f"[+] 恭喜！完美提取完毕！")
        print(f"    - 有效发音数量: {valid_count} 个")
        print(f"    - 提取音频总大小: {extracted_size / 1024 / 1024:.2f} MB")

if __name__ == '__main__':
    # 建议先清空上次的 extracted_wavs 文件夹
    extract_voice_library_fixed(input("请输入要提取的语音库文件名"), "extracted_wavs_full")
