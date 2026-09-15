package icu.yzvibe.android.ui

import android.app.UiModeManager
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat

/** 跟 iOS 的「外观」设置一一对应，存在 SharedPreferences 里。 */
enum class Appearance(val key: String, val label: String) {
    Auto("auto", "自动"),
    Light("light", "浅色"),
    Dark("dark", "深色");

    companion object {
        fun of(key: String?) = entries.firstOrNull { it.key == key } ?: Auto
    }
}

/**
 * Material 的配色表装不下 iOS 色板里的琥珀 / 鼠尾草 / 紫 / 蓝，这些语义色单独放一层，
 * 由 [LocalAccents] 下发，四套色板（浅 / 深 × 标准 / 高对比度）与 iOS `Palette` 逐个对齐。
 */
@Immutable
data class Accents(
    val brandSoft: Color,
    val brandText: Color,
    val sage: Color,
    val sageSoft: Color,
    val amber: Color,
    val amberText: Color,
    val amberSoft: Color,
    val purple: Color,
    val purpleSoft: Color,
    val blue: Color,
    val blueSoft: Color,
)

private val LightAccents =
    Accents(
        brandSoft = Color(0xFFFFF0E3),
        brandText = Color(0xFFA64000),
        sage = Color(0xFF1B7046),
        sageSoft = Color(0xFFE0F1E7),
        amber = Color(0xFFB0761A),
        amberText = Color(0xFF8A5A0E),
        amberSoft = Color(0xFFFBEFD6),
        purple = Color(0xFF6E4B9E),
        purpleSoft = Color(0xFFEFE8F7),
        blue = Color(0xFF1F6FA8),
        blueSoft = Color(0xFFE3EFF8),
    )
private val DarkAccents =
    Accents(
        brandSoft = Color(0xFF352419),
        brandText = Color(0xFFFFB57D),
        sage = Color(0xFF5FD08E),
        sageSoft = Color(0xFF23382D),
        amber = Color(0xFFE8B45C),
        amberText = Color(0xFFE8B45C),
        amberSoft = Color(0xFF3A3020),
        purple = Color(0xFFC09AE8),
        purpleSoft = Color(0xFF2F2838),
        blue = Color(0xFF6FB6E8),
        blueSoft = Color(0xFF22303A),
    )
private val LightHighContrastAccents =
    Accents(
        brandSoft = Color(0xFFFFE5CE),
        brandText = Color(0xFF863100),
        sage = Color(0xFF145A37),
        sageSoft = Color(0xFFD8EEE1),
        amber = Color(0xFF8A5A0E),
        amberText = Color(0xFF6E470A),
        amberSoft = Color(0xFFF8E9C8),
        purple = Color(0xFF573A7E),
        purpleSoft = Color(0xFFE9DFF4),
        blue = Color(0xFF155888),
        blueSoft = Color(0xFFDAE9F5),
    )
private val DarkHighContrastAccents =
    Accents(
        brandSoft = Color(0xFF3D281A),
        brandText = Color(0xFFFFCAA3),
        sage = Color(0xFF86E0AC),
        sageSoft = Color(0xFF2A4335),
        amber = Color(0xFFF2C97F),
        amberText = Color(0xFFF2C97F),
        amberSoft = Color(0xFF453A26),
        purple = Color(0xFFD4B8F2),
        purpleSoft = Color(0xFF392F44),
        blue = Color(0xFF94CCF2),
        blueSoft = Color(0xFF2A3A45),
    )

val LocalAccents = staticCompositionLocalOf { LightAccents }

/** `MaterialTheme.accents` 读起来跟 `MaterialTheme.colorScheme` 一致。 */
val MaterialTheme.accents: Accents
    @Composable @ReadOnlyComposable get() = LocalAccents.current

// Brand and semantic colors share the iOS palette; components remain native Material 3.
private val DarkColors =
    darkColorScheme(
        primary = Color(0xFFFF9A52),
        onPrimary = Color(0xFF261305),
        primaryContainer = Color(0xFF352419),
        onPrimaryContainer = Color(0xFFFFB57D),
        secondary = Color(0xFFB9B9C0),
        onSecondary = Color(0xFF19191D),
        secondaryContainer = Color(0xFF2D2D32),
        onSecondaryContainer = Color(0xFFF5F5F7),
        tertiary = Color(0xFF5FD08E),
        onTertiary = Color(0xFF163523),
        tertiaryContainer = Color(0xFF23382D),
        onTertiaryContainer = Color(0xFF5FD08E),
        background = Color(0xFF0B0B0D),
        onBackground = Color(0xFFF5F5F7),
        surface = Color(0xFF19191D),
        onSurface = Color(0xFFF5F5F7),
        surfaceVariant = Color(0xFF2D2D32),
        onSurfaceVariant = Color(0xFFB9B9C0),
        surfaceTint = Color.Transparent,
        surfaceDim = Color(0xFF0B0B0D),
        surfaceBright = Color(0xFF303035),
        surfaceContainerLowest = Color(0xFF0B0B0D),
        surfaceContainerLow = Color(0xFF141417),
        surfaceContainer = Color(0xFF19191D),
        surfaceContainerHigh = Color(0xFF222226),
        surfaceContainerHighest = Color(0xFF2D2D32),
        outline = Color(0xFF6C6C75),
        outlineVariant = Color(0xFF36363D),
        error = Color(0xFFFF6961),
        onError = Color(0xFF3D1110),
        errorContainer = Color(0xFF3A2422),
        onErrorContainer = Color(0xFFFF8B84),
        inverseSurface = Color(0xFFF5F5F7),
        inverseOnSurface = Color(0xFF19191B),
        inversePrimary = Color(0xFFC04B00),
    )
