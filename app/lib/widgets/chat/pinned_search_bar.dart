import 'package:flutter/material.dart';

class PinnedSearchBar extends StatelessWidget {
  final int pinnedCount;
  final VoidCallback onOpenPins;
  final VoidCallback onSearch;

  const PinnedSearchBar({
    super.key,
    required this.pinnedCount,
    required this.onOpenPins,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onSearch,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: isDark ? Colors.white10 : Colors.black.withOpacity(0.04),
                  border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 18, color: isDark ? Colors.white70 : Colors.black54),
                    const SizedBox(width: 8),
                    Text(
                      'Search in chat',
                      style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: onOpenPins,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: isDark ? Colors.white10 : Colors.black.withOpacity(0.04),
                border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
              ),
              child: Row(
                children: [
                  const Text('📌', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Text('$pinnedCount', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}