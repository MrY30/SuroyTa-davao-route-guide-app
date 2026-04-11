import 'package:hive/hive.dart';

part 'favorite_location.g.dart'; 

@HiveType(typeId: 0)
class FavoriteLocation {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final double latitude;

  @HiveField(3)
  final double longitude;

  @HiveField(4)
  final int? iconCodePoint;

  @HiveField(5)
  final bool isFavorite;

  FavoriteLocation({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.iconCodePoint,
    required this.isFavorite,
  });
}