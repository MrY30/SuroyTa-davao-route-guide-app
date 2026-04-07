import 'package:hive/hive.dart';
import 'package:sakay_ta_mobile_app/models/favorite_location.dart';

class HiveService {
  final _locationBox = Hive.box<FavoriteLocation>('locations_box');
  final _settingsBox = Hive.box('settings_box');

  // SAVE A LOCATION
  Future<void> saveLocation(FavoriteLocation location) async {
    await _locationBox.put(location.id, location);
  }

  // GET ALL FAVORITES
  List<FavoriteLocation> getFavorites() {
    return _locationBox.values.where((loc) => loc.isFavorite).toList();
  }

  // GET HISTORY
  List<FavoriteLocation> getHistory() {
    return _locationBox.values.where((loc) => !loc.isFavorite).toList();
  }

  // DELETE A LOCATION
  Future<void> deleteLocation(String id) async {
    await _locationBox.delete(id);
  }
  
  // CLEAR HISTORY
  Future<void> clearHistory() async {
    final historyKeys = _locationBox.values
        .where((loc) => !loc.isFavorite)
        .map((loc) => loc.id);
    await _locationBox.deleteAll(historyKeys);
  }

  // Read the preference (Defaults to true if the user has never opened the app before)
  bool getShowInfoOnStartup() {
    return _settingsBox.get('show_startup_info', defaultValue: true);
  }

  // Save the preference
  Future<void> toggleShowInfoOnStartup(bool value) async {
    await _settingsBox.put('show_startup_info', value);
  }

}