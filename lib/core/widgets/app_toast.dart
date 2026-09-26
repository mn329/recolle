import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';

/// 画面上部に出る、すりガラスのカプセル型の通知。
///
/// [AppToastHost] をアプリのルートに置いておけば、`context` なしで表示できるので
/// `await` の後（画面が閉じた後）でも安全に呼べる。ホストが無いとき（テストなど）は何もしない。
abstract final class AppToast {
  static _AppToastHostState? _host;

  static void show(
    String message, {
    IconData? icon,
    bool isError = false,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _host?._show(
      _ToastData(
        message: message,
        icon:
            icon ??
            (isError ? CupertinoIcons.exclamationmark_circle_fill : null),
        isError: isError,
        actionLabel: actionLabel,
        onAction: onAction,
      ),
    );
  }

  static void error(String message) => show(message, isError: true);
}

class _ToastData {
  const _ToastData({
    required this.message,
    required this.isError,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final IconData? icon;
  final bool isError;
  final String? actionLabel;
  final VoidCallback? onAction;

  Duration get displayDuration => actionLabel != null
      ? const Duration(seconds: 4)
      : const Duration(milliseconds: 2600);
}

class AppToastHost extends StatefulWidget {
  const AppToastHost({super.key, required this.child});

  final Widget child;

  @override
  State<AppToastHost> createState() => _AppToastHostState();
}

class _AppToastHostState extends State<AppToastHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    reverseDuration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutBack,
    reverseCurve: Curves.easeInCubic,
  );
  _ToastData? _current;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    AppToast._host = this;
  }

  @override
  void dispose() {
    if (AppToast._host == this) AppToast._host = null;
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _show(_ToastData data) {
    if (data.isError) HapticFeedback.mediumImpact();
    setState(() => _current = data);
    _controller.forward(from: _controller.value > 0.5 ? 0.6 : 0);
    _timer?.cancel();
    _timer = Timer(data.displayDuration, _dismiss);
  }

  Future<void> _dismiss() async {
    _timer?.cancel();
    await _controller.reverse();
    if (mounted && !_controller.isAnimating) setState(() => _current = null);
  }

  @override
  Widget build(BuildContext context) {
    final data = _current;
    return Stack(
      children: [
        widget.child,
        if (data != null)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 16,
            right: 16,
            child: AnimatedBuilder(
              animation: _curve,
              builder: (context, child) => Opacity(
                opacity: _controller.value.clamp(0, 1),
                child: Transform.translate(
                  offset: Offset(0, -24 * (1 - _curve.value)),
                  child: child,
                ),
              ),
              child: GestureDetector(
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0) < 0) _dismiss();
                },
                child: _ToastCapsule(
                  data: data,
                  onAction: () {
                    data.onAction?.call();
                    _dismiss();
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ToastCapsule extends StatelessWidget {
  const _ToastCapsule({required this.data, required this.onAction});

  final _ToastData data;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final icon = data.icon;
    final colors = context.colors;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Semantics(
          liveRegion: true,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: colors.shadow,
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                  decoration: BoxDecoration(
                    color: colors.toastBackground,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: colors.toastBorder),
                  ),
                  child: Row(
                    children: [
                      if (icon != null) ...[
                        Icon(
                          icon,
                          size: 20,
                          color: data.isError
                              ? context.colors.destructive
                              : context.colors.accent,
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(
                          data.message,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppFonts.body,
                            color: context.colors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                      if (data.actionLabel != null)
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 32),
                          onPressed: onAction,
                          child: Text(
                            data.actionLabel!,
                            style: TextStyle(
                              color: context.colors.accent,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      else
                        const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
