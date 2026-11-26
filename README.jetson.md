# RHEL 10 bootc ISO for NVIDIA Jetson Orin

Build an offline installer ISO for an NVIDIA Jetson Orin. The image starts from `registry.redhat.io/nvidia/nvidia-jetpack-for-rhel10:7.2.1_6.12.0-211.72.1_110226170017`, installs MicroShift 4.22, and embeds the container images that MicroShift needs so the Orin can boot disconnected.

Build on an aarch64 RHEL host, such as an AWS `m7g` instance. The JetPack image is arm64-only. Give the host at least 150 GB of free disk space. The JetPack image, the embedded MicroShift images, the osbuild store, and the ISO each need their own copy.

Run the commands as root so the image is pulled into `/var/lib/containers/storage`, which is the store mounted into the builder.

## Prepare the host

Register the host and enable repository management. `subscription-manager register` prompts for the Red Hat account.

```bash
subscription-manager register
subscription-manager config --rhsm.manage_repos=1
```

Log in to the Red Hat container registry:

```bash
podman login registry.redhat.io
```

## Kickstart

Create a working directory and `config.toml`. Replace `changeme` before writing the ISO to anything that will be installed.

`bootc-image-builder` inserts the `ostreecontainer` command. The kickstart below is the full installer configuration. The operating system payload is already in the ISO, so the installer does not need a route to a registry. The installed system still needs an address: `network --bootproto=dhcp` writes a DHCP profile and brings it up on boot. `pd_ignore_unused` is required on Jetson Orin.

Run the remaining commands from this directory.

```toml
[customizations.installer.kickstart]
contents = """
text
keyboard us
timezone --utc GMT
network --bootproto=dhcp --device=link --activate --onboot=yes --hostname=jetson-orin
bootloader --append="rhgb crashkernel=auto cloud-init=disabled pd_ignore_unused"

rootpw --lock
zerombr
clearpart --all --initlabel --disklabel=gpt
reqpart --add-boot
part pv.01 --grow
volgroup rhel pv.01
logvol / --vgname=rhel --name=root --fstype=xfs --size=20480
logvol swap --vgname=rhel --name=swap --recommended

services --enabled=sshd
user --name=admin --groups=wheel,video --plaintext --password=changeme
reboot --eject
"""
```

```bash
mkdir ./output
```

MicroShift LVMS looks for a volume group named `rhel`. `/` is a fixed 20 GB logical volume so the rest of that group stays free for persistent volumes.

## Build the MicroShift image

`Containerfile` installs MicroShift from the layered `rhocp/4.22` and `fast-datapath` CDN repositories under the `rhel9` content tree (per Red Hat’s RHEL 10 workaround), even though the base image is RHEL 10. The build uses entitlement PEMs as Podman/buildah secrets instead of subscription-manager repo IDs. `embed_image.sh` stores each image under `/usr/lib/containers-image-cache` with `skopeo copy --preserve-digests`, and records the reference in `mapping.txt`. The pull secret and the host entitlement are mounted as build secrets and are not written into the image.

Place a pull secret at `pull-secret.json` in this directory. That file is gitignored. A Podman build secret has to be a file, and `/etc/pki/entitlement` is a directory, so pass the certificate and key separately.

GitHub Actions writes the repository secret `OPENSHIFT_PULL_SECRET` to `/tmp/pull-secret.json` and passes it to buildah as `id=pullsecret` (see `.github/workflows/build_rhel_bootc.yml`).

```bash
CERT=$(ls /etc/pki/entitlement/[0-9]*.pem | grep -v -- '-key.pem' | head -n1)
KEY=$(ls /etc/pki/entitlement/[0-9]*-key.pem | head -n1)

podman build \
    --secret id=entitlement-cert,src="$CERT" \
    --secret id=entitlement-key,src="$KEY" \
    --secret id=pullsecret,src=./pull-secret.json \
    -t localhost/nvidia-jetpack-rhel10-microshift:0.1 \
    -f Containerfile .
```

On first boot, `microshift.service` runs `copy_embedded_images.sh` before MicroShift starts. The script copies the cache into the local container store, which is the step the disconnected Orin cannot do from a registry.

## Build the ISO

```bash
podman run --rm --privileged --pull=newer \
    --security-opt label=type:unconfined_t \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    -v "$(pwd)/config.toml:/config.toml:ro" \
    -v "$(pwd)/output:/output" \
    registry.redhat.io/rhel10/bootc-image-builder:latest \
    --type iso \
    --config /config.toml \
    --local \
    localhost/nvidia-jetpack-rhel10-microshift:0.1
```

The ISO is written to `output/bootiso/install.iso`.

## Write the USB

Copy the ISO to a USB disk large enough to hold it. Replace `/dev/sdX` with the USB device.

```bash
dd if=./output/bootiso/install.iso of=/dev/sdX bs=4M status=progress
sync
```

Boot the Jetson Orin from that USB. After it is up, copy the pull secret onto the device. CRI-O expects that file even when the images are already local:

```bash
sudo vi /etc/crio/openshift-pull-secret
sudo chmod 600 /etc/crio/openshift-pull-secret
```

Open the API port if another machine on the local network needs it:

```bash
sudo firewall-cmd --permanent --zone=public --add-port=6443/tcp
sudo firewall-cmd --reload
```

The installed system records the image reference used at build time. `bootc upgrade` on an air-gapped Orin fails. Later updates are delivered with `bootc switch` from an image carried on removable media.
