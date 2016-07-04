#!/bin/env python

import blank_template
import json
import os
import subprocess
import sys
import tarfile

if __name__ == '__main__':

    # Load template
    fname = sys.argv[1]
    template = blank_template.load_template(fname)

    # Generate ova.xml
    version = {'hostname': 'golm-2', 'date': '2016-04-29', 'product_version': '7.0.0', 'product_brand': 'XenServer', 'build_number': '125122c', 'xapi_major': '1', 'xapi_minor': '9', 'export_vsn': '2'}
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

    # Import XS template
    uuid = subprocess.check_output(["xe", "vm-import", "filename=%s.tar" % template_name, "preserve=true"])

    # Set default_template = true
    out = subprocess.check_output(["xe", "template-param-set", "other-config:default_template=true", "uuid=%s" % uuid.strip()])
