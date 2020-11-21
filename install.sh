#!/usr/bin/env bash

# (Install Docker CE)
## Set up the repository
### Install required packages
sudo yum install -y yum-utils device-mapper-persistent-data lvm2

# sync time
systemctl start ntpd
systemctl enable ntpd

## Add the Docker repository
sudo yum-config-manager --add-repo \
  https://download.docker.com/linux/centos/docker-ce.repo

# Install Docker CE
sudo yum update -y && sudo yum install -y \
  containerd.io \
  docker-ce \
  docker-ce-cli

## Create /etc/docker
sudo mkdir /etc/docker

# Set up the Docker daemon
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
}
EOF

# Create /etc/systemd/system/docker.service.d
sudo mkdir -p /etc/systemd/system/docker.service.d

# Restart Docker
sudo systemctl daemon-reload
sudo systemctl restart docker

sudo systemctl enable docker

### Install kubernetes-master on node1 or kubernetes-client on others

cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF

# Install Kubernetes
yum install -y kubelet kubeadm kubectl

systemctl enable kubelet
systemctl start kubelet

# Configure Firewall
if [[ $(hostname) == "node1" ]]; then
  firewall-cmd --permanent --add-port=6443/tcp
  firewall-cmd --permanent --add-port=2379-2380/tcp
  firewall-cmd --permanent --add-port=10250/tcp
  firewall-cmd --permanent --add-port=10251/tcp
  firewall-cmd --permanent --add-port=10252/tcp
  firewall-cmd --permanent --add-port=10255/tcp
  firewall-cmd --reload
else
  firewall-cmd --permanent --add-port=10251/tcp
  firewall-cmd --permanent --add-port=10255/tcp
  firewall-cmd --reload
fi

# Configure IPTables to ensure that packets are properly processed by IP tableds during filtering and port forwarding.
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

sysctl --system

# Disable SELinux to allow containers access to the host filesystem.
sudo setenforce 0
#sudo sed -i ‘s/^SELINUX=enforcing$/SELINUX=permissive/’ /etc/selinux/config

# Disable SWAP to enable the kubelet to work properly
#sudo sed -i '/swap/d' /etc/fstab
sudo swapoff -a

### Run Kubernetes on master or join on client
if [[ $(hostname) == "node1" ]]; then
  kubeadm init --apiserver-advertise-address=`hostname -I | awk '{ print $2 }'` --pod-network-cidr=10.244.0.0/16 --ignore-preflight-errors=NumCPU | tee /tmp/kube_output
  cat /tmp/kube_output | tail -2 > /vagrant/join_command

  mkdir -p /home/vagrant/.kube
  cp -i /etc/kubernetes/admin.conf /home/vagrant/.kube/config
  chown vagrant:vagrant -R /home/vagrant/.kube

  kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
else
  . /vagrant/join_command
fi