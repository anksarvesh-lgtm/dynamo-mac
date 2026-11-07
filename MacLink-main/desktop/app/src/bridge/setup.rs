// SPDX-License-Identifier: GPL-3.0-or-later
//! `Setup`: QML singleton behind the installer's and uninstaller's window
//! (`qml/setup/SetupWindow.qml`; see `crate::setup`).

use std::{
    path::PathBuf,
    pin::Pin,
    sync::{Mutex, OnceLock},
};

use cxx_qt::Threading;
use cxx_qt_lib::QString;

use crate::setup::{self, Event, Kind, Mode, Outcome};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    unsafe extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qml_singleton]
        /// "install" or "remove".
        #[qproperty(QString, mode)]
        /// "welcome", "working", "done" or "failed".
        #[qproperty(QString, phase)]
        /// For installs: "fresh", "update", "reinstall" or "older".
        #[qproperty(QString, kind)]
        #[qproperty(QString, version)]
        #[qproperty(QString, installed_version, cxx_name = "installedVersion")]
        #[qproperty(bool, dark)]
        #[qproperty(bool, reduce_motion, cxx_name = "reduceMotion")]
        #[qproperty(f64, progress)]
        #[qproperty(QString, step)]
        #[qproperty(QString, message)]
        #[qproperty(QString, icon_url, cxx_name = "iconUrl")]
        #[qproperty(QString, qr_url, cxx_name = "qrUrl")]
        #[qproperty(QString, android_url, cxx_name = "androidUrl")]
        type Setup = super::SetupRust;
    }

    impl cxx_qt::Threading for Setup {}
    impl cxx_qt::Initialize for Setup {}

    unsafe extern "RustQt" {
        /// Install, or remove, depending on the mode.
        #[qinvokable]
        fn start(self: Pin<&mut Setup>);
        #[qinvokable]
        #[cxx_name = "openApp"]
        fn open_app(self: &Setup);
        #[qinvokable]
        #[cxx_name = "openAndroidPage"]
        fn open_android_page(self: &Setup);
        /// Called when the window closes for good.
        #[qinvokable]
        fn finish(self: &Setup);
    }
}

#[derive(Default)]
pub struct SetupRust {
    mode: QString,
    phase: QString,
    kind: QString,
    version: QString,
    installed_version: QString,
    dark: bool,
    reduce_motion: bool,
    progress: f64,
    step: QString,
    message: QString,
    icon_url: QString,
    qr_url: QString,
    android_url: QString,
}

static MODE: OnceLock<Mode> = OnceLock::new();
/// Where the app ended up, for Open MacLink.
static INSTALLED_DIR: Mutex<Option<PathBuf>> = Mutex::new(None);

/// Sets what the window is for, before QML loads.
pub fn set_mode(mode: Mode) {
    let _ = MODE.set(mode);
}

fn mode() -> Option<&'static Mode> {
    MODE.get()
}

