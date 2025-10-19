import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../screens/library_screen.dart';

class SimplifiedHeaderWidget extends StatelessWidget {
  const SimplifiedHeaderWidget({Key? key}) : super(key: key);

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
          // Left side - empty for now, could add title or other elements
          const Expanded(
            child: SizedBox(),
          ),
          
          // Right side - Library icon
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const LibraryScreen(),
                ),
              );
            },
            icon: Icon(
              Icons.folder_outlined,
              color: AppColors.menuText,
              size: 24,
            ),
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
        ],
      ),
    );
  }
}
