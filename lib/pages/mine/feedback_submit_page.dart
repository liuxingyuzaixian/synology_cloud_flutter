import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../components/app_dialog.dart';
import '../../network/dsm_api.dart';
import '../../network/license_api.dart';
import '../../utils/app_adaptive.dart';
import '../../utils/license_manager.dart';

/// 意见反馈提交页：文字（≤300 字）+ 图片（≤9 张）+ 静默采集硬件信息。
class FeedbackSubmitPage extends StatefulWidget {
  const FeedbackSubmitPage({super.key});

  static const int maxImages = 9;
  static const int maxContentLength = 300;

  @override
  State<FeedbackSubmitPage> createState() => _FeedbackSubmitPageState();
}

class _FeedbackSubmitPageState extends State<FeedbackSubmitPage> {
  final TextEditingController _controller = TextEditingController();
  final List<XFile> _images = [];
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final remain = FeedbackSubmitPage.maxImages - _images.length;
    if (remain <= 0) return;
    final picked = await ImagePicker().pickMultiImage(imageQuality: 80);
    if (picked.isEmpty) return;
    setState(() {
      _images.addAll(picked.take(remain));
    });
    if (picked.length > remain) {
      AppDialog.toast('最多 ${FeedbackSubmitPage.maxImages} 张，已保留前 $remain 张');
    }
  }

  /// 静默采集硬件信息：App 版本、系统、设备/域名，NAS 型号主机名尽力读取。
  Future<Map<String, Object?>> _collectHardware() async {
    final hardware = <String, Object?>{};
    try {
      final info = await PackageInfo.fromPlatform();
      final buildNum = int.tryParse(info.buildNumber) ?? 0;
      hardware['appVersion'] =
          buildNum > 0 ? '${info.version}+$buildNum' : info.version;
    } catch (_) {}
    try {
      hardware['os'] =
          '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    } catch (_) {}
    final manager = LicenseManager();
    if ((manager.deviceId ?? '').isNotEmpty) {
      hardware['deviceId'] = manager.deviceId;
    }
    if (manager.currentDomain.isNotEmpty) {
      hardware['domain'] = manager.currentDomain;
    }
    // NAS 型号/主机名：普通用户无权限读取时静默跳过。
    try {
      final sys = await DsmApi().systemInfo();
      final sysData = (sys['data'] ?? {}) as Map;
      final model = (sysData['model'] ?? '').toString();
      final hostname = (sysData['hostname'] ?? '').toString();
      if (model.isNotEmpty) hardware['model'] = model;
      if (hostname.isNotEmpty) hardware['hostname'] = hostname;
    } catch (_) {}
    return hardware;
  }

  Future<void> _submit() async {
    final content = _controller.text.trim();
    if (content.isEmpty) {
      AppDialog.toast('请填写反馈内容');
      return;
    }
    setState(() => _submitting = true);
    final close = AppDialog.showLoading(label: '正在提交...');
    try {
      final api = LicenseApi();
      // 逐张上传图片，拿到公网 URL。
      final urls = <String>[];
      for (var i = 0; i < _images.length; i++) {
        urls.add(await api.uploadImage(_images[i].path));
      }
      final hardware = await _collectHardware();
      await api.submitFeedback(
        content: content,
        images: urls,
        hardware: hardware,
        deviceId: LicenseManager().deviceId,
      );
      close();
      AppDialog.toast('反馈已提交，感谢你的建议');
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      close();
      AppDialog.toast('提交失败：$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('我要反馈')),
      body: ListView(
        padding: EdgeInsets.all(16.aw),
        children: [
          Text(
            '问题描述',
            style: TextStyle(fontSize: 15.asp, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 8.h),
          TextField(
            controller: _controller,
            maxLines: 6,
            maxLength: FeedbackSubmitPage.maxContentLength,
            decoration: InputDecoration(
              hintText: '请描述你遇到的问题或建议（最多 300 字）',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            '截图（选填，最多 ${FeedbackSubmitPage.maxImages} 张）',
            style: TextStyle(fontSize: 15.asp, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 8.h),
          _buildImageGrid(theme),
          SizedBox(height: 24.h),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: 14.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
            ),
            child: Text(_submitting ? '提交中...' : '提交反馈',
                style: TextStyle(fontSize: 15.asp)),
          ),
          SizedBox(height: 8.h),
          Text(
            '提交时会附带 App 版本与设备信息，帮助开发者定位问题',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.asp, color: theme.hintColor),
          ),
          SizedBox(height: 24.h),
        ],
      ),
    );
  }

  /// 九宫格：已选图片 + 追加按钮。
  Widget _buildImageGrid(ThemeData theme) {
    final items = <Widget>[
      for (var i = 0; i < _images.length; i++) _buildImageItem(theme, i),
      if (_images.length < FeedbackSubmitPage.maxImages)
        _buildAddButton(theme),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8.aw,
      crossAxisSpacing: 8.aw,
      children: items,
    );
  }

  Widget _buildImageItem(ThemeData theme, int index) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8.r),
          child: Image.file(File(_images[index].path), fit: BoxFit.cover),
        ),
        Positioned(
          top: 4.aw,
          right: 4.aw,
          child: GestureDetector(
            onTap: () => setState(() => _images.removeAt(index)),
            child: Container(
              padding: EdgeInsets.all(2.aw),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.close, size: 14.aw, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAddButton(ThemeData theme) {
    return InkWell(
      onTap: _pickImages,
      borderRadius: BorderRadius.circular(8.r),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Icon(Icons.add_photo_alternate_outlined,
            size: 28.aw, color: theme.hintColor),
      ),
    );
  }
}
