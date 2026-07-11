Import("env")

import os
from datetime import date

version_path = os.path.join(env["PROJECT_DIR"], "VERSION")
with open(version_path, encoding="utf-8") as version_file:
    version = version_file.read().strip()

build_date = date.today().isoformat()

env.Append(
    CPPDEFINES=[
        ("FIRMWARE_VERSION", '\\"' + version + '\\"'),
        ("BUILD_DATE", '\\"' + build_date + '\\"'),
    ]
)
