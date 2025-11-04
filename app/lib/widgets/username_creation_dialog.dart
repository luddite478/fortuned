import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/app_colors.dart';

class UsernameCreationDialog extends StatefulWidget {
  final String title;
  final String message;
  final Function(String username) onSubmit;

  const UsernameCreationDialog({
    super.key,
    required this.title,
    required this.message,
    required this.onSubmit,
  });

  @override
  State<UsernameCreationDialog> createState() => _UsernameCreationDialogState();
}

class _UsernameCreationDialogState extends State<UsernameCreationDialog> {
  final TextEditingController _usernameController = TextEditingController();
  String? _errorMessage;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  String? _validateUsername(String username) {
    if (username.isEmpty) {
      return 'Username is required';
    }
    if (username.length < 3) {
      return 'Username must be at least 3 characters';
    }
    // Check for valid characters: alphanumeric, underscore, hyphen
    final validPattern = RegExp(r'^[a-zA-Z0-9_-]+$');
    if (!validPattern.hasMatch(username)) {
      return 'Only letters, numbers, _ and - allowed';
    }
    return null;
  }

  Future<void> _handleSubmit() async {
    final username = _usernameController.text.trim();
    final error = _validateUsername(username);

    if (error != null) {
      setState(() {
        _errorMessage = error;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await widget.onSubmit(username);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final dialogWidth = (size.width * 0.85).clamp(280.0, 400.0);

    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Container(
          width: dialogWidth,
          constraints: const BoxConstraints(maxHeight: 400),
          decoration: BoxDecoration(
            color: AppColors.sequencerSurfaceRaised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.sequencerBorder, width: 0.5),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title
                  Row(
                    children: [
                      Text(
                        widget.title,
                        style: GoogleFonts.sourceSans3(
                          color: AppColors.sequencerText,
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (!_isSubmitting)
                        IconButton(
                          icon: Icon(Icons.close, color: AppColors.sequencerLightText, size: 24),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Message
                  Text(
                    widget.message,
                    style: GoogleFonts.sourceSans3(
                      color: AppColors.sequencerLightText,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Username input field
                  TextField(
                    controller: _usernameController,
                    enabled: !_isSubmitting,
                    autofocus: true,
                    style: GoogleFonts.sourceSans3(
                      color: AppColors.sequencerText,
                      fontSize: 16,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Enter username',
                      hintStyle: GoogleFonts.sourceSans3(
                        color: AppColors.sequencerLightText.withOpacity(0.5),
                        fontSize: 16,
                      ),
                      filled: true,
                      fillColor: AppColors.sequencerSurfaceBase,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppColors.sequencerBorder, width: 0.5),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppColors.sequencerBorder, width: 0.5),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppColors.sequencerAccent, width: 1.5),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppColors.sequencerAccent, width: 1.5),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppColors.sequencerAccent, width: 1.5),
                      ),
                      errorText: _errorMessage,
                      errorStyle: GoogleFonts.sourceSans3(
                        color: AppColors.sequencerAccent,
                        fontSize: 12,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    onChanged: (value) {
                      if (_errorMessage != null) {
                        setState(() {
                          _errorMessage = null;
                        });
                      }
                    },
                    onSubmitted: (_) => _handleSubmit(),
                  ),
                  const SizedBox(height: 8),

                  // Format hint
                  Text(
                    'Min 3 characters, letters, numbers, _ and -',
                    style: GoogleFonts.sourceSans3(
                      color: AppColors.sequencerLightText.withOpacity(0.7),
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Submit button
                  SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _handleSubmit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.sequencerAccent,
                        foregroundColor: AppColors.sequencerText,
                        disabledBackgroundColor: AppColors.sequencerBorder,
                        disabledForegroundColor: AppColors.sequencerLightText,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isSubmitting
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.sequencerText,
                                ),
                              ),
                            )
                          : Text(
                              'Create Username',
                              style: GoogleFonts.sourceSans3(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

