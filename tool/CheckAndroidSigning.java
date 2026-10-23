import java.io.File;
import java.security.KeyStore;
import java.security.PrivateKey;
import java.util.Arrays;

/** Validates existing signing credentials without writing or printing them. */
public class CheckAndroidSigning {
    public static void main(String[] args) {
        char[] storePassword = System.getenv("CM_KEYSTORE_PASSWORD").toCharArray();
        char[] keyPassword = System.getenv("CM_KEY_PASSWORD").toCharArray();
        try {
            KeyStore store = KeyStore.getInstance(
                    new File(System.getenv("CM_KEYSTORE_PATH")), storePassword);
            String alias = System.getenv("CM_KEY_ALIAS");
            if (!(store.getKey(alias, keyPassword) instanceof PrivateKey)
                    || store.getCertificate(alias) == null) {
                throw new IllegalStateException("No private key and certificate for signing alias");
            }
            System.out.println("OK: existing Android signing key and passwords verified");
        } catch (Exception error) {
            System.err.println("Android signing validation failed: " + error.getClass().getSimpleName());
            System.exit(1);
        } finally {
            Arrays.fill(storePassword, '\0');
            Arrays.fill(keyPassword, '\0');
        }
    }
}
