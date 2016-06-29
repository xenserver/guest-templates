from xml.dom import minidom
import blank_template
import constants

class HVMTemplate(blank_template.BaseTemplate):

    def __init__(self, data):
        super(HVMTemplate, self).__init__(data)

        # PV params
        self.PV_bootloader = ""
        self.PV_kernel = ""
        self.PV_ramdisk = ""
        self.PV_args = ""
        self.PV_bootloader_args = ""
        self.PV_legacy_args = ""

        # HVM params
        self.HVM_boot_policy = constants.hvm_boot_policy
        self.HVM_boot_params = constants.hvm_boot_params
        self.HVM_shadow_multiplier = 1.0
