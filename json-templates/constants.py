kib = 1024
mib = 1024 * kib
gib = 1024 * mib

pv_bootloader = "pygrub"
hvm_boot_policy = "BIOS order"
hvm_boot_params = {"order": "cdn"}

# Values of memory parameters for templates.
memory_static_min_mib = 1024
memory_static_max_mib = 2048
memory_dynamic_min_mib = 2048
memory_dynamic_max_mib = 2048

class Actions(object):
    destroy = "destroy"
    restart = "restart"

class PowerStates(object):
    Running = "Running"
    Halted = "Halted"