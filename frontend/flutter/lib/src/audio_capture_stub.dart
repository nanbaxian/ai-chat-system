typedef AudioChunkCallback = void Function(List<int> chunk);

class AudioCapture {
  AudioCapture(this.onChunk, {int targetSampleRate = 16000})
      : targetSampleRate = targetSampleRate;

  final AudioChunkCallback onChunk;
  final int targetSampleRate;

  void start(Object? stream) {}
  void stop() {}
}
