class PPGConfig {
  final int samplingRate;
  final int windowSizeSeconds;

  const PPGConfig({
    this.samplingRate = 30, // FPS
    this.windowSizeSeconds = 10,
  });
}
