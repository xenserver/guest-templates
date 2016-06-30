import constants
import datetime
import json
import re
import uuid
from xml.dom import minidom


def amount_to_int(amt):
    scale = { 'T': 40, 't': 40, 'G': 30, 'g': 30, 'M': 20, 'm': 20, 'K': 10, 'k': 10 }

    m = re.match(r'(\d+)([GgMmKk])?$', amt)
    if not m:
        raise ValueError("invalid amount: " + amt)
    v = int(m.group(1))
    if m.group(2):
        v = v << scale[m.group(2)]
    return v

def get_bool_key(d, key, default):
    v = d.get(key, default)
    if isinstance(v, basestring):
        v = v.lower() in ('t', 'true', 'y', 'yes', '1')
    return v

class Platform(object):

    def __init__(self, data, defaults = False):
        if defaults or 'nx' in data:
            self.nx = 'true' if get_bool_key(data, 'nx', True) else 'false'
        if defaults or 'acpi' in data:
            self.acpi = '1' if get_bool_key(data, 'acpi', True) else '0'
        if defaults or 'apic' in data:
            self.apic = 'true' if get_bool_key(data, 'apic', True) else 'false'
        if defaults or 'pae' in data:
            self.pae = 'true' if get_bool_key(data, 'pae', True) else 'false'
        if defaults or 'hpet' in data:
            self.hpet = 'true' if get_bool_key(data, 'hpet', True) else 'false'
        if 'vga' in data:
            self.vga = data['vga']
        if 'videoram' in data:
            self.videoram = str(amount_to_int(data['videoram']) >> 20)
        if defaults or 'viridian' in data:
            self.viridian = 'true' if get_bool_key(data, 'viridian', True) else 'false'
        if 'device_id' in data:
            self.device_id = data['device_id']

    def getPlatform(self):
        return self.__dict__

    def update(self, new):
        self.__dict__.update(new.__dict__)

class OtherConfig(object):

    def __init__(self, data):
        self.mac_seed = data.get('mac_seed', str(uuid.uuid4()))
        if 'disks' in data:
            self.disks = DiskDevices(data['disks']).toXML()
        if 'other_config' in data:
            self.__dict__.update(data['other_config'])
        self.default_template = 'false' # cannot import with this set to 'true'

    def getOtherConfig(self):
        return self.__dict__

    def update(self, new):
        self.__dict__.update(new.__dict__)

class DiskDevices(object):

    def __init__(self, disks):
        self.disks = []
        for disk in disks:
            self.disks.append(Disk(disk['size'],
                                   disk.get('sr', ''),
                                   disk.get('bootable', True),
                                   disk.get('type', 'system')))

    def toXML(self):
        doc = minidom.Document()
        root = doc.createElement('provision')
        doc.appendChild(root)

        position = 0
        for disk in self.disks:
            entry = disk.getDiskEntry()
            entry.setAttribute('device', str(position))
            root.appendChild(entry)
            position += 1

        return doc.documentElement.toxml('utf-8')

class Disk(object):

    def __init__(self, size, sr, bootable, disk_type):
        self.size = amount_to_int(size)
        self.sr = sr
        self.bootable = 'true' if bootable else 'false'
        self.type = disk_type

    def getDiskEntry(self):
        doc = minidom.Document()
        entry = doc.createElement('disk')
        for element_name, element_value in self.__dict__.items():
            entry.setAttribute(element_name, str(element_value))

        return entry


