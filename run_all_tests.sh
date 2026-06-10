#!/usr/bin/env bash
set -euo pipefail

WORKSPACE_DIR="redeemer-pnt"

echo "==> Cleaning old workspace..."
rm -rf "${WORKSPACE_DIR}" setup_pnt.sh

echo "==> Constructing production tree..."
mkdir -p "${WORKSPACE_DIR}/src"

echo "==> Generating dependency manifest [Cargo.toml]..."
cat << 'PROJECT_MANIFEST' > "${WORKSPACE_DIR}/Cargo.toml"
[package]
name = "redeemer-pnt"
version = "0.1.0"
edition = "2021"

[dependencies]

[dev-dependencies]
static_assertions = "1.1.0"
PROJECT_MANIFEST

echo "==> Depositing reference engine core [src/lib.rs]..."
cat << 'SOURCE_CODE' > "${WORKSPACE_DIR}/src/lib.rs"
#![no_std]

use core::cell::UnsafeCell;
use core::sync::atomic::{compiler_fence, Ordering};
use core::ptr::addr_of;
use core::marker::PhantomData;

#[repr(transparent)]
pub struct VolatileCell<T> {
    value: UnsafeCell<T>,
}

impl<T: Copy> VolatileCell<T> {
    #[inline(always)]
    pub fn read(&self) -> T {
        unsafe { core::ptr::read_volatile(self.value.get()) }
    }
    #[inline(always)]
    pub fn write(&self, value: T) {
        unsafe { core::ptr::write_volatile(self.value.get(), value) }
    }
}

#[repr(C, align(4))]
pub struct PntHardwareRegisters<const ELEMENTS: usize> {
    pub laser_power_ctrl: VolatileCell<u32>,
    pub sensor_feed_ctrl: VolatileCell<u32>,
    _reserved: [u32; 2],
    pub matrix_output: [VolatileCell<f32>; 3],
    pub phase_array: [VolatileCell<f32>; ELEMENTS],
}

pub struct RedeemerPntModule<const ELEMENTS: usize> {
    pub hw_ptr: *mut PntHardwareRegisters<ELEMENTS>,
}

impl<const ELEMENTS: usize> RedeemerPntModule<ELEMENTS> {
    #[inline(always)]
    pub fn read_spatial_vector(&self, out: &mut [f32; 3]) -> Result<(), &'static str> {
        if self.hw_ptr.is_null() { return Err("NullHWPtr"); }

        compiler_fence(Ordering::SeqCst);
        unsafe {
            let matrix_ptr = addr_of!((*self.hw_ptr).matrix_output) as *const VolatileCell<f32>;
            out[0] = (*matrix_ptr.add(0)).read();
            out[1] = (*matrix_ptr.add(1)).read();
            out[2] = (*matrix_ptr.add(2)).read();
        }
        compiler_fence(Ordering::SeqCst);
        Ok(())
    }
}

#[derive(Copy, Clone, Debug, Default, PartialEq)]
pub struct Complex32 {
    pub re: f32,
    pub im: f32,
}

impl Complex32 {
    #[inline(always)]
    pub const fn new(re: f32, im: f32) -> Self { Self { re, im } }

    #[inline(always)]
    pub fn add(self, other: Self) -> Self {
        Self { re: self.re + other.re, im: self.im + other.im }
    }

    #[inline(always)]
    pub fn mul(self, other: Self) -> Self {
        Self {
            re: self.re * other.re - self.im * other.im,
            im: self.re * other.im + self.im * other.re,
        }
    }
}

pub const SEARCH_STEPS: usize = 48;
pub const PRODUCTION_RESOLUTION_RAD: f32 = 0.00008;

pub struct SpatialDftEngine<const E: usize, const N: usize> {
    pub blades: [RedeemerPntModule<E>; N],
    pub baseline_coefficients: [f32; N],
    pub calibration_offsets: [f32; N],
    pub sin_lut: [f32; 512],
    pub _marker: PhantomData<*mut ()>,
}

impl<const E: usize, const N: usize> SpatialDftEngine<E, N> {
    #[inline(always)]
    fn floor_f32(x: f32) -> f32 {
        let i = x as i32;
        if x < 0.0 && x != i as f32 {
            (i - 1) as f32
        } else {
            i as f32
        }
    }

    #[inline(always)]
    pub fn lut_sin_cos(&self, theta: f32) -> (f32, f32) {
        let tau = core::f32::consts::TAU;
        let normalized = theta - tau * Self::floor_f32(theta / tau);
        let idx = ((normalized * (512.0 / tau)) as usize) % 512;

        let sin_val = self.sin_lut[idx];
        let cos_idx = (idx + 128) % 512;
        let cos_val = self.sin_lut[cos_idx];
        (sin_val, cos_val)
    }

