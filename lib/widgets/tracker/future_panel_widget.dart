import 'package:flutter/material.dart';

class FuturePanelWidget extends StatelessWidget {
  const FuturePanelWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1f2937),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: Text(
          'Future Panel',
          style: TextStyle(
            color: Colors.grey,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
} 