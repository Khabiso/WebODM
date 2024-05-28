#!/bin/bash
set -eo pipefail
__dirname=$(cd "$(dirname "$0")"; pwd -P)
cd "${__dirname}"

platform="Linux" # Assumed
uname=$(uname)
case $uname in
    "Darwin")
    platform="MacOS / OSX"
    ;;
    MINGW*)
    platform="Windows"
    ;;
esac

if [[ $platform = "Windows" ]]; then
    export COMPOSE_CONVERT_WINDOWS_PATHS=1
fi

dev_mode=false
gpu=false
clusterodm=false  # Flag to enable/disable ClusterODM

# define realpath replacement function
if [[ $platform = "MacOS / OSX" ]]; then
    realpath() {
        [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
    }
fi

# Load default values
source "${__dirname}/.env"
DEFAULT_PORT="$WO_PORT"
DEFAULT_HOST="$WO_HOST"
DEFAULT_MEDIA_DIR="$WO_MEDIA_DIR"
DEFAULT_DB_DIR="$WO_DB_DIR"
DEFAULT_SSL="$WO_SSL"
DEFAULT_SSL_INSECURE_PORT_REDIRECT="$WO_SSL_INSECURE_PORT_REDIRECT"
DEFAULT_BROKER="$WO_BROKER"
DEFAULT_NODES="$WO_DEFAULT_NODES"
DEFAULT_CLUSTER_NODES=2  # Default number of ClusterODM nodes

# Parse args for overrides
POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    --port)
    export WO_PORT="$2"
    shift # past argument
    shift # past value
    ;;
    --hostname)
    export WO_HOST="$2"
    shift # past argument
    shift # past value
    ;;
    --media-dir)
    WO_MEDIA_DIR=$(realpath "$2")
    export WO_MEDIA_DIR
    shift # past argument
    shift # past value
    ;;
    --db-dir)
    WO_DB_DIR=$(realpath "$2")
    export WO_DB_DIR
    shift # past argument
    shift # past value
    ;;
    --ssl)
    export WO_SSL=YES
    shift # past argument
    ;;
    --ssl-key)
    WO_SSL_KEY=$(realpath "$2")
    export WO_SSL_KEY
    shift # past argument
    shift # past value
    ;;
    --ssl-cert)
    WO_SSL_CERT=$(realpath "$2")
    export WO_SSL_CERT
    shift # past argument
    shift # past value
    ;;
    --ssl-insecure-port-redirect)
    export WO_SSL_INSECURE_PORT_REDIRECT="$2"
    shift # past argument
    shift # past value
    ;;
    --debug)
    export WO_DEBUG=YES
    shift # past argument
    ;;
    --dev)
    export WO_DEBUG=YES
    export WO_DEV=YES
    dev_mode=true
    shift # past argument
    ;;
    --gpu)
    gpu=true
    shift # past argument
    ;;
    --broker)
    export WO_BROKER="$2"
    shift # past argument
    shift # past value
    ;;
    --no-default-node)
    echo "ATTENTION: --no-default-node is deprecated. Use --default-nodes instead."
    export WO_DEFAULT_NODES=0
    shift # past argument
    ;;
    --with-micmac)
    load_micmac_node=true
    shift # past argument
    ;;
    --detached)
    detached=true
    shift # past argument
    ;;
    --default-nodes)
    export WO_DEFAULT_NODES="$2"
    shift # past argument
    shift # past value
    ;;
    --settings)
    WO_SETTINGS=$(realpath "$2")
    export WO_SETTINGS
    shift # past argument
    shift # past value
    ;;    
    --worker-memory)
    WO_WORKER_MEMORY="$2"
    export WO_WORKER_MEMORY
    shift # past argument
    shift # past value
    ;;  
    --worker-cpus)
    WO_WORKER_CPUS="$2"
    export WO_WORKER_CPUS
    shift # past argument
    shift # past value
    ;;
    --cluster-nodes)
    DEFAULT_CLUSTER_NODES="$2"
    shift # past argument
    shift # past value
    ;;
    --clusterodm)
    clusterodm=true
    shift # past argument
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameter

