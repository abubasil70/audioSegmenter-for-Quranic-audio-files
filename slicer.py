import sys
import os
from pydub import AudioSegment

# I have the three files of FFmpeg lib in the same directory. 
current_dir = os.path.dirname(os.path.abspath(__file__))

ffmpeg_exe = os.path.join(current_dir, "ffmpeg.exe")
ffprobe_exe = os.path.join(current_dir, "ffprobe.exe")

# إخبار المكتبة بمكان الملفات في المجلد الحالي
AudioSegment.converter = ffmpeg_exe
AudioSegment.ffprobe   = ffprobe_exe

# إضافة المجلد الحالي للمسار لضمان عمل ffprobe
os.environ["PATH"] += os.pathsep + current_dir

def slice_audio(source_path, start_ms, end_ms, output_path):
    try:
        if not os.path.exists(source_path):
            print(f"File not found: {source_path}")
            return

        audio = AudioSegment.from_file(source_path)
        
        # القص والحفظ
        sliced = audio[float(start_ms):float(end_ms)]
        sliced.export(output_path, format="mp3")
        #print("Done")

    except Exception as e:
        print(f"Error: {str(e)}")

if __name__ == "__main__":
    if len(sys.argv) == 5:
        slice_audio(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
