#!/usr/bin/env bash
# Runs the system-packages init script, as the chart renders it, on the real Moodle image under
# Docker with the init container's capabilities, and checks the paths that matter: install,
# fallback to the image's files, required=true, a package the install upgrades, and a path that is
# a file. Needs docker, helm and python3 with PyYAML, and the Alpine mirror. Not run in CI.
set -u
CHART="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${IMAGE:-erseco/alpine-moodle:v5.2.4}"
command -v docker >/dev/null && docker info >/dev/null 2>&1 || { echo "skip: docker is not available"; exit 0; }
WORK=$(mktemp -d); trap 'rm -rf "$WORK"; docker volume rm -f sp-test-vol >/dev/null 2>&1' EXIT
fail=0
check() { if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }

render() { # extra helm args -> script on stdout
  helm template t "$CHART" -f "$CHART/ci/default-values.yaml" --set systemPackages.enabled=true \
    --set 'systemPackages.paths={/usr/share/icu,/usr/share/ghostscript,/usr/share/fontconfig,/etc/fonts}' "$@" |
  python3 -c "
import yaml,sys
d=[x for x in yaml.safe_load_all(sys.stdin) if x and x.get('kind')=='Deployment'][0]
print([c for c in d['spec']['template']['spec']['initContainers'] if c['name']=='system-packages'][0]['args'][0])"
}
run() { # script file -> exit code; volume sp-test-vol holds /pkgroot
  docker volume rm -f sp-test-vol >/dev/null; docker volume create sp-test-vol >/dev/null
  docker run --rm --user 0 --cap-drop ALL --cap-add CHOWN --cap-add DAC_OVERRIDE --cap-add FOWNER \
    --cap-add FSETID --cap-add SETFCAP --security-opt no-new-privileges --entrypoint sh \
    -v sp-test-vol:/pkgroot -v "$1":/init.sh:ro "$IMAGE" /init.sh >"$1.log" 2>&1
}
vol() { docker run --rm --entrypoint sh -v sp-test-vol:/p:ro "$IMAGE" -c "$1"; }

render --set 'systemPackages.packages={ghostscript,icu-data-full}' > "$WORK/good.sh"
run "$WORK/good.sh"; check "install succeeds" $?
vol 'test -x /p/bin/gs && test -d /p/root/usr/share/icu && ! test -e /p/.orig'; check "install exports gs and the icu path, and removes the pristine copy" $?

render --set 'systemPackages.packages={no-such-pkg-xyz}' > "$WORK/bad.sh"
run "$WORK/bad.sh"; check "bogus package with required=false exits 0" $?
vol 'test -f /p/root/usr/share/icu/*/icudt*.dat && ! test -e /p/bin/gs && ! test -e /p/.orig'; check "fallback leaves the image's own icu data and no gs" $?

render --set 'systemPackages.packages={no-such-pkg-xyz}' --set systemPackages.required=true > "$WORK/req.sh"
run "$WORK/req.sh"; [ $? -ne 0 ]; check "bogus package with required=true fails" $?

# a failure after the install, in the export step, must also fall back
sed 's#^comm -13 /tmp/before.v /tmp/after.v | sed#false; comm -13 /tmp/before.v /tmp/after.v | sed#' "$WORK/good.sh" > "$WORK/post.sh"
grep -q '^ *false; comm' "$WORK/post.sh"; check "post-install failure script was built" $?
run "$WORK/post.sh"; check "failure after the install exits 0 with required=false" $?
vol 'test -f /p/root/usr/share/icu/*/icudt*.dat && ! test -e /p/bin/gs && ! test -e /p/.orig'; check "failure after the install restores the image's files" $?

# an image package the install upgrades must be refused
sed 's#^apk info -v | sort > /tmp/before.v#apk info -v | sort | sed "s/^busybox-1.*/busybox-0.9-r0/" > /tmp/before.v#' "$WORK/good.sh" > "$WORK/upg.sh"
run "$WORK/upg.sh"; grep -q "upgraded packages the image already has" "$WORK/upg.sh.log"; check "an upgraded image package is detected" $?
vol '! test -e /p/bin/gs'; check "an upgraded image package triggers the fallback" $?

render --set 'systemPackages.packages={ghostscript}' --set 'systemPackages.paths={/etc/hostname}' > "$WORK/file.sh"
run "$WORK/file.sh"; [ $? -ne 0 ] && grep -q "is a file in the image" "$WORK/file.sh.log"; check "a path that is a file in the image is refused" $?

exit $fail