    pub fn compute_mle_peak(
        &self,
        raw_snapshots: &[[f32; 3]; N],
        power_surface: &mut [[f32; SEARCH_STEPS]; SEARCH_STEPS],
        resolution_rad: f32,
    ) -> (usize, usize) {
        let mut max_power = -1.0f32;
        let mut peak_x = 0;
        let mut peak_y = 0;

        let mut static_steering_phasors = [Complex32::new(1.0, 0.0); N];
        let mut base_meas_lat = [Complex32::new(1.0, 0.0); N];
        let mut base_meas_lon = [Complex32::new(1.0, 0.0); N];

        for i in 0..N {
            let steering_phase = self.baseline_coefficients[i] * core::f32::consts::PI + self.calibration_offsets[i];
            let (s_sin, s_cos) = self.lut_sin_cos(-steering_phase);
            static_steering_phasors[i] = Complex32::new(s_cos, s_sin);

            let (m_sin_lat, m_cos_lat) = self.lut_sin_cos(raw_snapshots[i][0]);
            base_meas_lat[i] = Complex32::new(m_cos_lat, m_sin_lat);

            let (m_sin_lon, m_cos_lon) = self.lut_sin_cos(raw_snapshots[i][1]);
            base_meas_lon[i] = Complex32::new(m_cos_lon, m_sin_lon);
        }

        for sx in 0..SEARCH_STEPS {
            let lat_offset = (sx as f32 - (SEARCH_STEPS as f32 * 0.5)) * resolution_rad;

            for sy in 0..SEARCH_STEPS {
                let lon_offset = (sy as f32 - (SEARCH_STEPS as f32 * 0.5)) * resolution_rad;

                let mut acc_lat = Complex32::new(0.0, 0.0);
                let mut acc_lon = Complex32::new(0.0, 0.0);

                for i in 0..N {
                    // Phase steering must scale physically across the array baseline coefficients
                    let (off_sin_lat, off_cos_lat) = self.lut_sin_cos(-lat_offset * self.baseline_coefficients[i]);
                    let rot_lat = Complex32::new(off_cos_lat, off_sin_lat);

                    let (off_sin_lon, off_cos_lon) = self.lut_sin_cos(-lon_offset * self.baseline_coefficients[i]);
                    let rot_lon = Complex32::new(off_cos_lon, off_sin_lon);

                    let scan_lat = static_steering_phasors[i].mul(rot_lat);
                    let scan_lon = static_steering_phasors[i].mul(rot_lon);

                    acc_lat = acc_lat.add(base_meas_lat[i].mul(scan_lat));
                    acc_lon = acc_lon.add(base_meas_lon[i].mul(scan_lon));
                }

                let power = (acc_lat.re * acc_lat.re + acc_lat.im * acc_lat.im) +
                            (acc_lon.re * acc_lon.re + acc_lon.im * acc_lon.im);

                power_surface[sx][sy] = power;

                let is_new_max = (power > max_power) as usize;
                peak_x = [peak_x, sx][is_new_max];
                peak_y = [peak_y, sy][is_new_max];
                max_power = [max_power, power][is_new_max];
            }
        }
        (peak_x, peak_y)
    }
}

unsafe impl<const E: usize, const N: usize> Sync for SpatialDftEngine<E, N> {}

#[cfg(test)]
mod tests {
    extern crate std;
    use std::f32::consts::{PI, TAU};
    use core::marker::PhantomData;
    use super::*;

    fn generate_test_lut() -> [f32; 512] {
        let mut lut = [0.0f32; 512];
        for i in 0..512 {
            lut[i] = ((i as f32) * (TAU / 512.0)).sin();
        }
        lut
    }

    const TEST_RESOLUTION_RAD: f32 = (TAU / 512.0) * 4.0;

    fn make_engine(lut: [f32; 512]) -> SpatialDftEngine<16, 4> {
        SpatialDftEngine {
            blades: [
                RedeemerPntModule { hw_ptr: core::ptr::null_mut() },
                RedeemerPntModule { hw_ptr: core::ptr::null_mut() },
                RedeemerPntModule { hw_ptr: core::ptr::null_mut() },
                RedeemerPntModule { hw_ptr: core::ptr::null_mut() },
            ],
            baseline_coefficients: [0.25, 0.75, -0.25, -0.75],
            calibration_offsets: [0.0; 4],
            sin_lut: lut,
            _marker: PhantomData,
        }
    }

    #[test]
    fn test_lut_accuracy() {
        let lut = generate_test_lut();
        let engine = make_engine(lut);
        for i in [0usize, 64, 128, 192, 256, 384] {
            let angle = (i as f32) * (TAU / 512.0);
            let (s, c) = engine.lut_sin_cos(angle);
            assert!((s - angle.sin()).abs() < 0.02, "sin LUT deviation detected at element {i}");
            assert!((c - angle.cos()).abs() < 0.02, "cos LUT deviation detected at element {i}");
        }
    }

    #[test]
    fn test_mle_peak_localization() {
        let lut = generate_test_lut();
        let engine = make_engine(lut);

        let target_x_step: isize = 2;
        let target_y_step: isize = 2;

        let target_lat_offset = (target_x_step as f32) * TEST_RESOLUTION_RAD;
        let target_lon_offset = (target_y_step as f32) * TEST_RESOLUTION_RAD;

        let mut snapshots = [[0.0f32; 3]; 4];
        for i in 0..4 {
            let base_phase = engine.baseline_coefficients[i] * PI;
            // The injected test wavefront must geometrically traverse the array
            snapshots[i][0] = base_phase + (target_lat_offset * engine.baseline_coefficients[i]);
            snapshots[i][1] = base_phase + (target_lon_offset * engine.baseline_coefficients[i]);
        }

        let mut power_surface = [[0.0f32; SEARCH_STEPS]; SEARCH_STEPS];
        let (px, py) = engine.compute_mle_peak(&snapshots, &mut power_surface, TEST_RESOLUTION_RAD);

        let center = SEARCH_STEPS / 2;
        assert_eq!(px, (center as isize + target_x_step) as usize,
            "lat peak mismatch: got {px}, expected {}", center as isize + target_x_step);
        assert_eq!(py, (center as isize + target_y_step) as usize,
            "lon peak mismatch: got {py}, expected {}", center as isize + target_y_step);
    }
}
SOURCE_CODE

echo "==> Deploying mathematical test matrix validation..."
cd "${WORKSPACE_DIR}"
cargo test -- --nocapture
