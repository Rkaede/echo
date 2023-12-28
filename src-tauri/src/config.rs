use crate::APP;

use log::{info, warn};
use serde_json::{json, Value};
use std::sync::Mutex;
use tauri::{Manager, Wry};
use tauri_plugin_store::{Store, StoreBuilder};

pub struct StoreWrapper(pub Mutex<Store<Wry>>);

pub fn init_config(app: &mut tauri::App) {
    let app_data_dir = app.handle().path_resolver().app_data_dir().unwrap();
    let config_path = app_data_dir.join("config.json");

    info!("Load config from: {:?}", config_path);
    let mut store = StoreBuilder::new(app.handle(), config_path).build();

    match store.load() {
        Ok(_) => info!("Config loaded"),
        Err(e) => {
            warn!("Config load error: {:?}", e);
            info!("Config not found, creating new config");
        }
    }
    app.manage(StoreWrapper(Mutex::new(store)));
}

pub fn get(key: &str) -> Option<Value> {
    let state = APP.get().unwrap().state::<StoreWrapper>();
    let mut store = state.0.lock().unwrap();
    store.load().unwrap();
    match store.get(key) {
        Some(value) => Some(value.clone()),
        None => None,
    }
}

pub fn set<T: serde::ser::Serialize>(key: &str, value: T) {
    let state = APP.get().unwrap().state::<StoreWrapper>();
    let mut store = state.0.lock().unwrap();
    store.insert(key.to_string(), json!(value)).unwrap();
    store.save().unwrap();
}

pub fn is_first_run() -> bool {
    let state = APP.get().unwrap().state::<StoreWrapper>();
    let store = state.0.lock().unwrap();
    store.is_empty()
}

pub fn create_default_config() {
    set("model", "base");
    set("sound-effects", true);
    set("sound-volume", 1);
    set("sound-start", "tick.mp3");
    set("sound-stop", "tick.mp3");
    set("sound-complete", "tick.mp3");
}
