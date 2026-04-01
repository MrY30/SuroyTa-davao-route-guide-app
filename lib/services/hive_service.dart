import 'package:hive/hive.dart';
import '../models/favorite_location.dart';

class HiveService {
  // Grab the box we opened in main.dart
  final _locationBox = Hive.box<FavoriteLocation>('locations_box');
  final _settingsBox = Hive.box('settings_box');

  // 1. SAVE A LOCATION
  Future<void> saveLocation(FavoriteLocation location) async {
    // We use the unique 'id' as the key so we can easily find/delete it later
    await _locationBox.put(location.id, location);
  }

  // 2. GET ALL FAVORITES
  List<FavoriteLocation> getFavorites() {
    return _locationBox.values.where((loc) => loc.isFavorite).toList();
  }

  // 3. GET HISTORY
  List<FavoriteLocation> getHistory() {
    return _locationBox.values.where((loc) => !loc.isFavorite).toList();
  }

  // 4. DELETE A LOCATION
  Future<void> deleteLocation(String id) async {
    await _locationBox.delete(id);
  }
  
  // 5. CLEAR HISTORY (Optional, but good UX)
  Future<void> clearHistory() async {
    final historyKeys = _locationBox.values
        .where((loc) => !loc.isFavorite)
        .map((loc) => loc.id);
    await _locationBox.deleteAll(historyKeys);
  }

  // 1. Read the preference (Defaults to true if the user has never opened the app before)
  bool getShowInfoOnStartup() {
    return _settingsBox.get('show_startup_info', defaultValue: true);
  }

  // 2. Save the preference
  Future<void> toggleShowInfoOnStartup(bool value) async {
    await _settingsBox.put('show_startup_info', value);
  }

}