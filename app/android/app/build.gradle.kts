import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// google-services.json があるときだけ Firebase の設定を取り込む（FIREBASE_ENABLED=true で使う）。
// 無くてもビルドは通り、Firebase は AppConfig.firebaseEnabled が false のまま初期化されない。
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// --dart-define の値をネイティブ設定（AdMob の App ID）にも使う。Flutter は Gradle の
// プロパティ "dart-defines" に、Base64 の "KEY=VALUE" をカンマ区切りで渡す。
val dartDefines: Map<String, String> =
    (project.findProperty("dart-defines") as String?)
        ?.split(",")
        ?.filter { it.isNotEmpty() }
        ?.mapNotNull {
            val decoded = String(Base64.getDecoder().decode(it), Charsets.UTF_8)
            val index = decoded.indexOf("=")
            if (index <= 0) null else decoded.substring(0, index) to decoded.substring(index + 1)
        }
        ?.toMap()
        ?: emptyMap()

// ワンコシリーズと同じく、CIでは環境変数を直接使う。秘密値をPropertiesへ書き直すと
// バックスラッシュ・改行・非ASCII文字が別の値として解釈される可能性がある。
val codemagicKeystorePath = System.getenv("CM_KEYSTORE_PATH")?.takeIf { it.isNotBlank() }
val useCodemagicSigning = codemagicKeystorePath != null
fun requiredSigningEnvironment(name: String): String =
    System.getenv(name)?.takeIf { it.isNotEmpty() }
        ?: throw GradleException("Missing Android signing environment variable: $name")

val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (!useCodemagicSigning && file.exists()) file.inputStream().use { load(it) }
}
val useKeyPropertiesSigning = keystoreProperties.isNotEmpty()
fun requiredSigningProperty(name: String): String =
    keystoreProperties.getProperty(name)?.takeIf { it.isNotEmpty() }
        ?: throw GradleException("Missing Android signing property: $name")

android {
    namespace = "jp.aile.nanikiru_cam"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications が java.time などを使うため。
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "jp.aile.nanikiru_cam"
        // 仕様 12 章: Android 8（API 26）以上。
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // 既定は Google の公開テスト App ID。本番は --dart-define=ADMOB_APP_ID_ANDROID=... で渡す。
        manifestPlaceholders["admobAppId"] =
            dartDefines["ADMOB_APP_ID_ANDROID"] ?: "ca-app-pub-3940256099942544~3347511713"
    }

    signingConfigs {
        if (useCodemagicSigning) {
            create("release") {
                storeFile = file(codemagicKeystorePath!!)
                storePassword = requiredSigningEnvironment("CM_KEYSTORE_PASSWORD")
                keyAlias = requiredSigningEnvironment("CM_KEY_ALIAS")
                keyPassword = requiredSigningEnvironment("CM_KEY_PASSWORD")
            }
        } else if (useKeyPropertiesSigning) {
            create("release") {
                keyAlias = requiredSigningProperty("keyAlias")
                keyPassword = requiredSigningProperty("keyPassword")
                storeFile = file(requiredSigningProperty("storeFile"))
                storePassword = requiredSigningProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (useCodemagicSigning || useKeyPropertiesSigning) {
                    signingConfigs.getByName("release")
                } else {
                    // key.properties が無いときは debug 署名（flutter run --release 用）。
                    signingConfigs.getByName("debug")
                }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
