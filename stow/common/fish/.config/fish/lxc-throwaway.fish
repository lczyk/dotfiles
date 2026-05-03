function lxc-throwaway
    argparse h/help d/debug -- $argv

    function _help
        echo "Usage: lxc-throwaway <mode> <name> [<options>]"
        echo "Manage throwaway LXD containers."
        echo ""
        echo "Modes:"
        echo "  new <name> [<options>]   Create a new throwaway container with the specified name."
        echo "  which <name>             Show SSH access for throwaway containers with the specified name."
        echo "  clean                    Delete all throwaway containers."
        echo "  list                     List all throwaway containers."
        echo "  stop                     Stop all throwaway containers."
    end

    set __mode $argv[1]
    set __rest $argv[2..-1]

    switch $__mode
        case new
            __lxc_throwaway_new $__rest
            return $status
        case which
            __lxc_throwaway_which $__rest
            return $status
        case clean
            __lxc_throwaway_clean
            return $status
        case list
            __lxc_throwaway_list
            return $status
        case stop
            __lxc_throwaway_stop
            return $status
        case '*'
            _help
            return 1
    end
end

function __lxc_throwaway_new
    set -l name $argv[1]
    set -l rest $argv[2..-1]

    set -l allowed_names bionic focal jammy noble oracular plucky
    if not contains $name $allowed_names
        echo "Error: Invalid name '$name'. Allowed names are: $allowed_names"
        return 1
    end

    # FIND SSH key path from env variable
    if not set -q LXC_THROWAWAY_SSH_KEY_PATH
        echo "Error: LXC_THROWAWAY_SSH_KEY_PATH environment variable is not set. Please set it to the path of your SSH public key."
        return 1
    end
    if not test -f $LXC_THROWAWAY_SSH_KEY_PATH
        echo "Error: SSH key file '$LXC_THROWAWAY_SSH_KEY_PATH' does not exist. Please set the LXC_THROWAWAY_SSH_KEY_PATH environment variable to the path of your SSH public key."
        return 1
    end

    # make sure the file is a *.pub file
    if not string match -q '*.pub' $LXC_THROWAWAY_SSH_KEY_PATH
        echo "Error: SSH key file '$LXC_THROWAWAY_SSH_KEY_PATH' is not a valid public key file. Please set the LXC_THROWAWAY_SSH_KEY_PATH environment variable to the path of your SSH public key."
        return 1
    end

    if not set -q LXC_THROWAWAY_KNOWN_HOSTS_PATH
        echo "Error: LXC_THROWAWAY_KNOWN_HOSTS_PATH environment variable is not set. Please set it to the path of your known_hosts file."
        return 1
    end
    if not test -f $LXC_THROWAWAY_KNOWN_HOSTS_PATH
        echo "Error: Known hosts file '$LXC_THROWAWAY_KNOWN_HOSTS_PATH' does not exist. Please set the LXC_THROWAWAY_KNOWN_HOSTS_PATH environment variable to the path of your known_hosts file."
        return 1
    end

    # make a new container with a unique name
    set -l num 0
    set -l container_name throwaway-$name-(printf "%02d" $num)
    set -l present_names (lxc list -fcompact -cn | tail -n+2 | tr -d \[:blank:\])
    while contains $container_name $present_names
        set num (math $num + 1)
        set container_name throwaway-$name-(printf "%02d" $num)
        set -l present_names (lxc list -fcompact -cn | tail -n+2 | tr -d \[:blank:\])
    end

    echo "Creating throwaway container '$container_name'..."
    lxc launch ubuntu:$name $container_name $rest
    if test $status -ne 0
        echo "Error: Failed to create container '$container_name'."
        return 1
    end

    # wait for the container to be ready
    echo "Waiting for container '$container_name' to be ready..."
    lxc exec $container_name -- sh -c "while ! grep -q 'Startup finished' /var/log/syslog 2>/dev/null; do sleep 1; done"
    if test $status -ne 0
        echo "Error: Failed to wait for container '$container_name' to be ready."
        return 1
    end

    echo "Setting password for ubuntu user in $container_name"
    lxc exec $container_name -- bash -c 'yes ubuntu | passwd ubuntu' 1>/dev/null 2>&1
    if test $status -ne 0
        echo "Error: Failed to set password for 'ubuntu' user in container '$container_name'."
        return 1
    end

    echo "Adding SSH key to container '$container_name'"
    lxc exec $container_name -- mkdir -p /home/ubuntu/.ssh
    cat $LXC_THROWAWAY_SSH_KEY_PATH | lxc exec $container_name -- sh -c "cat >> /home/ubuntu/.ssh/authorized_keys"
    if test $status -ne 0
        echo "Error: Failed to add SSH key to container '$container_name'."
        return 1
    end

    echo "Installing Fish shell in container '$container_name' and setting it as default shell for 'ubuntu' user"
    lxc exec $container_name -- apt update 1>/dev/null 2>&1
    lxc exec $container_name -- apt upgrade -y 1>/dev/null 2>&1
    lxc exec $container_name -- apt install -y fish 1>/dev/null 2>&1
    lxc exec $container_name -- bash -c 'chsh ubuntu -s `which fish`'

    set -l container_ip (lxc list -fcompact -cn4 $container_name | tail -n+2 | tr -s \[:blank:\] | cut -d' ' -f3)

    # remove the container's IP from known_hosts if it exists
    ssh-keygen -f $LXC_THROWAWAY_KNOWN_HOSTS_PATH -R $container_ip 1>/dev/null 2>&1
    ssh-keyscan -H $container_ip >>$LXC_THROWAWAY_KNOWN_HOSTS_PATH
    # if test $status -ne 0

    echo "You can now SSH into the container '$container_name' using the command:"
    echo "ssh -i $LXC_THROWAWAY_SSH_KEY_PATH ubuntu@$container_ip"
    echo "ssh -i $LXC_THROWAWAY_SSH_KEY_PATH ubuntu@$container_ip" | fish_clipboard_copy
