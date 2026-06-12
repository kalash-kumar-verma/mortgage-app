import 'package:flutter/material.dart';

class ConflictBadge extends StatelessWidget {
  const ConflictBadge({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Sync Conflict / Needs Attention',
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.error_outline,
          color: Colors.red,
          size: 20,
        ),
      ),
    );
  }
}
