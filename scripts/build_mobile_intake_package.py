#!/usr/bin/env python3
"""
Builds the CQ Mobile Intake unlocked package source from the main project, so every file has one copy (force-app).

    python3 scripts/build_mobile_intake_package.py          # rebuild packages/cq-mobile-intake/force-app
    python3 scripts/build_mobile_intake_package.py --check  # fail if the package copy is out of date

Run it before every package version. It copies the files listed below, adds package-only/ (permission sets, tab),
and writes the two permission sets' field access from the fields actually included.
"""
import os, re, shutil, sys, filecmp

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'force-app', 'main', 'default')
PKG = os.path.join(ROOT, 'packages', 'cq-mobile-intake')
OUT = os.path.join(PKG, 'force-app', 'main', 'default')
EXTRA = os.path.join(PKG, 'package-only', 'main', 'default')

CLASSES = ['CqEventIntake', 'CqIntakeChat', 'CqEventExtract', 'CqEventParts', 'CqEventLotLink']
TESTS = ['CqIntakeTestData', 'CqEventIntakeTest', 'CqIntakeChatTest', 'CqIntakeChatClipTest', 'CqEventExtractTest', 'CqEventPartsTest', 'CqEventLotLinkTest']
LWC = ['cqIntakeConversation', 'cqStyles']
TRIGGERS = ['QualityEventLotLink']
OBJECTS = ['Quality_Event__c', 'Event_Question__c', 'Event_Answer__c', 'Quick_Log_Category__c']   # whole objects
TABS = ['Quality_Event__c']
FIELDS = {   # our fields on objects that are not ours
    'Case': ['Aware_Date__c', 'Customer_Reported__c', 'Found_By__c', 'Injured_Person__c', 'Injury_Reported__c', 'Lot_Number__c',
             'Product_Affected__c', 'Reported_By__c', 'Safety_Risk_Reported__c', 'Supplier_Reported__c', 'Where_Found__c'],
    'compliancequest__SQX_Nonconformance__c': ['Quick_Log__c', 'Quick_Log_Category__c', 'Trend_Event__c'],
}
# Admin edits questions and categories; reporters read them.
USER_EDIT = {'Quality_Event__c', 'Event_Answer__c', 'Case', 'compliancequest__SQX_Nonconformance__c'}


def files():
    out = []
    for c in CLASSES + TESTS:
        out += [f'classes/{c}.cls', f'classes/{c}.cls-meta.xml']
    for t in TRIGGERS:
        out += [f'triggers/{t}.trigger', f'triggers/{t}.trigger-meta.xml']
    for l in LWC:
        out += [f'lwc/{l}/{f}' for f in sorted(os.listdir(os.path.join(SRC, 'lwc', l)))]
    for o in OBJECTS:
        for dp, _, fs in os.walk(os.path.join(SRC, 'objects', o)):
            out += [os.path.relpath(os.path.join(dp, f), SRC) for f in sorted(fs)]
    for t in TABS:
        out.append(f'tabs/{t}.tab-meta.xml')
    for o, fs in FIELDS.items():
        out += [f'objects/{o}/fields/{f}.field-meta.xml' for f in fs]
    return out


def fieldperm_rows():
    rows = []
    for o in OBJECTS + list(FIELDS):
        d = os.path.join(SRC, 'objects', o, 'fields')
        names = sorted(f[:-len('.field-meta.xml')] for f in os.listdir(d)) if o in OBJECTS else FIELDS[o]
        for n in names:
            x = open(os.path.join(d, n + '.field-meta.xml')).read()
            if re.search(r'<required>true|<type>MasterDetail|<formula>|<type>AutoNumber', x):
                continue   # access comes with the object / cannot be set
            rows.append((o, n))
    return rows


