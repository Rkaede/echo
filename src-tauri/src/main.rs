// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use config::*;
use crossbeam_channel::{unbounded, Sender};
use download::WhisperModelDownloader;
use env_logger::Builder;
use log::{info, LevelFilter};
use once_cell::sync::OnceCell;
use std::io::Write;
use std::sync::{Arc, Mutex};
use tauri::{
    AppHandle, CustomMenuItem, Manager, PhysicalPosition, State, SystemTray, SystemTrayEvent,
    SystemTrayMenu, Window,
};
use tauri_plugin_autostart::MacosLauncher;

mod accessibility;
mod audio;
mod config;
mod download;
mod paste;
mod record;
mod whisper;

struct RecordState(Arc<Mutex<Option<Sender<()>>>>);

// Global AppHandle
pub static APP: OnceCell<tauri::AppHandle> = OnceCell::new();

#[tauri::command]
fn download_model(window: tauri::Window, src: String, target: String, model: String) {
    std::thread::spawn(move || {
        let dl = WhisperModelDownloader::new(window.app_handle().clone());
        dl.download(&src, &target, &model)
    });
}

#[tauri::command]
fn open_debug_window(app: AppHandle) -> Result<(), String> {
    app.get_window("debug").unwrap().show().unwrap();
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
    let main_window = window.app_handle().get_window("overlay").unwrap();
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
            // AppHandle singleton
            APP.get_or_init(|| app.handle());

            // Init config
            info!("Init Config Store");
            init_config(app);

            if is_first_run() {
                create_default_config();
                info!("First Run, opening onboarding window");
                // todo: show onboarding window
            }
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
        .on_system_tray_event(|app, event| {
            if let SystemTrayEvent::MenuItemClick { id, .. } = event {
                match id.as_str() {
                    "settings" => {
                        app.get_window("settings").unwrap().show().unwrap();
                        app.get_window("settings").unwrap().set_focus().unwrap();
                    }
                    "quit" => {
                        std::process::exit(0);
                    }
                    "debug" => {
                        open_debug_window(app.clone()).unwrap();
                    }
                    _ => {}
                }
            }
        })
        .on_window_event(|event| {
            // prevent the window from closing
            if let tauri::WindowEvent::CloseRequested { api, .. } = event.event() {
                println!("close requested");
                event.window().hide().unwrap();
                api.prevent_close();
            }
        })
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|_, event| {
            if let tauri::RunEvent::ExitRequested { api, .. } = event {
                api.prevent_exit();
            }
        });
}
