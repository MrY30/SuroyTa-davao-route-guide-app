import 'package:hive/hive.dart';

// This part is crucial! It tells the generator what file to create.
part 'favorite_location.g.dart'; 

@HiveType(typeId: 0) // Every unique class in Hive needs a unique typeId
class FavoriteLocation {
  @HiveField(0)
  final String id; // A unique ID (usually the timestamp of when it was saved)

  @HiveField(1)
  final String name;

  @HiveField(2)
  final double latitude;

  @HiveField(3)
  final double longitude;

  @HiveField(4)
  final int? iconCodePoint;

  @HiveField(5)
  final bool isFavorite; // true = Favorite, false = History

  FavoriteLocation({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.iconCodePoint,
    required this.isFavorite,
  });
}