import 'package:flutter/material.dart';
import '../../core/constants.dart';

class CustomNavigation extends StatelessWidget{
  final VoidCallback onTap;
  final IconData icon;
  final String label;
  final int index;
  final int selectedIndex;
  
  const CustomNavigation({
    super.key,
    required this.icon,
    required this.label,
    required this.index,
    required this.onTap,
    required this.selectedIndex,
  });

  @override
  Widget build(BuildContext context) {
    bool isSelected = selectedIndex == index;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        width: 123,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? fontColor : unselectedNavColor,
              size: 30,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 0),
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? fontColor : unselectedNavColor,
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}