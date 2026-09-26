import 'package:flutter/material.dart';
import 'package:recolle/core/widgets/app_toast.dart';

/// [MaterialApp.builder] に渡す、全画面の外側の枠。
///
/// シートは CupertinoPageScaffold で作っていて Material の文字設定が届かず、
/// そのままでは文字に黄色の二重下線（スタイル未設定の表示）が付く。
/// Material と同じ本文のスタイルを既定にして、どの画面・シートでも同じ見た目にする。
Widget buildAppRoot(BuildContext context, Widget? child) {
  return DefaultTextStyle(
    style: Theme.of(context).textTheme.bodyMedium!,
    child: AppToastHost(child: child!),
  );
}
