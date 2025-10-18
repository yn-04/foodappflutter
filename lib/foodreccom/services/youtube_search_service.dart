import 'package:http/http.dart' as http;

class YoutubeSearchService {
  static const _mSearch = 'https://m.youtube.com/results';
  static const _wSearch = 'https://www.youtube.com/results';

  // Returns first videoId for given query, or null if not found.
  static Future<String?> fetchFirstVideoId(String query) async {
    final cleaned = _sanitize(query);
    final variants = <String>{
      cleaned,
      '$cleaned recipe',
      '$cleaned วิธีทำ',
      'วิธีทำ $cleaned',
      '$cleaned สูตร',
    }.where((q) => q.trim().isNotEmpty).toList();

    for (final q in variants) {
      final id = await _searchOnce(q, preferMobile: true) ?? await _searchOnce(q, preferMobile: false);
      if (id != null) return id;
    }
    return null;
  }

  static String _sanitize(String s) {
    // ตัด emoji/วงเล็บ/อักขระพิเศษออก เหลือไทย/อังกฤษ/ตัวเลข/ช่องว่าง
    var out = s.replaceAll(RegExp(r"[\(\)\[\]\{\}<>]|\s+"), ' ').trim();
    out = out.replaceAll(RegExp(r"[^0-9A-Za-zก-๙\s]"), '');
    return out.trim();
  }

  static Future<String?> _searchOnce(String q, {bool preferMobile = true}) async {
    try {
      final encoded = Uri.encodeQueryComponent(q);
      final base = preferMobile ? _mSearch : _wSearch;
      // sp=EgIQAQ== คือ filter เฉพาะวิดีโอ (Type=Video)
      final url = '$base?search_query=$encoded&sp=EgIQAQ%3D%3D&hl=th';
      final res = await http
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent': preferMobile
                  ? 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36'
                  : 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
              'Accept-Language': 'th,en;q=0.9',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final body = res.body;

      // 1) JSON: "videoId":"XXXXXXXXXXX"
      final reJson = RegExp(r'"videoId"\s*:\s*"([a-zA-Z0-9_-]{11})"');
      final m1 = reJson.firstMatch(body);
      if (m1 != null) return m1.group(1);
      // 2) URL watch parameter
      final reWatch = RegExp(r'watch\?v=([a-zA-Z0-9_-]{11})');
      final m2 = reWatch.firstMatch(body);
      if (m2 != null) return m2.group(1);
      // 3) JSON URL field
      final reUrl = RegExp(r'"url"\s*:\s*"/watch\?v=([a-zA-Z0-9_-]{11})"');
      final m3 = reUrl.firstMatch(body);
      if (m3 != null) return m3.group(1);
      return null;
    } catch (_) {
      return null;
    }
  }
}
