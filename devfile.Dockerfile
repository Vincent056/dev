# updateBaseImages.sh can't operate on SHA-based tags as they're not date-based or semver-sequential, and therefore cannot be ordered
FROM fedora

LABEL com.redhat.component="devfile-base-container"
LABEL name="devfile/base-developer-image"
LABEL version="fedora"

#labels for container catalog
LABEL summary="devfile base developer image"
LABEL description="Image with base developers tools. Languages SDK and runtimes excluded."
LABEL io.k8s.display-name="devfile-developer-base"
LABEL io.openshift.expose-services=""

USER 0

ENV HOME=/home/tooling
RUN mkdir -p /home/tooling/

RUN dnf update -y && \
    dnf install -y bash openssl-devel curl diffutils git git-lfs iproute jq less lsof man nano procps p7zip p7zip-plugins \
                   perl-Digest-SHA net-tools openssh-clients rsync socat sudo time vim wget zip stow && \
                   dnf clean all

RUN dnf install -y ripgrep bat fd-find gh

# install unzip
RUN dnf install -y unzip zip wget curl nano git

COPY --chown=0:0 .stow-local-ignore /home/tooling/

RUN \
    # add user and configure it
    useradd -u 10001 -G wheel,root -d /home/user --shell /bin/bash -m user && \
    # Setup $PS1 for a consistent and reasonable prompt
    touch /etc/profile.d/udi_prompt.sh && \
    chown 10001 /etc/profile.d/udi_prompt.sh && \
    echo "export PS1='\W \`git branch --show-current 2>/dev/null | sed -r -e \"s@^(.+)@\(\1\) @\"\`$ '" >> /etc/profile.d/udi_prompt.sh && \
    # Copy the global git configuration to user config as global /etc/gitconfig
    # file may be overwritten by a mounted file at runtime
    cp /etc/gitconfig ${HOME}/.gitconfig && \
    chown 10001 ${HOME}/ ${HOME}/.viminfo ${HOME}/.gitconfig ${HOME}/.stow-local-ignore && \
    # Set permissions on /etc/passwd and /home to allow arbitrary users to write
    chgrp -R 0 /home && \
    chmod -R g=u /etc/passwd /etc/group /home && \
    
    # Create symbolic links from /home/tooling/ -> /home/user/
    stow . -t /home/user/ -d /home/tooling/ && \
    # Bash-related files are backed up to /home/tooling/ incase they are deleted when persistUserHome is enabled.
    cp /home/user/.bashrc /home/tooling/.bashrc && \
    cp /home/user/.bash_profile /home/tooling/.bash_profile && \
    chown 10001 /home/tooling/.bashrc /home/tooling/.bash_profile


USER 10001
ENV HOME=/home/user
WORKDIR /projects

USER 0
# $PROFILE_EXT contains all additions made to the bash environment
ENV PROFILE_EXT=/etc/profile.d/udi_environment.sh
RUN touch ${PROFILE_EXT} & chown 10001 ${PROFILE_EXT}

# We install everything to /home/tooling/ as /home/user/ may get overriden, see github.com/eclipse/che/issues/22412
ENV HOME=/home/tooling

# NodeJS
RUN mkdir -p /home/tooling/.nvm/
ENV NVM_DIR="/home/tooling/.nvm"
ENV NODEJS_20_VERSION=20.7.0
# note that 18.18.0 is the latest but 18.16.1 is the supported version downstream and in ubi8
ENV NODEJS_18_VERSION=18.16.1
ENV NODEJS_DEFAULT_VERSION=${NODEJS_18_VERSION}
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | PROFILE=/dev/null bash
RUN echo 'export NVM_DIR="$HOME/.nvm"' >> ${PROFILE_EXT} \
    && echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ${PROFILE_EXT}
RUN source /home/user/.bashrc && \
    nvm install v${NODEJS_20_VERSION} && \
    nvm install v${NODEJS_18_VERSION} && \
    nvm alias default v${NODEJS_DEFAULT_VERSION} && nvm use v${NODEJS_DEFAULT_VERSION} && \
    npm install --global yarn@v1.22.17 &&\
    chgrp -R 0 /home/tooling && chmod -R g=u /home/tooling
ENV PATH=$NVM_DIR/versions/node/v${NODEJS_DEFAULT_VERSION}/bin:$PATH
ENV NODEJS_HOME_20=$NVM_DIR/versions/node/v${NODEJS_20_VERSION}
ENV NODEJS_HOME_18=$NVM_DIR/versions/node/v${NODEJS_18_VERSION}

# kube
ENV KUBECONFIG=/home/user/.kube/config

# Define user directory for binaries
RUN mkdir -p /home/tooling/.local/bin && \
    chgrp -R 0 /home && chmod -R g=u /home
ENV PATH="/home/user/.local/bin:$PATH"
ENV PATH="/home/tooling/.local/bin:$PATH"

# Required packages for AWT
RUN dnf install -y libXext libXrender libXtst libXi

# Lombok
ENV LOMBOK_VERSION=1.18.18
RUN wget -O /usr/local/lib/lombok.jar https://projectlombok.org/downloads/lombok-${LOMBOK_VERSION}.jar

# Scala
RUN curl -fLo cs https://git.io/coursier-cli && \
    chmod +x cs && \
    mv cs /usr/local/bin/
RUN curl -fLo sbt https://raw.githubusercontent.com/dwijnand/sbt-extras/master/sbt && \
    chmod +x sbt && \
    mv sbt /usr/local/bin/
