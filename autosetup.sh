#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly REPOSITORY_URL="https://github.com/gosaad/gosaad-releases.git"
readonly RAW_BASE_URL="https://raw.githubusercontent.com/gosaad/gosaad-releases/main"

SCRIPT_DIR=""
DEPLOY_DIR=""
ENV_FILE=""
ENV_TEMPLATE=""
PLATFORM=""
LINUX_FAMILY=""
TEMP_ENV_FILE=""

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "$TEMP_ENV_FILE" && -f "$TEMP_ENV_FILE" ]]; then
    rm -f "$TEMP_ENV_FILE"
  fi
}

trap cleanup EXIT

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

run_privileged() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
    return
  fi

  command_exists sudo || die "sudo is required to install and configure Docker."
  sudo "$@"
}

ask_yes_no() {
  local prompt="$1"
  local answer=""

  while true; do
    if [[ -t 0 ]]; then
      read -r -p "$prompt [y/N]: " answer
    elif [[ -r /dev/tty ]]; then
      read -r -p "$prompt [y/N]: " answer < /dev/tty
    else
      die "Interactive input is required for this decision, but no terminal is available: $prompt"
    fi

    case "$answer" in
      y|Y|yes|Yes|YES)
        return 0
        ;;
      n|N|no|No|NO|'')
        return 1
        ;;
      *)
        log "Please answer yes or no."
        ;;
    esac
  done
}

print_help() {
  cat <<'EOF'
Usage: bash autosetup.sh [OPTION]

Install Docker and Docker Compose when needed, generate .env, and optionally
start the local GoSAAD deployment.

Options:
  -h, --help  Show this help message and exit.
  --automatic Generate .env without prompting when it does not exist, ask before
              replacing an existing .env, and then start the deployment.
  --env-only  Generate or replace .env without checking Docker or starting
              the deployment.

APP_VERSION is copied from the existing .env when it exists, or from
.env.example on first installation. This installer never changes it.
EOF
}

detect_platform() {
  local kernel_name=""
  local kernel_release=""

  kernel_name="$(uname -s)"
  case "$kernel_name" in
    MINGW*|MSYS*|CYGWIN*)
      die "Windows Bash environments are not supported. Run this installer on Linux, macOS, or WSL with Docker Desktop integration."
      ;;
    Darwin)
      PLATFORM="macos"
      return
      ;;
    Linux)
      kernel_release="$(uname -r)"
      if grep -qiE '(microsoft|wsl)' <<<"$kernel_release" || { [[ -r /proc/version ]] && grep -qiE '(microsoft|wsl)' /proc/version; }; then
        PLATFORM="wsl"
        return
      fi
      detect_linux_family
      PLATFORM="linux"
      return
      ;;
    *)
      die "Unsupported operating system: $kernel_name."
      ;;
  esac
}

detect_linux_family() {
  local os_id=""
  local os_id_like=""

  [[ -r /etc/os-release ]] || die "Cannot identify this Linux distribution because /etc/os-release is unavailable."
  # shellcheck disable=SC1091
  . /etc/os-release
  os_id="$ID"
  os_id_like="${ID_LIKE:-}"

  case "$os_id $os_id_like" in
    *debian*|*ubuntu*)
      LINUX_FAMILY="apt"
      ;;
    *fedora*|*rhel*|*centos*|*rocky*|*almalinux*)
      LINUX_FAMILY="dnf"
      ;;
    *)
      die "Unsupported Linux distribution: $os_id. Supported distributions are Debian/Ubuntu and Fedora/RHEL."
      ;;
  esac
}

configure_apt_repository() {
  local docker_os=""
  local codename=""
  local architecture=""

  # shellcheck disable=SC1091
  . /etc/os-release
  case "$ID" in
    ubuntu)
      docker_os="ubuntu"
      codename="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
      ;;
    debian)
      docker_os="debian"
      codename="$VERSION_CODENAME"
      ;;
    *)
      die "Docker's apt repository is not configured for distribution ID: $ID."
      ;;
  esac
  architecture="$(dpkg --print-architecture)"

  run_privileged apt-get update
  run_privileged apt-get install -y ca-certificates curl
  run_privileged install -m 0755 -d /etc/apt/keyrings
  run_privileged curl -fsSL "https://download.docker.com/linux/$docker_os/gpg" -o /etc/apt/keyrings/docker.asc
  run_privileged chmod a+r /etc/apt/keyrings/docker.asc
  printf 'Types: deb\nURIs: https://download.docker.com/linux/%s\nSuites: %s\nComponents: stable\nArchitectures: %s\nSigned-By: /etc/apt/keyrings/docker.asc\n' \
    "$docker_os" "$codename" "$architecture" | run_privileged tee /etc/apt/sources.list.d/docker.sources >/dev/null
  run_privileged apt-get update
}

