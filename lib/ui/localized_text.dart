import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/app_store.dart';

/// Product labels follow the selected app language; user-entered names stay raw.
class LocalizedText extends ConsumerWidget {
  final String label;
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final bool? softWrap;
  final TextOverflow? overflow;
  final int? maxLines;
  const LocalizedText(
    this.label, {
    super.key,
    this.style,
    this.textAlign,
    this.textDirection,
    this.softWrap,
    this.overflow,
    this.maxLines,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) => Text(
    ref.watch(appProvider).tr(label),
    style: style,
    textAlign: textAlign,
    textDirection: textDirection,
    softWrap: softWrap,
    overflow: overflow,
    maxLines: maxLines,
  );
}
