#!/bin/bash

# Install cri-tools
CRICTL_VERSION="v1.20.0"

wget https://github.com/kubernetes-sigs/cri-tools/releases/download/$CRICTL_VERSION/crictl-$CRICTL_VERSION-linux-amd64.tar.gz
sudo tar zxvf crictl-$CRICTL_VERSION-linux-amd64.tar.gz -C /usr/local/bin
rm -f crictl-$CRICTL_VERSION-linux-amd64.tar.gz

# Install cri-o
CRIO_VERSION="1.18"

curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:${CRIO_VERSION}.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:${CRIO_VERSION}/CentOS_8/devel:kubic:libcontainers:stable:cri-o:${CRIO_VERSION}.repo

sudo yum install -y cri-o
sed 's|/usr/libexec/crio/conmon|/usr/bin/conmon|' -i /etc/crio/crio.conf
sudo systemctl start cri-o

# Install sriov-cni: A Container Network Interface(CNI) binary used in OpenShift to attach VF into container

git clone https://github.com/openshift/sriov-cni.git
pushd sriov-cni
sudo yum install -yq go
make build  # build sriov-cni binary
cp -f build/sriov /usr/libexec/cni/  # copy sriov-cni binary to default crio cni directory

# Configure default crio CNI configuration file
# VF_PCI_ID from cmdline

VF_PCI_ID=$1

cat > "/etc/cni/net.d/1-sriov-net-attach-def.conf" << EOF
{ "cniVersion":"0.3.1", "name":"sriov-net","type":"sriov","vlan":0,"spoofchk":"off","vlanQoS":0,"ipam":{"type":"host-local","subnet":"10.56.217.0/24","rangeStart":"10.56.217.171","rangeEnd":"10.56.217.181","routes":[{"dst":"0.0.0.0/0"}],"gateway":"10.56.217.1"}, "deviceID": "${VF_PCI_ID}" }
EOF

# Run a pod
cat > "pod.json" << EOF
{
    "metadata": {
        "name": "sriov-pod-sandbox",
        "namespace": "default",
        "attempt": 1,
        "uid": "hdishd83djaidwnduwk28bcsb"
    },
    "log_directory": "/tmp",
    "linux": {
    }
}
EOF

pod_id=$(crictl runp --runtime=runc pod.json)  # record the pod_id returned by this cmd

# Pull container image
CONTAINER_IMAGE="quay.io/zshi/centos:httpd-iperf"
crictl pull $CONTAINER_IMAGE

# Run a container inside pod
cat > "container.json" << EOF
{
  "metadata": {
      "name": "sriov-container"
  },
  "image":{
      "image": "$CONTAINER_IMAGE"
  },
  "command": [
      "top"
  ],
  "log_path":"sriov-container.log",
  "linux": {
  }
}
EOF

crictl create ${pod_id}  container.json pod.json

# Get sriov container id
crictl ps --all

# Check sriov interface inside container
crictl exec -it ${container_id} bash
ifconfig eth0 # execute inside container
ethtool -i eth0 # execut inside container
