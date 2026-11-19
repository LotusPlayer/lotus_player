// ==============================================================================
// LOTUS EQUALIZER & DSP SERVICE (HIGH-PRECISION HARDWARE INTERPOLATION & BIO-ENGINE)
// File: lib/core/services/lotus_equalizer_service.dart
// Features: 10-Band Virtual EQ interpolated into 5-Band Hardware DSP,
//           Hardware AudioSessionId Dynamic Binding, SharedPreferences Throttled Save,
//           Mood Bio-Engine & Binaural/Isochronic Modulation Pipeline.
// Compatible: Flutter 3.27+ / Android 14, 15, 16 / Nubia MyOS 15 / Media3
// ==============================================================================

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DspPreset {
  final String name;
  final List<double> bandGainsDb;

  /// Auxiliary insert effects applied alongside the 10-band EQ when this
  /// preset is selected (0..1000 for bass/virtualizer, 0..1500 mB for loudness).
  final int bassBoostStrength;
  final int virtualizerStrength;
  final int loudnessMb;

  const DspPreset({
    required this.name,
    required this.bandGainsDb,
    this.bassBoostStrength = 0,
    this.virtualizerStrength = 0,
    this.loudnessMb = 0,
  });
}

class LotusEqualizerService extends ChangeNotifier {
  static final LotusEqualizerService instance = LotusEqualizerService._();

  LotusEqualizerService._() {
    _initCompleter = Completer<void>();
    _initPersistenceAndChannels();
    _listenToDeviceRouteChanges();
  }

  late final Completer<void> _initCompleter;
  Future<void> get ensureInitialized => _initCompleter.future;

  static const MethodChannel _dspChannel =
  MethodChannel('com.souljalazian.lotus_player/dsp_equalizer');
  static const MethodChannel _audioPlatformChannel =
  MethodChannel('com.souljalazian.lotus_player/audio_effects');

  static const String _kEqEnabledKey = 'lotus_dsp_eq_enabled';
  static const String _kActivePresetKey = 'lotus_dsp_active_preset';
  static const String _kBandGainsKey = 'lotus_dsp_band_gains';

  static const String _kMoodBioEngineActiveKey = 'lotus_mood_bio_engine_active';
  static const String _kMoodToneBlendKey = 'lotus_mood_tone_blend';
  static const String _kMoodIsochronicDepthKey = 'lotus_mood_isochronic_depth';
  static const String _kMoodPulseFrequencyKey = 'lotus_mood_pulse_frequency';
  static const String _kMoodNoiseMaskKey = 'lotus_mood_noise_mask';

  SharedPreferences? _cachedPrefs;

  bool _isEnabled = true;
  String _activePresetName = 'Harmonic Bloom';
  int _audioSessionId = 0;
  final Set<int> _attachedSessionIds = <int>{};

  bool _playbackActive = false;
  bool _isMoodBioEngineActive = false;
  double _moodToneBlend = 0.35;
  double _moodIsochronicDepth = 0.35;
  double _moodNoiseMask = 0.25;
  double _moodPulseFrequency = 6.0;

  bool _hasQueriedHardware = false;
  int _hardwareBandCount = 5;
  List<int> _hardwareCenterFreqsHz = <int>[60, 230, 910, 3600, 14000];
  int _minLevelMilliBels = -1500;
  int _maxLevelMilliBels = 1500;

  final List<int> _centerFrequenciesHz = const <int>[
    31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000
  ];

  late final List<double> _precomputedLogFrequencies =
  _centerFrequenciesHz.map((int f) => math.log(f.toDouble())).toList();

  List<double> _bandGainsDb = <double>[
    2.0, 1.5, 0.5, 0.0, -0.5, 1.0, 1.5, 2.5, 2.5, 2.0
  ];

  Timer? _debounceSaveTimer;
  Timer? _throttleSyncTimer;
  bool _isSyncRunning = false;
  bool _needsTrailingDspSync = false;

