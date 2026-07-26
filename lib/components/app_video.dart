import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// A [Video] whose Material controls are lifted away from the very bottom
/// edge.
///
/// media_kit's default (non-fullscreen) seek bar sits flush against the bottom
/// of the widget, where it overlaps the iOS home-indicator gesture area and
/// any app chrome drawn at the bottom of the screen — making the progress bar
/// hard or impossible to tap. We raise the whole control cluster above the
/// safe area (plus an optional [extraBottom] to clear app-level bottom bars).
class AppVideo extends StatelessWidget {
  final VideoController controller;

  /// Extra bottom offset (px) on top of the safe area, used to clear an
  /// app-level bottom bar drawn over the video (e.g. the preview download bar).
  final double extraBottom;

  const AppVideo({
    super.key,
    required this.controller,
    this.extraBottom = 0,
  });

  // media_kit shows a CircularProgressIndicator whenever player.state.buffering
  // is true. On NAS streams that flag can get stuck on during otherwise smooth
  // playback (a permanent spinner). We already cover the genuine initial load
  // with our own poster + spinner, so suppress the built-in one here.
  static Widget _noBufferingIndicator(BuildContext context) =>
      const SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom + 16 + extraBottom;
    return MaterialVideoControlsTheme(
      normal: MaterialVideoControlsThemeData(
        // NOTE: the seek bar has its OWN margin, independent of the button
        // bar. Both must be lifted, otherwise the progress bar stays flush
        // against the bottom (in the home-indicator / app-bar zone) and
        // cannot be tapped.
        seekBarMargin: EdgeInsets.only(left: 16, right: 16, bottom: bottom),
        bottomButtonBarMargin:
            EdgeInsets.only(left: 16, right: 8, bottom: bottom),
        // media_kit's default seek bar is a 2.4px line inside a 36px touch
        // strip — very easy to miss on a phone (feels "undraggable"). Enlarge
        // the touch area, the visible bar and the thumb so it grabs reliably.
        seekBarHeight: 4,
        seekBarContainerHeight: 56,
        seekBarThumbSize: 18,
        bufferingIndicatorBuilder: _noBufferingIndicator,
      ),
      fullscreen: const MaterialVideoControlsThemeData(
        seekBarMargin: EdgeInsets.only(left: 16, right: 16, bottom: 48),
        bottomButtonBarMargin:
            EdgeInsets.only(left: 16, right: 8, bottom: 48),
        seekBarHeight: 4,
        seekBarContainerHeight: 56,
        seekBarThumbSize: 18,
        bufferingIndicatorBuilder: _noBufferingIndicator,
      ),
      // Transparent fill so the poster/thumbnail placed behind this widget
      // shows through until libmpv renders the first frame (no black flash).
      child: Video(
        controller: controller,
        fit: BoxFit.contain,
        fill: Colors.transparent,
      ),
    );
  }
}
