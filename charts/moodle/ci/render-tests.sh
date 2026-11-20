#!/usr/bin/env bash
# Render tests for the Moodle chart: run from anywhere, needs helm and python3 with PyYAML.
set -u
CHART="$(cd "$(dirname "$0")/.." && pwd)"
BASE=(-f "$CHART/ci/default-values.yaml")
fail=0

render() { helm template t "$CHART" "${BASE[@]}" "$@" 2>&1; }
check() { # name, condition exit status
  if [ "$2" -eq 0 ]; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi
}
renders() { local name=$1; shift; render "$@" >/dev/null; check "$name" $?; }
rejects() { local name=$1 msg=$2; shift 2; local out; out=$(render "$@"); [ $? -ne 0 ] && grep -q -- "$msg" <<<"$out"; check "$name" $?; }
count() { grep -c -- "$1" <<<"$2"; }

SP=(--set systemPackages.enabled=true --set 'systemPackages.packages={ghostscript,icu-data-full}'
    --set 'systemPackages.paths={/usr/share/icu,/usr/share/ghostscript,/etc/fonts}')

# systemPackages
out=$(render); [ "$(count system-packages "$out")" = 0 ]; check "systemPackages disabled renders nothing" $?
out=$(render "${SP[@]}")
grep -q 'name: system-packages' <<<"$out" && grep -q 'LD_LIBRARY_PATH' <<<"$out" \
  && [ "$(count 'subPath: root/' "$out")" = 3 ]; check "systemPackages enabled renders init, env and one mount per path" $?
out=$(render --set 'systemPackages.packages={ghostscript}' --set 'systemPackages.paths={/tmp}'); [ $? -eq 0 ] && [ "$(count system-packages "$out")" = 0 ]
check "systemPackages disabled ignores its lists, so enabled=false is a kill switch" $?
rejects "systemPackages empty packages fails" "empty systemPackages.packages" --set systemPackages.enabled=true
rejects "systemPackages relative path fails" "not an absolute path" "${SP[@]}" --set 'systemPackages.paths={usr/share/icu}'
rejects "systemPackages code tree path fails" "lies where the chart mounts" "${SP[@]}" --set 'systemPackages.paths={/var/www/html/x}'
rejects "systemPackages duplicate path fails" "duplicates or nests" "${SP[@]}" --set 'systemPackages.paths={/etc/fonts,/etc/fonts}'
rejects "systemPackages path equal to mountPath fails" "duplicates or nests" "${SP[@]}" --set 'systemPackages.paths={/opt/system-packages}'
rejects "systemPackages bad package name fails" "not an Alpine package name" "${SP[@]}" --set 'systemPackages.packages={a;b}'
rejects "systemPackages LD_LIBRARY_PATH in extraEnvVars fails" "LD_LIBRARY_PATH" "${SP[@]}" \
  --set 'extraEnvVars[0].name=LD_LIBRARY_PATH' --set 'extraEnvVars[0].value=/x'

rejects "systemPackages moodledata path fails" "lies where the chart mounts" "${SP[@]}" --set 'systemPackages.paths={/var/www/moodledata}'
rejects "systemPackages dot component fails" "clean absolute path" "${SP[@]}" --set 'systemPackages.paths={/etc/fonts,/etc/./fonts}'
rejects "systemPackages /tmp fails" "need whole" "${SP[@]}" --set 'systemPackages.paths={/tmp}'
rejects "systemPackages php config path fails" "need whole" "${SP[@]}" --set 'systemPackages.paths={/etc/php83/conf.d}'
rejects "systemPackages other php version config path fails" "need whole" "${SP[@]}" --set 'systemPackages.paths={/etc/php84/conf.d}'
rejects "systemPackages nginx path fails" "need whole" "${SP[@]}" --set 'systemPackages.paths={/etc/nginx/conf.d}'
rejects "systemPackages chart config path fails" "lies where the chart mounts" "${SP[@]}" --set 'systemPackages.paths={/opt/sei/custom-scripts}'
rejects "systemPackages mountPath /usr/bin fails" "need whole" "${SP[@]}" --set systemPackages.mountPath=/usr/bin
rejects "systemPackages path over an extraVolumeMounts mount fails" "overlaps the mount" "${SP[@]}" \
  --set 'extraVolumeMounts[0].name=x' --set 'extraVolumeMounts[0].mountPath=/usr/share/ghostscript'