# Template restrictions (added to recommendations field for clients, especially UI clients)
class Recommendations(object):

    def __init__(self, data, defaults = False):

        if 'max_memory' in data:
            self.memory_static_max = str(amount_to_int(data['max_memory']))
        if 'vcpus_max' in data:
            self.vcpus_max = str(data['vcpus_max'])
        if 'number_of_vbds' in data:
            self.number_of_vbds = str(data['number_of_vbds'])
        if 'number_of_vifs' in data:
            self.number_of_vifs = str(data['number_of_vifs'])
        if defaults or 'has_vendor_device' in data:
            self.has_vendor_device = 'true' if get_bool_key(data, 'has_vendor_device', False) else 'false'
        if 'allow_gpu_passthrough' in data:
            self.allow_gpu_passthrough = '1' if get_bool_key(data, 'allow_gpu_passthrough', False) else '0'
        if 'allow_vgpu' in data:
            self.allow_vgpu = '1' if get_bool_key(data, 'allow_vgpu', False) else '0'

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
            entry.setAttribute(attr, self.__dict__.get(field.replace('-', '_'), ""))

        for prop in ('number-of-vbds', 'number-of-vifs'):
            entry = doc.createElement('restriction')
            entry.setAttribute('property', prop)
            entry.setAttribute('max', self.__dict__.get(prop.replace('-', '_'), ""))
            root.appendChild(entry)

        return doc.documentElement.toxml('utf-8')

    def update(self, new):
        self.__dict__.update(new.__dict__)


class BlankTemplate(object):
    """Collection of common template parameters"""

    def __init__(self):
        self.allowed_operations = []
        self.current_operations = {}
        self.power_state = constants.PowerStates.Halted
        self.user_version = 1
        self.is_a_template = True
        self.suspend_VDI = "OpaqueRef:NULL"
        self.resident_on = "OpaqueRef:NULL"
        self.affinity = "OpaqueRef:NULL"
        self.VCPUs_params = {}
        self.VCPUs_max = 1
        self.VCPUs_at_startup = 1
        self.actions_after_shutdown = constants.Actions.destroy
        self.actions_after_reboot = constants.Actions.restart
        self.actions_after_crash = constants.Actions.restart
        self.consoles = []
        self.VIFs = []
        self.VBDs = []
        self.crash_dumps = []
        self.VTPMs = []
        self.PCI_bus = ""
        self.domid = (-1)
        self.domarch = ""
        self.last_boot_CPU_flags = {}
        self.is_control_domain = False
        self.metrics = "OpaqueRef:NULL"
        self.guest_metrics = "OpaqueRef:NULL"
        self.last_booted_record = ""
        self.xenstore_data = {}
        self.ha_always_run = False
        self.ha_restart_priority = ""
        self.is_a_snapshot = False
        self.snapshot_of = "OpaqueRef:NULL"
        self.snapshots = []
        self.snapshot_time = datetime.datetime(1970, 1, 1)
        self.transportable_snapshot_id = ""
        self.blobs = {}
        self.tags = []
        self.blocked_operations = {}
        self.snapshot_info = {}
        self.snapshot_metadata = ""
        self.parent = "OpaqueRef:NULL"
        self.children = []
        self.bios_strings = {}
        self.protection_policy = "OpaqueRef:NULL"
        self.is_snapshot_from_vmpp = False
        self.appliance = "OpaqueRef:NULL"
        self.start_delay = 0
        self.shutdown_delay = 0
        self.order = 0
        self.VGPUs = []
        self.attached_PCIs = []
        self.suspend_SR = "OpaqueRef:NULL"
        self.version = 0
        self.generation_id = ""
        self.hardware_platform_version = 0
        self.has_vendor_device = False

    def createMember(self, doc, father, member_name):
        entry = doc.createElement('member')
        father.appendChild(entry)
        name = doc.createElement('name')
        entry.appendChild(name)
        name.appendChild(doc.createTextNode(member_name))
        value = doc.createElement('value')
        entry.appendChild(value)

        return value

    def toXML(self, version):

        record_dict = dict(self.__dict__)
        record_dict['platform'] = self.platform.getPlatform()
        record_dict['other_config'] = self.other_config.getOtherConfig()
        record_dict['recommendations'] = self.recommendations.toXML()

        doc = minidom.Document()
        root = doc.createElement('value')
        doc.appendChild(root)

        main_struct = doc.createElement('struct')
        root.appendChild(main_struct)

        ver_member = self.createMember(doc, main_struct, 'version')
        struct = doc.createElement('struct')
        ver_member.appendChild(struct)

        for n, v in version.items():
            value = self.createMember(doc, struct, n)
            value.appendChild(doc.createTextNode(v))

        obj_member = self.createMember(doc, main_struct, 'objects')
        obj_array = doc.createElement('array')
        obj_member.appendChild(obj_array)
        obj_data = doc.createElement('data')
        obj_array.appendChild(obj_data)
        obj_value = doc.createElement('value')
        obj_data.appendChild(obj_value)
        struct = doc.createElement('struct')
        obj_value.appendChild(struct)

        for n, v in (('class', 'VM'), ('id', 'Ref:0')):
            value = self.createMember(doc, struct, n)
            value.appendChild(doc.createTextNode(v))

        snapshot = self.createMember(doc, struct, 'snapshot')
        struct2 = doc.createElement('struct')
        snapshot.appendChild(struct2)

        for n2, v2 in record_dict.items():
            value = self.createMember(doc, struct2, n2)

            if isinstance(v2, basestring) and v2 != "":
                value.appendChild(doc.createTextNode(v2))

            elif isinstance(v2, datetime.datetime):
                date = doc.createElement('dateTime.iso8601')
                value.appendChild(date)
                date.appendChild(doc.createTextNode(v2.strftime("%Y%m%dT%H:%M:%SZ")))

            elif isinstance(v2, float):
                double = doc.createElement('double')
                value.appendChild(double)
                double.appendChild(doc.createTextNode(str(v2)))

            elif isinstance(v2, bool):
                boolean = doc.createElement('boolean')
                value.appendChild(boolean)
                boolean.appendChild(doc.createTextNode("%i" % v2))

            elif isinstance(v2, list):
                struct3 = doc.createElement('array')
                value.appendChild(struct3)
                data = doc.createElement('data')
                struct3.appendChild(data)
                for n3,v3 in v2:
                    value = self.createMember(doc, data, n3)
                    value.appendChild(doc.createTextNode(v3))

            elif isinstance(v2, dict):
                struct3 = doc.createElement('struct')
                value.appendChild(struct3)
                for n3,v3 in v2.items():
                    value = self.createMember(doc, struct3, n3)
                    value.appendChild(doc.createTextNode(v3))

            elif isinstance(v2, int):
                value.appendChild(doc.createTextNode(str(v2)))

        return doc.toprettyxml(indent = '   ')

    def update(self, template):
        self.__dict__.update(template)

