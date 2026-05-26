podman build --no-cache --rm --file Containerfile.Bootstrap --tag loco:bootstrap .
podman run --interactive --tty --publish 5152:5150 loco:bootstrap
echo "browse http://localhost:5152/"
