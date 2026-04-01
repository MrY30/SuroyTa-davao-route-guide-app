import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
// Import your PinMode enum and constants here!
import '../../core/constants.dart';
import '../../main.dart';

class CustomPinButton extends StatelessWidget {
  final String label;
  final String imagePath;
  final PinMode mode;
  final PinMode currentMode; // We need to know the app's current mode to determine the color
  final LatLng? pinData;
  final VoidCallback onTap;

  const CustomPinButton({
    super.key,
    required this.label,
    required this.imagePath,
    required this.mode,
    required this.currentMode,
    required this.pinData,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Paste your existing 3-State Visual Logic here
    // (e.g., bool isSelecting = currentMode == mode; bool isPlaced = pinData != null; ...)

    // Paste your SizedBox and ElevatedButton code here.
    // Use the variables passed in the constructor (label, imagePath, onTap) inside the button.
    bool isSelecting = currentPinMode == mode;
    bool isPlaced = pinData != null;

    Color bgColor = btnColor;
    Color txtColor = fontColor;
    Widget trailingIcon = const SizedBox.shrink();

    // The 3-State Visual Logic
    if (isPlaced) {
      bgColor = primaryColor; // STATE 3: Placed (Solid Primary Color)
      txtColor = fontColor;
      // Add a tiny checkmark to really sell the "Placed" state
      trailingIcon = const Padding(
        padding: EdgeInsets.only(left: 4), 
        child: Icon(Icons.check_circle, color: Colors.white, size: 16)
      );
    } else if (isSelecting) {
      bgColor = disableColor; // STATE 2: Selecting (Dimmed/Pulsing)
      txtColor = fontColor;
    } 
    // Otherwise, it falls back to STATE 1: Idle (btnColor)

    return SizedBox(
      width: 120, // Slightly wider to accommodate the new checkmark
      height: 40,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: txtColor,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          elevation: isPlaced ? 6 : (isSelecting ? 0 : 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Image.asset(imagePath, width: 24, height: 24),
            const SizedBox(width: 6),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ),
            ),
            trailingIcon, 
          ],
        ),
      ),
    );
  }
}