configure_dnf_repository() {
  local docker_os=""

  # shellcheck disable=SC1091
  . /etc/os-release
  case "$ID" in
    fedora)
      docker_os="fedora"
      ;;
    rhel|centos|rocky|almalinux)
      docker_os="rhel"
      ;;
    *)
      die "Docker's RPM repository is not configured for distribution ID: $ID."
      ;;
  esac

  run_privileged dnf install -y dnf-plugins-core
  run_privileged dnf config-manager addrepo --from-repofile "https://download.docker.com/linux/$docker_os/docker-ce.repo"
}

install_linux_docker() {
  case "$LINUX_FAMILY" in
    apt)
      configure_apt_repository
      run_privileged apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    dnf)
      configure_dnf_repository
      run_privileged dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      ;;
    *)
      die "Unsupported Linux package family: $LINUX_FAMILY."
      ;;
  esac

  command_exists systemctl || die "Docker was installed, but systemctl is unavailable to start the Docker service. Start Docker manually, then rerun this installer."
  run_privileged systemctl enable --now docker
}

ensure_current_user_docker_access() {
  local current_user=""

  current_user="$(id -un)"
  if id -nG "$current_user" | tr ' ' '\n' | grep -Fxq docker; then
    die "Docker is available only through elevated privileges in this shell. Sign out and sign back in so your docker-group membership is refreshed, then rerun this installer."
  fi

  log "Adding $current_user to the docker group. This grants root-equivalent access through the Docker daemon."
  run_privileged usermod -aG docker "$current_user"
  die "Docker group membership was updated. Sign out and sign back in, then rerun this installer."
}

ensure_docker_access() {
  if docker info >/dev/null 2>&1; then
    return
  fi

  if run_privileged docker info >/dev/null 2>&1; then
    ensure_current_user_docker_access
  fi

  die "Docker is installed but its daemon is unavailable. Start Docker and rerun this installer."
}

install_macos_docker() {
  command_exists brew || die "Docker Desktop must be installed through Homebrew on macOS. Install Homebrew and rerun this installer."
  brew install --cask docker
  open -a Docker || die "Docker Desktop was installed but could not be started. Start Docker Desktop manually, then rerun this installer."
  die "Docker Desktop is starting. Wait until it reports that Docker is running, then rerun this installer."
}

ensure_docker() {
  if command_exists docker; then
    case "$PLATFORM" in
      wsl)
        docker info >/dev/null 2>&1 || die "Docker Desktop integration is unavailable in WSL. Start Docker Desktop, enable this WSL distribution in its settings, and rerun this installer."
        return
        ;;
      macos)
        if docker info >/dev/null 2>&1; then
          return
        fi
        open -a Docker || die "Docker is installed but Docker Desktop could not be started. Start it manually, then rerun this installer."
        die "Docker Desktop is starting. Wait until it is running, then rerun this installer."
        ;;
      linux)
        if docker info >/dev/null 2>&1; then
          return
        fi
        if command_exists systemctl; then
          run_privileged systemctl start docker
        fi
        ensure_docker_access
        return
        ;;
      *)
        die "Unsupported platform state: $PLATFORM."
        ;;
    esac
  fi

  case "$PLATFORM" in
    wsl)
      die "Docker is not available in WSL. Install and start Docker Desktop on Windows, enable this WSL distribution, and rerun this installer."
      ;;
    macos)
      install_macos_docker
      ;;
    linux)
      install_linux_docker
      ensure_docker_access
      ;;
    *)
      die "Unsupported platform state: $PLATFORM."
      ;;
  esac
}

install_linux_compose_plugin() {
  case "$LINUX_FAMILY" in
    apt)
      configure_apt_repository
      run_privileged apt-get install -y docker-compose-plugin
      ;;
    dnf)
      configure_dnf_repository
      run_privileged dnf install -y docker-compose-plugin
      ;;
    *)
      die "Unsupported Linux package family: $LINUX_FAMILY."
      ;;
  esac
}

