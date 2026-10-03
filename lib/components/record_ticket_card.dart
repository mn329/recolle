import 'package:flutter/material.dart';
import 'package:recolle/core/theme/app_colors.dart';
import 'package:recolle/core/theme/app_fonts.dart';
import 'package:recolle/core/widgets/decoded_network_image.dart';
import 'package:recolle/features/records/data/records_repository.dart';
import 'package:recolle/features/records/models/record.dart';

class RecordTicketCard extends StatefulWidget {
  final Record record;
  final VoidCallback onTap;

  const RecordTicketCard({
    super.key,
    required this.record,
    required this.onTap,
  });

  @override
  State<RecordTicketCard> createState() => _RecordTicketCardState();
}

class _RecordTicketCardState extends State<RecordTicketCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onTap();
  }

  void _handleTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: GestureDetector(
          // 券面は文字と写真を並べているだけなので、余白も含めて券面全体で反応させる
          behavior: HitTestBehavior.opaque,
          onTapDown: _handleTapDown,
          onTapUp: _handleTapUp,
          onTapCancel: _handleTapCancel,
          child: TicketFace(
            title: widget.record.title,
            artistOrAuthor: widget.record.artistOrAuthor,
            date: widget.record.date,
            endDate: widget.record.isMultiDay ? widget.record.lastDate : null,
            photoCount: widget.record.ticketImageUrls.length,
            photo: switch (widget.record.coverImageUrl) {
              final url? => LayoutBuilder(
                builder: (context, constraints) {
                  final request = RecordsRepository.ticketImageRequest(url);
                  return DecodedNetworkImage(
                    url: request.url,
                    headers: request.headers,
                    logicalWidth: constraints.maxWidth,
                    logicalHeight: constraints.maxHeight,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        ColoredBox(color: context.colors.card),
                  );
                },
              ),
              null => null,
            },
          ),
        ),
      ),
    );
  }
}

String _twoDigits(int n) => n.toString().padLeft(2, '0');

const _weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

/// 一覧に並ぶチケットの見た目。作成画面のプレビューとも共有する。
///
/// 右の半券（もぎり）に写真を敷き、券の形で切り抜く。写真がなければ「ADMIT ONE」と入れる。
class TicketFace extends StatelessWidget {
  const TicketFace({
    super.key,
    required this.title,
    required this.artistOrAuthor,
    required this.date,
    this.endDate,
    this.photo,
    this.photoCount = 0,
  });

  static const double height = 120;

  final String title;
  final String artistOrAuthor;
  final DateTime date;

  /// 複数日の公演の最終日。
  final DateTime? endDate;

  /// 半券いっぱいに敷く写真。
  final Widget? photo;

  /// 写真の枚数。2 枚以上なら半券に枚数ぶんの点を出す。
  final int photoCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final d = date;
    final end = endDate;
    final dateText = [
      '${d.year}.${_twoDigits(d.month)}.${_twoDigits(d.day)}',
      _weekdays[d.weekday - 1],
      if (end != null) '– ${_twoDigits(end.month)}.${_twoDigits(end.day)}',
    ].join('  ');
    // 影も切り欠きのある券面の形に沿わせる（四角い影だと明るい背景で帯が浮く）
    return PhysicalShape(
      clipper: TicketClipper(),
      clipBehavior: Clip.antiAlias,
      color: colors.ticketBase,
      shadowColor: colors.shadow,
      elevation: 8,
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stubWidth =
                constraints.maxWidth * (1 - TicketClipper.notchPositionRatio);
            return Stack(
              children: [
                Positioned(
                  top: 0,
                  right: 0,
                  bottom: 0,
                  width: stubWidth,
                  child: switch (photo) {
                    final photo? => _PhotoStub(photo: photo, count: photoCount),
                    null => const _AdmitOneStub(),
                  },
                ),
                Positioned(
                  top: 12,
                  right: stubWidth,
                  bottom: 12,
                  width: 1,
                  child: CustomPaint(
                    painter: DashedLinePainter(color: colors.ticketDivider),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 22,
                  right: stubWidth + 14,
                  bottom: 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: AppFonts.titleStyle(
                          fontSize: 19,
                          color: colors.accent,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        artistOrAuthor,
                        style: TextStyle(
                          color: colors.ticketText,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        dateText,
                        style: AppFonts.monoStyle(
                          fontSize: 14,
                          color: colors.ticketText.withValues(alpha: 0.6),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PhotoStub extends StatelessWidget {
  const _PhotoStub({required this.photo, required this.count});

  final Widget photo;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        photo,
        if (count > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: Semantics(
              label: '写真$count枚',
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < count; i++)
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(
                          alpha: i == 0 ? 0.95 : 0.5,
                        ),
                        boxShadow: const [
                          BoxShadow(color: Color(0x66000000), blurRadius: 3),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _AdmitOneStub extends StatelessWidget {
  const _AdmitOneStub();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: RotatedBox(
        quarterTurns: 1,
        child: Text(
          'ADMIT ONE',
          style: AppFonts.displayStyle(
            fontSize: 18,
            letterSpacing: 3,
            color: context.colors.accent.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

class TicketClipper extends CustomClipper<Path> {
  /// 切り欠き（半券の切り取り線）の位置。左端からの割合。
  static const double notchPositionRatio = 0.75;

  @override
  Path getClip(Size size) {
    final path = Path();
    const double cornerRadius = 16.0; // 角の丸み
    const double notchRadius = 8.0; // 切り欠きの大きさ

    // 左上からスタート
    path.moveTo(cornerRadius, 0);

    // 1. 上の辺を描いて、途中で半円（切り欠き）を描く
    path.lineTo(size.width * notchPositionRatio - notchRadius, 0);
    path.arcToPoint(
      Offset(size.width * notchPositionRatio + notchRadius, 0),
      radius: const Radius.circular(notchRadius),
      clockwise: false, // 反時計回りに描くと「凹み」になる
    );

    path.lineTo(size.width - cornerRadius, 0);

    // 右上の角
    path.quadraticBezierTo(size.width, 0, size.width, cornerRadius);

    // 右の辺
    path.lineTo(size.width, size.height - cornerRadius);

    // 右下の角
    path.quadraticBezierTo(
      size.width,
      size.height,
      size.width - cornerRadius,
      size.height,
    );

    // 2. 下の辺にも同様に切り欠きを描く
    path.lineTo(size.width * notchPositionRatio + notchRadius, size.height);
    path.arcToPoint(
      Offset(size.width * notchPositionRatio - notchRadius, size.height),
      radius: const Radius.circular(notchRadius),
      clockwise: false,
    );

    path.lineTo(cornerRadius, size.height);

    // 左下の角
    path.quadraticBezierTo(0, size.height, 0, size.height - cornerRadius);

    // 左の辺
    path.lineTo(0, cornerRadius);

    // 左上の角
    path.quadraticBezierTo(0, 0, cornerRadius, 0);

    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

class DashedLinePainter extends CustomPainter {
  final Color color;

  DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    double dashHeight = 4, dashSpace = 4, startY = 0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    // 高さいっぱいになるまで線を引く -> 空ける -> 線を引く を繰り返す
    while (startY < size.height) {
      canvas.drawLine(Offset(0, startY), Offset(0, startY + dashHeight), paint);
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}
