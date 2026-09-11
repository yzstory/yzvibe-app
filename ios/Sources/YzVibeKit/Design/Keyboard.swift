import SwiftUI
import UIKit

/// 收起键盘。
/// 上一屏（新建会话表单、搜索框）的键盘如果还没落下，SwiftUI 会把键盘高度算进新页面的安全区，
/// 输入条就会悬在屏幕中间，等系统补发 keyboardWillHide 才归位——所以换屏时主动收一次。
@MainActor
func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
