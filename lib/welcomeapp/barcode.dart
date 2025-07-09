import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'dart:async';

class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key});

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  CameraController? _cameraController;
  BarcodeScanner? _barcodeScanner;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  String? _scannedCode;
  List<Barcode> _barcodes = [];
  late List<CameraDescription> _cameras;

  @override
  void initState() {
    super.initState();
    _initializeBarcodeScanner();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      // เพิ่ม timeout
      _cameras = await availableCameras().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Timeout: ไม่สามารถเข้าถึงกล้องได้');
        },
      );

      if (_cameras.isNotEmpty) {
        _cameraController = CameraController(
          _cameras.first,
          ResolutionPreset.low,
          enableAudio: false,
        );

        await _cameraController!.initialize().timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw Exception('Timeout: การเตรียมกล้องใช้เวลานานเกินไป');
          },
        );

        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
          await Future.delayed(const Duration(milliseconds: 500));
          _startImageStream();
        }
      } else {
        throw Exception('ไม่พบกล้องในอุปกรณ์');
      }
    } catch (e) {
      print('Error initializing camera: $e');
      if (mounted) {
        // แสดง dialog แทน SnackBar
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('ไม่สามารถเปิดกล้องได้'),
            content: Text(
              'สาเหตุ: $e\n\n'
              'กรุณาตรวจสอบ:\n'
              '• อนุญาตการใช้กล้องในการตั้งค่า\n'
              '• ไม่มีแอปอื่นใช้กล้องอยู่\n'
              '• รีสตาร์ทแอป',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // ปิด dialog
                  Navigator.pop(context); // กลับหน้าก่อน
                },
                child: const Text('ตกลง'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _initializeCamera(); // ลองใหม่
                },
                child: const Text('ลองใหม่'),
              ),
            ],
          ),
        );
      }
    }
  }

  void _initializeBarcodeScanner() {
    _barcodeScanner = BarcodeScanner(
      formats: [
        BarcodeFormat.qrCode,
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.code93,
        BarcodeFormat.codabar,
        BarcodeFormat.dataMatrix,
        BarcodeFormat.pdf417,
        BarcodeFormat.aztec,
        BarcodeFormat.upca,
        BarcodeFormat.upce,
        BarcodeFormat.itf,
      ],
    );
  }

  void _startImageStream() {
    if (_cameraController?.value.isStreamingImages == true) {
      return; // ป้องกันการเริ่ม stream ซ้ำ
    }

    _cameraController!.startImageStream((CameraImage image) {
      if (!_isProcessing) {
        _isProcessing = true;
        _processImage(image).then((_) {
          // เพิ่มหน่วงเวลาเล็กน้อยระหว่างการประมวลผล
          Future.delayed(const Duration(milliseconds: 100), () {
            _isProcessing = false;
          });
        });
      }
    });
  }

  Future<void> _processImage(CameraImage image) async {
    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage != null) {
        final barcodes = await _barcodeScanner!.processImage(inputImage);

        if (barcodes.isNotEmpty && mounted) {
          setState(() {
            _barcodes = barcodes;
            _scannedCode =
                barcodes.first.displayValue ?? barcodes.first.rawValue;
          });

          // หยุดการสแกนเมื่อพบบาร์โค้ด
          if (_cameraController?.value.isStreamingImages == true) {
            await _cameraController?.stopImageStream();
          }
          _showBarcodeDialog(barcodes.first);
        }
      }
    } catch (e) {
      print('Error processing image: $e');
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final camera = _cameras.first;
    final sensorOrientation = camera.sensorOrientation;

    InputImageRotation? rotation;
    if (sensorOrientation == 90) {
      rotation = InputImageRotation.rotation90deg;
    } else if (sensorOrientation == 180) {
      rotation = InputImageRotation.rotation180deg;
    } else if (sensorOrientation == 270) {
      rotation = InputImageRotation.rotation270deg;
    } else {
      rotation = InputImageRotation.rotation0deg;
    }

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    if (image.planes.length != 1) return null;
    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  void _showBarcodeDialog(Barcode barcode) {
    String barcodeValue =
        barcode.displayValue ?? barcode.rawValue ?? "ไม่พบข้อมูล";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('พบบาร์โค้ด'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ประเภท: ${_getBarcodeTypeName(barcode.type)}'),
            const SizedBox(height: 8),
            Text('ข้อมูล: $barcodeValue'),
            if (barcode.type == BarcodeType.url &&
                _isValidUrl(barcodeValue)) ...[
              const SizedBox(height: 8),
              Text('URL: $barcodeValue'),
            ],
            if (barcode.type == BarcodeType.email &&
                _isValidEmail(barcodeValue)) ...[
              const SizedBox(height: 8),
              Text('Email: $barcodeValue'),
            ],
            if (barcode.type == BarcodeType.phone &&
                _isValidPhone(barcodeValue)) ...[
              const SizedBox(height: 8),
              Text('Phone: $barcodeValue'),
            ],
            if (barcode.type == BarcodeType.wifi) ...[
              const SizedBox(height: 8),
              Text('WiFi: $barcodeValue'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _restartScanning();
            },
            child: const Text('สแกนต่อ'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context, barcodeValue);
            },
            child: const Text('ใช้ข้อมูลนี้'),
          ),
        ],
      ),
    );
  }

  bool _isValidUrl(String? value) {
    if (value == null) return false;
    return Uri.tryParse(value) != null &&
        (value.startsWith('http://') || value.startsWith('https://'));
  }

  bool _isValidEmail(String? value) {
    if (value == null) return false;
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value);
  }

  bool _isValidPhone(String? value) {
    if (value == null) return false;
    return RegExp(r'^[\+]?[0-9\-\(\)\s]+$').hasMatch(value);
  }

  String _getBarcodeTypeName(BarcodeType type) {
    switch (type) {
      case BarcodeType.wifi:
        return 'WiFi';
      case BarcodeType.url:
        return 'URL';
      case BarcodeType.email:
        return 'Email';
      case BarcodeType.phone:
        return 'Phone';
      case BarcodeType.sms:
        return 'SMS';
      case BarcodeType.text:
        return 'Text';
      case BarcodeType.contactInfo:
        return 'Contact';
      case BarcodeType.calendarEvent:
        return 'Calendar';
      case BarcodeType.isbn:
        return 'ISBN';
      case BarcodeType.unknown:
        return 'Unknown';
      default:
        return 'Other';
    }
  }

  void _restartScanning() {
    setState(() {
      _scannedCode = null;
      _barcodes.clear();
      _isProcessing = false;
    });

    // หน่วงเวลาเล็กน้อยก่อนเริ่มสแกนใหม่
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted && _cameraController?.value.isInitialized == true) {
        _startImageStream();
      }
    });
  }

  @override
  void dispose() {
    _isProcessing = false;
    if (_cameraController?.value.isStreamingImages == true) {
      _cameraController?.stopImageStream();
    }
    _cameraController?.dispose();
    _barcodeScanner?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('สแกนบาร์โค้ด'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () {
              _cameraController?.setFlashMode(FlashMode.torch);
            },
          ),
          IconButton(
            icon: const Icon(Icons.flash_off),
            onPressed: () {
              _cameraController?.setFlashMode(FlashMode.off);
            },
          ),
        ],
      ),
      body: _isCameraInitialized
          ? Stack(
              children: [
                // Camera Preview
                SizedBox(
                  width: double.infinity,
                  height: double.infinity,
                  child: CameraPreview(_cameraController!),
                ),

                // Overlay with scanning area
                Container(
                  width: double.infinity,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                  ),
                  child: Center(
                    child: Container(
                      width: 250,
                      height: 250,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.transparent,
                      ),
                      child: Stack(
                        children: [
                          // Corner borders
                          Positioned(
                            top: 0,
                            left: 0,
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: const BoxDecoration(
                                border: Border(
                                  top: BorderSide(
                                    color: Colors.green,
                                    width: 4,
                                  ),
                                  left: BorderSide(
                                    color: Colors.green,
                                    width: 4,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: const BoxDecoration(
                                border: Border(
                                  top: BorderSide(
                                    color: Colors.green,
                                    width: 4,
                                  ),
                                  right: BorderSide(
                                    color: Colors.green,
                                    width: 4,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            left: 0,
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: Colors.green,
                                    width: 4,
                                  ),
                                  left: BorderSide(
                                    color: Colors.green,
                                    width: 4,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: const BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: Colors.green,
                                    width: 4,
                                  ),
                                  right: BorderSide(
                                    color: Colors.green,
                                    width: 4,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Instructions
                Positioned(
                  bottom: 100,
                  left: 0,
                  right: 0,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'วางบาร์โค้ดหรือ QR Code ภายในกรอบสี่เหลี่ยม',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),

                // Scanned result display
                if (_scannedCode != null)
                  Positioned(
                    top: 100,
                    left: 0,
                    right: 0,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'พบ: $_scannedCode',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),

                // Loading indicator เมื่อกำลังประมวลผล
                if (_isProcessing)
                  const Positioned(
                    top: 50,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
              ],
            )
          : const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('กำลังเตรียมกล้อง...'),
                ],
              ),
            ),
    );
  }
}
