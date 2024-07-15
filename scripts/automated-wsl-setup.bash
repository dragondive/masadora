#!/bin/bash

display_help()
{
cat << EOF
Usage: setup.bash [OPTION]...

-h, --help
    Display this help

-u, --username <username>
    Create a local user <username> and set it as the default user.

    If not specified, the WSL distro name will be used as the default username and password.

-p, --perform-operations [operations,...]
    Comma-separated list of operations to be performed. All other operations will be skipped.

    If neither --perform-operations nor --skip-operations is specified, all operations
    will be performed by default. See the list of supported operations below.

-s, --skip-operations [operations,...]
    Comma-separated list of operations to be skipped. All other operations will be performed.
    
    If neither --perform-operations nor --skip-operations is specified, all operations
    will be performed by default. See the list of supported operations below.

Supported operations:

    create_user
        Create a new user and set it as the default user. See also --username option.

    enable_systemd
        Enable systemd in WSL.

    install_docker
        Install docker and docker-compose.

    install_git
        Install git.

    copy_ssh_keys
        Copy ssh keys from Windows to WSL and set the correct permissions.

    install_utilities
        Install general utilities used in development environment.

    install_vscode_extensions
        Install some useful vscode extensions.

EOF
}

ARGUMENTS=("$@")
options=$(getopt -l \
    "help,username:,perform-operations:,skip-operations:", \
    -o "hu:p:s:" -- \
    "${ARGUMENTS[@]}")
eval set -- "$options"

declare -A ALL_OPERATIONS
ALL_OPERATIONS=(
    [create_user]=1
    [enable_systemd]=1
    [install_docker]=1
    [install_git]=1
    [copy_ssh_keys]=1
    [install_utilities]=1
    [install_vscode_extensions]=1
)

declare -A PERFORM_OPERATION

PERFORM_OPERATIONS_FLAG=0
SKIP_OPERATIONS_FLAG=0

while true; do
case "$1" in
-h|--help)
    display_help
    exit 0
    ;;
-u|--username)
    shift
    export DEFAULT_USER="$1"
    ;;
-p|--perform-operations)
    shift
    PERFORM_OPERATIONS_FLAG=1

    for operation in "${!ALL_OPERATIONS[@]}"; do
        PERFORM_OPERATION[$operation]=0
    done

    IFS=',' read -ra operations <<< "$1"
    for operation in "${operations[@]}"; do
        PERFORM_OPERATION[$operation]=1
    done
    ;;
-s|--skip-operations)
    shift
    SKIP_OPERATIONS_FLAG=1

    for operation in "${!ALL_OPERATIONS[@]}"; do
        PERFORM_OPERATION[$operation]=1
    done

    IFS=',' read -ra operations <<< "$1"
    for operation in "${operations[@]}"; do
        PERFORM_OPERATION[$operation]=0
    done
    ;;
--)
    shift
    break
    ;;
esac
shift
done

if [[ $PERFORM_OPERATIONS_FLAG -eq 0 && $SKIP_OPERATIONS_FLAG -eq 0 ]]; then
    for operation in "${!ALL_OPERATIONS[@]}"; do
        PERFORM_OPERATION[$operation]=1
    done
fi

