// lib/rawmaterial/widgets/search_filter_bar.dart — แถบค้นหา + ตัวกรองวันหมดอายุ
import 'package:flutter/material.dart';

class SearchFilterBar extends StatelessWidget {
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;

  final String selectedExpiryFilter;
  final int? customDays;
  final List<String> expiryOptions;
  final ValueChanged<String> onSelectExpiry;
  final VoidCallback onOpenCustomDays;

  const SearchFilterBar({
    super.key,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.selectedExpiryFilter,
    required this.customDays,
    required this.expiryOptions,
    required this.onSelectExpiry,
    required this.onOpenCustomDays,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: searchController,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'ค้นหาวัตถุดิบ',
                hintStyle: TextStyle(color: Colors.grey[400]),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: Colors.grey[400],
                  size: 20,
                ),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear,
                          color: Colors.grey[400],
                          size: 20,
                        ),
                        onPressed: () {
                          searchController.clear();
                          onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: Colors.grey[300]!, width: 1.3),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: Colors.grey[300]!, width: 1.3),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: Colors.grey[400]!, width: 1.5),
                ),
              ),
              onChanged: (v) => onSearchChanged(v),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: selectedExpiryFilter == 'ทั้งหมด'
                  ? Colors.white
                  : Colors.yellow[300],
              border: Border.all(
                color: selectedExpiryFilter == 'ทั้งหมด'
                    ? Colors.grey[400]!
                    : Colors.yellow[600]!,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: PopupMenuButton<String>(
              tooltip: 'กรองตามวันหมดอายุ (จะแสดงเรียงใกล้หมดอายุก่อน)',
              offset: const Offset(0, 40),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      color: selectedExpiryFilter == 'ทั้งหมด'
                          ? Colors.grey[600]
                          : Colors.black,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      selectedExpiryFilter == 'ทั้งหมด'
                          ? 'หมดอายุ'
                          : (selectedExpiryFilter == 'กำหนดเอง'
                                ? 'หมดอายุ (${customDays ?? 0} วัน)'
                                : 'หมดอายุ: $selectedExpiryFilter'),
                      style: TextStyle(
                        color: selectedExpiryFilter == 'ทั้งหมด'
                            ? Colors.grey[600]
                            : Colors.black,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Icon(
                      Icons.arrow_drop_down,
                      color: selectedExpiryFilter == 'ทั้งหมด'
                          ? Colors.grey[600]
                          : Colors.black,
                    ),
                  ],
                ),
              ),
              itemBuilder: (_) => expiryOptions.map((opt) {
                final isCustom = opt == 'กำหนดเอง…';
                final isSelected = isCustom
                    ? selectedExpiryFilter == 'กำหนดเอง'
                    : selectedExpiryFilter == opt;
                final label =
                    (isCustom &&
                        selectedExpiryFilter == 'กำหนดเอง' &&
                        customDays != null)
                    ? 'กำหนดเอง (${customDays} วัน)'
                    : opt;
                return PopupMenuItem<String>(
                  value: opt,
                  child: Row(
                    children: [
                      if (isSelected)
                        const Icon(Icons.check, size: 18, color: Colors.black)
                      else
                        const SizedBox(width: 18),
                      const SizedBox(width: 6),
                      Text(label),
                    ],
                  ),
                );
              }).toList(),
              onSelected: (val) {
                if (val == 'กำหนดเอง…') {
                  onOpenCustomDays();
                } else {
                  onSelectExpiry(val);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