RUN curl -fLo mill https://raw.githubusercontent.com/lefou/millw/main/millw && \
    chmod +x mill && \
    mv mill /usr/local/bin/

# C/CPP
RUN dnf -y install llvm gcc gcc-c++ clang clang-libs clang-tools-extra gdb

# Go 1.18+    - installed to /usr/bin/go
# gopls 0.10+ - installed to /home/tooling/go/bin/gopls and /home/tooling/go/pkg/mod/
RUN dnf install -y golang && \
    GO111MODULE=on go install -v golang.org/x/tools/gopls@latest && \
    chgrp -R 0 /home/tooling && chmod -R g=u /home/tooling
ENV GOBIN="/home/tooling/go/bin/"
ENV PATH="$GOBIN:$PATH"

# OpenScape-Scanner

RUN dnf install -y openscap-scanner
# Python
RUN dnf -y install python3 python3-devel python3-setuptools python3-pip nss_wrapper

RUN cd /usr/bin \
    && if [ ! -L python ]; then ln -s python3 python; fi \
    && if [ ! -L pydoc ]; then ln -s pydoc3 pydoc; fi \
    && if [ ! -L python-config ]; then ln -s python3-config python-config; fi

RUN pip install pylint yq

# install xfsprogs for xfs_growfs
RUN dnf install -y xfsprogs

# rust
ENV CARGO_HOME=/home/tooling/.cargo \
    RUSTUP_HOME=/home/tooling/.rustup \
    PATH=/home/tooling/.cargo/bin:${PATH}
RUN curl --proto '=https' --tlsv1.2 -sSfo rustup https://sh.rustup.rs && \
    chmod +x rustup && \
    mv rustup /usr/bin/ && \
    rustup -y --no-modify-path --profile minimal -c rust-src -c rust-analysis -c rls && \
    chgrp -R 0 /home/tooling && chmod -R g=u /home/tooling

# camel-k
ENV KAMEL_VERSION 1.11.0
RUN curl -L https://github.com/apache/camel-k/releases/download/v${KAMEL_VERSION}/camel-k-client-${KAMEL_VERSION}-linux-64bit.tar.gz | tar -C /usr/local/bin -xz \
    && chmod +x /usr/local/bin/kamel



# oc client
RUN curl -L https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.14.5/openshift-client-linux.tar.gz | tar -C /usr/local/bin -xz \
    && chmod +x /usr/local/bin/oc && \
    chmod +x /usr/local/bin/kubectl

## podman buildah skopeo
RUN dnf -y reinstall shadow-utils && \
    dnf -y install fuse-overlayfs && fuse-overlayfs -V && \
    dnf -y install podman buildah skopeo
RUN echo 'alias docker=podman' >> ${PROFILE_EXT}

# Set up environment variables to note that this is
# not starting with usernamespace and default to
# isolate the filesystem with chroot.
ENV _BUILDAH_STARTED_IN_USERNS="" BUILDAH_ISOLATION=chroot

# Tweaks to make rootless buildah work
RUN touch /etc/subgid /etc/subuid  && \
    chmod g=u /etc/subgid /etc/subuid /etc/passwd  && \
    echo user:10000:65536 > /etc/subuid  && \
    echo user:10000:65536 > /etc/subgid

# Adjust storage.conf to enable Fuse storage.
RUN sed -i -e 's|^#mount_program|mount_program|g' -e '/additionalimage.*/a "/var/lib/shared",' /usr/share/containers/storage.conf
RUN mkdir -p /var/lib/shared/overlay-images /var/lib/shared/overlay-layers; \
    touch /var/lib/shared/overlay-images/images.lock; \
    touch /var/lib/shared/overlay-layers/layers.lock


# Configure container engine
COPY --chown=0:0 containers.conf /etc/containers/containers.conf

# Install kubedock
ENV KUBEDOCK_VERSION 0.13.0
RUN curl -L https://github.com/joyrex2001/kubedock/releases/download/${KUBEDOCK_VERSION}/kubedock_${KUBEDOCK_VERSION}_linux_amd64.tar.gz | tar -C /usr/local/bin -xz \
    && chmod +x /usr/local/bin/kubedock

# Configure the podman wrapper
COPY --chown=0:0 podman-wrapper.sh /usr/bin/podman.wrapper
RUN mv /usr/bin/podman /usr/bin/podman.orig


## shellcheck
RUN dnf install -y xz ShellCheck

## install openssl1.1
RUN dnf install -y openssl1.1.x86_64

# # Bash completions
RUN dnf -y install bash-completion \
    && dnf clean all \
    && rm -rf /var/cache/yum

RUN oc completion bash > /usr/share/bash-completion/completions/oc \
    && kubectl completion bash > /usr/share/bash-completion/completions/kubectl \
    && cat ${NVM_DIR}/bash_completion > /usr/share/bash-completion/completions/nvm


# Set permissions on /etc/passwd and /home to allow arbitrary users to write
RUN chgrp -R 0 /home && chmod -R g=u /etc/passwd /etc/group /home

# cleanup dnf cache
RUN dnf -y clean all --enablerepo='*'

COPY --chown=0:0 entrypoint.sh /

RUN chmod +x /entrypoint.sh

# fix openssl
RUN echo "/usr/local/lib64" > /etc/ld.so.conf.d/openssl.conf
RUN ldconfig

USER 10001

ENV HOME=/home/user

WORKDIR /projects
ENTRYPOINT [ "/entrypoint.sh" ]
CMD ["tail", "-f", "/dev/null"]