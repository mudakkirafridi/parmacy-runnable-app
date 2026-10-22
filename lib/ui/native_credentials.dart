import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Android's EditText owns its IME/composing buffer. Native edits are never
/// echoed back via setText, including deletion followed by replacement.
Widget credentialInput({
  Key? key,
  required TextEditingController controller,
  bool readOnly = false,
  bool obscureText = false,
  TextInputType? keyboardType,
  TextInputAction? textInputAction,
  TextDirection? textDirection,
  Iterable<String>? autofillHints,
  bool autocorrect = false,
  bool enableSuggestions = false,
  bool enableIMEPersonalizedLearning = false,
  TextCapitalization textCapitalization = TextCapitalization.none,
  SmartDashesType? smartDashesType,
  SmartQuotesType? smartQuotesType,
  ValueChanged<String>? onSubmitted,
  required InputDecoration decoration,
}) {
  if (!kIsWeb && Platform.isAndroid) {
    return NativeCredentialField(
      key: key,
      controller: controller,
      readOnly: readOnly,
      obscureText: obscureText,
      password: decoration.suffixIcon != null,
      decoration: decoration,
      onSubmitted: onSubmitted,
    );
  }
  return TextField(
    key: key,
    controller: controller,
    readOnly: readOnly,
    obscureText: obscureText,
    keyboardType: keyboardType,
    textInputAction: textInputAction,
    textDirection: textDirection,
    autofillHints: autofillHints,
    autocorrect: false,
    enableSuggestions: false,
    enableIMEPersonalizedLearning: false,
    textCapitalization: textCapitalization,
    smartDashesType: SmartDashesType.disabled,
    smartQuotesType: SmartQuotesType.disabled,
    onSubmitted: onSubmitted,
    decoration: decoration,
  );
}

/// Version programmatic resets so an in-flight native edit cannot undo Clear.
class CredentialTextSession {
  CredentialTextSession(this.controller, this.write)
    : nativeText = controller.text {
    controller.addListener(changed);
  }
  final TextEditingController controller;
  final void Function(String text, int epoch) write;
  String nativeText;
  int epoch = 0;
  void changed() {
    if (controller.text == nativeText) return;
    nativeText = controller.text;
    epoch++;
    write(nativeText, epoch);
  }

  void receive(String text, int generation) {
    if (generation != epoch) return;
    nativeText = text;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void dispose() => controller.removeListener(changed);
}

class NativeCredentialField extends StatefulWidget {
  const NativeCredentialField({
    super.key,
    required this.controller,
    required this.decoration,
    required this.password,
    required this.obscureText,
    required this.readOnly,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final InputDecoration decoration;
  final bool password, obscureText, readOnly;
  final ValueChanged<String>? onSubmitted;
  @override
  State<NativeCredentialField> createState() => _NativeCredentialState();
}

class _NativeCredentialState extends State<NativeCredentialField> {
  MethodChannel? channel;
  late CredentialTextSession session;
  bool focused = false;
  @override
  void initState() {
    super.initState();
    bind();
  }

  void bind() {
    session = CredentialTextSession(widget.controller, (text, epoch) {
      channel?.invokeMethod<void>('setText', {
        'text': text,
        'epoch': session.epoch,
      });
    });
  }

  Future<void> receive(MethodCall call) async {
    if (!mounted) return;
    if (call.method == 'changed') {
      final args = Map<Object?, Object?>.from(call.arguments as Map);
      session.receive(args['text'] as String, args['epoch'] as int);
    } else if (call.method == 'focus') {
      setState(() => focused = call.arguments == true);
    } else if (call.method == 'submit') {
      widget.onSubmitted?.call(widget.controller.text);
    }
  }

  Map<String, Object?> get config => {
    'password': widget.password,
    'obscure': widget.obscureText,
    'readOnly': widget.readOnly,
    'color': Theme.of(context).colorScheme.onSurface.toARGB32(),
    'label': widget.decoration.labelText ?? '',
  };
  void created(int id) {
    channel = MethodChannel('pharmacy/credential/$id')
      ..setMethodCallHandler(receive);
    channel!.invokeMethod<void>('setText', {
      'text': widget.controller.text,
      'epoch': session.epoch,
    });
    channel!.invokeMethod<void>('configure', config);
  }

  @override
  void didUpdateWidget(covariant NativeCredentialField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      session.dispose();
      bind();
      channel?.invokeMethod<void>('setText', {
        'text': widget.controller.text,
        'epoch': session.epoch,
      });
    }
    channel?.invokeMethod<void>('configure', config);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    channel?.invokeMethod<void>('configure', config);
  }

  @override
  void dispose() {
    session.dispose();
    channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: widget.decoration.copyWith(
      floatingLabelBehavior: FloatingLabelBehavior.always,
    ),
    isFocused: focused,
    isEmpty: widget.controller.text.isEmpty,
    child: SizedBox(
      height: 32,
      child: AndroidView(
        viewType: 'pharmacy/credential',
        layoutDirection: TextDirection.ltr,
        creationParams: {
          ...config,
          'text': session.nativeText,
          'epoch': session.epoch,
        },
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: created,
      ),
    ),
  );
}
