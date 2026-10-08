import 'package:flutter/widgets.dart';

/// 表示やアーティストを切り替えたとき、中身をふわっと入れ替える。
///
/// [contentKey] が変わったときだけ動かし、同じ表示のまま中身が更新されたときは動かさない。
/// 「視差効果を減らす」がオンなら切り替えるだけにする。
class ContentSwitcher extends StatelessWidget {
  const ContentSwitcher({
    super.key,
    required this.contentKey,
    required this.child,
  });

  final Object? contentKey;
  final Widget child;

  static const Duration duration = Duration(milliseconds: 320);
  static const Duration reverseDuration = Duration(milliseconds: 160);

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : duration,
      reverseDuration: reduceMotion ? Duration.zero : reverseDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      // 高さの違う中身を上端でそろえて重ねる。親の制約をそのまま渡し、短い中身も幅いっぱいに置く
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        fit: StackFit.passthrough,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(contentKey), child: child),
    );
  }
}

/// [ContentSwitcher] のスクロール一覧（sliver）版。
///
/// 長い一覧を少しずつ描く仕組みを保つため、前の中身は重ねずに、新しい中身をふわっと表示する。
class SliverContentSwitcher extends StatefulWidget {
  const SliverContentSwitcher({
    super.key,
    required this.contentKey,
    required this.sliver,
  });

  final Object? contentKey;
  final Widget sliver;

  @override
  State<SliverContentSwitcher> createState() => _SliverContentSwitcherState();
}

class _SliverContentSwitcherState extends State<SliverContentSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: ContentSwitcher.duration,
      value: 1,
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  }

  @override
  void didUpdateWidget(SliverContentSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contentKey != widget.contentKey) {
      // 別の画面が上に重なっているあいだは Ticker が止まり、アニメーションが進まない。
      // 0 から始めると中身が見えないまま止まるので、そのときはアニメーションなしで表示する
      final animate =
          !MediaQuery.disableAnimationsOf(context) && TickerMode.of(context);
      if (animate) {
        _controller.forward(from: 0);
      } else {
        _controller.value = 1;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SliverFadeTransition(opacity: _opacity, sliver: widget.sliver);
  }
}
