#!/bin/env python

import blank_template
import httplib
import json
import os
import subprocess
import sys
import tarfile
import time
import urllib
import XenAPI

if __name__ == '__main__':

    # Load template
    fname = sys.argv[1]
    template = blank_template.load_template(fname)

    # Generate ova.xml
    version = {'hostname': 'localhost', 'date': '1970-01-01', 'product_version': '7.0.0', 'product_brand': 'XenServer', 'build_number': '0x', 'xapi_major': '1', 'xapi_minor': '9', 'export_vsn': '2'}
    xml = template.toXML(version)
    ova_xml = open("ova.xml", "w")
    ova_xml.write(xml)
    ova_xml.close()

    # Generate tarball containing ova.xml
    template_name = os.path.splitext(fname)[0]
    tar = tarfile.open("%s.tar" % template_name, "w")
    tar.add("ova.xml")
    tar.close()
    os.remove("ova.xml")

    # Create session to XAPI
    session = XenAPI.xapi_local()
    session.xenapi.login_with_password('', '', '', 'create-template')

    # Import XS template
    task_ref = session.xenapi.task.create("import-%s" % template.uuid, "Import of template %s" % template.uuid)
    fh = open("%s.tar" % template_name)
    conn = httplib.HTTPConnection("localhost", 80)
    params = urllib.urlencode({'session_id': session._session, 'task_id': task_ref, 'restore': 'true', 'uuid': template.uuid})
    conn.request("PUT", "/import_metadata?" + params, fh)
    response = conn.getresponse()
    fh.close()

    # Wait for import to complete
    task_status = 'pending'
    while task_status == 'pending':
        time.sleep(0.5)
        task_status = session.xenapi.task.get_status(task_ref)
    session.xenapi.task.destroy(task_ref)

    # Set default_template = true
    template_ref = session.xenapi.VM.get_by_uuid(template.uuid)
    other_config = session.xenapi.VM.get_other_config(template_ref)
    other_config['default_template'] = 'true'
    session.xenapi.VM.set_other_config(template_ref, other_config)

    session.xenapi.session.logout()
