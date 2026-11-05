//! UniFFI bindings exposing `mdcore` to Swift.

uniffi::setup_scaffolding!();

#[uniffi::export]
pub fn core_version() -> String {
    mdcore::version().to_string()
}

#[uniffi::export]
pub fn greet(name: String) -> String {
    mdcore::greet(&name)
}
