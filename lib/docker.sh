#!/usr/bin/env bash

# PROMPT COLOURS
readonly RESET='\033[0;0m'
readonly BLACK='\033[0;30m'
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[0;37m'

readonly DOCKER_MINIMAL_VERSION=18.04.0
readonly DOCKER_COMPOSE_MINIMAL_VERSION=1.24.0

function check_requirements() {
    check_docker
    check_docker_compose
    check_jq
}

function check_version () {
    local version=$1
    local require_version=$2
    local package=$3

    dpkg --compare-versions ${version} 'ge' ${require_version} \
        || (echo -e "${RED}Requirement: need '${package}:${require_version}', you are '${package}:${version}'." && exit 1)
}

function check_docker() {
    if [[ "$(which docker)" == "" ]]; then
        echo -e "${RED}Requirement: need 'docker:${DOCKER_MINIMAL_VERSION}' see https://docs.docker.com/install/linux/docker-ce/ubuntu ."
        exit 1
    fi

    check_version $(docker -v | sed 's/,//'| awk '{print $3}') ${DOCKER_MINIMAL_VERSION} 'docker'
}

function check_docker_compose() {
    if [[ "$(which docker-compose)" == "" ]]; then
        echo -e "${RED}Requirement: need 'docker-compose:${DOCKER_COMPOSE_MINIMAL_VERSION}' see https://docs.docker.com/compose/install ."
        exit 1
    fi

    check_version $(docker-compose -v | sed 's/,//'| awk '{print $3}') ${DOCKER_COMPOSE_MINIMAL_VERSION} 'docker-compose'
}

function check_jq() {
    if [[ "$(which jq)" == "" ]]; then
        echo -e "${RED}Requirement: need 'jq' try 'sudo apt install jq' ."
        exit 1
    fi
}

function ask_value() {
    local message=$1
    local default_value=$2
    local value

    read -p "${message}" value

    if [[ -z ${value} ]]; then
        if [[ -z ${default_value} ]]; then
            value=$(ask_value "${message}" ${default_value})
        else
            value="${default_value}"
        fi
    fi

    echo "${value}"
}

function get_docker_environment() {
    local env=${ENV}

    if [[ -z ${env} ]]; then
        env=$(ask_value 'Choose the docker environment (default: dev): ' dev)
    fi

    echo ${env}
}

function check_docker_environment() {
    local directory=$1
    local env=$2

    if [[ ! -d ${directory}/${env} ]]; then
        echo -e "${RED}The environment '${env}' does not exit."
        exit 1
    fi

    if [[ ! -f ${directory}/${env}/docker-compose.yml ]]; then
        echo -e "${RED}The environment '${env}' does not contain file 'docker-compose.yml'."
        exit 1
    fi
}

function docker_compose_configure_env() {
    local directory=$1
    local env_file="${1}/.env"
    local env_dist_file="${1}/.env.dist"

    if [[ -f ${env_dist_file} ]]; then
        for line in $(cat ${env_dist_file}); do
            configure_env_value ${env_file} $(echo ${line} | cut -d '=' -f 1) $(echo ${line} | cut -d '=' -f 2-)
        done
    fi
}

function configure_env_value() {
    local env_file=$1
    local key=$2
    local default_value=$3
    local value

    if [[ ! -f ${env_file} ]]; then
        touch ${env_file}
    fi

    value=$(get_compute_env_value ${key} ${default_value})

    if [[ -z ${value} ]]; then
        if [[ "$(grep -Ec "^${key}=" ${env_file})" -eq 0 ]]; then
            value=$(ask_value "Define the value of ${key} (default: ${default_value}): " ${default_value})
        else
            value=$(awk -F "${key} *= *" '{print $2}' ${env_file})
        fi
    fi

    sed -e "/^${key}=/d" -i ${env_file}
    echo "${key}=${value}" >> ${env_file}
}

function get_compute_env_value() {
    local key=$1
    local default_value=$2
    local value

    case ${key} in
        COMPOSE_PROJECT_NAME)
            value=${default_value}
        ;;
        HTTP_PATH)
            value=${default_value}
        ;;
        HTTP_HOST)
            value=${default_value}
            add_host ${value}
        ;;
        DOCKER_UID)
            value=$(id -u)
        ;;
        XDEBUG_REMOTE_HOST)
            value=$(docker network inspect bridge | jq -r '.[].IPAM.Config | first | .Gateway')
        ;;
    esac

    echo ${value}
}

function add_host() {
    local host=$1

    if [[ "$(grep -c ${host} /etc/hosts )" -eq 0 ]]; then
        sudo /bin/sh -c "echo \"127.0.0.1 ${host}\" >> /etc/hosts"
    fi
}

function docker_compose_build() {
    local directory=$1
    local options=$2
    local current_directory=$(pwd)

    cd ${directory}
    docker-compose build --parallel ${options}
    cd ${current_directory}
}

function docker_compose_up() {
    local directory=$1
    local options=${2}
    local current_directory=$(pwd)

    cd ${directory}
    docker-compose up --detach --remove-orphans ${options}
    cd ${current_directory}
}

check_requirements
