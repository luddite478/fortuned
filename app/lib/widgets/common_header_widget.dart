import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../utils/app_colors.dart';
import '../screens/app_settings_screen.dart';

class CommonHeaderWidget extends StatelessWidget {
  final String? customTitle; // Optional custom title instead of current user name

  const CommonHeaderWidget({
    Key? key,
    this.customTitle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, child) {
        final currentUser = authService.currentUser;
        if (currentUser == null && customTitle == null) return const SizedBox();
        
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
              // User info with online indicator
              Expanded(
                child: Row(
                  children: [
                    Text(
                      customTitle ?? currentUser!.name,
                      style: GoogleFonts.sourceSans3(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.menuText,
                        letterSpacing: 1.5,
                      ),
                    ),
                    if (customTitle == null) ...[
                      const SizedBox(width: 8),
                      // Online indicator next to user name
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppColors.menuOnlineIndicator,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              
              // Settings button (only show for current user, not for custom titles)
              if (customTitle == null)
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AppSettingsScreen(),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.settings,
                      size: 16,
                      color: AppColors.menuText,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
} 