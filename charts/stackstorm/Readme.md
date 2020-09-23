# Stackstorm for Crucible
[StackStorm](https://stackstorm.com/) is an open-source engine that can connect applications via actions. 
## Stackstorm for K8s 
The [StackStorm HA](https://docs.stackstorm.com/install/k8s_ha.html) Helm Chart is still considered in BETA, but is available for use now. This project uses the StackStorm HA in order to allow Crucible to perform actions against VMWare virtual machines.
## Implementation
The public Helm Chart should be used to install StackStorm HA via the [Installation Guide](https://docs.stackstorm.com/install/k8s_ha.html).  There are *a lot* of settings however, so this repository provides an **example.values.yaml** file to help get you started.

The **example.values.yaml** is not meant to be a replacement for reviewing all of hte values in the StackStorm Helm Chart, but rather to provide a minimal required subset of settings that must be configured to have StackStorm working correctly for Crucible use.

### Example Deployment
``` bash
helm repo add stackstorm https://helm.stackstorm.com/
helm pull --untar stackstorm/stackstorm-ha
```
- Edit the **Chart.yaml** to set the desired appVersion

``` bash
# Create custom values
cp stackstorm-ha/values.yaml stackstorm-ha/stackstorm-values.yaml
```
- Fill in stackstorm-values.yaml, using the provided **example.values.yaml** as a template

``` bash
helm install stackstorm stackstorm-ha -f stackstorm-ha/stackstorm-values.yaml --timeout 6000s
```
## Notes
### Helm Chart Version
The currently available Helm Charts all reference **dev** versions of StackStorm Docker containers.  Because these are unstable and the version of Python differs, it's recommended to run a **helm pull** to obtain the StackStorm Chart and customize the **appVersion** there.  In the examples given in this repository, _version 3.1.0_ is used because it's still on Python 2.

### Self-Signed VMWare Certificates
One of the major issues is the ability of this deployment to trust self-signed certificates.  There's at least two things that would need to be modified:

 1. Environment Variables need to be configured to be injected into at least st2api and st2actionrunner, so that Python can trust an arbitrary certificate bundle.

	At the time of this writing, [PR #120](https://github.com/StackStorm/stackstorm-ha/pull/120) is open to allow for environment variable injection.
 2. The deployment must allow for injection of custom certificates.

In the mean time, it's necessary for Crucible that the **vSphere pack** be configured with **ssl_verify: false**.
### Issues
 
 - Password characters, length and complexity are important when filling in the **values.yaml** file.  If the Helm Chart is not deploying properly, consider adjusting the password.  The public examples are a good start -- if they don't contain special characters, consider avoiding them in your implementation.