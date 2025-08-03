import 'package:flutter/material.dart';

/// Centralized color management for the Niyya app
/// 
/// Contains two main color palettes:
/// 1. Sequencer colors - Dark theme for sequencer screens and widgets
/// 2. Menu colors - Black-white/dark-light gray theme for menu screens
class AppColors {
  
  // Sequencer colors - dark theme for music production interface
  static const Color sequencerPageBackground = Color(0xFF3A3A3A); // Dark gray background
  static const Color sequencerSurfaceBase = Color(0xFF4A4A47); // Gray-beige base surface
  static const Color sequencerSurfaceRaised = Color(0xFF525250); // Protruding surface color
  static const Color sequencerSurfacePressed = Color(0xFF424240); // Pressed/active surface
  static const Color sequencerText = Color(0xFFE8E6E0); // Light text for contrast
  static const Color sequencerLightText = Color(0xFFB8B6B0); // Muted light text
  static const Color sequencerAccent = Color(0xFF8B7355); // Brown accent for highlights
  static const Color sequencerBorder = Color(0xFF5A5A57); // Subtle borders
  static const Color sequencerShadow = Color(0xFF2A2A2A); // Dark shadows for depth
  static const Color sequencerCellEmpty = Color(0xFF3E3E3B); // Empty grid cells
  static const Color sequencerCellEmptyAlternate = Color(0xFF3E3E3B); // Same as cellEmpty for consistency
  static const Color sequencerCellFilled = Color(0xFF5C5A55); // Filled grid cells
  static const Color sequencerSecondaryButton = Color(0xFF6A6A67); // Grayed out secondary buttons
  static const Color sequencerSecondaryButtonAlt = Color(0xFF5A5A57); // Alternative secondary button
  static const Color sequencerPrimaryButton = Color(0xFF9B8365); // Lighter main action button
  
  // Menu colors - black-white/dark-light gray theme for navigation and content screens
  static const Color menuPageBackground = Color(0xFFF8F8F8); // Light gray background
  static const Color menuEntryBackground = Color(0xFFFFFFFF); // White entry background
  static const Color menuText = Color(0xFF1A1A1A); // Dark gray/black text
  static const Color menuLightText = Color(0xFF666666); // Medium gray text
  static const Color menuBorder = Color(0xFFE0E0E0); // Light gray border
  static const Color menuOnlineIndicator = Color(0xFF4CAF50); // Green indicator
  static const Color menuOnlineIndicatorActive = Color(0xFF7629C3); // Purple for active/online states
  static const Color menuErrorColor = Color(0xFFDC2626); // Red for errors
  
  // Button colors for menu screens
  static const Color menuPrimaryButton = Color(0xFF1A1A1A); // Dark primary button
  static const Color menuPrimaryButtonText = Color(0xFFFFFFFF); // White text on dark button
  static const Color menuSecondaryButton = Color(0xFFFFFFFF); // White secondary button
  static const Color menuSecondaryButtonText = Color(0xFF1A1A1A); // Dark text on light button
  static const Color menuSecondaryButtonBorder = Color(0xFF1A1A1A); // Dark border for secondary button
  
  // Legacy button colors for gradual migration
  static const Color menuButtonBackground = Color(0xFFF0F0F0); // Light gray for subtle buttons
  static const Color menuButtonBorder = Color(0xFFD0D0D0); // Gray border for subtle buttons
  
  // Checkpoint-specific colors
  static const Color menuCheckpointBackground = Color(0xFFF5F5F5); // Checkpoint cards
  static const Color menuCurrentUserCheckpoint = Color(0xFFEEEEEE); // Current user checkpoints
} 