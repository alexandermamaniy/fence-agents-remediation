# Build the manager binary
FROM quay.io/centos/centos:stream9 AS builder
RUN dnf install -y jq git \
    && dnf clean all -y

WORKDIR /workspace
# Copy the Go Modules manifests for detecting Go version
COPY go.mod go.mod
COPY go.sum go.sum

RUN \
    # get Go version from mod file
    export GO_VERSION=$(grep -oE "toolchain go[[:digit:]]\.[[:digit:]]+\.[[:digit:]]" go.mod | awk '{print $2}') && \
    echo ${GO_VERSION} && \
    # find filename for latest z version from Go download page
    export GO_FILENAME=$(curl -sL 'https://go.dev/dl/?mode=json&include=all' | jq -r "[.[] | select(.version == \"${GO_VERSION}\")][0].files[] | select(.os == \"linux\" and .arch == \"s390x\") | .filename") && \
    echo ${GO_FILENAME} && \
    # download and unpack
    curl -sL -o go.tar.gz "https://golang.org/dl/${GO_FILENAME}" && \
    tar -C /usr/local -xzf go.tar.gz && \
    rm go.tar.gz

# add Go directory to PATH
ENV PATH="${PATH}:/usr/local/go/bin"
RUN go version

# Copy the go source
COPY cmd/ cmd/
COPY api/ api/
COPY internal/ internal/
COPY hack/ hack/
COPY pkg/ pkg/
COPY version/ version/
COPY vendor/ vendor/

# for getting version info
COPY .git/ .git/

# Build
RUN ./hack/build.sh

FROM quay.io/centos/centos:stream9

WORKDIR /
COPY --from=builder /workspace/manager .

# Add many Fence Agents packages
RUN dnf install -y dnf-plugins-core \
    && dnf --enablerepo=highavailability install -y fence-agents-amt-ws fence-agents-apc-snmp fence-agents-cisco-ucs \
    fence-agents-eaton-snmp fence-agents-emerson fence-agents-eps fence-agents-ibmblade fence-agents-ifmib fence-agents-ilo2 \
    fence-agents-intelmodular fence-agents-ipdu fence-agents-ipmilan fence-agents-redfish fence-agents-rhevm \
    fence-agents-vmware-rest fence-agents-vmware-soap \
    fence-agents-kubevirt fence-agents-ibm-powervs fence-agents-ibm-vpc \
    && dnf clean all -y

# Add fence_ibmz from upstream (no RPM available in HighAvailability repo)
# python3 and curl are already present in the base image; only python3-requests is needed
RUN dnf install -y python3-requests \
    && dnf clean all -y \
    && curl -sL -o fence_ibmz.py https://raw.githubusercontent.com/ClusterLabs/fence-agents/master/agents/ibmz/fence_ibmz.py \
    && sed -i 's+@PYTHON@+/usr/libexec/platform-python+' fence_ibmz.py \
    && sed -i 's+@FENCEAGENTSLIBDIR@+/usr/share/fence+' fence_ibmz.py \
    && cp fence_ibmz.py /usr/sbin/fence_ibmz \
    && chmod +x /usr/sbin/fence_ibmz \
    && rm fence_ibmz.py

USER 65532:65532
ENTRYPOINT ["/manager"]
