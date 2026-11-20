FROM registry.redhat.io/nvidia/nvidia-jetpack-for-rhel10:7.2.1_6.12.0-211.72.1_110226170017

# Pin to RHEL 9.8 via /etc/dnf/vars/releasever and /etc/yum/vars/releasever
# Copy container image embedding and copy scripts, and systemd drop in for copying images
# Note: file permissions from the repo are preserved
COPY files/ /

# Enable the microshift-related and RHEL EUS repos
# MicroShift 4.22 is published in the RHEL 9 rhocp and fast-datapath repositories.
# Note: RHEL EUS repos only available if customer has EUS subscription
RUN <<EOF
set -euo pipefail

# Grab the system architecture e.g. x86_64 etc.
ARCH="$(uname -m)"

dnf config-manager --set-disabled \
  rhel-10-for-${ARCH}-baseos-rpms \
  rhel-10-for-${ARCH}-appstream-rpms

dnf config-manager --set-enabled \
  rhocp-4.22-for-rhel-9-${ARCH}-rpms \
  fast-datapath-for-rhel-9-${ARCH}-rpms \
  rhel-10-for-${ARCH}-baseos-eus-rpms \
  rhel-10-for-${ARCH}-appstream-eus-rpms

dnf install -y microshift microshift-release-info firewalld skopeo jq

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
