{{- define "terraform-installation" }}
# Skip installation
if [ "${SKIP_TERRAFORM_INSTALLATION,,}" == "true" ]; then
    exit 0
fi

if [ ! -d $Terraform__BinaryPath ]; then

    # Install Unzip
    apt-get update && apt-get install -y unzip wget

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
else
    echo "Terraform already installed."
fi

{{- end }}