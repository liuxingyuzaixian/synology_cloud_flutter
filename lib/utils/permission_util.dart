import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../components/app_dialog.dart';

class PermissionUtil {
  PermissionUtil._();

  static Future<bool> request({
    required Permission permission,
    String name = '权限',
    BuildContext? context,
  }) async {
    final status = await permission.status;
    if (status.isGranted || status.isLimited) return true;

    final result = await permission.request();
    if (result.isGranted || result.isLimited) return true;

    if (result.isPermanentlyDenied || result.isRestricted) {
      final shouldOpenSettings = await AppDialog.confirm(
        title: '$name不可用',
        message: '请在系统设置中开启$name后继续使用。',
        cancelText: '稍后再说',
        confirmText: '去设置',
      );
      if (shouldOpenSettings) {
        await openAppSettings();
      }
    } else {
      AppDialog.toast('未获得$name权限');
    }
    return false;
  }

  static Future<bool> requestCamera({BuildContext? context}) {
    return request(permission: Permission.camera, name: '相机', context: context);
  }

  static Future<bool> requestMicrophone({BuildContext? context}) {
    return request(permission: Permission.microphone, name: '麦克风', context: context);
  }

  static Future<bool> requestGallery({BuildContext? context}) {
    return request(permission: Permission.photos, name: '相册', context: context);
  }

  static Future<bool> requestLocation({BuildContext? context}) {
    return request(
      permission: Permission.locationWhenInUse,
      name: '定位',
      context: context,
    );
  }

  static Future<bool> requestNotification({BuildContext? context}) {
    return request(
      permission: Permission.notification,
      name: '通知',
      context: context,
    );
  }

  static Future<bool> isGranted(Permission permission) async {
    final status = await permission.status;
    return status.isGranted || status.isLimited;
  }
}