ensure_compose() {
  if docker compose version >/dev/null 2>&1; then
    return
  fi

  case "$PLATFORM" in
    wsl)
      die "Docker Compose is unavailable in WSL. Enable Docker Desktop WSL integration and rerun this installer."
      ;;
    macos)
      command_exists brew || die "Docker Compose is unavailable. Update or reinstall Docker Desktop, start it, and rerun this installer."
      brew reinstall --cask docker
      open -a Docker || die "Docker Desktop was reinstalled but could not be started. Start it manually, then rerun this installer."
      die "Docker Desktop was reinstalled and is starting. Wait until it is running, then rerun this installer."
      ;;
    linux)
      install_linux_compose_plugin
      docker compose version >/dev/null 2>&1 || die "Docker Compose plugin installation completed but 'docker compose' is still unavailable."
      ;;
    *)
      die "Unsupported platform state: $PLATFORM."
      ;;
  esac
}

resolve_deploy_directory() {
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  if [[ -f "$SCRIPT_DIR/docker-compose.yml" && -f "$SCRIPT_DIR/.env.example" ]]; then
    DEPLOY_DIR="$SCRIPT_DIR"
  else
    DEPLOY_DIR="$(pwd -P)/gosaad-releases"
  fi
  ENV_FILE="$DEPLOY_DIR/.env"
  ENV_TEMPLATE="$DEPLOY_DIR/.env.example"
}

download_file() {
  local url="$1"
  local destination="$2"
  local temporary_file=""

  temporary_file="$(mktemp "$DEPLOY_DIR/.download.XXXXXX")"
  if command_exists curl; then
    if ! curl --fail --location --silent --show-error "$url" --output "$temporary_file"; then
      rm -f "$temporary_file"
      die "Failed to download $url."
    fi
  elif command_exists wget; then
    if ! wget --quiet --output-document="$temporary_file" "$url"; then
      rm -f "$temporary_file"
      die "Failed to download $url."
    fi
  else
    rm -f "$temporary_file"
    die "Git is unavailable and neither curl nor wget is installed, so release files cannot be downloaded."
  fi

  mv "$temporary_file" "$destination"
}

ensure_deployment_files() {
  if [[ -d "$DEPLOY_DIR" ]]; then
    [[ -f "$DEPLOY_DIR/docker-compose.yml" && -f "$ENV_TEMPLATE" ]] || die "Deployment directory exists but is missing docker-compose.yml or .env.example: $DEPLOY_DIR"
    return
  fi

  if command_exists git; then
    git clone "$REPOSITORY_URL" "$DEPLOY_DIR"
  else
    mkdir -p "$DEPLOY_DIR"
    download_file "$RAW_BASE_URL/docker-compose.yml" "$DEPLOY_DIR/docker-compose.yml"
    download_file "$RAW_BASE_URL/.env.example" "$ENV_TEMPLATE"
  fi

  [[ -f "$DEPLOY_DIR/docker-compose.yml" && -f "$ENV_TEMPLATE" ]] || die "Release files were not created successfully in $DEPLOY_DIR."
}

generate_secret() {
  local secret=""

  command_exists openssl || die "openssl is required to generate secure environment secrets. Install openssl and rerun this installer."
  secret="$(openssl rand -hex 32)"
  [[ "$secret" =~ ^[0-9a-f]{64}$ ]] || die "openssl produced an invalid secret."
  printf '%s' "$secret"
}

read_app_version() {
  local source_file="$1"
  local line=""
  local app_version=""
  local matches=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      APP_VERSION=*)
        app_version="${line#APP_VERSION=}"
        matches=$((matches + 1))
        ;;
    esac
  done < "$source_file"

  [[ "$matches" -eq 1 ]] || die "Expected exactly one APP_VERSION entry in $source_file, found $matches."
  [[ "$app_version" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "APP_VERSION in $source_file is empty or invalid: $app_version"
  printf '%s' "$app_version"
}

resolve_app_version() {
  if [[ -f "$ENV_FILE" ]]; then
    read_app_version "$ENV_FILE"
    return
  fi

  read_app_version "$ENV_TEMPLATE"
}

write_generated_env() {
  local postgres_password="$1"
  local app_db_password="$2"
  local jwt_secret="$3"
  local jwt_refresh_secret="$4"
  local app_version="$5"
  local line=""
  local app_version_found=0
  local postgres_found=0
  local app_db_found=0
  local jwt_found=0
  local jwt_refresh_found=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      APP_VERSION=*)
        printf 'APP_VERSION=%s\n' "$app_version" >> "$TEMP_ENV_FILE"
        app_version_found=1
        ;;
      POSTGRES_PASSWORD=*)
        printf 'POSTGRES_PASSWORD=%s\n' "$postgres_password" >> "$TEMP_ENV_FILE"
        postgres_found=1
        ;;
      APP_DB_PASSWORD=*)
        printf 'APP_DB_PASSWORD=%s\n' "$app_db_password" >> "$TEMP_ENV_FILE"
        app_db_found=1
        ;;
      JWT_SECRET=*)
        printf 'JWT_SECRET=%s\n' "$jwt_secret" >> "$TEMP_ENV_FILE"
        jwt_found=1
        ;;
      JWT_REFRESH_SECRET=*)
        printf 'JWT_REFRESH_SECRET=%s\n' "$jwt_refresh_secret" >> "$TEMP_ENV_FILE"
        jwt_refresh_found=1
        ;;
      *)
        printf '%s\n' "$line" >> "$TEMP_ENV_FILE"
        ;;
    esac
  done < "$ENV_TEMPLATE"

  [[ "$app_version_found" -eq 1 ]] || die ".env.example is missing APP_VERSION."
  [[ "$postgres_found" -eq 1 ]] || die ".env.example is missing POSTGRES_PASSWORD."
  [[ "$app_db_found" -eq 1 ]] || die ".env.example is missing APP_DB_PASSWORD."
  [[ "$jwt_found" -eq 1 ]] || die ".env.example is missing JWT_SECRET."
  [[ "$jwt_refresh_found" -eq 1 ]] || die ".env.example is missing JWT_REFRESH_SECRET."
}

