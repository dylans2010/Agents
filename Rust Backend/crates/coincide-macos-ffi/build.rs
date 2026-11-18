fn main() {
    println!("cargo:rerun-if-changed=../coincide-desktop/src/computer_use_macos.m");
    println!("cargo:rerun-if-changed=../coincide-desktop/src/computer_use_macos.h");
    if std::env::var_os("CARGO_FEATURE_NATIVE_COMPUTER_USE").is_some()
        && std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("macos")
    {
        cc::Build::new()
            .file("../coincide-desktop/src/computer_use_macos.m")
            .flag("-fobjc-arc")
            .flag("-fblocks")
            .flag("-std=gnu11")
            .compile("coincide_computer_use");
        for framework in ["Foundation", "AppKit", "ApplicationServices", "CoreGraphics"] {
            println!("cargo:rustc-link-lib=framework={framework}");
        }
        println!("cargo:rustc-link-arg=-Wl,-weak_framework,ScreenCaptureKit");
    }
}