private val LightColors =
    lightColorScheme(
        primary = Color(0xFFC04B00),
        onPrimary = Color.White,
        primaryContainer = Color(0xFFFFF0E3),
        onPrimaryContainer = Color(0xFFA64000),
        secondary = Color(0xFF606065),
        onSecondary = Color.White,
        secondaryContainer = Color(0xFFE9E9EB),
        onSecondaryContainer = Color(0xFF19191B),
        tertiary = Color(0xFF1B7046),
        onTertiary = Color.White,
        tertiaryContainer = Color(0xFFE0F1E7),
        onTertiaryContainer = Color(0xFF1B7046),
        background = Color(0xFFF6F6F7),
        onBackground = Color(0xFF19191B),
        surface = Color.White,
        onSurface = Color(0xFF19191B),
        surfaceVariant = Color(0xFFE9E9EB),
        onSurfaceVariant = Color(0xFF606065),
        surfaceTint = Color.Transparent,
        surfaceDim = Color(0xFFE9E9EB),
        surfaceBright = Color.White,
        surfaceContainerLowest = Color.White,
        surfaceContainerLow = Color(0xFFFAFAFB),
        surfaceContainer = Color.White,
        surfaceContainerHigh = Color(0xFFF0F0F2),
        surfaceContainerHighest = Color(0xFFE9E9EB),
        outline = Color(0xFF79797F),
        outlineVariant = Color(0xFFDEDEE2),
        error = Color(0xFFC4261C),
        onError = Color.White,
        errorContainer = Color(0xFFFBE3E0),
        onErrorContainer = Color(0xFFA31A12),
        inverseSurface = Color(0xFF19191D),
        inverseOnSurface = Color(0xFFF5F5F7),
        inversePrimary = Color(0xFFFF9A52),
    )

/** 系统「增强对比度」开关打开时用：压暗次要文字、加深强调色，与 iOS 的两套高对比色板一致。 */
private val LightHighContrastColors =
    LightColors.copy(
        primary = Color(0xFFA73D00),
        primaryContainer = Color(0xFFFFE5CE),
        onPrimaryContainer = Color(0xFF863100),
        secondary = Color(0xFF49494F),
        secondaryContainer = Color(0xFFE4E4E7),
        onSecondaryContainer = Color(0xFF111113),
        tertiary = Color(0xFF145A37),
        tertiaryContainer = Color(0xFFD8EEE1),
        onTertiaryContainer = Color(0xFF145A37),
        onBackground = Color(0xFF111113),
        onSurface = Color(0xFF111113),
        surfaceVariant = Color(0xFFE4E4E7),
        onSurfaceVariant = Color(0xFF49494F),
        surfaceDim = Color(0xFFE4E4E7),
        surfaceContainerLow = Color(0xFFF9F9FA),
        surfaceContainerHigh = Color(0xFFEFEFF1),
        surfaceContainerHighest = Color(0xFFE4E4E7),
        outline = Color(0xFF626269),
        outlineVariant = Color(0xFFBDBDC5),
        error = Color(0xFFA31A12),
        errorContainer = Color(0xFFF9D9D5),
        onErrorContainer = Color(0xFF7A140E),
        inversePrimary = Color(0xFFFFB078),
    )
private val DarkHighContrastColors =
    DarkColors.copy(
        primary = Color(0xFFFFB078),
        onPrimary = Color(0xFF1F0F02),
        primaryContainer = Color(0xFF3D281A),
        onPrimaryContainer = Color(0xFFFFCAA3),
        secondary = Color(0xFFD6D6DC),
        secondaryContainer = Color(0xFF303035),
        tertiary = Color(0xFF86E0AC),
        tertiaryContainer = Color(0xFF2A4335),
        onTertiaryContainer = Color(0xFF86E0AC),
        background = Color(0xFF030304),
        onBackground = Color.White,
        surface = Color(0xFF141417),
        onSurface = Color.White,
        surfaceVariant = Color(0xFF303035),
        onSurfaceVariant = Color(0xFFD6D6DC),
        surfaceDim = Color(0xFF030304),
        surfaceBright = Color(0xFF3A3A40),
        surfaceContainerLowest = Color(0xFF030304),
        surfaceContainerLow = Color(0xFF0E0E11),
        surfaceContainer = Color(0xFF141417),
        surfaceContainerHigh = Color(0xFF242429),
        surfaceContainerHighest = Color(0xFF303035),
        outline = Color(0xFFB8B8C2),
        outlineVariant = Color(0xFF4A4A52),
        error = Color(0xFFFF8B84),
        errorContainer = Color(0xFF452A28),
        onErrorContainer = Color(0xFFFF8B84),
        inversePrimary = Color(0xFFA73D00),
    )

