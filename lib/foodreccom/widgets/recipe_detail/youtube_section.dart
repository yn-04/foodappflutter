import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import '../../models/recipe/recipe_model.dart';
import '../../services/youtube_search_service.dart';

class RecipeYoutubeSection extends StatefulWidget {
  final RecipeModel recipe;
  const RecipeYoutubeSection({super.key, required this.recipe});

  @override
  State<RecipeYoutubeSection> createState() => _RecipeYoutubeSectionState();
}

class _RecipeYoutubeSectionState extends State<RecipeYoutubeSection> {
  String? _videoId;
  bool _loading = true;
  String? _lastQuery;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final thaiName = widget.recipe.name.trim();
    final englishName = widget.recipe.originalTitle.trim();

    String normalizeKey(String value) => value.trim().toLowerCase();
    final seen = <String>{};
    final queries = <String>[];

    void addQuery(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      final key = normalizeKey(trimmed);
      if (seen.add(key)) queries.add(trimmed);
    }

    final hasThai = thaiName.isNotEmpty;
    final hasEnglish = englishName.isNotEmpty;
    if (hasThai &&
        hasEnglish &&
        normalizeKey(thaiName) != normalizeKey(englishName)) {
      addQuery('$thaiName $englishName');
      addQuery('$englishName $thaiName');
    }
    if (hasEnglish) addQuery(englishName);
    if (hasThai) addQuery(thaiName);
    addQuery('recipe');

    String? id;
    String? usedQuery;
    for (final query in queries) {
      id = await YoutubeSearchService.fetchFirstVideoId(query);
      if (id != null) {
        usedQuery = query;
        break;
      }
    }
    if (!mounted) return;
    setState(() {
      _videoId = id;
      _loading = false;
      _lastQuery = usedQuery ?? queries.first;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox.shrink();
    }
    final hasVideo = _videoId != null && _videoId!.isNotEmpty;
    final thumb = hasVideo
        ? 'https://i.ytimg.com/vi/$_videoId/hqdefault.jpg'
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '▶️ วิดีโอสอนทำ (YouTube)',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (hasVideo)
          GestureDetector(
            onTap: _openVideo,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Image.network(thumb!, fit: BoxFit.cover),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(40),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: const Icon(
                    Icons.play_arrow,
                    size: 48,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          )
        else
          _searchCard(context),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: hasVideo ? _openVideo : _openSearch,
            icon: const Icon(Icons.ondemand_video),
            label: Text(hasVideo ? 'เปิดใน YouTube' : 'ค้นหาใน YouTube'),
          ),
        ),
      ],
    );
  }

  Future<void> _openVideo() async {
    if (_videoId == null) return;
    final vid = _videoId!;
    // Try scheme for YouTube app first
    final candidates = <String>[
      'vnd.youtube:$vid',
      'youtube://www.youtube.com/watch?v=$vid',
      'https://www.youtube.com/watch?v=$vid',
    ];
    for (final url in candidates) {
      if (await _openFlexible(url)) return;
    }
    _showSnack('ไม่พบแอป/เบราว์เซอร์สำหรับเปิด YouTube');
  }

  Future<void> _openSearch() async {
    final defaultBase = widget.recipe.originalTitle.trim().isNotEmpty
        ? widget.recipe.originalTitle.trim()
        : widget.recipe.name.trim();
    final base = (_lastQuery ?? defaultBase).trim();
    final q = base.isEmpty ? 'recipe' : base;
    final url =
        'https://www.youtube.com/results?search_query=${Uri.encodeComponent(q)}';
    if (await _openFlexible(url)) return;
    _showSnack('ไม่พบแอป/เบราว์เซอร์สำหรับเปิดลิงก์ YouTube');
  }

  Future<bool> _openFlexible(String url) async {
    final uri = Uri.parse(url);
    // Try external app/browser
    if (await canLaunchUrl(uri)) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication))
          return true;
      } catch (_) {}
    }
    // Try platform default
    try {
      if (await launchUrl(uri, mode: LaunchMode.platformDefault)) return true;
    } catch (_) {}
    // Try in-app browser view (if supported)
    try {
      if (await launchUrl(uri, mode: LaunchMode.inAppBrowserView)) return true;
    } catch (_) {}
    // Copy to clipboard as last resort
    try {
      await Clipboard.setData(ClipboardData(text: url));
    } catch (_) {}
    return false;
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _searchCard(BuildContext context) {
    return GestureDetector(
      onTap: _openSearch,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.red[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red[200]!),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.ondemand_video, color: Colors.red),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'ไม่พบวิดีโอโดยตรง • แตะเพื่อค้นหาใน YouTube',
                style: TextStyle(
                  color: Colors.red[800],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.open_in_new, color: Colors.red),
          ],
        ),
      ),
    );
  }
}