usage(){
  echo "Usage: $0 <command>"
  echo
  echo "This program helps to manage the setup/teardown of the docker containers for running WebODM. We recommend that you read the full documentation of docker at https://docs.docker.com if you want to customize your setup."
  echo
  echo "Command list:"
  echo "  start [options]        Start WebODM"
  echo "  stop                   Stop WebODM"
  echo "  down                   Stop and remove WebODM's docker containers"
  echo "  update                 Update WebODM to the latest release"
  echo "  liveupdate             Update WebODM to the latest release without stopping it"
  echo "  rebuild                Rebuild all docker containers and perform cleanups"
  echo "  checkenv               Do an environment check and install missing components"
  echo "  test                   Run the unit test suite (developers only)"
  echo "  resetadminpassword \"<new password>\"  Reset the administrator's password to a new one. WebODM must be running when executing this command and the password must be enclosed in double quotes."
  echo ""
  echo "Options:"
  echo "  --port <port>                 Set the port that WebODM should bind to (default: $DEFAULT_PORT)"
  echo "  --hostname <hostname>         Set the hostname that WebODM will be accessible from (default: $DEFAULT_HOST)"
  echo "  --media-dir <path>            Path where processing results will be stored to (default: $DEFAULT_MEDIA_DIR (docker named volume))"
  echo "  --db-dir <path>               Path where the Postgres db data will be stored to (default: $DEFAULT_DB_DIR (docker named volume))"
  echo "  --ssl                         Enable SSL and automatically request and install a certificate from letsencrypt.org. (default: $DEFAULT_SSL)"
  echo "  --ssl-key <path>              Manually specify path to SSL key file. (default: none)"
  echo "  --ssl-cert <path>             Manually specify path to SSL cert file. (default: none)"
  echo "  --ssl-insecure-port-redirect  Redirect all insecure port traffic to secure port. (default: $DEFAULT_SSL_INSECURE_PORT_REDIRECT)"
  echo "  --debug                       Enable debug mode. (default: $DEFAULT_DEBUG)"
  echo "  --dev                         Enable development mode. (default: $DEFAULT_DEV)"
  echo "  --gpu                         Enable GPU support (default: $DEFAULT_GPU)"
  echo "  --broker <url>                Specify a custom Redis broker URL for Celery (default: $DEFAULT_BROKER)"
  echo "  --default-nodes <num>         Set the number of default NodeODM nodes attached to WebODM on startup (default: $DEFAULT_NODES)"
  echo "  --settings <path>             Specify a custom Django settings file"
  echo "  --worker-memory <memory>      Specify the memory limit for the WebODM worker containers"
  echo "  --worker-cpus <cpus>          Specify the number of CPUs available to the WebODM worker containers"
  echo "  --cluster-nodes <num>         Set the number of ClusterODM nodes to start (default: $DEFAULT_CLUSTER_NODES)"
  echo "  --clusterodm                  Enable ClusterODM support"
  echo
  echo "By default, WebODM will be accessible at http://localhost:8000"
  exit 1
}

start(){
  command -v docker >/dev/null 2>&1 || { echo >&2 "docker is required but it's not installed. Aborting."; exit 1; }
  command -v docker-compose >/dev/null 2>&1 || { echo >&2 "docker-compose is required but it's not installed. Aborting."; exit 1; }

  if [[ $gpu = true ]]; then
    echo "Enabling GPU support..."
    export WO_GPU=YES
  fi

  echo "Starting WebODM..."
  docker-compose -f docker-compose.yml up -d --remove-orphans

  if [[ $clusterodm = true ]]; then
    echo "Starting ClusterODM with $DEFAULT_CLUSTER_NODES nodes..."
    docker-compose -f docker-compose.clusterodm.yml up -d --scale clusterodm-worker=$DEFAULT_CLUSTER_NODES --remove-orphans
  fi

  echo "WebODM started."
}

stop(){
  echo "Stopping WebODM..."
  docker-compose -f docker-compose.yml down
  if [[ $clusterodm = true ]]; then
    echo "Stopping ClusterODM..."
    docker-compose -f docker-compose.clusterodm.yml down
  fi
  echo "WebODM stopped."
}

# Other commands...

case "$1" in
  start)
    start
    ;;
  stop)
    stop
    ;;
  # Other cases...
  *)
    usage
    ;;
esac

exit 0
