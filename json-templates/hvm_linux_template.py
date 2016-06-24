from xml.dom import minidom
import blank_template
import constants
import uuid

class HVMTemplate(blank_template.BaseTemplate):

    def __init__(self, data):
        super(HVMTemplate, self).__init__(data)
        self.platform = Platform().getPlatform()
        self.other_config = OtherConfig(data).getOtherConfig()
        self.recommendations = Recommendations(int(data["max_memory_gib"]) * constants.gib).toXML()

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
        self.HVM_shadow_multiplier = 1L

class Platform(object):

    def __init__(self):
        self.nx = "true"
        self.acpi = "1"
        self.apic = "true"
        self.pae = "true"
        self.hpet = "true"
        self.vga = "std"
        self.videoram = "8"
        self.viridian = "false"
        self.device_id = "0001"

    def getPlatform(self):
        return self.__dict__

class OtherConfig(object):

    def __init__(self, data):
        if "mac_seed" in data:
            self.mac_seed = data["mac_seed"]
        else:
            self.mac_seed = str(uuid.uuid4())
        self.default_template = "false"
        self.linux_template = "true"
        root_disk_size_gib = int(data["root_disk_size_gib"]) * constants.gib
        self.disks = DiskDevices(data).toXML()
        self.install_methods = "cdrom,nfs,http,ftp"

    def getOtherConfig(self):
        return self.__dict__

class DiskDevices(object):

    def __init__(self, data):
        root_disk_size_gib = int(data["root_disk_size_gib"]) * constants.gib
        disk0 = Disk(str(root_disk_size_gib), "", "true", "system")
        self.disks = [disk0]

    def toXML(self):
        doc = minidom.Document()
        root = doc.createElement('provision')
        doc.appendChild(root)

        position = 0
        for disk in self.disks:
            entry = disk.getDiskEntry()
            entry.setAttribute('device', str(position))
            root.appendChild(entry)
            position = position + 1

        return doc.documentElement.toxml('utf-8')

class Disk(object):

    def __init__(self, size, sr, bootable, disk_type):
        self. size = size
        self.sr = sr
        self.bootable = bootable
        self.type = disk_type

    def getDiskEntry(self):
        doc = minidom.Document()
        entry = doc.createElement('disk')
        for element_name, element_value in self.__dict__.items():
            entry.setAttribute(element_name, element_value)

        return entry


# Template restrictions (added to recommendations field for clients, especially UI clients)
class Recommendations(object):

    def __init__(self, memory_static_max):

        self.memory_static_max = str(memory_static_max)
        self.vcpus_max = "32"
        self.number_of_vbds = "255"
        self.number_of_vifs = "7"
        self.has_vendor_device = "false"
        self.allow_gpu_passthrough = "1"
        self.allow_vgpu = "1"

    def toXML(self):

        doc = minidom.Document()
        root = doc.createElement('restrictions')
        doc.appendChild(root)

        for field, attr in (('memory-static-max', 'max'),
                            ('vcpus-max', 'max'),
                            ('has-vendor-device', 'value'),
                            ('allow-gpu-passthrough', 'value'),
                            ('allow-vgpu', 'value')):
            entry = doc.createElement('restriction')
            root.appendChild(entry)
            entry.setAttribute('field', field)
            entry.setAttribute(attr, self.__dict__[field.replace('-', '_')])

        for prop in ('number-of-vbds', 'number-of-vifs'):
            entry = doc.createElement('restriction')
            entry.setAttribute('property', prop)
            entry.setAttribute('max', self.__dict__[prop.replace('-', '_')])
            root.appendChild(entry)

        return doc.documentElement.toxml('utf-8')