backup_timestamp() {
  if [[ "$PLATFORM" == "macos" ]]; then
    command_exists perl || die "Perl is required to create a millisecond-resolution backup filename on macOS. Install Perl and rerun this installer."
    perl -MTime::HiRes=time -MPOSIX=strftime -e '$time = time; printf "%s-%03d", strftime("%d-%m-%y-%H-%M-%S", localtime($time)), int(($time - int($time)) * 1000);'
    return
  fi

  date '+%d-%m-%y-%H-%M-%S-%3N'
}

generate_env() {
  local app_version=""
  local postgres_password=""
  local app_db_password=""
  local jwt_secret=""
  local jwt_refresh_secret=""
  local backup_file=""
  local timestamp=""

  if [[ -f "$ENV_FILE" ]] && ! ask_yes_no "A .env file already exists. Override it?"; then
    log "Keeping the existing .env file."
    return
  fi

  app_version="$(resolve_app_version)"
  postgres_password="$(generate_secret)"
  app_db_password="$(generate_secret)"
  jwt_secret="$(generate_secret)"
  jwt_refresh_secret="$(generate_secret)"

  umask 077
  TEMP_ENV_FILE="$(mktemp "$DEPLOY_DIR/.env.generated.XXXXXX")"
  write_generated_env "$postgres_password" "$app_db_password" "$jwt_secret" "$jwt_refresh_secret" "$app_version"

  if [[ -f "$ENV_FILE" ]]; then
    timestamp="$(backup_timestamp)"
    backup_file="$DEPLOY_DIR/.env.backup-$timestamp"
    [[ ! -e "$backup_file" ]] || die "Backup file already exists: $backup_file. No changes were made; try again."
    mv "$ENV_FILE" "$backup_file"
  fi

  mv "$TEMP_ENV_FILE" "$ENV_FILE"
  TEMP_ENV_FILE=""
  log "Generated $ENV_FILE while preserving APP_VERSION=$app_version."
}

start_deployment() {
  [[ -f "$ENV_FILE" ]] || die "Cannot start GoSAAD because .env is missing. Generate it, then rerun this installer."
  (
    cd "$DEPLOY_DIR"
    docker compose up -d
    docker compose ps
  )
}

main() {
  local automatic=0
  local env_only=0

  case "$#" in
    0)
      ;;
    1)
      case "$1" in
        -h|--help)
          print_help
          return
          ;;
        --automatic)
          automatic=1
          ;;
        --env-only)
          env_only=1
          ;;
        *)
          die "Unsupported option: $1. Run 'bash autosetup.sh --help' for usage."
          ;;
      esac
      ;;
    *)
      die "Expected at most one option. Run 'bash autosetup.sh --help' for usage."
      ;;
  esac

  detect_platform
  resolve_deploy_directory

  if [[ "$env_only" -eq 1 ]]; then
    ensure_deployment_files
    generate_env
    return
  fi

  ensure_docker
  ensure_compose
  ensure_deployment_files

  if [[ "$automatic" -eq 1 ]]; then
    generate_env
    start_deployment
    return
  fi

  if ask_yes_no "Do you want to generate the .env file now?"; then
    generate_env
  fi

  if ask_yes_no "Do you want to start GoSAAD now?"; then
    start_deployment
  else
    log "Run this later from $DEPLOY_DIR: docker compose up -d"
  fi
}

main "$@"
