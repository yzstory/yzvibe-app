package icu.yzvibe.android.core

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import android.util.Base64
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import org.json.JSONObject

/** Small durable documents use atomic replace; all calls from the repository's IO dispatcher. */
class LocalStore(context: Context) {
    private val root = File(context.filesDir, "state").apply { mkdirs() }
    private val keys = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }

    private fun file(name: String) =
        AtomicFile(
            File(
                root,
                MessageDigest.getInstance("SHA-256").digest(name.toByteArray()).joinToString("") {
                    "%02x".format(it)
                },
            )
        )

    @Synchronized
    fun read(name: String): JSONObject =
        runCatching {
                JSONObject(file(name).openRead().use { it.readBytes().toString(Charsets.UTF_8) })
            }
            .getOrDefault(JSONObject())

    @Synchronized
    fun write(name: String, value: JSONObject) {
        val target = file(name)
        val out = target.startWrite()
        try {
            out.write(value.toString().toByteArray())
            target.finishWrite(out)
        } catch (e: Exception) {
            target.failWrite(out)
            throw e
        }
    }

    private fun key(): SecretKey =
        (keys.getKey("yzvibe-pairing", null) as? SecretKey)
            ?: KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
                .apply {
                    init(
                        KeyGenParameterSpec.Builder(
                                "yzvibe-pairing",
                                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                            )
                            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                            .build()
                    )
                }
                .generateKey()

    fun saveToken(id: String, token: String) {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, key())
        write(
            "token:$id",
            obj(
                "iv" to Base64.encodeToString(c.iv, Base64.NO_WRAP),
                "data" to Base64.encodeToString(c.doFinal(token.toByteArray()), Base64.NO_WRAP),
            ),
        )
    }

    fun token(id: String): String {
        val j = read("token:$id")
        if (!j.has("data")) return ""
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(
            Cipher.DECRYPT_MODE,
            key(),
            GCMParameterSpec(128, Base64.decode(j.getString("iv"), Base64.NO_WRAP)),
        )
        return c.doFinal(Base64.decode(j.getString("data"), Base64.NO_WRAP))
            .toString(Charsets.UTF_8)
    }
}
