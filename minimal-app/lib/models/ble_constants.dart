const String omiServiceUuid = '19b10000-e8f2-537e-4f6c-d104768a1214';
const String audioDataStreamCharacteristicUuid = '19b10001-e8f2-537e-4f6c-d104768a1214';
const String audioCodecCharacteristicUuid = '19b10002-e8f2-537e-4f6c-d104768a1214';
const String batteryServiceUuid = '0000180f-0000-1000-8000-00805f9b34fb';
const String batteryLevelCharacteristicUuid = '00002a19-0000-1000-8000-00805f9b34fb';
const String deviceInformationServiceUuid = '0000180a-0000-1000-8000-00805f9b34fb';
const String firmwareRevisionCharacteristicUuid = '00002a26-0000-1000-8000-00805f9b34fb';

enum BleAudioCodec {
  pcm16,
  pcm8,
  opus,
  opusFS320,
  unknown;

  @override
  String toString() {
    switch (this) {
      case BleAudioCodec.opusFS320:
        return 'opus_fs320';
      case BleAudioCodec.opus:
        return 'opus';
      case BleAudioCodec.pcm16:
        return 'pcm16';
      case BleAudioCodec.pcm8:
        return 'pcm8';
      default:
        return 'pcm8';
    }
  }

  static BleAudioCodec fromId(int id) {
    switch (id) {
      case 1:
        return BleAudioCodec.pcm8;
      case 20:
        return BleAudioCodec.opus;
      case 21:
        return BleAudioCodec.opusFS320;
      default:
        return BleAudioCodec.pcm8;
    }
  }

  int get sampleRate {
    switch (this) {
      case BleAudioCodec.opusFS320:
      case BleAudioCodec.opus:
      case BleAudioCodec.pcm16:
      case BleAudioCodec.pcm8:
        return 16000;
      default:
        return 16000;
    }
  }
}

