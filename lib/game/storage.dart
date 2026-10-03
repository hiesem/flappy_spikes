import 'package:shared_preferences/shared_preferences.dart';

/// Persistence layer for bestScore / gamesPlayed / muteSound / musicVolume.
class GameStorage {
  static const String _bestScoreKey = 'bestScore';
  static const String _gamesPlayedKey = 'gamesPlayed';
  static const String _muteSoundKey = 'muteSound';
  static const String _musicVolumeKey = 'musicVolume';

  int bestScore = 0;
  int gamesPlayed = 0;
  bool muteSound = false;
  double musicVolume = 0.6;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    bestScore = prefs.getInt(_bestScoreKey) ?? 0;
    gamesPlayed = prefs.getInt(_gamesPlayedKey) ?? 0;
    muteSound = prefs.getBool(_muteSoundKey) ?? false;
    musicVolume = prefs.getDouble(_musicVolumeKey) ?? 0.6;
  }

  Future<void> saveBestScore(int value) async {
    bestScore = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_bestScoreKey, value);
  }

  Future<void> incrementGamesPlayed() async {
    gamesPlayed++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_gamesPlayedKey, gamesPlayed);
  }

  Future<void> saveMuteSound(bool value) async {
    muteSound = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_muteSoundKey, value);
  }

  Future<void> saveMusicVolume(double value) async {
    musicVolume = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_musicVolumeKey, value);
  }
}
