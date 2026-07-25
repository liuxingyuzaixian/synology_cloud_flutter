import 'package:flutter/widgets.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class AppAdaptive {
  AppAdaptive._();

  static const designSize = Size(375, 812);
}

extension AppGap on num {
  SizedBox get hGap => SizedBox(height: toDouble().h);
  SizedBox get wGap => SizedBox(width: toDouble().w);
}

extension AppPercentSize on num {
  double get wp => ScreenUtil().screenWidth * toDouble() / 100;
  double get hp => ScreenUtil().screenHeight * toDouble() / 100;
}
