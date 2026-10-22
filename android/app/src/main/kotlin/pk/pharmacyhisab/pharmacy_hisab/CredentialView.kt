package pk.pharmacyhisab.pharmacy_hisab

import android.content.Context
import android.graphics.Color
import android.os.Build
import android.text.Editable
import android.text.InputType
import android.text.TextWatcher
import android.text.method.PasswordTransformationMethod
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class CredentialFactory(private val messenger: BinaryMessenger) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        CredentialView(context, viewId, (args as? Map<*, *>) ?: emptyMap<Any, Any>(), messenger)
}

private class CredentialView(context: Context, id: Int, args: Map<*, *>, messenger: BinaryMessenger) : PlatformView {
    private val edit = EditText(context)
    private val channel = MethodChannel(messenger, "pharmacy/credential/$id")
    private var suppress = false
    private var epoch = (args["epoch"] as? Number)?.toInt() ?: 0
    private var mode: Boolean? = null
    init {
        edit.setSingleLine(true)
        edit.setPadding(0, 0, 0, 0)
        edit.setBackgroundColor(Color.TRANSPARENT)
        edit.textSize = 18f
        edit.textDirection = View.TEXT_DIRECTION_LTR
        if (Build.VERSION.SDK_INT >= 26) edit.importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
        configure(args)
        edit.setText(args["text"] as? String ?: "")
        edit.setSelection(edit.length())
        edit.addTextChangedListener(object : TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: Editable?) {
                if (!suppress) channel.invokeMethod("changed", mapOf("text" to s.toString(), "epoch" to epoch))
            }
        })
        edit.setOnFocusChangeListener { _, focused -> channel.invokeMethod("focus", focused) }
        edit.setOnEditorActionListener { _, action, _ ->
            if (action == EditorInfo.IME_ACTION_DONE) { channel.invokeMethod("submit", null); true } else false
        }
        channel.setMethodCallHandler { call, result ->
            val value = (call.arguments as? Map<*, *>) ?: emptyMap<Any, Any>()
            when (call.method) {
                "setText" -> {
                    epoch = (value["epoch"] as Number).toInt()
                    val text = value["text"] as String
                    if (edit.text.toString() != text) {
                        suppress = true
                        edit.setText(text)
                        edit.setSelection(edit.length())
                        suppress = false
                    }
                    result.success(null)
                }
                "configure" -> { configure(value); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
    private fun configure(args: Map<*, *>) {
        val password = args["password"] == true
        // Change the input type only when the field kind changes. Rebuilds,
        // eye toggles and validation never restart or replace its Editable.
        if (mode != password) {
            edit.inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS or
                (if (password) InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD else InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS)
            mode = password
        }
        val obscure = args["obscure"] == true
        val start = edit.selectionStart.coerceAtLeast(0)
        val end = edit.selectionEnd.coerceAtLeast(0)
        val shouldHide = password && obscure
        if ((edit.transformationMethod is PasswordTransformationMethod) != shouldHide) {
            edit.transformationMethod = if (shouldHide) PasswordTransformationMethod.getInstance() else null
            edit.setSelection(start.coerceAtMost(edit.length()), end.coerceAtMost(edit.length()))
        }
        edit.setTextColor((args["color"] as? Number)?.toInt() ?: Color.BLACK)
        edit.contentDescription = args["label"] as? String ?: ""
        edit.imeOptions = EditorInfo.IME_ACTION_DONE or EditorInfo.IME_FLAG_NO_EXTRACT_UI or EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING
        val enabled = args["readOnly"] != true
        if (!enabled && edit.hasFocus()) {
            edit.clearFocus()
            (edit.context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager).hideSoftInputFromWindow(edit.windowToken, 0)
        }
        edit.isEnabled = enabled
    }
    override fun getView(): View = edit
    override fun dispose() { edit.clearFocus(); channel.setMethodCallHandler(null) }
}
