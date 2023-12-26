#[cfg(target_os = "macos")]
pub fn query_accessibility_permissions() -> bool {
    let trusted = macos_accessibility_client::accessibility::application_is_trusted_with_prompt();
    if trusted {
        println!("[rust]: app is trusted for accessibility");
    } else {
        println!("[rust]: app is NOT trusted for accessibility");
    }
    return trusted;
}

#[cfg(not(target_os = "macos"))]
pub fn query_accessibility_permissions() -> bool {
    print!("[rust]: Who knows... 🤷‍♀️");
    return true;
}
