package icu.yzvibe.android.platform

import android.content.Context
import android.content.ContextWrapper
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity

fun approvalGate(context: Context, error: (String) -> Unit, action: () -> Unit) {
    if (
        !context
            .getSharedPreferences("preferences", Context.MODE_PRIVATE)
            .getBoolean("approvalAuth", false)
    ) {
        action()
        return
    }
    var current = context
    while (current !is FragmentActivity && current is ContextWrapper) current = current.baseContext
    val activity =
        current as? FragmentActivity
            ?: run {
                error("无法打开系统身份验证")
                return
            }
    val authenticators =
        (if (android.os.Build.VERSION.SDK_INT >= 30)
            BiometricManager.Authenticators.BIOMETRIC_STRONG
        else BiometricManager.Authenticators.BIOMETRIC_WEAK) or
            BiometricManager.Authenticators.DEVICE_CREDENTIAL
    if (
        BiometricManager.from(context).canAuthenticate(authenticators) !=
            BiometricManager.BIOMETRIC_SUCCESS
    ) {
        error("请先设置设备锁屏密码或指纹")
        return
    }
    val prompt =
        BiometricPrompt(
            activity,
            ContextCompat.getMainExecutor(context),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(
                    result: BiometricPrompt.AuthenticationResult
                ) = action()

                override fun onAuthenticationError(code: Int, text: CharSequence) {
                    if (
                        code !in
                            listOf(
                                BiometricPrompt.ERROR_USER_CANCELED,
                                BiometricPrompt.ERROR_NEGATIVE_BUTTON,
                            )
                    )
                        error(text.toString())
                }
            },
        )
    prompt.authenticate(
        BiometricPrompt.PromptInfo.Builder()
            .setTitle("确认远程审批")
            .setSubtitle("验证身份后允许电脑执行此操作")
            .setAllowedAuthenticators(authenticators)
            .build()
    )
}
