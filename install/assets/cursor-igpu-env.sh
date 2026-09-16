# Pandora: Cursor/Electron Intel Mesa template (IDs filled at install by module 60).
# Prefer the generated ~/.config/pandora/cursor-igpu-env.sh after install.
# Session-wide defaults (all apps) live in /etc/environment.d/90-pandora-igpu.conf.
export __GLX_VENDOR_LIBRARY_NAME=mesa
export __EGL_VENDOR_LIBRARY_FILENAMES=/usr/share/glvnd/egl_vendor.d/50_mesa.json
export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/intel_icd.json
export MESA_VK_DEVICE_SELECT=8086:a788!
export DRI_PRIME=pci-0000_00_02_0
export __NV_PRIME_RENDER_OFFLOAD=0
unset __VK_LAYER_NV_optimus 2>/dev/null || true
export CUDA_VISIBLE_DEVICES=
export NVIDIA_VISIBLE_DEVICES=void
export ELECTRON_OZONE_PLATFORM_HINT="${ELECTRON_OZONE_PLATFORM_HINT:-auto}"
