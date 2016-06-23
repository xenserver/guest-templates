import constants
import datetime
from xml.dom import minidom

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
        self.memory_overhead = "19922944"
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

    def toXML(self, default_params):

        doc = minidom.Document()
        root = doc.createElement('value')
        doc.appendChild(root)

        main_struct = doc.createElement('struct')
        root.appendChild(main_struct)

        ver_member = self.createMember(doc, main_struct, 'version')
        struct = doc.createElement('struct')
        ver_member.appendChild(struct)

        for n, v in default_params['version'].items():
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

        for n2, v2 in self.__dict__.items():
            value = self.createMember(doc, struct2, n2)

            if isinstance(v2, basestring) and v2 != "":
                value.appendChild(doc.createTextNode(v2))

            elif isinstance(v2, datetime.datetime):
                date = doc.createElement('dateTime.iso8601')
                value.appendChild(date)
                date.appendChild(doc.createTextNode(v2.strftime("%Y%m%dT%H:%M:%SZ")))

            elif isinstance(v2, long):
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

class BaseTemplate(BlankTemplate):
    def __init__(self, template):
        super(BaseTemplate, self).__init__()
        self.uuid = template["uuid"]
        self.name_label = template["name_label"]
        self.name_description = template["name_description"]
        self.memory_target = constants.memory_dynamic_max_mib * constants.mib
        self.memory_static_max = constants.memory_static_max_mib  * constants.mib
        self.memory_dynamic_max = constants.memory_dynamic_max_mib * constants.mib
        self.memory_dynamic_min = constants.memory_dynamic_min_mib * constants.mib
        self.memory_static_min = int(template["min_memory_gib"]) * constants.gib
