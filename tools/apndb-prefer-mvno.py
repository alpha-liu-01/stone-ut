#!/usr/bin/env python3
"""Make an MVNO's APNs the plain entries for its MCC/MNC in an apns-conf.xml.

ofono's apndb provisioning on Ubuntu Touch does not match on
mvno_type/mvno_match_data, so a Fizz SIM (302/500, GID1 55) is provisioned
with the base carrier's (Videotron's) APNs. For the given MCC/MNC this keeps
only the entries whose mvno_type/mvno_match_data match, with those two
attributes removed, and drops every other entry for that MCC/MNC. All other
carriers are left as they are.

usage: apndb-prefer-mvno.py IN OUT MCC MNC MVNO_TYPE MATCH_DATA
"""
import sys
import xml.etree.ElementTree as ET


def main():
    if len(sys.argv) != 7:
        sys.exit(__doc__)
    src, dst, mcc, mnc, mvno_type, match = sys.argv[1:]
    tree = ET.parse(src)
    root = tree.getroot()
    kept = dropped = 0
    for apn in list(root):
        if apn.tag != "apn" or apn.get("mcc") != mcc or apn.get("mnc") != mnc:
            continue
        if (apn.get("mvno_type") == mvno_type and
                apn.get("mvno_match_data", "").lower() == match.lower()):
            del apn.attrib["mvno_type"]
            del apn.attrib["mvno_match_data"]
            kept += 1
        else:
            root.remove(apn)
            dropped += 1
    if not kept:
        sys.exit("no %s=%s entries for %s/%s in %s" % (mvno_type, match, mcc, mnc, src))
    tree.write(dst, encoding="utf-8", xml_declaration=True)
    print("%s/%s: kept %d %s=%s entries, dropped %d others" %
          (mcc, mnc, kept, mvno_type, match, dropped))


if __name__ == "__main__":
    main()
