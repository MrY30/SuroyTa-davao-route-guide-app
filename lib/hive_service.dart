import 'package:hive/hive.dart';
import 'models/favorite_location.dart';

class HiveService {
  // Grab the box we opened in main.dart
  final _locationBox = Hive.box<FavoriteLocation>('locations_box');

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
}