def permset(label, desc, objects, edit_objects, extra_fields=(), classes=(), tabs=()):
    p = ['<?xml version="1.0" encoding="UTF-8"?>', '<PermissionSet xmlns="http://soap.sforce.com/2006/04/metadata">']
    p += [f'    <classAccesses>\n        <apexClass>{c}</apexClass>\n        <enabled>true</enabled>\n    </classAccesses>' for c in classes]
    p.append(f'    <description>{desc}</description>')
    for o, n in fieldperm_rows() + list(extra_fields):
        if o not in [x[0] for x in objects]:
            continue
        ed = 'true' if o in edit_objects else 'false'
        p.append(f'    <fieldPermissions>\n        <editable>{ed}</editable>\n        <field>{o}.{n}</field>\n        <readable>true</readable>\n    </fieldPermissions>')
    p.append('    <hasActivationRequired>false</hasActivationRequired>')
    p.append(f'    <label>{label}</label>')
    for o, (c, r, e, dl) in objects:
        p.append(f'    <objectPermissions>\n        <allowCreate>{str(c).lower()}</allowCreate>\n        <allowDelete>{str(dl).lower()}</allowDelete>\n'
                 f'        <allowEdit>{str(e).lower()}</allowEdit>\n        <allowRead>{str(r).lower()}</allowRead>\n'
                 f'        <modifyAllRecords>false</modifyAllRecords>\n        <object>{o}</object>\n        <viewAllRecords>false</viewAllRecords>\n    </objectPermissions>')
    p += [f'    <tabSettings>\n        <tab>{t}</tab>\n        <visibility>Visible</visibility>\n    </tabSettings>' for t in tabs]
    p.append('</PermissionSet>\n')
    return '\n'.join(p)


def build(dest):
    if os.path.exists(dest):
        shutil.rmtree(dest)
    for f in files():
        os.makedirs(os.path.dirname(os.path.join(dest, f)), exist_ok=True)
        shutil.copy2(os.path.join(SRC, f), os.path.join(dest, f))
    for dp, _, fs in os.walk(EXTRA):
        for f in fs:
            rel = os.path.relpath(os.path.join(dp, f), EXTRA)
            os.makedirs(os.path.dirname(os.path.join(dest, rel)), exist_ok=True)
            shutil.copy2(os.path.join(dp, f), os.path.join(dest, rel))
    ps = os.path.join(dest, 'permissionsets')
    os.makedirs(ps, exist_ok=True)
    user_objects = [('Quality_Event__c', (True, True, True, False)), ('Event_Answer__c', (True, True, True, False)),
                    ('Event_Question__c', (False, True, False, False)), ('Quick_Log_Category__c', (False, True, False, False)),
                    ('Case', (True, True, False, False)), ('Account', (False, True, False, False)),
                    ('compliancequest__SQX_Nonconformance__c', (False, True, False, False))]
    open(os.path.join(ps, 'CQ_Mobile_Intake_User.permissionset-meta.xml'), 'w').write(permset(
        'CQ Mobile Intake User', 'Report a problem from the mobile intake: sends Quality Events, or Cases for problems found at a customer.',
        user_objects, USER_EDIT, extra_fields=[('Case', 'AccountId'), ('Case', 'Description'), ('Case', 'Origin'), ('Case', 'Priority'),
                                               ('Case', 'Subject'), ('Case', 'Type')],
        classes=CLASSES, tabs=['Report_an_Event', 'Quality_Event__c']))
    admin_objects = [('Quality_Event__c', (True, True, True, True)), ('Event_Answer__c', (True, True, True, True)),
                     ('Event_Question__c', (True, True, True, True)), ('Quick_Log_Category__c', (True, True, True, True))]
    open(os.path.join(ps, 'CQ_Mobile_Intake_Admin.permissionset-meta.xml'), 'w').write(permset(
        'CQ Mobile Intake Admin', 'Set up the mobile intake: questions (and which Case field each answer goes to), read-aloud clips and quick-log categories.',
        admin_objects, {'Quality_Event__c', 'Event_Answer__c', 'Event_Question__c', 'Quick_Log_Category__c'},
        classes=CLASSES, tabs=['Report_an_Event', 'Quality_Event__c']))


def same(a, b):
    c = filecmp.dircmp(a, b)
    if c.left_only or c.right_only or c.diff_files or c.funny_files:
        return False
    return all(same(os.path.join(a, s), os.path.join(b, s)) for s in c.common_dirs)


if __name__ == '__main__':
    if '--check' in sys.argv:
        tmp = os.path.join(PKG, '.check')
        build(tmp)
        ok = os.path.exists(OUT) and same(tmp, OUT)
        shutil.rmtree(tmp)
        print('up to date' if ok else 'OUT OF DATE: run python3 scripts/build_mobile_intake_package.py')
        sys.exit(0 if ok else 1)
    build(OUT)
    n = sum(len(fs) for _, _, fs in os.walk(OUT))
    print(f'built {os.path.relpath(OUT, ROOT)}: {n} files')