private val YzTypography =
    Typography(
        headlineLarge =
            TextStyle(
                fontSize = 32.sp,
                lineHeight = 40.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = 0.sp,
            ),
        headlineSmall =
            TextStyle(fontSize = 24.sp, lineHeight = 32.sp, fontWeight = FontWeight.SemiBold),
        titleLarge =
            TextStyle(fontSize = 21.sp, lineHeight = 29.sp, fontWeight = FontWeight.SemiBold),
        titleMedium =
            TextStyle(fontSize = 17.sp, lineHeight = 25.sp, fontWeight = FontWeight.SemiBold),
        titleSmall =
            TextStyle(fontSize = 14.sp, lineHeight = 21.sp, fontWeight = FontWeight.SemiBold),
        bodyLarge = TextStyle(fontSize = 16.sp, lineHeight = 26.sp),
        bodyMedium = TextStyle(fontSize = 14.sp, lineHeight = 22.sp),
        bodySmall = TextStyle(fontSize = 12.sp, lineHeight = 18.sp),
        labelLarge =
            TextStyle(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium),
        labelMedium =
            TextStyle(fontSize = 12.sp, lineHeight = 18.sp, fontWeight = FontWeight.Medium),
        labelSmall = TextStyle(fontSize = 11.sp, lineHeight = 16.sp),
    )

val Orange: Color
    @Composable get() = MaterialTheme.colorScheme.primary

/** 系统「增强对比度」开关，Android 14 才有；更早的版本一律按标准对比度处理。 */
@Composable
private fun highContrast(): Boolean {
    val context = LocalContext.current
    if (android.os.Build.VERSION.SDK_INT < 34) return false
    val manager = context.getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager ?: return false
    return manager.contrast >= 0.5f
}

@Composable
fun YzTheme(appearance: Appearance = Appearance.Auto, content: @Composable () -> Unit) {
    val dark =
        when (appearance) {
            Appearance.Auto -> isSystemInDarkTheme()
            Appearance.Light -> false
            Appearance.Dark -> true
        }
    val contrast = highContrast()
    val colors =
        when {
            dark && contrast -> DarkHighContrastColors
            dark -> DarkColors
            contrast -> LightHighContrastColors
            else -> LightColors
        }
    val accents =
        when {
            dark && contrast -> DarkHighContrastAccents
            dark -> DarkAccents
            contrast -> LightHighContrastAccents
            else -> LightAccents
        }
    // 窗口本身由 Activity 的 enableEdgeToEdge 负责画到系统栏底下，这里只管图标明暗。
    // 不能交给 enableEdgeToEdge 自动判断：应用内「外观」可以覆盖系统深色模式，两者会对不上。
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as? android.app.Activity)?.window ?: return@SideEffect
            WindowCompat.getInsetsController(window, view).apply {
                isAppearanceLightStatusBars = !dark
                isAppearanceLightNavigationBars = !dark
            }
        }
    }
    CompositionLocalProvider(LocalAccents provides accents) {
        MaterialTheme(
            colorScheme = colors,
            typography = YzTypography,
            shapes =
                Shapes(
                    small = RoundedCornerShape(12.dp),
                    medium = RoundedCornerShape(20.dp),
                    large = RoundedCornerShape(24.dp),
                    extraLarge = RoundedCornerShape(28.dp),
                ),
            content = content,
        )
    }
}

@Composable
fun StatusMark(status: String) {
    val color =
        when (status) {
            "running" -> MaterialTheme.colorScheme.primary
            "waiting_approval",
            "error" -> MaterialTheme.colorScheme.error
            "idle",
            "在线" -> MaterialTheme.colorScheme.tertiary
            else -> MaterialTheme.colorScheme.onSurfaceVariant
        }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (status == "running")
            CircularProgressIndicator(Modifier.size(12.dp), color = color, strokeWidth = 1.5.dp)
        else Box(Modifier.size(7.dp).background(color, CircleShape))
        Text(statusLabel(status), color = color, style = MaterialTheme.typography.labelMedium)
    }
}

@Composable
fun EmptyState(title: String, description: String) {
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 48.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(title, style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(8.dp))
        Text(
            description,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
    }
}
