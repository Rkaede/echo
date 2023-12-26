// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use crossbeam_channel::{unbounded, Sender};
use download::WhisperModelDownloader;
use env_logger::Builder;
use log::{info, LevelFilter};
use std::io::Write;
use std::sync::{Arc, Mutex};
use tauri::{
    AppHandle, CustomMenuItem, Manager, PhysicalPosition, State, SystemTray, SystemTrayEvent,
    SystemTrayMenu, Window,
};
use tauri_plugin_autostart::MacosLauncher;

mod accessibility;
mod audio;
mod download;
mod paste;
mod record;
mod whisper;

struct RecordState(Arc<Mutex<Option<Sender<()>>>>);

#[tauri::command]
fn download_model(window: tauri::Window, src: String, target: String, model: String) {
    std::thread::spawn(move || {
        let dl = WhisperModelDownloader::new(window.app_handle().clone());
        dl.download(&src, &target, &model)
    });
}

#[tauri::command]
fn open_debug_window(app: AppHandle) -> Result<(), String> {
    let _ = app.get_window("debug").unwrap().show().unwrap();
    Ok(())
}

fn position_window_at_top_center(window: &Window) {
    if let Ok(Some(monitor)) = window.primary_monitor() {
        let screen_size = monitor.size();
        let window_size = window.outer_size().unwrap_or_default();
        let new_x = (screen_size.width - window_size.width) / 2;
        let new_y = 0; // offset from top

        let _ = window.set_position(tauri::Position::Physical(PhysicalPosition {
            x: new_x as i32,
            y: new_y,
        }));
    }
}

#[tauri::command]
fn start_recording(model: String, state: State<'_, RecordState>, window: tauri::Window) {
    let main_window = window.app_handle().get_window("main").unwrap();
    position_window_at_top_center(&main_window);
    let _ = main_window.show();
    let mut lock = state.0.lock().unwrap();
    let (stop_record_tx, stop_record_rx) = unbounded();
    *lock = Some(stop_record_tx);
    println!("[rust]: start_command");
    std::thread::spawn(move || {
        let record = record::Record::new(window.app_handle().clone());
        record.start(model, stop_record_rx).unwrap();
    });
}

#[tauri::command]
fn stop_recording(state: State<'_, RecordState>) {
    println!("[rust]: stop_command");
    let mut lock = state.0.lock().unwrap();
    if let Some(stop_record_tx) = lock.take() {
        stop_record_tx.send(()).unwrap()
    }
}

#[tauri::command]
fn log(text: &str) {
    info!("[ui]: {}", text);
}

fn main() {
    Builder::new()
        .format(|buf, record| {
            writeln!(
                buf,
                "[{}] | {}",
                record.level().to_string().to_lowercase(),
                record.args()
            )
        })
        .filter(None, LevelFilter::Info)
        .init();

    let settings = CustomMenuItem::new("settings".to_string(), "Settings");
    let quit = CustomMenuItem::new("quit".to_string(), "Quit").accelerator("Cmd+Q");
    let system_tray_menu = SystemTrayMenu::new().add_item(settings).add_item(quit);

    tauri::Builder::default()
        .plugin(tauri_plugin_store::Builder::default().build())
        .plugin(tauri_plugin_autostart::init(
            MacosLauncher::LaunchAgent,
            Some(vec![]),
        ))
        .setup(move |app| {
            // prevent the app icon from showing on the dock
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);

            Ok(())
        })
        .manage(RecordState(Default::default()))
        .system_tray(SystemTray::new().with_menu(system_tray_menu))
        .invoke_handler(tauri::generate_handler![
            log,
            open_debug_window,
            start_recording,
            stop_recording,
            download_model
        ])
        .on_system_tray_event(|app, event| match event {
            SystemTrayEvent::MenuItemClick { id, .. } => match id.as_str() {
                "settings" => {
                    app.get_window("settings").unwrap().show().unwrap();
                }
                "quit" => {
                    std::process::exit(0);
                }
                "debug" => {
                    open_debug_window(app.clone()).unwrap();
                }
                "hide" => {
                    let window = app.get_window("main").unwrap();
                    window.hide().unwrap();
                }
                _ => {}
            },
            _ => {}
        })
        // prevent the window from closing
        .on_window_event(|event| match event.event() {
            tauri::WindowEvent::CloseRequested { api, .. } => {
                print!("close requested");
                event.window().hide().unwrap();
                api.prevent_close();
            }
            _ => {}
        })
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|_, event| match event {
            tauri::RunEvent::ExitRequested { api, .. } => {
                api.prevent_exit();
            }
            _ => {}
        });
}
