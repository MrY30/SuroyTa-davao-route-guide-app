import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

// 1. Define what data this tower holds
class MapState {
  final LatLng? startPin;
  final LatLng? destinationPin;

  MapState({this.startPin, this.destinationPin});

  MapState copyWith({LatLng? startPin, LatLng? destinationPin}) {
    return MapState(
      startPin: startPin ?? this.startPin,
      destinationPin: destinationPin ?? this.destinationPin,
    );
  }
}

class MapStateNotifier extends Notifier<MapState> {
  @override
  MapState build() {
    return MapState(startPin: null, destinationPin: null); 
  }

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

final mapStateProvider = NotifierProvider<MapStateNotifier, MapState>(() {
  return MapStateNotifier();
});