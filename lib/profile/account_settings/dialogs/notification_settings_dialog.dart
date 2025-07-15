// dialogs/notification_settings_dialog.dart
import 'package:flutter/material.dart';

class NotificationSettingsDialog extends StatefulWidget {
  const NotificationSettingsDialog({Key? key}) : super(key: key);

  @override
  State<NotificationSettingsDialog> createState() =>
      _NotificationSettingsDialogState();
}

class _NotificationSettingsDialogState
    extends State<NotificationSettingsDialog> {
  // Notification time settings
  bool _morningEnabled = true;
  TimeOfDay _morningTime = const TimeOfDay(hour: 8, minute: 0);

  bool _eveningEnabled = true;
  TimeOfDay _eveningTime = const TimeOfDay(hour: 18, minute: 0);

  bool _bedtimeEnabled = false;
  TimeOfDay _bedtimeTime = const TimeOfDay(hour: 21, minute: 0);

  Future<void> _selectTime(BuildContext context, String type) async {
    TimeOfDay initialTime;

    switch (type) {
      case 'morning':
        initialTime = _morningTime;
        break;
      case 'evening':
        initialTime = _eveningTime;
        break;
      case 'bedtime':
        initialTime = _bedtimeTime;
        break;
      default:
        initialTime = const TimeOfDay(hour: 12, minute: 0);
    }

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: Theme.of(context).copyWith(
            timePickerTheme: TimePickerThemeData(
              backgroundColor: Colors.white,
              hourMinuteShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              dayPeriodShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        switch (type) {
          case 'morning':
            _morningTime = picked;
            break;
          case 'evening':
            _eveningTime = picked;
            break;
          case 'bedtime':
            _bedtimeTime = picked;
            break;
        }
      });
    }
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void _saveSettings() {
    // TODO: Save notification settings to database
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('บันทึกการตั้งค่าเวลาสำเร็จ'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'ตั้งเวลาการแจ้งเตือน',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Morning notification
            _buildTimeSettingTile(
              icon: Icons.wb_sunny,
              iconColor: Colors.orange,
              title: 'การแจ้งเตือนเช้า',
              subtitle: 'แจ้งเตือนเริ่มต้นวันใหม่',
              time: _morningTime,
              enabled: _morningEnabled,
              onToggle: (value) => setState(() => _morningEnabled = value),
              onTimeTap: () => _selectTime(context, 'morning'),
            ),

            const SizedBox(height: 8),

            // Evening notification
            _buildTimeSettingTile(
              icon: Icons.wb_twilight,
              iconColor: Colors.deepOrange,
              title: 'การแจ้งเตือนเย็น',
              subtitle: 'แจ้งเตือนสรุปกิจกรรมประจำวัน',
              time: _eveningTime,
              enabled: _eveningEnabled,
              onToggle: (value) => setState(() => _eveningEnabled = value),
              onTimeTap: () => _selectTime(context, 'evening'),
            ),

            const SizedBox(height: 8),

            // Bedtime notification
            _buildTimeSettingTile(
              icon: Icons.bedtime,
              iconColor: Colors.indigo,
              title: 'การแจ้งเตือนก่อนนอน',
              subtitle: 'แจ้งเตือนเตรียมตัวพักผ่อน',
              time: _bedtimeTime,
              enabled: _bedtimeEnabled,
              onToggle: (value) => setState(() => _bedtimeEnabled = value),
              onTimeTap: () => _selectTime(context, 'bedtime'),
            ),

            const SizedBox(height: 16),

            // Additional settings
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'หมายเหตุ',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'การแจ้งเตือนจะทำงานเฉพาะเมื่อเปิดการแจ้งเตือนในหน้าการตั้งค่าหลัก',
                    style: TextStyle(fontSize: 12, color: Colors.blue),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        ElevatedButton(
          onPressed: _saveSettings,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          child: const Text('บันทึก'),
        ),
      ],
    );
  }

  Widget _buildTimeSettingTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required TimeOfDay time,
    required bool enabled,
    required ValueChanged<bool> onToggle,
    required VoidCallback onTimeTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
        color: enabled ? Colors.white : Colors.grey[50],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: enabled ? Colors.black : Colors.grey,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: enabled ? Colors.grey[600] : Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                onChanged: onToggle,
                activeColor: Colors.black,
              ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: onTimeTap,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'เวลา:',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    Row(
                      children: [
                        Text(
                          _formatTime(time),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.access_time, size: 16),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
