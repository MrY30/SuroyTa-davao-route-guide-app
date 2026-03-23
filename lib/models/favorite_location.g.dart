// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'favorite_location.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FavoriteLocationAdapter extends TypeAdapter<FavoriteLocation> {
  @override
  final int typeId = 0;

  @override
  FavoriteLocation read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FavoriteLocation(
      id: fields[0] as String,
      name: fields[1] as String,
      latitude: fields[2] as double,
      longitude: fields[3] as double,
      iconCodePoint: fields[4] as int?,
      isFavorite: fields[5] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, FavoriteLocation obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.latitude)
      ..writeByte(3)
      ..write(obj.longitude)
      ..writeByte(4)
      ..write(obj.iconCodePoint)
      ..writeByte(5)
      ..write(obj.isFavorite);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FavoriteLocationAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