rejects "systemPackages bad repository fails" "not an http(s) URL" "${SP[@]}" --set 'systemPackages.repositories={ftp://x}'
rejects "systemPackages absolute repository path fails" "not an http(s) URL" "${SP[@]}" --set 'systemPackages.repositories={/mnt/mirror/main}'
rejects "systemPackages /var/run path fails" "need whole" "${SP[@]}" --set 'systemPackages.paths={/var/run}'
rejects "systemPackages path under /run fails" "need whole" "${SP[@]}" --set 'systemPackages.paths={/run/x}'
rejects "systemPackages path under /tmp fails" "need whole" "${SP[@]}" --set 'systemPackages.paths={/tmp/client_temp}'
rejects "systemPackages path over a string extraVolumeMounts mount fails" "overlaps the mount" "${SP[@]}" \
  --set-string 'extraVolumeMounts=- name: x
  mountPath: /usr/share/ghostscript'
renders "systemPackages with only dataPackages renders" --set systemPackages.enabled=true --set 'systemPackages.dataPackages={icu-data-full}' --set 'systemPackages.paths={/usr/share/icu}'
rejects "systemPackages with neither packages nor dataPackages fails" "empty systemPackages.packages and systemPackages.dataPackages" --set systemPackages.enabled=true
out=$(render "${SP[@]}" --set 'systemPackages.extraEnvVars[0].name=HTTPS_PROXY' --set 'systemPackages.extraEnvVars[0].value=http://p:3128' \
  --set 'systemPackages.repositories={https://m.example/alpine/v3.24/main}' --set systemPackages.sizeLimit=2Gi)
grep -q 'HTTPS_PROXY' <<<"$out" && grep -q '/etc/apk/repositories' <<<"$out" && grep -q 'sizeLimit: 2Gi' <<<"$out"
check "systemPackages extraEnvVars, repositories and sizeLimit render" $?
out=$(render "${SP[@]}"); grep -q 'sizeLimit: 1Gi' <<<"$out" && grep -q -- '- ALL' <<<"$out" && grep -q 'RuntimeDefault' <<<"$out"
check "systemPackages init container drops capabilities, sets seccomp and a size limit" $?

# an empty template in extraVolumeMounts, initContainers or sidecars must still render
EMPTY=$(mktemp)
printf '%s\n' 'extraVolumeMounts: |' '  {{- if .Values.foo }}' '  - name: x' '    mountPath: /x' '  {{- end }}' \
  'sidecars: |' '  {{- if .Values.foo }}' '  - name: s' '    image: busybox' '  {{- end }}' > "$EMPTY"
renders "empty extraVolumeMounts and sidecars templates render" -f "$EMPTY"
renders "empty templates render with systemPackages on" -f "$EMPTY" "${SP[@]}"
renders "empty templates render with a shared claim" -f "$EMPTY" --set persistence.moodle.enabled=true --set persistence.moodle.type=persistentVolumeClaim \
  --set persistence.moodle.existingClaim=shared --set persistence.moodle.subPath=a --set persistence.moodle.size=null --set persistence.moodle.storageClass=null \
  --set persistence.moodledata.type=persistentVolumeClaim --set persistence.moodledata.existingClaim=shared --set persistence.moodledata.subPath=b \
  --set persistence.moodledata.size=null --set persistence.moodledata.storageClass=null
rm -f "$EMPTY"

# progressDeadlineSeconds
out=$(render); [ "$(count progressDeadlineSeconds "$out")" = 0 ]; check "progressDeadlineSeconds unset renders no field" $?
out=$(render --set progressDeadlineSeconds=3900); grep -q 'progressDeadlineSeconds: 3900' <<<"$out"; check "progressDeadlineSeconds set renders" $?
rejects "progressDeadlineSeconds below probe budget fails" "default of 600" --set progressDeadlineSeconds=600
rejects "progressDeadlineSeconds equal to probe budget fails" "not above the startup probe" --set progressDeadlineSeconds=1200
renders "progressDeadlineSeconds above probe budget renders" --set progressDeadlineSeconds=1201

rejects "progressDeadlineSeconds below a custom startup probe fails" "not above the startup probe" --set progressDeadlineSeconds=3900 \
  --set customStartupProbe.periodSeconds=30 --set customStartupProbe.failureThreshold=200 --set customStartupProbe.httpGet.path=/ --set customStartupProbe.httpGet.port=8080
renders "progressDeadlineSeconds above a short custom startup probe renders" --set progressDeadlineSeconds=700 \
  --set customStartupProbe.periodSeconds=10 --set customStartupProbe.failureThreshold=60 --set customStartupProbe.httpGet.path=/ --set customStartupProbe.httpGet.port=8080

