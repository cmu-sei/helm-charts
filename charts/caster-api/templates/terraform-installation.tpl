{{- define "terraform-installation" }}
# Skip installation
if [ "${SKIP_TERRAFORM_INSTALLATION,,}" == "true" ]; then
    exit 0
fi

if [ ! -d $Terraform__BinaryPath ]; then

    # Install Unzip
    apt-get update && apt-get install -y unzip

    # Create Terraform directories
    mkdir -p "$Terraform__RootWorkingDirectory"
    mkdir -p "$Terraform__PluginDirectory"
    mkdir -p "$Terraform__BinaryPath"

    # Get current Terraform version
    TERRAFORM_VERSION=$(curl -s https://api.github.com/repos/hashicorp/terraform/releases/latest | jq -r .name)

    # Make Terraform version directory
    mkdir -p "$Terraform__BinaryPath/${TERRAFORM_VERSION:1}"
    mkdir -p "$Terraform__BinaryPath/${Terraform__DefaultVersion}"

    # Download and Unzip Terraform Latest
    cd "$Terraform__BinaryPath/${TERRAFORM_VERSION:1}"
    curl -s -O "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION:1}/terraform_${TERRAFORM_VERSION:1}_linux_amd64.zip"
    unzip "terraform_${TERRAFORM_VERSION:1}_linux_amd64.zip"
    rm "terraform_${TERRAFORM_VERSION:1}_linux_amd64.zip"

    # Download and Unzip Terraform Default Version
    cd "$Terraform__BinaryPath/${Terraform__DefaultVersion}"
    curl -s -O "https://releases.hashicorp.com/terraform/${Terraform__DefaultVersion}/terraform_${Terraform__DefaultVersion}_linux_amd64.zip"
    unzip "terraform_${Terraform__DefaultVersion}_linux_amd64.zip"
    rm "terraform_${Terraform__DefaultVersion}_linux_amd64.zip"

    # Install Terraform Random provider
    echo "Installing Terraform random provider..."
    mkdir -p "$Terraform__PluginDirectory/registry.terraform.io/hashicorp/random"
    cd "$Terraform__PluginDirectory/registry.terraform.io/hashicorp/random"
    curl -s -O https://releases.hashicorp.com/terraform-provider-random/2.3.0/terraform-provider-random_2.3.0_linux_amd64.zip
    mkdir -p "$Terraform__PluginDirectory/registry.terraform.io/-/random"
    cp "terraform-provider-random_2.3.0_linux_amd64.zip" "$Terraform__PluginDirectory/registry.terraform.io/-/random"
    echo "Done."

    # Install Terraform VSphere provider
    echo "Installing Terraform vsphere provider..."
    mkdir -p "$Terraform__PluginDirectory/registry.terraform.io/hashicorp/vsphere"
    cd "$Terraform__PluginDirectory/registry.terraform.io/hashicorp/vsphere"
    TERRAFORM_VSPHERE_VERSION=$(curl -s https://api.github.com/repos/hashicorp/terraform-provider-vsphere/releases/latest | jq -r .name)
    curl -s -O "https://releases.hashicorp.com/terraform-provider-vsphere/${TERRAFORM_VSPHERE_VERSION:1}/terraform-provider-vsphere_${TERRAFORM_VSPHERE_VERSION:1}_linux_amd64.zip"
    mkdir -p "$Terraform__PluginDirectory/registry.terraform.io/-/vsphere"
    cp "terraform-provider-vsphere_${TERRAFORM_VSPHERE_VERSION:1}_linux_amd64.zip" "$Terraform__PluginDirectory/registry.terraform.io/-/vsphere"
    echo "Done."

    # Install Terraform Crucible provider
    echo "Installing Terraform Crucible provider..."
    CRUCIBLE_PROVIDER_VERSION=$(curl -s "$CRUCIBLE_PROVIDER_DEPLOYMENT")
    mkdir -p "$Terraform__PluginDirectory/registry.terraform.io/-/crucible/$CRUCIBLE_PROVIDER_VERSION/linux_amd64"
    cd "$Terraform__PluginDirectory/registry.terraform.io/-/crucible/$CRUCIBLE_PROVIDER_VERSION/linux_amd64"
    curl -s -O "$CRUCIBLE_PROVIDER_DEPLOYMENT/linux_amd64/terraform-provider-crucible_$CRUCIBLE_PROVIDER_VERSION"
    mkdir -p "$Terraform__PluginDirectory/registry.terraform.local/sei/crucible/$CRUCIBLE_PROVIDER_VERSION/linux_amd64"
    cp "terraform-provider-crucible_$CRUCIBLE_PROVIDER_VERSION" "$Terraform__PluginDirectory/registry.terraform.local/sei/crucible/$CRUCIBLE_PROVIDER_VERSION/linux_amd64"
    echo "Done."
else
    echo "Terraform already installed."
fi

{{- end }}