end

function __lxc_throwaway_which
    set -l name $argv[1]
    if not set -q name
        echo "Error: No name provided. Usage: lxc-throwaway which <name>"
        return 1
    end

    set -l throwaway_containers (lxc list -fcompact -cn | tail -n+2 | tr -d \[:blank:\] | string match -r '^throwaway-'$name'.*')
    if test (count $throwaway_containers) -eq 0
        echo "No throwaway containers found for name '$name'."
        return 1
    end

    echo "Throwaway containers for name '$name':"
    for container in $throwaway_containers
        set -l container_ip (lxc list -fcompact -cn4 $container | tail -n+2 | tr -s \[:blank:\] | cut -d' ' -f3)
        echo "$container ssh -i $LXC_THROWAWAY_SSH_KEY_PATH ubuntu@$container_ip"
    end
end

function __lxc_throwaway_list
    set -l throwaway_containers (lxc list -fcompact -cn | tail -n+2 | tr -d \[:blank:\] | string match -r '^throwaway-.*')
    for container in $throwaway_containers
        echo "$container"
    end
end

function __lxc_throwaway_clean
    set -l throwaway_containers (lxc list -fcompact -cn | tail -n+2 | tr -d \[:blank:\] | string match -r '^throwaway-.*')
    if test (count $throwaway_containers) -eq 0
        return 0
    end
    echo "Deleting $(count $throwaway_containers) throwaway containers."
    # clean up known_hosts file
    for container in $throwaway_containers
        set -l container_ip (lxc list -fcompact -cn4 $container | tail -n+2 | tr -s \[:blank:\] | cut -d' ' -f3)
        ssh-keygen -f $LXC_THROWAWAY_KNOWN_HOSTS_PATH -R $container_ip 1>/dev/null 2>&1
    end
    lxc delete $throwaway_containers --force
end

function __lxc_throwaway_stop
    set -l throwaway_containers (lxc list -fcompact -cn | tail -n+2 | tr -d \[:blank:\] | string match -r '^throwaway-.*')
    if test (count $throwaway_containers) -eq 0
        return 0
    end
    lxc stop $throwaway_containers &>/dev/null
end
