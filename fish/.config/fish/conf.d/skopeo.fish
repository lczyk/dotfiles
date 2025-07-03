if type -q skopeo
    skopeo completion fish | source

    # fish function to copy OCI images to Docker daemon
    # for example: skopeo-copy-rock ubuntu_24.04 
    function skopeo-copy-rock
        set _short_name (echo $argv[1] | cut -d_ -f1)
        set _short_version (echo $argv[1] | cut -d_ -f2)
        set _trail (echo $argv[1] | cut -d_ -f3-)
        # make sure the trail ends with .rock
        if not string match -q '*.*' $_trail
            echo "Error: The third part of the image name must end with .rock"
            return 1
        end
        rockcraft.skopeo --insecure-policy copy oci-archive:$argv[1] docker-daemon:$_short_name:$_short_version
    end
end