#!/bin/bash

set -e
set -x

PROD_NAME=anarchyhpc
SPEC_FILE=${PROD_NAME}.spec
SPEC_IN_FILE=${SPEC_FILE}.in

SCRIPTDIR=$(
    cd "$(dirname "$0")"
    pwd
)

if [ ! -f "${SCRIPTDIR}/${SPEC_IN_FILE}" ]; then
    echo "No ${SPEC_IN_FILE} file found"
    exit 1
fi

# ---------------------------------------------
# Determine VERSION and BUILD from Git
# ---------------------------------------------
if git describe --tags --long >/dev/null 2>&1; then
    # Example tag: v15.3-12-gabcdef
    DESCRIBE=$(git describe --tags --long)

    # Extract version (strip leading v if present)
    VERSION=$(echo "$DESCRIBE" | sed -E 's/^v?([0-9]+\.[0-9]+).*/\1/')

    # Extract build number (the middle field)
    BUILD=$(echo "$DESCRIBE" | awk -F- '{print $2}')
else
    VERSION=9999
    BUILD=$(git rev-list --count HEAD)
fi

# ---------------------------------------------
# Prepare RPM build tree
# ---------------------------------------------
mkdir -p "${SCRIPTDIR}"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

# Substitute version/build into spec
sed -e "s/__VERSION__/$VERSION/" \
    -e "s/__BUILD__/$BUILD/" \
    "${SCRIPTDIR}/${SPEC_IN_FILE}" \
    > "${SCRIPTDIR}/SPECS/${SPEC_FILE}"

# Append git log to changelog
git log --format="* %cd %aN%n- (%h) %s%n" --date=local --no-merges \
    | sed -E 's/[0-9]+:[0-9]+:[0-9]+ //' \
    >> "${SCRIPTDIR}/SPECS/${SPEC_FILE}"

# Create source tarball
git archive \
    --format=tar.gz \
    --prefix="${PROD_NAME}-${VERSION}-${BUILD}/" \
    -o "${SCRIPTDIR}/SOURCES/${PROD_NAME}-${VERSION}-${BUILD}.tar.gz" \
    HEAD

# ---------------------------------------------
# Build SRPM and RPM
# ---------------------------------------------
rm -f "${SCRIPTDIR}/SRPMS/"*.rpm
rpmbuild -bs --define "_topdir ${SCRIPTDIR}" "${SCRIPTDIR}/SPECS/${SPEC_FILE}"

rm -f "${SCRIPTDIR}/RPMS/"*.rpm
rpmbuild --rebuild --define "_topdir ${SCRIPTDIR}" "${SCRIPTDIR}/SRPMS/"*.rpm