impl cxx_qt::Initialize for qobject::Setup {
    fn initialize(mut self: Pin<&mut Self>) {
        let this_version = env!("CARGO_PKG_VERSION");
        let installed = setup::installed();
        self.as_mut().set_version(QString::from(this_version));
        self.as_mut().set_installed_version(QString::from(
            installed.as_ref().map(|i| i.version.as_str()).unwrap_or_default(),
        ));
        self.as_mut().set_dark(crate::win::system_dark());
        self.as_mut().set_reduce_motion(crate::win::reduce_motion());
        self.as_mut().set_phase(QString::from("welcome"));
        self.as_mut().set_icon_url(QString::from(&setup::icon_url(192)));
        self.as_mut().set_qr_url(QString::from(&setup::android_qr("#2C1600", "#FFFFFF")));
        self.as_mut().set_android_url(QString::from(setup::ANDROID_URL));
        match mode() {
            Some(Mode::Remove { installed }) => {
                *INSTALLED_DIR.lock().unwrap_or_else(|e| e.into_inner()) = Some(installed.clone());
                self.as_mut().set_mode(QString::from("remove"));
            }
            _ => {
                let kind = match setup::kind(installed.as_ref().map(|i| i.version.as_str()), this_version) {
                    Kind::Fresh => "fresh",
                    Kind::Update => "update",
                    Kind::Reinstall => "reinstall",
                    Kind::Older => "older",
                };
                self.as_mut().set_kind(QString::from(kind));
                self.as_mut().set_mode(QString::from("install"));
            }
        }
        // Debug builds only: open on a given screen, to check how it looks.
        if cfg!(debug_assertions)
            && let Ok(phase) = std::env::var("MACLINK_SETUP_PREVIEW")
        {
            if let Ok(theme) = std::env::var("MACLINK_SETUP_THEME") {
                self.as_mut().set_dark(theme == "dark");
            }
            if let Ok(kind) = std::env::var("MACLINK_SETUP_KIND") {
                self.as_mut().set_kind(QString::from(&kind));
                self.as_mut().set_installed_version(QString::from("0.1.0"));
            }
            if phase == "working" {
                self.as_mut().set_step(QString::from(setup::Step::Files.label()));
                self.as_mut().set_progress(0.45);
            }
            if phase == "failed" {
                self.as_mut().set_message(QString::from("Not enough space on the disk."));
            }
            if phase == "declined" {
                self.as_mut().set_message(QString::from(
                    "Setup needs your permission to install. Nothing was changed.",
                ));
                self.as_mut().set_phase(QString::from("welcome"));
            } else {
                self.as_mut().set_phase(QString::from(&phase));
            }
        }
    }
}

impl qobject::Setup {
    pub fn start(mut self: Pin<&mut Self>) {
        if self.phase().to_string() == "working" {
            return;
        }
        let Some(mode) = mode().cloned() else { return };
        self.as_mut().set_phase(QString::from("working"));
        self.as_mut().set_message(QString::default());
        self.as_mut().set_progress(0.02);
        let removing = matches!(mode, Mode::Remove { .. });
        self.as_mut().set_step(QString::from("Waiting for permission"));
        let qt = self.qt_thread();
        std::thread::spawn(move || {
            let report = |event: Event| {
                if let Event::Step(step) = event {
                    let _ = qt.queue(move |mut o| {
                        o.as_mut().set_step(QString::from(step.label()));
                        let p = step.progress().max(*o.progress());
                        o.as_mut().set_progress(p);
                    });
                }
            };
            let outcome = match &mode {
                Mode::Install { installer } => setup::install(installer, report),
                Mode::Remove { installed } => setup::remove(installed, report),
            };
            if outcome == Outcome::Done && !removing {
                *INSTALLED_DIR.lock().unwrap_or_else(|e| e.into_inner()) = setup::installed().map(|i| i.dir);
            }
            let _ = qt.queue(move |mut o| match outcome {
                Outcome::Done => {
                    o.as_mut().set_progress(1.0);
                    o.as_mut().set_phase(QString::from("done"));
                }
                Outcome::Declined => {
                    o.as_mut().set_phase(QString::from("welcome"));
                    o.as_mut().set_message(QString::from(if removing {
                        "Uninstalling needs your permission. Nothing was changed."
                    } else {
                        "Setup needs your permission to install. Nothing was changed."
                    }));
                }
                Outcome::Failed(reason) => {
                    tracing::warn!(reason, "setup failed");
                    o.as_mut().set_phase(QString::from("failed"));
                    o.as_mut().set_message(QString::from(&reason));
                }
            });
        });
    }

    pub fn open_app(&self) {
        let dir = INSTALLED_DIR.lock().unwrap_or_else(|e| e.into_inner()).clone();
        if let Some(dir) = dir
            && let Err(e) = setup::open_app(&dir)
        {
            tracing::warn!(error = %e, "can't open MacLink");
        }
    }

    pub fn open_android_page(&self) {
        let _ = crate::win::shell::open_url(setup::ANDROID_URL);
    }

    pub fn finish(&self) {
        if matches!(mode(), Some(Mode::Remove { .. })) {
            setup::delete_own_copy_later();
        }
    }
}
