FROM registry.redhat.io/nvidia/nvidia-jetpack-for-rhel10:7.2.1_6.12.0-211.72.1_110226170017

# MicroShift 4.22 for RHEL 10.2 is published in the RHEL 9 rhocp and fast-datapath
# repositories. Podman secrets are files, so the entitlement cert and key are
# mounted separately and exist only for this RUN.
RUN --mount=type=secret,id=entitlement-cert,target=/run/secrets/entitlement.pem \
    --mount=type=secret,id=entitlement-key,target=/run/secrets/entitlement-key.pem \
    CERT=/run/secrets/entitlement.pem && \
    KEY=/run/secrets/entitlement-key.pem && \
    printf '%s\n' \
      '[rhocp-4.22]' \
      'name=Red Hat OpenShift 4.22 for RHEL 9' \
      'baseurl=https://cdn.redhat.com/content/dist/layered/rhel9/aarch64/rhocp/4.22/os' \
      'enabled=1' \
      'gpgcheck=1' \
      'gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release' \
      'sslverify=1' \
      'sslcacert=/etc/rhsm/ca/redhat-uep.pem' \
      "sslclientcert=${CERT}" \
      "sslclientkey=${KEY}" \
      > /etc/yum.repos.d/rhocp-4.22.repo && \
    printf '%s\n' \
      '[fast-datapath]' \
      'name=Red Hat Fast Datapath for RHEL 9' \
      'baseurl=https://cdn.redhat.com/content/dist/layered/rhel9/aarch64/fast-datapath/os' \
      'enabled=1' \
      'gpgcheck=1' \
      'gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release' \
      'sslverify=1' \
      'sslcacert=/etc/rhsm/ca/redhat-uep.pem' \
      "sslclientcert=${CERT}" \
      "sslclientkey=${KEY}" \
      > /etc/yum.repos.d/fast-datapath.repo && \
    dnf install -y microshift microshift-release-info firewalld skopeo jq && \
    systemctl enable microshift && \
    firewall-offline-cmd --zone=trusted --add-source=10.42.0.0/16 && \
    firewall-offline-cmd --zone=trusted --add-source=169.254.169.1 && \
    dnf clean all && \
    rm -f /etc/yum.repos.d/rhocp-4.22.repo /etc/yum.repos.d/fast-datapath.repo

COPY embed_image.sh copy_embedded_images.sh /usr/bin/
COPY microshift-copy-images.conf /usr/lib/systemd/system/microshift.service.d/microshift-copy-images.conf
RUN chmod 755 /usr/bin/embed_image.sh /usr/bin/copy_embedded_images.sh

# Image references come from the installed microshift-release-info RPM so they
# match this MicroShift build. --all keeps manifest-list digests intact.
RUN --mount=type=secret,id=pullsecret,dst=/tmp/pull-secret.json \
    images="$(jq -r '.images[]' /usr/share/microshift/release/release-"$(uname -m)".json)" && \
    test -n "${images}" && \
    for img in ${images}; do \
        /usr/bin/embed_image.sh "${img}" --all ; \
    done