  // 10-band order: 31, 62, 125, 250, 500, 1k, 2k, 4k, 8k, 16k Hz (gains in dB, ±12 max).
  static const Map<String, DspPreset> presets = <String, DspPreset>{
    'Harmonic Bloom': DspPreset(
      name: 'Harmonic Bloom',
      bandGainsDb: <double>[3.0, 2.0, 1.0, 0.0, -1.0, 0.5, 1.0, 2.0, 2.5, 2.0],
      bassBoostStrength: 300,
      virtualizerStrength: 150,
    ),
    'Flat / Bit-Perfect': DspPreset(
      name: 'Flat / Bit-Perfect',
      bandGainsDb: <double>[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
    ),
    'Club Bass Boost': DspPreset(
      name: 'Club Bass Boost',
      bandGainsDb: <double>[7.0, 5.5, 3.5, 1.5, 0.0, -0.5, 0.0, 1.0, 1.5, 1.0],
      bassBoostStrength: 800,
      loudnessMb: 200,
    ),
    'Audiophile Vocal': DspPreset(
      name: 'Audiophile Vocal',
      bandGainsDb: <double>[-2.0, -1.0, 0.0, 1.5, 3.0, 4.0, 3.0, 1.5, 0.5, -1.0],
    ),
    'Electronic / Synth': DspPreset(
      name: 'Electronic / Synth',
      bandGainsDb: <double>[5.5, 4.0, 2.0, 0.0, -1.5, -0.5, 1.0, 2.5, 3.5, 4.0],
      bassBoostStrength: 600,
      virtualizerStrength: 500,
      loudnessMb: 100,
    ),
    'Rock / Metal': DspPreset(
      name: 'Rock / Metal',
      bandGainsDb: <double>[5.0, 3.5, 1.5, 0.0, -1.0, -0.5, 1.5, 3.0, 4.0, 3.5],
      bassBoostStrength: 500,
      virtualizerStrength: 200,
      loudnessMb: 150,
    ),
    'Bass Extreme (Subwoofer)': DspPreset(
      name: 'Bass Extreme (Subwoofer)',
      bandGainsDb: <double>[9.0, 8.0, 6.0, 3.0, 0.0, -1.0, -1.0, 0.0, 1.0, 1.0],
      bassBoostStrength: 1000,
      loudnessMb: 300,
    ),
    'Treble Sparkle (Air)': DspPreset(
      name: 'Treble Sparkle (Air)',
      bandGainsDb: <double>[-1.0, -1.0, -0.5, 0.0, 0.0, 0.5, 2.0, 4.0, 6.0, 7.0],
      virtualizerStrength: 300,
      loudnessMb: 100,
    ),
    'Hip-Hop / Trap': DspPreset(
      name: 'Hip-Hop / Trap',
      bandGainsDb: <double>[6.0, 5.0, 4.0, 2.0, 0.0, -0.5, 0.0, 1.0, 1.5, 1.0],
      bassBoostStrength: 900,
      loudnessMb: 200,
    ),
    'Pop': DspPreset(
      name: 'Pop',
      bandGainsDb: <double>[2.0, 3.0, 4.0, 3.0, 1.0, -0.5, -0.5, 0.0, 1.5, 2.0],
      bassBoostStrength: 400,
      loudnessMb: 100,
    ),
    'Jazz': DspPreset(
      name: 'Jazz',
      bandGainsDb: <double>[2.5, 1.5, 0.5, 0.0, -0.5, 0.0, 1.5, 2.5, 2.0, 1.5],
      bassBoostStrength: 200,
      virtualizerStrength: 100,
    ),
    'Classical': DspPreset(
      name: 'Classical',
      bandGainsDb: <double>[3.0, 2.0, 1.0, 0.0, -0.5, 0.0, 1.0, 2.0, 3.0, 3.5],
      bassBoostStrength: 200,
      virtualizerStrength: 250,
    ),
    'Vocal Clarity (Podcast)': DspPreset(
      name: 'Vocal Clarity (Podcast)',
      bandGainsDb: <double>[-3.0, -2.0, -0.5, 0.5, 2.5, 4.5, 3.5, 2.0, 0.5, -0.5],
      loudnessMb: 200,
    ),
    '3D Surround (Wide)': DspPreset(
      name: '3D Surround (Wide)',
      bandGainsDb: <double>[4.0, 3.0, 2.0, 1.0, 0.0, 0.0, 1.0, 2.0, 2.5, 2.5],
      bassBoostStrength: 400,
      virtualizerStrength: 800,
      loudnessMb: 100,
    ),
    'Loudness (Max Volume)': DspPreset(
      name: 'Loudness (Max Volume)',
      bandGainsDb: <double>[3.0, 2.5, 2.0, 1.5, 1.0, 1.0, 1.5, 2.0, 2.5, 3.0],
      bassBoostStrength: 500,
      virtualizerStrength: 200,
      loudnessMb: 1500,
    ),
    'Acoustic / Folk': DspPreset(
      name: 'Acoustic / Folk',
      bandGainsDb: <double>[2.0, 2.5, 2.0, 1.0, 0.5, 1.0, 2.0, 2.5, 2.0, 1.0],
      bassBoostStrength: 200,
      virtualizerStrength: 100,
    ),
  };

  bool get isEnabled => _isEnabled;
  String get activePresetName => _activePresetName;
  int get audioSessionId => _audioSessionId;
  List<int> get centerFrequenciesHz => _centerFrequenciesHz;
  List<double> get bandGainsDb => List<double>.unmodifiable(_bandGainsDb);

  bool get isMoodBioEngineActive => _isMoodBioEngineActive;
  double get moodToneBlend => _moodToneBlend;
  double get moodIsochronicDepth => _moodIsochronicDepth;
  double get moodNoiseMask => _moodNoiseMask;
  double get moodPulseFrequency => _moodPulseFrequency;

  Future<SharedPreferences> _getPrefs() async {
    return _cachedPrefs ??= await SharedPreferences.getInstance();
  }

  void _listenToDeviceRouteChanges() {
    _dspChannel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onAudioDeviceChanged') {
        await _syncWithHardwareDsp();
        if (_isMoodBioEngineActive) await _syncMoodBioEngineHardware();
      }
    });
  }

  Future<void> _initPersistenceAndChannels() async {
    try {
      final SharedPreferences prefs = await _getPrefs();
      _isEnabled = prefs.getBool(_kEqEnabledKey) ?? true;
      _activePresetName = prefs.getString(_kActivePresetKey) ?? 'Harmonic Bloom';

      final List<String>? savedGains = prefs.getStringList(_kBandGainsKey);
      if (savedGains != null && savedGains.length == _bandGainsDb.length) {
        _bandGainsDb = savedGains.map((String s) => double.tryParse(s) ?? 0.0).toList();
      }

      _isMoodBioEngineActive = prefs.getBool(_kMoodBioEngineActiveKey) ?? false;
      _moodToneBlend = (prefs.getDouble(_kMoodToneBlendKey) ?? 0.35).clamp(0.0, 1.0);
      _moodIsochronicDepth = (prefs.getDouble(_kMoodIsochronicDepthKey) ?? 0.35).clamp(0.0, 1.0);
      _moodNoiseMask = (prefs.getDouble(_kMoodNoiseMaskKey) ?? 0.25).clamp(0.0, 1.0);
      _moodPulseFrequency = (prefs.getDouble(_kMoodPulseFrequencyKey) ?? 6.0).clamp(0.5, 20.0);

      notifyListeners();
    } catch (_) {
    } finally {
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
    }
  }

  Future<void> attachAudioSession(int sessionId, {bool force = false}) async {
    if (sessionId <= 0) return;
    if (!force && _audioSessionId == sessionId && _attachedSessionIds.contains(sessionId)) {
      return;
    }
    _audioSessionId = sessionId;
    _attachedSessionIds.add(sessionId);

    await ensureInitialized;

    await _invokePlatformMethod('attachAudioSession', <String, dynamic>{
      'audioSessionId': _audioSessionId,
      'force': force,
    });

    if (!_hasQueriedHardware || force) {
      await _queryHardwareCapabilities();
      _hasQueriedHardware = true;
    }

    await _syncWithHardwareDsp();

    if (_isEnabled) {
      final DspPreset? active = presets[_activePresetName];
      if (active != null) {
        await setAuxEffects(
          bassStrength: active.bassBoostStrength,
          virtualizerStrength: active.virtualizerStrength,
          loudnessMb: active.loudnessMb,
        );
      }
    }

    if (_isMoodBioEngineActive) {
      await _syncMoodBioEngineHardware();
    }
  }

  Future<void> _queryHardwareCapabilities() async {
    try {
      final dynamic raw = await _dspChannel.invokeMethod('getEqualizerParameters');
      if (raw is Map) {
        final Map<dynamic, dynamic> data = raw;
        _hardwareBandCount = (data['numberOfBands'] as num?)?.toInt() ?? 5;
        _minLevelMilliBels = (data['minLevel'] as num?)?.toInt() ?? -1500;
        _maxLevelMilliBels = (data['maxLevel'] as num?)?.toInt() ?? 1500;

        final List<dynamic>? freqs = data['centerFrequencies'] as List<dynamic>?;
        if (freqs != null && freqs.isNotEmpty) {
          _hardwareCenterFreqsHz = freqs.map((dynamic f) => ((f as num) / 1000).round()).toList();
        }
      }
    } catch (_) {}
  }

  int _toMilliBels(double db) => (db * 100).round().clamp(_minLevelMilliBels, _maxLevelMilliBels);

  List<int> _interpolateGainsForHardware() {
    if (_hardwareBandCount >= 10) {
      return _bandGainsDb.map(_toMilliBels).toList();
    }

    final int n = math.min(_hardwareBandCount, _hardwareCenterFreqsHz.length);
    if (n <= 0) return _bandGainsDb.take(5).map(_toMilliBels).toList();

    final List<double> logs = _precomputedLogFrequencies;

    return List<int>.generate(n, (int h) {
      final double x = math.log(math.max(1, _hardwareCenterFreqsHz[h]).toDouble());

      if (x <= logs.first) return _toMilliBels(_bandGainsDb.first);
      if (x >= logs.last) return _toMilliBels(_bandGainsDb.last);

      for (int i = 0; i < logs.length - 1; i++) {
        if (x <= logs[i + 1]) {
          final double t = (x - logs[i]) / (logs[i + 1] - logs[i]);
          final double db = _bandGainsDb[i] + (_bandGainsDb[i + 1] - _bandGainsDb[i]) * t;
          return _toMilliBels(db);
        }
      }
      return 0;
    });
  }

  Future<dynamic> _invokePlatformMethod(String method, Map<String, dynamic> params) async {
    try {
      return await _dspChannel.invokeMethod<dynamic>(method, params);
    } on MissingPluginException {
      return await _audioPlatformChannel.invokeMethod<dynamic>(method, params);
    } catch (_) {
      return null;
    }
  }

  void _scheduleThrottledDspSync() {
    if (_isSyncRunning) {
      _needsTrailingDspSync = true;
      return;
    }
    if (_throttleSyncTimer?.isActive ?? false) return;

    _throttleSyncTimer = Timer(const Duration(milliseconds: 24), () async {
      _isSyncRunning = true;
      try {
        await _syncWithHardwareDsp();
      } finally {
        _isSyncRunning = false;
        if (_needsTrailingDspSync) {
          _needsTrailingDspSync = false;
          _scheduleThrottledDspSync();
        }
      }
    });
  }

  Future<void> _syncWithHardwareDsp() async {
    final Map<String, dynamic> params = <String, dynamic>{
      'audioSessionId': _audioSessionId,
      'enabled': _isEnabled,
      'bandGainsMilliBels': _interpolateGainsForHardware(),
    };
    await _invokePlatformMethod('applyDspSettings', params);
  }

  Future<void> _syncMoodBioEngineHardware() async {
    await _invokePlatformMethod('applyMoodBioEngine', <String, dynamic>{
      'audioSessionId': _audioSessionId,
      'enabled': _isMoodBioEngineActive,
      'toneBlend': _moodToneBlend,
      'isochronicDepth': _moodIsochronicDepth,
      'noiseMask': _moodNoiseMask,
      'pulseFrequency': _moodPulseFrequency,
      'playbackActive': _playbackActive,
    });
  }

  /// Passthrough for BassBoost / Virtualizer / LoudnessEnhancer (0..1000, mB for loudness).
  Future<void> setAuxEffects({
    int? bassStrength,
    int? virtualizerStrength,
    int? loudnessMb,
  }) async {
    await _invokePlatformMethod('setAuxEffects', <String, dynamic>{
      if (bassStrength != null) 'bassStrength': bassStrength,
      if (virtualizerStrength != null) 'virtualizerStrength': virtualizerStrength,
      if (loudnessMb != null) 'loudnessMb': loudnessMb,
    });
  }

  Future<void> setPlaybackActive(bool active) async {
    if (_playbackActive == active) return;
    _playbackActive = active;
    if (!_isMoodBioEngineActive) return;
    await _invokePlatformMethod('setBioPlaybackActive', <String, dynamic>{
      'active': active,
    });
  }

  Future<void> setMoodBioEngine({
    required bool enabled,
    double? toneBlend,
    double? isochronicDepth,
    double? noiseMask,
    double? pulseFrequency,
  }) async {
    _isMoodBioEngineActive = enabled;
    if (toneBlend != null) _moodToneBlend = toneBlend.clamp(0.0, 1.0);
    if (isochronicDepth != null) _moodIsochronicDepth = isochronicDepth.clamp(0.0, 1.0);
    if (noiseMask != null) _moodNoiseMask = noiseMask.clamp(0.0, 1.0);
    if (pulseFrequency != null) _moodPulseFrequency = pulseFrequency.clamp(0.5, 20.0);

    notifyListeners();
    await _syncMoodBioEngineHardware();
    _scheduleSave();
  }

  void _scheduleSave() {
    _debounceSaveTimer?.cancel();
    _debounceSaveTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        final SharedPreferences prefs = await _getPrefs();
        await Future.wait(<Future<bool>>[
          prefs.setBool(_kEqEnabledKey, _isEnabled),
          prefs.setString(_kActivePresetKey, _activePresetName),
          prefs.setStringList(_kBandGainsKey, _bandGainsDb.map((double g) => g.toStringAsFixed(1)).toList()),
          prefs.setBool(_kMoodBioEngineActiveKey, _isMoodBioEngineActive),
          prefs.setDouble(_kMoodToneBlendKey, _moodToneBlend),
          prefs.setDouble(_kMoodIsochronicDepthKey, _moodIsochronicDepth),
          prefs.setDouble(_kMoodNoiseMaskKey, _moodNoiseMask),
          prefs.setDouble(_kMoodPulseFrequencyKey, _moodPulseFrequency),
        ]);
      } catch (_) {}
    });
  }

  Future<void> toggleEnabled(bool enabled) async {
    _isEnabled = enabled;
    notifyListeners();
    await _syncWithHardwareDsp();
    if (enabled) {
      final DspPreset? current = presets[_activePresetName];
      if (current != null) {
        await setAuxEffects(
          bassStrength: current.bassBoostStrength,
          virtualizerStrength: current.virtualizerStrength,
          loudnessMb: current.loudnessMb,
        );
      }
    } else {
      await setAuxEffects(bassStrength: 0, virtualizerStrength: 0, loudnessMb: 0);
    }
    _scheduleSave();
  }

  Future<void> setBandGain(int bandIndex, double gainDb) async {
    if (bandIndex < 0 || bandIndex >= _bandGainsDb.length) return;
    _bandGainsDb[bandIndex] = gainDb.clamp(-12.0, 12.0);
    _activePresetName = 'Custom';
    notifyListeners();

    _scheduleThrottledDspSync();
    _scheduleSave();
  }

  Future<void> applyPreset(String presetName) async {
    final DspPreset? target = presets[presetName];
    if (target == null) return;

    _activePresetName = target.name;
    _bandGainsDb = List<double>.from(target.bandGainsDb);

    notifyListeners();
    await _syncWithHardwareDsp();

    if (_isEnabled) {
      await setAuxEffects(
        bassStrength: target.bassBoostStrength,
        virtualizerStrength: target.virtualizerStrength,
        loudnessMb: target.loudnessMb,
      );
    } else {
      await setAuxEffects(bassStrength: 0, virtualizerStrength: 0, loudnessMb: 0);
    }
    _scheduleSave();
  }

  Future<void> resetToFlat() async {
    await applyPreset('Flat / Bit-Perfect');
  }

  Future<void> releaseHardware() async {
    await _invokePlatformMethod('release', <String, dynamic>{});
  }

  @override
  void dispose() {
    _debounceSaveTimer?.cancel();
    _throttleSyncTimer?.cancel();
    super.dispose();
  }
}