# one pod volume per claim; existingClaim refuses the creation settings the defaults carry
NOCREATE=()
for k in moodle moodledata; do NOCREATE+=(--set "persistence.$k.size=null" --set "persistence.$k.storageClass=null"); done
SHARED=(--set persistence.moodle.enabled=true --set persistence.moodle.type=persistentVolumeClaim
        --set persistence.moodle.existingClaim=shared --set persistence.moodle.subPath=moodlehtml
        --set persistence.moodledata.type=persistentVolumeClaim --set persistence.moodledata.existingClaim=shared
        --set persistence.moodledata.subPath=moodledata "${NOCREATE[@]}")
out=$(render "${SHARED[@]}")
vols=$(python3 -c '
import sys,yaml
d=[x for x in yaml.safe_load_all(sys.stdin) if x and x.get("kind")=="Deployment"][0]["spec"]["template"]["spec"]
pvc=[v["name"] for v in d["volumes"] if "persistentVolumeClaim" in v]
mounts=[(m["name"],m.get("subPath")) for c in d["containers"] for m in c["volumeMounts"] if m["name"] in pvc]
init=[(m["name"],m.get("subPath")) for c in d.get("initContainers",[]) if c["name"]=="volume-permissions" for m in c["volumeMounts"]]
print(len(pvc), sorted(set(s for _,s in mounts if s)), sorted(set(n for n,_ in mounts)), init)
' <<<"$out")
echo "     shared claim: $vols"
[[ "$vols" == "1 ['moodledata', 'moodlehtml'] ['moodledata'] [('moodledata', 'moodlehtml'), ('moodledata', 'moodledata')]" ]]; check "shared claim renders one volume, both subPaths, volume-permissions on the code subPath" $?
out=$(render --set persistence.moodle.enabled=true --set persistence.moodle.type=persistentVolumeClaim \
  --set persistence.moodle.existingClaim=code --set persistence.moodledata.type=persistentVolumeClaim \
  --set persistence.moodledata.existingClaim=data "${NOCREATE[@]}")
[ "$(count 'persistentVolumeClaim:' "$out")" = 2 ]; check "separate claims still render two volumes" $?
rejects "shared claim without subPaths fails" "sets no subPath" --set persistence.moodle.enabled=true \
  --set persistence.moodle.type=persistentVolumeClaim --set persistence.moodle.existingClaim=shared \
  --set persistence.moodledata.type=persistentVolumeClaim --set persistence.moodledata.existingClaim=shared "${NOCREATE[@]}"
rejects "shared claim with one key without a subPath fails" "sets no subPath" --set persistence.moodle.enabled=true \
  --set persistence.moodle.type=persistentVolumeClaim --set persistence.moodle.existingClaim=shared \
  --set persistence.moodledata.type=persistentVolumeClaim --set persistence.moodledata.existingClaim=shared --set persistence.moodledata.subPath=data "${NOCREATE[@]}"
rejects "shared claim with nested subPaths fails" "same as, or inside" --set persistence.moodle.enabled=true \
  --set persistence.moodle.type=persistentVolumeClaim --set persistence.moodle.existingClaim=shared --set persistence.moodle.subPath=data/html \
  --set persistence.moodledata.type=persistentVolumeClaim --set persistence.moodledata.existingClaim=shared --set persistence.moodledata.subPath=data "${NOCREATE[@]}"
rejects "shared claim with subPath . fails" "not a plain relative path" --set persistence.moodle.enabled=true \
  --set persistence.moodle.type=persistentVolumeClaim --set persistence.moodle.existingClaim=shared --set persistence.moodle.subPath=. \
  --set persistence.moodledata.type=persistentVolumeClaim --set persistence.moodledata.existingClaim=shared --set persistence.moodledata.subPath=data "${NOCREATE[@]}"
rejects "shared claim with a ./ subPath fails" "not a plain relative path" --set persistence.moodle.enabled=true \
  --set persistence.moodle.type=persistentVolumeClaim --set persistence.moodle.existingClaim=shared --set persistence.moodle.subPath=./html/uploads \
  --set persistence.moodledata.type=persistentVolumeClaim --set persistence.moodledata.existingClaim=shared --set persistence.moodledata.subPath=html "${NOCREATE[@]}"
out=$(render --set persistence.moodle.enabled=true --set persistence.moodle.type=persistentVolumeClaim --set persistence.moodle.existingClaim=shared --set persistence.moodle.subPath=html \
  --set persistence.plugincache.enabled=true --set persistence.plugincache.type=persistentVolumeClaim --set persistence.plugincache.existingClaim=shared --set persistence.plugincache.subPath=plugins \
  --set persistence.moodledata.type=emptyDir "${NOCREATE[@]}" --set persistence.plugincache.size=null --set persistence.plugincache.storageClass=null)
grep -q 'mountPath: /shared/plugincache' <<<"$out" && grep -q 'chown 65534:65534 /shared/plugincache' <<<"$out"
check "volume-permissions chowns the other key's directory when the shared volume is named moodle" $?
out=$(render --set persistence.moodledata.type=persistentVolumeClaim --set persistence.moodledata.existingClaim=shared --set persistence.moodledata.subPath=data \
  --set persistence.plugincache.enabled=true --set persistence.plugincache.type=persistentVolumeClaim --set persistence.plugincache.existingClaim=shared --set persistence.plugincache.subPath=plugins \
  "${NOCREATE[@]}" --set persistence.plugincache.size=null --set persistence.plugincache.storageClass=null)
grep -q 'name: volume-permissions' <<<"$out" && grep -q 'chown 65534:65534 /shared/moodledata' <<<"$out" && grep -q 'chown 65534:65534 /shared/plugincache' <<<"$out" && ! grep -q 'chown -R 65534:65534 /var/www/html' <<<"$out"
check "volume-permissions chowns every key's directory on a shared claim that does not include moodle" $?
out=$(render --set persistence.moodledata.type=persistentVolumeClaim --set persistence.moodledata.existingClaim=shared --set persistence.moodledata.subPath=data \
  --set persistence.plugincache.enabled=true --set persistence.plugincache.type=persistentVolumeClaim --set persistence.plugincache.existingClaim=shared --set persistence.plugincache.subPath=plugins \
  --set volumePermissions.enabled=false "${NOCREATE[@]}" --set persistence.plugincache.size=null --set persistence.plugincache.storageClass=null)
! grep -q 'name: volume-permissions' <<<"$out"; check "volumePermissions.enabled=false still turns the shared-claim chown off" $?
renders "a disabled readOnlyDirroot volume does not count as a claim" "${SHARED[@]}" --set readOnlyDirroot.volume.persistentVolumeClaim.claimName=shared
renders "shared claim with a dot-prefixed subPath renders" --set persistence.moodle.enabled=true \
  --set persistence.moodle.type=persistentVolumeClaim --set persistence.moodle.existingClaim=shared --set persistence.moodle.subPath=.moodle \
  --set persistence.moodledata.type=persistentVolumeClaim --set persistence.moodledata.existingClaim=shared --set persistence.moodledata.subPath=data "${NOCREATE[@]}"
rejects "shared claim with a .. subPath fails" "not a plain relative path" --set persistence.moodle.enabled=true \
  --set persistence.moodle.type=persistentVolumeClaim --set persistence.moodle.existingClaim=shared --set persistence.moodle.subPath=a/../b \
  --set persistence.moodledata.type=persistentVolumeClaim --set persistence.moodledata.existingClaim=shared --set persistence.moodledata.subPath=data "${NOCREATE[@]}"
rejects "extraVolumes on a persistence claim fails" "two volumes on one claim" "${SHARED[@]}" \
  --set 'extraVolumes[0].name=backup' --set 'extraVolumes[0].persistentVolumeClaim.claimName=shared'
out=$(render "${SHARED[@]}" --set 'extraVolumeMounts[0].name=moodle' --set 'extraVolumeMounts[0].mountPath=/x')
grep -A1 -- '- mountPath: /x' <<<"$out" | grep -q 'name: moodledata$' ; check "extraVolumeMounts naming a merged key follows the shared volume" $?

out=$(render "${SHARED[@]}" --set 'sidecars[0].name=side' --set 'sidecars[0].image=busybox' \
  --set 'sidecars[0].volumeMounts[0].name=moodle' --set 'sidecars[0].volumeMounts[0].mountPath=/c' \
  --set 'initContainers[0].name=pre' --set 'initContainers[0].image=busybox' \
  --set 'initContainers[0].volumeMounts[0].name=moodle' --set 'initContainers[0].volumeMounts[0].mountPath=/c')
python3 -c '
import sys,yaml
d=[x for x in yaml.safe_load_all(sys.stdin) if x and x.get("kind")=="Deployment"][0]["spec"]["template"]["spec"]
vols={v["name"] for v in d["volumes"]}
cs=d["containers"]+d.get("initContainers",[])
bad=[(c["name"],m["name"]) for c in cs for m in c.get("volumeMounts",[]) if m["name"] not in vols]
sys.exit(1 if bad or not any(c["name"] in ("side","pre") for c in cs) else 0)' <<<"$out"
check "every container mount, custom ones included, references an emitted volume" $?

exit $fail
