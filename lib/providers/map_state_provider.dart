import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

// 1. Define what data this tower holds
class MapState {
  final LatLng? startPin;
  final LatLng? destinationPin;

  MapState({this.startPin, this.destinationPin});

  // This is a helper method. In Riverpod, state is IMMUTABLE. 
  // We don't change variables directly; we create a new copy with the updated piece.
  MapState copyWith({LatLng? startPin, LatLng? destinationPin}) {
    return MapState(
      startPin: startPin ?? this.startPin,
      destinationPin: destinationPin ?? this.destinationPin,
    );
  }
}

// 2. The Controller (The plumber that manages the water)
class MapStateNotifier extends Notifier<MapState> {
  @override
  MapState build() {
    return MapState(startPin: null, destinationPin: null); 
  }

  // We explicitly create a new MapState to ensure nulls are accepted!
  void setStartPin(LatLng? coord) {
    state = MapState(startPin: coord, destinationPin: state.destinationPin);
  }

  void setDestinationPin(LatLng? coord) {
    state = MapState(startPin: state.startPin, destinationPin: coord);
  }

  void clearPins() {
    state = MapState(startPin: null, destinationPin: null);
  }
}

// 3. The Actual Provider (The pipe that widgets will connect to)
final mapStateProvider = NotifierProvider<MapStateNotifier, MapState>(() {
  return MapStateNotifier();
});