// lib/gemini_test_main.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

void main() {
  runApp(GeminiTestApp());
}

class GeminiTestApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gemini API Test',
      home: GeminiTestPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class GeminiTestPage extends StatefulWidget {
  @override
  _GeminiTestPageState createState() => _GeminiTestPageState();
}

class _GeminiTestPageState extends State<GeminiTestPage> {
  static const String _apiKey = 'AIzaSyCy1cWTsLIlBDsY1BfaUpgUw5ArL_aSrc0';
  late final GenerativeModel _model;

  String _output = 'กดปุ่มเพื่อทดสอบ Gemini AI';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: _apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.7,
        topK: 40,
        topP: 0.95,
        maxOutputTokens: 2048,
      ),
    );
  }

  Future<void> _testGeminiAPI() async {
    setState(() {
      _isLoading = true;
      _output = 'กำลังทดสอบ Gemini AI...\n';
    });

    try {
      final prompt = '''
คุณเป็นเชฟมืออาชีพและผู้เชี่ยวชาญด้านอาหาร กรุณาแนะนำเมนูอาหาร 3 เมนู โดยอ้างอิงจากสูตรที่มีอยู่จริงในเว็บไซต์ที่น่าเชื่อถือ

**วัตถุดิบที่มี**:
- ไข่ไก่: 3 ฟอง
- ข้าวสวย: 2 ถ้วย
- หอมใหญ่: 1 หัว

**ภารกิจ**: 
1. ค้นหาสูตรอาหารจากแหล่งข้อมูลที่เชื่อถือได้ เช่น:
   - Wongnai (เว็บรีวิวอาหารไทย)
   - Cookpad (สูตรอาหารจากผู้ใช้จริง)
   - Chef's Table YouTube channel
   - เว็บอาหารของหนังสือพิมพ์ชื่อดัง
   - บล็อกเชฟมืออาชีพ

2. ใส่ข้อมูลแหล่งอ้างอิงที่แท้จริง

**กรุณาตอบในรูปแบบ JSON เท่านั้น**:
{
  "recommendations": [
    {
      "menu_name": "ข้าวผัดไข่",
      "description": "เมนูง่าย ใช้ไข่และข้าว สูตรดั้งเดิม",
      "match_score": 85,
      "ingredients": [
        {"name": "ไข่ไก่", "amount": 2, "unit": "ฟอง"},
        {"name": "ข้าวสวย", "amount": 1, "unit": "ถ้วย"},
        {"name": "หอมใหญ่", "amount": 0.5, "unit": "หัว"}
      ],
      "steps": [
        {"step_number": 1, "instruction": "ตีไข่ใส่เกลือ", "time_minutes": 2},
        {"step_number": 2, "instruction": "ผัดไข่ให้สุก ตักขึ้น", "time_minutes": 3},
        {"step_number": 3, "instruction": "ผัดหอมใหญ่ ใส่ข้าว ผัดให้เข้ากัน", "time_minutes": 5}
      ],
      "cooking_time": 10,
      "prep_time": 5,
      "difficulty": "ง่าย",
      "servings": 2,
      "category": "อาหารจานหลัก",
      "nutrition": {
        "calories": 350,
        "protein": 14,
        "carbs": 40,
        "fat": 12
      },
      "source_name": "Wongnai Recipe",
      "source_url": "https://www.wongnai.com/recipes/fried-rice-with-egg",
      "source_type": "website",
      "chef_name": "Chef Sarawut",
      "tags": ["ง่าย", "ไว", "ประหยัด"]
    }
  ]
}

**สำคัญมาก**: 
- amount ต้องเป็นตัวเลขเท่านั้น (ห้ามใส่ช่วง เช่น 5-10)
- ต้องมี source_name และ source_url
- source_type: "website", "youtube", "cookbook", "blog"
- ใส่ชื่อเชฟหรือผู้เขียนสูตร (ถ้ามี)
- ตอบเฉพาะ JSON ไม่ใส่ข้อความอื่น
- ใส่ steps การทำอาหารด้วย
''';

      final stopwatch = Stopwatch()..start();

      final response = await _model
          .generateContent([Content.text(prompt)])
          .timeout(Duration(seconds: 30));

      stopwatch.stop();

      _addOutput('✅ ได้รับคำตอบใน ${stopwatch.elapsed.inSeconds} วินาที\n');

      if (response.text == null || response.text!.isEmpty) {
        _addOutput('❌ AI ไม่ได้ส่งคำตอบ\n');
        return;
      }

      final responseText = response.text!;
      _addOutput('📄 คำตอบจาก AI:\n');
      _addOutput('=' * 50 + '\n');
      _addOutput('$responseText\n');
      _addOutput('=' * 50 + '\n');

      // Clean JSON
      final cleanedJson = _cleanResponse(responseText);
      _addOutput('\n🔧 JSON ที่ทำความสะอาดแล้ว:\n');
      _addOutput('-' * 30 + '\n');
      _addOutput('$cleanedJson\n');
      _addOutput('-' * 30 + '\n');

      // Test Parse
      await _testJsonParsing(cleanedJson);
    } catch (e) {
      _addOutput('❌ เกิดข้อผิดพลาด: $e\n');

      if (e.toString().contains('PERMISSION_DENIED')) {
        _addOutput('🔑 ปัญหา: API Key ไม่ถูกต้อง\n');
      } else if (e.toString().contains('TimeoutException')) {
        _addOutput('⏱️ ปัญหา: AI ตอบช้าเกินไป\n');
      }
    }

    setState(() {
      _isLoading = false;
    });
  }

  void _addOutput(String text) {
    setState(() {
      _output += text;
    });
  }

  String _cleanResponse(String response) {
    String clean = response
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();

    final start = clean.indexOf('{');
    final end = clean.lastIndexOf('}') + 1;

    if (start != -1 && end > start) {
      clean = clean.substring(start, end);
    }

    // แก้ไข amount ที่เป็น range
    clean = clean.replaceAllMapped(
      RegExp(r'"amount":\s*(\d+)-(\d+)'),
      (match) => '"amount": "${match.group(1)}-${match.group(2)}"',
    );

    clean = clean.replaceAll(RegExp(r',(\s*[}\]])'), r'$1');

    return clean;
  }

  Future<void> _testJsonParsing(String jsonString) async {
    try {
      final jsonData = json.decode(jsonString);
      _addOutput('\n✅ JSON Parse สำเร็จ!\n');

      if (jsonData['recommendations'] == null) {
        _addOutput('⚠️  ไม่มี recommendations field\n');
        return;
      }

      final recommendations = jsonData['recommendations'] as List;
      _addOutput('📊 ได้เมนูทั้งหมด: ${recommendations.length} เมนู\n\n');

      for (int i = 0; i < recommendations.length; i++) {
        final menu = recommendations[i];
        _addOutput(
          '🍽️  เมนูที่ ${i + 1}: ${menu['menu_name'] ?? 'ไม่มีชื่อ'}\n',
        );
        _addOutput('   📝 รายละเอียด: ${menu['description'] ?? ''}\n');
        _addOutput('   ⭐ คะแนน: ${menu['match_score'] ?? 0}\n');
        _addOutput('   ⏱️  เวลาทำ: ${menu['cooking_time'] ?? 0} นาที\n');
        _addOutput('   📊 ความยาก: ${menu['difficulty'] ?? 'ไม่ระบุ'}\n');
        _addOutput('   🍽️  จำนวนที่ได้: ${menu['servings'] ?? 0} ที่\n');

        // แสดงแหล่งอ้างอิง
        if (menu['source_name'] != null || menu['source_url'] != null) {
          _addOutput('   📚 แหล่งอ้างอิง:\n');
          if (menu['source_name'] != null) {
            _addOutput('      • ชื่อ: ${menu['source_name']}\n');
          }
          if (menu['source_url'] != null &&
              menu['source_url'].toString().isNotEmpty) {
            _addOutput('      • URL: ${menu['source_url']}\n');
          }
          if (menu['source_type'] != null) {
            _addOutput('      • ประเภท: ${menu['source_type']}\n');
          }
          if (menu['chef_name'] != null) {
            _addOutput('      • เชฟ/ผู้เขียน: ${menu['chef_name']}\n');
          }
        }

        // แสดงวัตถุดิบ
        if (menu['ingredients'] != null) {
          final ingredients = menu['ingredients'] as List;
          _addOutput('   🥬 วัตถุดิบ (${ingredients.length} อย่าง):\n');

          for (var ing in ingredients) {
            final amount = ing['amount'];
            final amountType = amount.runtimeType.toString();
            _addOutput(
              '      • ${ing['name']}: $amount ${ing['unit']} ($amountType)\n',
            );

            if (amount is String && amount.contains('-')) {
              _addOutput('        ⚠️  WARNING: พบ range amount!\n');
            }
          }
        }

        // แสดงขั้นตอนการทำ
        if (menu['steps'] != null) {
          final steps = menu['steps'] as List;
          _addOutput('   👨‍🍳 ขั้นตอนการทำ (${steps.length} ขั้นตอน):\n');

          for (var step in steps) {
            final stepNum = step['step_number'] ?? 0;
            final instruction = step['instruction'] ?? '';
            final timeMinutes = step['time_minutes'] ?? 0;
            _addOutput('      $stepNum. $instruction ($timeMinutes นาที)\n');
          }
        }

        // แสดงข้อมูลโภชนาการ
        if (menu['nutrition'] != null) {
          final nutrition = menu['nutrition'];
          _addOutput('   📊 โภชนาการ (ต่อหนึ่งที่):\n');
          if (nutrition['calories'] != null) {
            final caloriesPerServing =
                (nutrition['calories'] / (menu['servings'] ?? 1));
            _addOutput('      • แคลอรี: ${caloriesPerServing.round()} kcal\n');
          }
          if (nutrition['protein'] != null) {
            _addOutput('      • โปรตีน: ${nutrition['protein']} g\n');
          }
          if (nutrition['carbs'] != null) {
            _addOutput('      • คาร์บอไฮเดรต: ${nutrition['carbs']} g\n');
          }
        }

        // แสดง tags
        if (menu['tags'] != null) {
          final tags = menu['tags'] as List;
          _addOutput('   🏷️  แท็ก: ${tags.join(', ')}\n');
        }

        _addOutput('\n');
      }

      _addOutput('🎉 การทดสอบเสร็จสิ้น!\n');
    } catch (parseError) {
      _addOutput('\n❌ JSON Parse ล้มเหลว: $parseError\n');
      _addOutput('💡 อาจมี amount เป็น range หรือ JSON ผิดรูปแบบ\n');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('🧪 Gemini API Test'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: _isLoading ? null : _testGeminiAPI,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              child: _isLoading
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('กำลังทดสอบ...'),
                      ],
                    )
                  : Text('🚀 ทดสอบ Gemini AI'),
            ),
            SizedBox(height: 16),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    _output,
                    style: TextStyle(fontFamily: 'Courier New', fontSize: 14),
                  ),
                ),
              ),
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _output = 'กดปุ่มเพื่อทดสอบ Gemini AI';
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[600],
                      foregroundColor: Colors.white,
                    ),
                    child: Text('🗑️ ล้างข้อมูล'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
