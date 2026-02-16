from pyanaconda.installclasses.centos import RHELBaseInstallClass
from pyanaconda.product import productName


class AnarchyHPCBaseInstallClass(RHELBaseInstallClass):
    name = "AnarchyHPC"
    sortPriority = 30000
    if not productName.startswith("CentOS"):
        hidden = True

    defaultFS = "ext4"
