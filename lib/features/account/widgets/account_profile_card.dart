import 'package:flutter/cupertino.dart';
import 'package:recolle/core/theme/app_colors.dart';

/// 設定アプリ最上部のような、アバターと名前を並べたプロフィール欄。
class AccountProfileCard extends StatelessWidget {
  const AccountProfileCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.isRegistered = false,
  });

  final String title;
  final String subtitle;
  final bool isRegistered;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isRegistered
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.goldLight, AppColors.gold],
                    )
                  : null,
              color: isRegistered ? null : AppColors.cardPressed,
            ),
            child: Icon(
              CupertinoIcons.person_fill,
              size: 32,
              color: isRegistered
                  ? CupertinoColors.black
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
