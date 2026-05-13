podman build --no-cache --rm --file Containerfile --tag loco:demo .
podman run --interactive --tty --publish 5150:5150 loco:demo
echo "browse http://localhost:5150/"
