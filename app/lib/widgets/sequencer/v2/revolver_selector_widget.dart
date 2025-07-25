import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Import colors from existing widget
class SequencerPhoneBookColors {
  static const Color pageBackground = Color(0xFF3A3A3A);
  static const Color surfaceBase = Color(0xFF4A4A47);
  static const Color surfaceRaised = Color(0xFF525250);
  static const Color surfacePressed = Color(0xFF424240);
  static const Color text = Color(0xFFE8E6E0);
  static const Color lightText = Color(0xFFB8B6B0);
  static const Color accent = Color(0xFF8B7355);
  static const Color border = Color(0xFF5A5A57);
  static const Color shadow = Color(0xFF2A2A2A);
}

enum RevolverAlignment {
  left,    // First item starts on the left
  center,  // First item starts in the center
}

class RevolverItem {
  final String displayText;
  final dynamic value;
  
  const RevolverItem({
    required this.displayText,
    required this.value,
  });
}

class RevolverSelectorWidget extends StatefulWidget {
  final List<RevolverItem> items;
  final dynamic selectedValue;
  final ValueChanged<dynamic> onChanged;
  final RevolverAlignment alignment;
  final double height;
  final double centerTileSize;
  final double sideTileSize;
  final String? title;
  
  const RevolverSelectorWidget({
    super.key,
    required this.items,
    required this.selectedValue,
    required this.onChanged,
    this.alignment = RevolverAlignment.left,
    this.height = 80,
    this.centerTileSize = 48,
    this.sideTileSize = 32,
    this.title,
  });

  @override
  State<RevolverSelectorWidget> createState() => _RevolverSelectorWidgetState();
}

class _RevolverSelectorWidgetState extends State<RevolverSelectorWidget> {
  late ScrollController _scrollController;
  late int _selectedIndex;
  late double _itemWidth;
  
