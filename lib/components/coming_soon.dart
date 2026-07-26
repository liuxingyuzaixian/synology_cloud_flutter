import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// 全局统一的"开发中"提示文案
const kComingSoonTitle = '开发中，敬请期待';

/// 通用的"开发中"页面组件
class ComingSoonPage extends StatelessWidget {
  final String? title;
  final String? message;

  const ComingSoonPage({super.key, this.title, this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title ?? kComingSoonTitle)),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(32.r),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.construction,
                size: 64.r,
                color: theme.colorScheme.primary.withAlpha(120),
              ),
              SizedBox(height: 16.h),
              Text(
                message ?? kComingSoonTitle,
                style: TextStyle(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8.h),
              Text(
                '我们正在努力开发此功能，请关注后续更新',
                style: TextStyle(
                  fontSize: 14.sp,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
