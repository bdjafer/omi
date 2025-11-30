import io
import os
import struct
import wave
import ctypes.util
from typing import Optional, Any

OPUS_AVAILABLE = False
opuslib: Any = None

def _setup_opus():
    global OPUS_AVAILABLE, opuslib
    opus_paths = [
        "/opt/homebrew/lib/libopus.dylib",
        "/opt/homebrew/lib/libopus.0.dylib", 
        "/usr/local/lib/libopus.dylib",
        "/usr/lib/libopus.so.0",
        ctypes.util.find_library("opus"),
    ]
    for path in opus_paths:
        if path and os.path.exists(path):
            os.environ.setdefault("OPUS_LIBRARY_PATH", path)
            break
    if "DYLD_LIBRARY_PATH" not in os.environ:
        os.environ["DYLD_LIBRARY_PATH"] = "/opt/homebrew/lib"
    try:
        import opuslib as _opus
        opuslib = _opus
        OPUS_AVAILABLE = True
        print("Opus decoder initialized successfully")
    except Exception as e:
        print(f"Warning: Opus not available ({e}), will save raw opus data")

_setup_opus()

class AudioHandler:
    def __init__(self, output_dir: str, filename: str, sample_rate: int = 16000, codec: str = "pcm16"):
        self.output_dir = output_dir
        self.filename = filename
        self.sample_rate = sample_rate
        self.codec = codec.lower()
        self.pcm_buffer = io.BytesIO()
        self.raw_buffer = io.BytesIO()
        self.opus_decoder: Any = None
        if self.codec in ("opus", "opus_fs320") and OPUS_AVAILABLE:
            try:
                self.opus_decoder = opuslib.Decoder(sample_rate, 1)
            except Exception as e:
                print(f"Failed to create Opus decoder: {e}")
        self.channels = 1
        self.sample_width = 2
        self.packet_count = 0
        os.makedirs(output_dir, exist_ok=True)

    def process_audio_bytes(self, data: bytes) -> None:
        if len(data) < 3:
            return
        audio_data = data[3:] if len(data) > 3 else data
        self.raw_buffer.write(data)
        if self.codec == "pcm8":
            pcm_data = self._convert_pcm8_to_pcm16(audio_data)
            self.pcm_buffer.write(pcm_data)
        elif self.codec == "pcm16":
            self.pcm_buffer.write(audio_data)
        elif self.codec in ("opus", "opus_fs320"):
            if self.opus_decoder:
                pcm_data = self._decode_opus(audio_data)
                if pcm_data:
                    self.pcm_buffer.write(pcm_data)
                    self.packet_count += 1
        else:
            self.pcm_buffer.write(audio_data)

    def _convert_pcm8_to_pcm16(self, pcm8_data: bytes) -> bytes:
        pcm16_samples = []
        for byte in pcm8_data:
            sample_16 = (byte - 128) * 256
            pcm16_samples.append(struct.pack('<h', max(-32768, min(32767, sample_16))))
        return b''.join(pcm16_samples)

    def _decode_opus(self, opus_data: bytes) -> Optional[bytes]:
        if not self.opus_decoder:
            return None
        try:
            frame_size = 320 if self.codec == "opus_fs320" else 160
            pcm = self.opus_decoder.decode(opus_data, frame_size)
            return pcm
        except Exception as e:
            if self.packet_count < 5:
                print(f"Opus decode error (packet {self.packet_count}): {e}")
            return None

    def finalize(self) -> str:
        raw_path = os.path.join(self.output_dir, f"{self.filename}.raw")
        raw_data = self.raw_buffer.getvalue()
        if raw_data:
            with open(raw_path, 'wb') as f:
                f.write(raw_data)
            print(f"Raw data saved: {raw_path} ({len(raw_data)} bytes)")
        wav_path = os.path.join(self.output_dir, f"{self.filename}.wav")
        pcm_data = self.pcm_buffer.getvalue()
        if not pcm_data:
            print(f"No PCM data decoded. Codec: {self.codec}, Opus available: {OPUS_AVAILABLE}, Decoder: {self.opus_decoder is not None}")
            with open(wav_path, 'wb') as f:
                pass
            return wav_path
        with wave.open(wav_path, 'wb') as wav_file:
            wav_file.setnchannels(self.channels)
            wav_file.setsampwidth(2)
            wav_file.setframerate(self.sample_rate)
            wav_file.writeframes(pcm_data)
        duration = len(pcm_data) / (self.sample_rate * self.channels * 2)
        print(f"WAV saved: {wav_path} ({duration:.1f}s, {len(pcm_data)} bytes, {self.packet_count} packets decoded)")
        return wav_path

    def get_duration_seconds(self) -> float:
        pcm_size = self.pcm_buffer.tell()
        bytes_per_second = self.sample_rate * self.channels * 2
        return pcm_size / bytes_per_second if bytes_per_second > 0 else 0