  @override
  void initState() {
    super.initState();
    _itemWidth = widget.centerTileSize + 16; // Add padding
    _selectedIndex = widget.items.indexWhere((item) => item.value == widget.selectedValue);
    if (_selectedIndex == -1) _selectedIndex = 0;
    
    _scrollController = ScrollController();
    
    // Calculate initial scroll position based on alignment
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToSelectedItem();
    });
  }
  
  @override
  void didUpdateWidget(RevolverSelectorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedValue != widget.selectedValue) {
      _selectedIndex = widget.items.indexWhere((item) => item.value == widget.selectedValue);
      if (_selectedIndex == -1) _selectedIndex = 0;
      _scrollToSelectedItem();
    }
  }
  
  void _scrollToSelectedItem() {
    if (!_scrollController.hasClients) return;
    
    double targetOffset;
    if (widget.alignment == RevolverAlignment.center) {
      // Center the selected item in the viewport
      final viewportWidth = _scrollController.position.viewportDimension;
      targetOffset = (_selectedIndex * _itemWidth) - (viewportWidth / 2) + (_itemWidth / 2);
    } else {
      // Align selected item to the left
      targetOffset = _selectedIndex * _itemWidth;
    }
    
    // Clamp to valid scroll range
    targetOffset = targetOffset.clamp(
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    );
    
    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }
  
  void _onItemTap(int index) {
    setState(() {
      _selectedIndex = index;
    });
    widget.onChanged(widget.items[index].value);
    _scrollToSelectedItem();
  }
  
  double _calculateScale(int index) {
    if (!_scrollController.hasClients) return index == _selectedIndex ? 1.0 : 0.7;
    
    final viewportWidth = _scrollController.position.viewportDimension;
    final centerOfViewport = _scrollController.offset + (viewportWidth / 2);
    final itemCenter = (index * _itemWidth) + (_itemWidth / 2);
    final distanceFromCenter = (centerOfViewport - itemCenter).abs();
    
    // Scale based on distance from center of viewport
    final maxDistance = _itemWidth * 2;
    final normalizedDistance = (distanceFromCenter / maxDistance).clamp(0.0, 1.0);
    
    return (1.0 - (normalizedDistance * 0.3)).clamp(0.7, 1.0);
  }
  
  double _calculateOpacity(int index) {
    if (!_scrollController.hasClients) return index == _selectedIndex ? 1.0 : 0.6;
    
    final viewportWidth = _scrollController.position.viewportDimension;
    final centerOfViewport = _scrollController.offset + (viewportWidth / 2);
    final itemCenter = (index * _itemWidth) + (_itemWidth / 2);
    final distanceFromCenter = (centerOfViewport - itemCenter).abs();
    
    // Opacity based on distance from center
    final maxDistance = _itemWidth * 2.5;
    final normalizedDistance = (distanceFromCenter / maxDistance).clamp(0.0, 1.0);
    
    return (1.0 - (normalizedDistance * 0.4)).clamp(0.6, 1.0);
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.title != null) ...[
          Text(
            widget.title!,
            style: GoogleFonts.sourceSans3(
              color: SequencerPhoneBookColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: SequencerPhoneBookColors.surfacePressed,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: SequencerPhoneBookColors.border,
              width: 0.5,
            ),
          ),
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollUpdateNotification) {
                setState(() {}); // Trigger rebuild to update scales/opacities
              }
              return false;
            },
            child: ListView.builder(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: _itemWidth),
              itemCount: widget.items.length,
              itemBuilder: (context, index) {
                final item = widget.items[index];
                final scale = _calculateScale(index);
                final opacity = _calculateOpacity(index);
                final isSelected = index == _selectedIndex;
                
                return Container(
                  width: _itemWidth,
                  child: Center(
                    child: AnimatedScale(
                      scale: scale,
                      duration: const Duration(milliseconds: 200),
                      child: AnimatedOpacity(
                        opacity: opacity,
                        duration: const Duration(milliseconds: 200),
                        child: GestureDetector(
                          onTap: () => _onItemTap(index),
                          child: Container(
                            width: widget.centerTileSize,
                            height: widget.centerTileSize,
                            decoration: BoxDecoration(
                              color: isSelected 
                                  ? SequencerPhoneBookColors.surfaceRaised
                                  : SequencerPhoneBookColors.surfaceBase,
                              borderRadius: BorderRadius.circular(2),
                              border: Border.all(
                                color: isSelected 
                                    ? SequencerPhoneBookColors.accent
                                    : SequencerPhoneBookColors.border,
                                width: isSelected ? 1.0 : 0.5,
                              ),
                              boxShadow: isSelected ? [
                                BoxShadow(
                                  color: SequencerPhoneBookColors.shadow,
                                  blurRadius: 2,
                                  offset: const Offset(0, 1),
                                ),
                              ] : null,
                            ),
                            child: Center(
                              child: Text(
                                item.displayText,
                                style: GoogleFonts.sourceSans3(
                                  color: isSelected 
                                      ? SequencerPhoneBookColors.accent
                                      : SequencerPhoneBookColors.lightText,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
  
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

// Helper functions to create common revolver configurations

/// Creates step jump selector (1-maxSequencerSteps, starting from center)
List<RevolverItem> createStepJumpItems(int maxSteps) {
  return List.generate(maxSteps, (index) => RevolverItem(
    displayText: '${index + 1}',
    value: index + 1,
  ));
}

/// Creates musical key selector (centered around default key)
List<RevolverItem> createKeyItems({int centerKey = 0, int range = 12}) {
  final items = <RevolverItem>[];
  
  // Create items from -range to +range
  for (int i = -range; i <= range; i++) {
    String displayText;
    if (i == 0) {
      displayText = '0'; // Default key
    } else if (i > 0) {
      displayText = '+$i';
    } else {
      displayText = '$i';
    }
    
    items.add(RevolverItem(
      displayText: displayText,
      value: centerKey + i,
    ));
  }
  
  return items;
} 