if [[ $EUID -eq 0 ]];
then
    echo "Running initial configuration as the root user..."

    if [[ ${PERFORM_OPERATION[create_user]} -eq 1 ]]; then
        echo "Creating a new user..."

        if [[ -z "$DEFAULT_USER" ]]; then
            DEFAULT_USER=$WSL_DISTRO_NAME
            DEFAULT_USER_PASSWORD=$WSL_DISTRO_NAME
            printf "%b" "No username specified. Using the WSL distro name "\
            "'$DEFAULT_USER' as the default username and password.\n"
        fi

        if [[ -z "$DEFAULT_USER_PASSWORD" ]]; then
            read -sp "Password for $DEFAULT_USER: " DEFAULT_USER_PASSWORD
            echo ""
        fi
        ENCRYPTED_PASSWORD=$(echo $DEFAULT_USER_PASSWORD | openssl passwd -1 -stdin)

        useradd \
            --create-home \
            --shell /bin/bash \
            --user-group --groups adm,sudo \
            --password "$ENCRYPTED_PASSWORD" \
            $DEFAULT_USER

        ### Set the default user and enable systemd ###
        printf "%b" \
        "[user]\n" \
        "default=$DEFAULT_USER\n" \
        | tee /etc/wsl.conf
    fi

    if [[ ${PERFORM_OPERATION[enable_systemd]} -eq 1 ]]; then
        echo "Enabling systemd..."
        printf "%b" \
        "[boot]\n" \
        "systemd=true\n" \
        | tee -a /etc/wsl.conf

        # Fix the exec format error to enable running Windows applications from WSL2.
        # credit: https://github.com/microsoft/WSL/issues/8952#issuecomment-1568212651
        sh -c 'echo :WSLInterop:M::MZ::/init:PF > /usr/lib/binfmt.d/WSLInterop.conf'
        systemctl restart systemd-binfmt
    fi

    if [[ ${PERFORM_OPERATION[install_docker]} -eq 1 ]]; then
        echo "Installing docker..."
        for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker \
                   containerd runc;
        do
            sudo apt-get remove $pkg
        done

        apt-get update -yq
        apt-get install -yq ca-certificates curl gnupg
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
            | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg

        echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update -yq
        apt-get install -yq docker-ce docker-ce-cli containerd.io \
                           docker-buildx-plugin docker-compose-plugin

        usermod -aG docker $DEFAULT_USER # enables user to run docker without `sudo`.
    fi

    if [[ ${PERFORM_OPERATION[install_git]} -eq 1 ]]; then
        echo "Installing git..."
        apt-get install -yq git-all
    fi

    if [[ ${PERFORM_OPERATION[install_utilities]} -eq 1 ]]; then
        echo "Installing utilities..."
        apt-get install -yq \
            kdiff3 \
            vim-gtk3 \
            terminator
    fi

    # The script may be rerun for specific operations after the first run created the
    # default user. Extracting the default username from the wsl.conf ensures the script
    # works properly for both cases.
    #
    # NOTE: The below simple approach does not take into account sections in the ini
    # file. If in future, multiple sections define a 'default' key, this approach will
    # fail. But this approach is ok until then.
    DEFAULT_USER=$(awk -F'=' '/default=/ { print $2 }' /etc/wsl.conf)
    echo "Switching to standard user '$DEFAULT_USER' for the next configurations..."
    exec sudo \
        --preserve-env=PATH,WSL_DISTRO_NAME,USERNAME,GITLAB_TOKEN \
        --login \
        --user "$DEFAULT_USER" \
        "$(realpath $0)" "${ARGUMENTS[@]}"
fi

echo "Running initial configuration as the standard user..."

if [[ ${PERFORM_OPERATION[copy_ssh_keys]} -eq 1 ]]; then
    echo "Copying ssh keys from Windows to WSL..."
    cp -Rv /mnt/c/Users/$USERNAME/.ssh ~/.ssh
    find ~/.ssh -type f -exec grep -rlE -- '-----BEGIN.*PRIVATE KEY-----' {} + \
        | xargs -I {} chmod 600 {}  # set permission 600 for all private key files
fi

if [[ ${PERFORM_OPERATION[install_git]} -eq 1 ]]; then
    echo "Copying .gitconfig from Windows to WSL..."
    cp /mnt/c/Users/$USERNAME/.gitconfig ~/.gitconfig
fi

if [[ ${PERFORM_OPERATION[install_utilities]} -eq 1 ]]; then
    echo "Copying .gvimrc from Windows to WSL..."
    cp /mnt/c/Users/$USERNAME/.gvimrc ~/.gvimrc
fi

if [[ ${PERFORM_OPERATION[install_vscode_extensions]} -eq 1 ]]; then
    echo "Installing vscode extensions..."
    code \
        --install-extension eamodio.gitlens \
        --install-extension ms-azuretools.vscode-docker \
        --install-extension ms-vscode-remote.remote-containers \
        --install-extension ms-vscode-remote.remote-ssh \
        --install-extension ms-vscode-remote.remote-wsl \
        --install-extension ms-vscode.vscode-speech \
        --install-extension redhat.vscode-yaml \
        --install-extension shd101wyy.markdown-preview-enhanced \
        --install-extension vscode-icons-team.vscode-icons \
        --force --verbose
fi

exit 0
