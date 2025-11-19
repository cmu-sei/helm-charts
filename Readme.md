# Helm at cmu-sei

Helm charts for deploying CMU Software Engineering Institute applications to Kubernetes.

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
helm show values sei/topomojo > topomojo.values.yaml

# Edit values as needed
vim topomojo.values.yaml

# Deploy the chart
helm install topomojo sei/topomojo -f topomojo.values.yaml

# Upgrade an existing deployment
helm upgrade topomojo sei/topomojo -f topomojo.values.yaml
```

## Available Charts

### Crucible Applications

The [Crucible](https://cmu-sei.github.io/crucible/) project provides a framework for creating, deploying, and managing virtual training environments.

| Chart | Description | Documentation |
|-------|-------------|---------------|
| [player](charts/player/) | Virtual environment collaboration platform | [README](charts/player/README.md) |
| [alloy](charts/alloy/) | Event orchestration and simulation launcher | [README](charts/alloy/README.md) |
| [caster](charts/caster/) | Infrastructure-as-code deployment with Terraform/OpenTofu | [README](charts/caster/README.md) |
| [steamfitter](charts/steamfitter/) | Scenario automation with StackStorm integration | [README](charts/steamfitter/README.md) |
| [topomojo](charts/topomojo/) | Virtual machine lab environment manager | [README](charts/topomojo/README.md) |
| [gameboard](charts/gameboard/) | Cybersecurity game design and competition platform | [README](charts/gameboard/README.md) |
| [blueprint](charts/blueprint/) | Master Scenario Event List (MSEL) planning | [README](charts/blueprint/README.md) |
| [gallery](charts/gallery/) | Exercise information and incident data sharing | [README](charts/gallery/README.md) |
| [cite](charts/cite/) | Collaborative Incident Threat Evaluator | [README](charts/cite/README.md) |

### Additional Applications

| Chart | Description |
|-------|-------------|
| [authhoc](charts/authhoc/) | Authentication and authorization service |
| [appmailrelay](charts/appmailrelay/) | Email relay service for applications |
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
| [stackstorm](charts/stackstorm/) | Event-driven automation platform |
| [statesman](charts/statesman/) | State management service |
| [staticweb](charts/staticweb/) | Static website hosting |
| [webmail](charts/webmail/) | Web-based email client |
