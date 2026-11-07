// SPDX-License-Identifier: GPL-3.0-or-later
//! `PhoneMic`: QML singleton for Phone as microphone (crate::phone_mic):
//! whether a phone's microphone is off, asked for or live, and which output
//! it plays into.

use std::pin::Pin;

use cxx_qt::Threading;
use cxx_qt_lib::QString;

use crate::{
    phone_mic::{self, Phase},
    state::Changes,
};

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
        /// "off", "asking" (waiting for the phone's user) or "live".
        #[qproperty(QString, phase)]
        /// The phone it asks or listens to, else the one it would ask ("" when none).
        #[qproperty(QString, device)]
        #[qproperty(QString, device_name, cxx_name = "deviceName")]
        /// The output devices, as JSON: `[{ "id", "name" }]`.
        #[qproperty(QString, outputs)]
        /// The output it plays into (an ID from `outputs`).
        #[qproperty(QString, output)]
        #[qproperty(QString, output_name, cxx_name = "outputName")]
        /// Whether `output` is a virtual audio cable (apps see it as a microphone).
        #[qproperty(bool, cable)]
        /// How loud it plays, in percent (`minGain` to `maxGain`).
        #[qproperty(i32, gain)]
        #[qproperty(i32, min_gain, cxx_name = "minGain")]
        #[qproperty(i32, max_gain, cxx_name = "maxGain")]
        type PhoneMic = super::PhoneMicRust;
    }

    impl cxx_qt::Threading for PhoneMic {}
    impl cxx_qt::Initialize for PhoneMic {}

    unsafe extern "RustQt" {
        #[qinvokable]
        fn start(self: &PhoneMic, device: &QString);
        #[qinvokable]
        fn stop(self: &PhoneMic);
        #[qinvokable]
        #[cxx_name = "chooseOutput"]
        fn choose_output(self: &PhoneMic, id: &QString);
        #[qinvokable]
        #[cxx_name = "setLoudness"]
        fn set_loudness(self: &PhoneMic, percent: i32);
        /// Lists the outputs again (one may have been plugged in).
        #[qinvokable]
        fn refresh(self: Pin<&mut PhoneMic>);
    }
}

#[derive(Default)]
pub struct PhoneMicRust {
    phase: QString,
    device: QString,
    device_name: QString,
    outputs: QString,
    output: QString,
    output_name: QString,
    cable: bool,
    gain: i32,
    min_gain: i32,
    max_gain: i32,
}

impl cxx_qt::Initialize for qobject::PhoneMic {
    fn initialize(self: Pin<&mut Self>) {
        super::subscribe(
            self.qt_thread(),
            Changes::MIC | Changes::DEVICES | Changes::CAPABILITIES,
            Self::refresh,
        );
    }
}

impl qobject::PhoneMic {
    pub fn refresh(mut self: Pin<&mut Self>) {
        let phase = match phone_mic::phase() {
            Phase::Off => "off",
            Phase::Asking(_) => "asking",
            Phase::Live(_) => "live",
        };
        let (device, device_name) =
            phone_mic::phone().map(|(id, name)| (id.to_string(), name)).unwrap_or_default();
        let (devices, output) = phone_mic::outputs();
        let list: Vec<_> =
            devices.iter().map(|d| serde_json::json!({ "id": d.id, "name": d.name })).collect();
        let chosen = output.as_deref().and_then(|id| devices.iter().find(|d| d.id == id));
        let name = chosen.map(|d| d.name.clone()).unwrap_or_default();
        let cable = chosen.is_some_and(|d| phone_mic::is_cable(&d.name));
        self.as_mut().set_phase(QString::from(phase));
        self.as_mut().set_device(QString::from(&device));
        self.as_mut().set_device_name(QString::from(&device_name));
        self.as_mut().set_outputs(QString::from(&serde_json::Value::Array(list).to_string()));
        self.as_mut().set_output(QString::from(output.unwrap_or_default().as_str()));
        self.as_mut().set_output_name(QString::from(&name));
        self.as_mut().set_cable(cable);
        self.as_mut().set_gain(phone_mic::gain() as i32);
        self.as_mut().set_min_gain(phone_mic::MIN_GAIN as i32);
        self.as_mut().set_max_gain(phone_mic::MAX_GAIN as i32);
    }

    pub fn start(&self, device: &QString) {
        if let Some(id) = super::parse_device(device) {
            phone_mic::start(id);
        }
    }

    pub fn stop(&self) {
        phone_mic::stop();
    }

    pub fn choose_output(&self, id: &QString) {
        phone_mic::set_output(String::from(id));
    }

    pub fn set_loudness(&self, percent: i32) {
        phone_mic::set_gain(percent.max(0) as u32);
    }
}
