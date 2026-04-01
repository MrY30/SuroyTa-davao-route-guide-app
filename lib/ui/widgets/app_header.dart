import 'package:flutter/material.dart';
import '../../core/constants.dart';

class AppHeader extends StatelessWidget{
  final VoidCallback onClick;

  const AppHeader({
    super.key,
    required this.onClick,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      width: double.infinity,
      decoration: BoxDecoration(
        color: btnColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: btnColor.withOpacity(0.3),
            offset: Offset(0, 20),
            blurRadius: 20
          )
        ],
      ),
      child: Stack(
        children: [
          Center(
              child:Text(
              "SUROY TA!",
              style: TextStyle(
                fontFamily: 'Cubao',
                fontSize: 30,
                color: fontColor,
                shadows: [
                  Shadow(
                    offset: Offset(1, 4),
                    blurRadius: 7,
                    color: Colors.black.withOpacity(0.5)
                  )
                ]
              ),
            ),
          ),
          // 2. The Help Icon pinned to the right edge
          Positioned(
            right: 10.0, // Gives it a little breathing room from the edge
            top: 0,
            bottom: 0,
            child: IconButton(
              icon: const Icon(Icons.help_outline, color: fontColor, size: 25),
              onPressed: onClick,
            ),
          ),
        ],
      ) 
      
    );
  }
}