class BaseTemplate(BlankTemplate):
    def __init__(self, template):

        super(BaseTemplate, self).__init__()
        self.platform = Platform(template)
        self.other_config = OtherConfig(template)
        self.recommendations = Recommendations(template)
        self.update(template, True)

    def update(self, template, defaults = False):

        if defaults or 'HVM_boot_params' in template:
            self.HVM_boot_params = template.get('HVM_boot_params', {})
        for k in ('HVM_boot_policy', 'PV_bootloader', 'PV_kernel', 'PV_ramdisk', 'PV_args',
                  'PV_bootloader_args', 'PV_legacy_args'):
            if defaults or k in template:
                self.__dict__[k] = template.get(k, '')

        blacklist = ( 'platform', 'other_config', 'recommendations', 'disks' )

        # apply template values over current values
        filtered_template = { k: v for k, v in template.iteritems() if k not in blacklist }
        super(BaseTemplate, self).update(filtered_template)

        if "min_memory" in template:
            self.memory_static_min = amount_to_int(template["min_memory"])
            self.memory_static_max = self.memory_static_min * 2
            self.memory_dynamic_min = self.memory_static_min * 2
            self.memory_dynamic_max = self.memory_static_min * 2
        if defaults or 'HVM_shadow_multiplier' in template:
            self.HVM_shadow_multiplier = template.get('HVM_shadow_multiplier', 1.0)

        # update contained objects
        self.platform.update(Platform(template, defaults))
        self.other_config.update(OtherConfig(template))
        self.recommendations.update(Recommendations(template, defaults))

def load_template(fname):
    """ Read JSON template and create a template object. If one template derives
    from another load that and apply changes upon that. """

    with open(fname) as templatefile:
        template = json.load(templatefile)

    if 'derived_from' in template:
        # load base template and overlay deltas
        ret = load_template(template['derived_from'])
        ret.update(template)
    else:
        ret = BaseTemplate(template)

    return ret
