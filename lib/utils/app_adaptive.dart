import 'package:flutter/widgets.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class AppAdaptive {
  AppAdaptive._();

  static const designSize = Size(375, 812);

  /// Maximum screen width (in dp) to use for adaptive scaling.
  /// Beyond this, widths and font sizes stop growing to avoid
  /// over-sized UI on tablets and landscape mode.
  static const double maxAdaptWidth = 600;
}

extension AppGap on num {
  SizedBox get hGap => SizedBox(height: toDouble().h);
  /// Uses adaptive width (capped at 600dp) to avoid oversized gaps on tablets.
  SizedBox get wGap => SizedBox(width: toDouble().aw);
  /// Height gap using adaptive height scaling.
  SizedBox get aGap => SizedBox(height: toDouble().aw);
}

extension AppPercentSize on num {
  double get wp => ScreenUtil().screenWidth * toDouble() / 100;
  double get hp => ScreenUtil().screenHeight * toDouble() / 100;
}

/// Adaptive versions of ScreenUtil extensions that cap screen width
/// at [AppAdaptive.maxAdaptWidth] (600dp) so that UI doesn't grow
/// disproportionately large on tablets and landscape mode.
///
/// Use `.aw` for dimensions (paddings, widths, icon sizes) and
/// `.asp` for font sizes instead of `.w` / `.sp` to ensure
/// a more consistent look across screen sizes.
extension AppAdaptiveExt on num {
  double get _clampedScale {
    final sw = ScreenUtil().screenWidth;
    final clamped = sw > AppAdaptive.maxAdaptWidth
        ? AppAdaptive.maxAdaptWidth.toDouble()
        : sw;
    return clamped / AppAdaptive.designSize.width;
  }

  /// Adaptive width — clamps max screen width to 600dp.
  /// Use this for paddings, icon sizes, widths, etc.
  double get aw => toDouble() * _clampedScale;

  /// Adaptive font size — same capped scaling as [aw].
  /// Use this instead of `.sp` to prevent oversized text on tablets.
  double get asp => toDouble() * _clampedScale;
}
