import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class LibraryHeaderWidget extends StatelessWidget {
  const LibraryHeaderWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.menuEntryBackground,
        border: Border(
          bottom: BorderSide(
            color: AppColors.menuBorder,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Left side - Back button
          IconButton(
            onPressed: () {
              Navigator.pop(context);
            },
            icon: Icon(
              Icons.arrow_back,
              color: AppColors.menuText,
              size: 24,
            ),
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          
          // Center - Title
          const Expanded(
            child: Center(
              child: Text(
                'LIBRARY',
                style: TextStyle(
                  color: AppColors.menuText,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
          
          // Right side - Empty space for symmetry
          const SizedBox(width: 40),
        ],
      ),
    );
  }
}
