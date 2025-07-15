// screens/family/widgets/family_member_tile.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FamilyMemberTile extends StatelessWidget {
  final String name;
  final String email;
  final String role;
  final String relationship;
  final bool isOwner;
  final bool isOnline;
  final String? avatarUrl;
  final String? healthStatus;
  final Timestamp? joinedDate;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;
  final VoidCallback? onViewHealth;

  const FamilyMemberTile({
    super.key,
    required this.name,
    required this.email,
    required this.role,
    required this.relationship,
    required this.isOwner,
    required this.isOnline,
    this.avatarUrl,
    this.healthStatus,
    this.joinedDate,
    this.onEdit,
    this.onRemove,
    this.onViewHealth,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onViewHealth,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            _buildAvatar(),
            const SizedBox(width: 16),
            Expanded(child: _buildMemberInfo()),
            if (!isOwner) _buildActionMenu(context),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    return Stack(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: Colors.grey[300],
          backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl!) : null,
          child: avatarUrl == null
              ? Icon(Icons.person, color: Colors.grey[600], size: 28)
              : null,
        ),
        if (isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMemberInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (healthStatus != null) _buildHealthStatusBadge(),
          ],
        ),
        const SizedBox(height: 4),
        if (email.isNotEmpty) _buildEmailText(),
        const SizedBox(height: 4),
        _buildRoleBadges(),
        if (joinedDate != null) _buildJoinDateText(),
      ],
    );
  }

  Widget _buildHealthStatusBadge() {
    final color = _getHealthStatusColor(healthStatus!);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        healthStatus!,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildEmailText() {
    return Text(
      email,
      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildRoleBadges() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: isOwner ? Colors.blue[100] : Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            role,
            style: TextStyle(
              fontSize: 12,
              color: isOwner ? Colors.blue[800] : Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _getRelationshipColor().withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            relationship,
            style: TextStyle(
              fontSize: 12,
              color: _getRelationshipColor(),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildJoinDateText() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        'เข้าร่วม: ${_formatJoinDate(joinedDate!)}',
        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
      ),
    );
  }

  Widget _buildActionMenu(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit?.call();
            break;
          case 'view':
            onViewHealth?.call();
            break;
          case 'remove':
            onRemove?.call();
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'view',
          child: Row(
            children: [
              Icon(Icons.visibility, size: 18, color: Colors.blue),
              SizedBox(width: 8),
              Text('ดูข้อมูลสุขภาพ'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit, size: 18, color: Colors.orange),
              SizedBox(width: 8),
              Text('แก้ไขข้อมูล'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'remove',
          child: Row(
            children: [
              Icon(Icons.remove_circle_outline, size: 18, color: Colors.red),
              SizedBox(width: 8),
              Text('ลบสมาชิก', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(Icons.more_vert, color: Colors.grey[600], size: 20),
      ),
    );
  }

  Color _getHealthStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'ดี':
      case 'excellent':
        return Colors.green;
      case 'ปกติ':
      case 'good':
        return Colors.blue;
      case 'ต้องดูแล':
      case 'fair':
        return Colors.orange;
      case 'เสี่ยง':
      case 'poor':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _getRelationshipColor() {
    switch (relationship.toLowerCase()) {
      case 'ตัวเอง':
        return Colors.blue;
      case 'คู่สมรส':
        return Colors.pink;
      case 'บุตร':
        return Colors.green;
      case 'บิดา':
      case 'มารดา':
        return Colors.purple;
      case 'พี่น้อง':
        return Colors.orange;
      case 'ญาติ':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  String _formatJoinDate(Timestamp timestamp) {
    final date = timestamp.toDate();
    final now = DateTime.now();
    final difference = now.difference(date).inDays;

    if (difference == 0) {
      return 'วันนี้';
    } else if (difference == 1) {
      return 'เมื่อวาน';
    } else if (difference < 7) {
      return '$difference วันที่แล้ว';
    } else if (difference < 30) {
      final weeks = (difference / 7).floor();
      return '$weeks สัปดาห์ที่แล้ว';
    } else if (difference < 365) {
      final months = (difference / 30).floor();
      return '$months เดือนที่แล้ว';
    } else {
      final years = (difference / 365).floor();
      return '$years ปีที่แล้ว';
    }
  }
}
