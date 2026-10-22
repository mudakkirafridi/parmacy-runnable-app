package pk.pharmacyhisab.pharmacy_hisab
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory("pharmacy/credential", CredentialFactory(flutterEngine.dartExecutor.binaryMessenger))
    }
}
