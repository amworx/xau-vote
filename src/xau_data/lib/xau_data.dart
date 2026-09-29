/// XAU Radar data layer: provider interfaces, mocks and offline pipeline.
///
/// Pure Dart. Market data and idea sources live behind interfaces
/// (spec §18/§19); the [RadarPipeline] orchestrator runs fully offline on
/// mocks. No network, no clock reads inside logic — callers pass `now` in.
///
/// T3.3 (GoldApiProvider) is intentionally absent: it requires Gate G3
/// (user confirmation + recorded licensing review) per TASK-03.
library;

export 'idea_source.dart';
export 'market_data_provider.dart';
export 'radar_pipeline.dart';
