import 'package:flutter/material.dart';
import 'package:sakay_ta_mobile_app/core/constants.dart';

class FavoriteCard extends StatelessWidget{
  final bool isVisible;
  final bool isSaved;
  final String displayTitle;
  final VoidCallback onClick;


  const FavoriteCard({
    super.key,
    required this.isVisible,
    required this.isSaved,
    required this.displayTitle,
    required this.onClick,

  });

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: isVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutBack,
      child: GestureDetector(
        onTap: onClick,
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: btnColor.withOpacity(0.8),
            borderRadius: BorderRadius.circular(13),
            boxShadow: [
              BoxShadow(
                color: btnColor.withOpacity(0.3),
                offset: Offset(0, 20),
                blurRadius: 20
              )
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20), 
            child:Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 20,
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
                Icon(isSaved ? Icons.star : Icons.star_border, color: isSaved ? Colors.amber : Colors.white),
              ],
            )
          )
        ),
      )
    );
  }
}