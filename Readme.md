# CMU SEI Helm Charts

Helm charts for deploying CMU Software Engineering Institute applications to Kubernetes.

All charts are designed for use with **Helm 3**.

## Repository

Add this Helm repository:

```bash
helm repo add sei https://helm.cmusei.dev/charts
helm repo update
```

## Quick Start

```bash
# View available charts
helm search repo sei

# Show default values for a chart
helm show values sei/identity > identity.values.yaml

# Edit values as needed
vim identity.values.yaml

# Deploy the chart
helm install my-identity sei/identity -f identity.values.yaml

# Upgrade an existing deployment
helm upgrade my-identity sei/identity -f identity.values.yaml
```

## Available Charts

### Crucible Applications

The [Crucible](https://cmu-sei.github.io/crucible/) project provides a framework for creating, deploying, and managing virtual training environments.

| Chart | Description | Documentation |
|-------|-------------|---------------|
| [identity](charts/identity/) | OAuth2/OIDC identity provider for authentication | [README](charts/identity/README.md) |
| [player](charts/player/) | Virtual environment collaboration platform | [README](charts/player/README.md) |
| [alloy](charts/alloy/) | Event orchestration and simulation launcher | [README](charts/alloy/README.md) |
| [caster](charts/caster/) | Infrastructure-as-code deployment with Terraform/OpenTofu | [README](charts/caster/README.md) |
| [steamfitter](charts/steamfitter/) | Scenario automation with StackStorm integration | [README](charts/steamfitter/README.md) |
| [topomojo](charts/topomojo/) | Virtual machine lab environment manager | [README](charts/topomojo/README.md) |
| [gameboard](charts/gameboard/) | Cybersecurity game design and competition platform | [README](charts/gameboard/README.md) |
| [blueprint](charts/blueprint/) | Master Scenario Event List (MSEL) planning | [README](charts/blueprint/README.md) |
| [gallery](charts/gallery/) | Exercise information and incident data sharing | [README](charts/gallery/README.md) |
| [cite](charts/cite/) | Collaborative Incident Threat Evaluator | [README](charts/cite/README.md) |

### Supporting Applications

| Chart | Description |
|-------|-------------|
| [appmailrelay](charts/appmailrelay/) | Email relay service for applications |
| [stackstorm](charts/stackstorm/) | Event-driven automation platform |

### Additional Applications

| Chart | Description |
|-------|-------------|
| [authhoc](charts/authhoc/) | Authentication and authorization service |
| [buckets](charts/buckets/) | Object storage management |
| [code-server](charts/code-server/) | VS Code in the browser |
| [cubescore](charts/cubescore/) | Scoring engine |
| [cubespace-client](charts/cubespace-client/) | Cubespace client application |
| [cubespace-server](charts/cubespace-server/) | Cubespace server application |
| [gamebrain](charts/gamebrain/) | Game engine component |
| [gameengine](charts/gameengine/) | Game execution engine |
| [groups](charts/groups/) | Group management service |
| [jarchive](charts/jarchive/) | Archive management |
| [learninglocker](charts/learninglocker/) | Learning Record Store (LRS) |
| [lrsql](charts/lrsql/) | SQL-based Learning Record Store |
| [market](charts/market/) | Marketplace application |
| [mattermost-team-edition](charts/mattermost-team-edition/) | Team collaboration platform |
| [mkdocs-material](charts/mkdocs-material/) | Documentation site generator |
| [osticket](charts/osticket/) | Support ticket system |
| [statesman](charts/statesman/) | State management service |
| [staticweb](charts/staticweb/) | Static website hosting |
| [webmail](charts/webmail/) | Web-based email client |

## Deployment Patterns

### Typical Crucible Stack

A complete Crucible environment typically includes:

1. **Identity** - Authentication provider
2. **Player** - Core platform (includes VM API)
3. **TopoMojo** OR **Gameboard** - Lab/game engine
4. **Alloy** - Event orchestration (optional)
5. **Caster** - Infrastructure deployment (optional)
6. **Steamfitter** - Automation (optional)
7. **Blueprint** - Exercise planning (optional)
8. **Gallery** - Information sharing (optional)
9. **CITE** - Incident evaluation (optional)

### Infrastructure Requirements

- **PostgreSQL**: One database per application (or separate instances)
- **GitLab**: Required for Caster (Terraform state storage)
- **StackStorm**: Required for Steamfitter
- **vSphere/Proxmox**: Required for TopoMojo, Player VM API, Caster
- **Redis**: Recommended for multi-replica deployments
- **NFS**: Recommended for ISO storage and shared files

### Service Integration

Many Crucible applications integrate with each other:

```
Identity ──┬──> Player ──> VM API ──> vSphere
           ├──> TopoMojo ──> vSphere
           ├──> Gameboard ──> TopoMojo
           ├──> Alloy ──┬──> Player
           │            ├──> Caster ──> vSphere/Azure
           │            └──> Steamfitter ──> StackStorm
           └──> Caster
```

## License

Charts are provided by the Carnegie Mellon University Software Engineering Institute.

For specific licensing information, refer to individual application repositories.
