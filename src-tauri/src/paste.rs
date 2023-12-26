use crate::accessibility;
use core_graphics::event::{CGEvent, CGEventFlags, CGEventTapLocation};
use core_graphics::event_source::{CGEventSource, CGEventSourceStateID};

pub fn paste(text: &str) -> Result<(), Box<dyn std::error::Error>> {
    // copy to clipboard
    let the_string = text;
    cli_clipboard::set_contents(the_string.to_owned()).map_err(|e| {
        eprintln!("[rust]: Failed to set clipboard contents: {}", e);
        e
    })?;
    println!("[rust]: copied to clipboard: {}", the_string);

    let trusted = accessibility::query_accessibility_permissions();

    if trusted {
        let source = CGEventSource::new(CGEventSourceStateID::HIDSystemState).unwrap();
        let source_clone = source.clone();
        let paste_event = CGEvent::new_keyboard_event(source, 9, true).unwrap();
        paste_event.set_flags(CGEventFlags::CGEventFlagCommand);
        paste_event.post(CGEventTapLocation::HID);
        let release_event = CGEvent::new_keyboard_event(source_clone, 9, false).unwrap();
        release_event.set_flags(CGEventFlags::CGEventFlagCommand);
        release_event.post(CGEventTapLocation::HID);
    }

    Ok(())
}
