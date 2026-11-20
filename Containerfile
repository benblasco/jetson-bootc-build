FROM registry.redhat.io/nvidia/nvidia-jetpack-for-rhel10:7.2.1_6.12.0-211.72.1_110226170017

# Copy container image embedding and copy scripts, and systemd drop in for copying images
# Note: file permissions from the repo are preserved
COPY files/ /

# Install MicroShift from layered rhocp/fast-datapath CDN repos (rhel9 tree on CDN).
# RHEL 10 cannot enable RHEL 9 repo IDs via subscription-manager; pass host
# entitlements as build secrets (see README.jetson.md and build_rhel_bootc.yml).
RUN --mount=type=secret,id=entitlement-cert \
    --mount=type=secret,id=entitlement-key \
<<EOF
set -euo pipefail

ARCH="$(uname -m)"
CERT=/run/secrets/entitlement-cert
KEY=/run/secrets/entitlement-key

cat > /etc/yum.repos.d/microshift-rhocp.repo <<REPO
[rhocp-4.22]
name=Red Hat OpenShift 4.22 for RHEL 9
baseurl=https://cdn.redhat.com/content/dist/layered/rhel9/${ARCH}/rhocp/4.22/os
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
sslverify=1
sslcacert=/etc/rhsm/ca/redhat-uep.pem
sslclientcert=${CERT}
sslclientkey=${KEY}
REPO

cat > /etc/yum.repos.d/microshift-fast-datapath.repo <<REPO
[fast-datapath]
name=Red Hat Fast Datapath for RHEL 9
baseurl=https://cdn.redhat.com/content/dist/layered/rhel9/${ARCH}/fast-datapath/os
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
sslverify=1
sslcacert=/etc/rhsm/ca/redhat-uep.pem
sslclientcert=${CERT}
sslclientkey=${KEY}
REPO

dnf install -y microshift microshift-release-info firewalld skopeo jq

rm -f /etc/yum.repos.d/microshift-rhocp.repo /etc/yum.repos.d/microshift-fast-datapath.repo
dnf clean all

EOF

RUN <<EOF
set -euo pipefail

systemctl enable microshift

firewall-offline-cmd --zone=trusted --add-source=10.42.0.0/16 && \
firewall-offline-cmd --zone=trusted --add-source=169.254.169.1 && \

EOF

# Image references come from the installed microshift-release-info RPM so they
# match this MicroShift build. --all keeps manifest-list digests intact.
#RUN --mount=type=secret,id=pullsecret,dst=/tmp/pull-secret.json \
#    images="$(jq -r '.images[]' /usr/share/microshift/release/release-"$(uname -m)".json)" && \
#    test -n "${images}" && \
#    for img in ${images}; do \
#        /usr/bin/embed_image.sh "${img}" --all ; \
#    done
