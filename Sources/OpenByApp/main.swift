import AppKit
import OpenBy

// 进程入口运行于主线程；显式进入 MainActor 后装配 AppKit 生命周期。
MainActor.assumeIsolated { openByMain() }
