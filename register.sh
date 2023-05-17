#!/bin/bash

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
DATA_DIR="$SCRIPT_DIR/data"
CONFIG_DIR="$SCRIPT_DIR/config"

save_pubkey() {
    local pk=$($CLEOS -u ${API_URL} get table $CONTRACT $CONTRACT config | jq -crM '.rows[] | select(.name = "public_key") | .value')
    echo -e "-----BEGIN PUBLIC KEY-----\n$pk\n-----END PUBLIC KEY-----"> ${DATA_DIR}/keys/${CHAIN}.pem
}

encrypt() {
    echo "$1" | openssl pkeyutl -inkey ${DATA_DIR}/keys/${CHAIN}.pem -pubin -encrypt -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 2>/dev/null | base64 -w 0
}

load_defaults() {
    echo -e " Loading settings from: \e[32m$1\e[0m"

    DEFAULT_SETTINGS=$(cat $1 2> /dev/null | jq -crM)
}

load_account_settings() {
    echo -e " Loading account settings from: \e[32m$1\e[0m"

    local settings=$(cat $1 2> /dev/null | jq -crM)

    # Override default values with account settings
    DEFAULT_SETTINGS=$(echo "$DEFAULT_SETTINGS $settings" | jq -scrM add)
}

get_default() {
    val=$(echo $DEFAULT_SETTINGS | jq -crM ".${1}")
    if [ -z "$val" ] || [ "$val" == "null" ]; then
        val=$2
    fi

    echo $val
}

save_settings() {
    # Write account settings to disk
    echo -e "[\e[32m*\e[0m] Saving settings to disk: \e[32m$ACC_FILE\e[0m"
    echo "${SETTINGS_JSON}" | jq -M "." > "$ACC_FILE"
}

# Prompt for value
prompt() {

    local default=${3}

    local suffix=""
    if [ -n "$default" ]; then
      suffix=" [${default}]"
    fi

    while true; do
      echo -ne "[\e[32m*\e[0m] ${1}${suffix}: "
      read -r

      if [[ -z $REPLY ]]; then
        if [[ -n "$default" ]]; then
          eval $2=\"$default\"
          break
        fi
      else
        eval $2=$REPLY
        break
      fi

    done
}

# Prompt for boolean value
# <prompt text> <out_var> [ <default_value> ]
prompt_bool() {

    local default=${3:-false}

    local t='y/N'
    if [ "$3" == 'true' ]; then
        t='Y/n'
    fi

    echo -ne "[\e[32m*\e[0m] $1 [$t]: "
    read -r
    if [[ -z $REPLY ]]; then
        val=$default
    elif [[ $REPLY =~ ^[Yy]$ ]]; then
        val="true"
    else :
        val="false"
    fi

    eval $2=\"$val\"
}

# Prompt for integer value.
# <prompt text> <out_var> [ <default_value> ] [ <min> ] [ <max> ]
prompt_int() {

    local default=$3
    local min=$4
    local max=$5

    local t="integer"

    # Min
    if [ -n "$min" ]; then
        t="$t $min"
        # Max
        if [ -n "$max" ]; then
            t="$t-$max"
        fi
    fi

    if [ -n "$default" ]; then
        t="$t, default: $default"
    fi

    while true; do
        echo -ne "[\e[32m*\e[0m] $1 [$t]: "
        read -r

        if [ -n "$default" ] && [ -z $REPLY ]; then
            eval $2=$default
            break
        fi

        if [[ $REPLY =~ ^[0-9]+$ ]]; then

            if [ -n "$min" ] && [ "$REPLY" -lt "$min" ]; then
                echo -e "\e[31mError\e[0m: '$REPLY' must be greater or equal to $min"
                continue
            fi

            if [ -n "$max" ] && [ "$REPLY" -gt "$max" ]; then
                echo -e "\e[31mError\e[0m: '$REPLY' must be less than or equal to $max"
                continue
            fi

            eval $2=$REPLY
            break
        fi

        echo "Error: must be a number"
    done
}

CHAIN_LIST=$(cat ${CONFIG_DIR}/chains.json)

# List chains
echo "Chains:" $(echo $CHAIN_LIST | jq -crM 'keys | @tsv' | tr '\t' ',')

while true; do
    # Prompt for settings
    prompt "Enter chain" CHAIN

    CHAIN_SETTINGS=$(echo $CHAIN_LIST | jq -crM ".${CHAIN}")
    if [ -n "$CHAIN_SETTINGS" ] && [ "$CHAIN_SETTINGS" != "null" ]; then
        # Set values from chain.json
        CLEOS=$(echo $CHAIN_SETTINGS | jq -crM ".cleos")
        API_URL=$(echo $CHAIN_SETTINGS | jq -crM ".api")
        CONTRACT=$(echo $CHAIN_SETTINGS | jq -crM ".contract")
        break
    fi

    echo "Error: Invalid chain '${CHAIN}'"
done

if [ -f "${CONFIG_DIR}/${CHAIN}.json" ]; then
    prompt_bool "Do you want to load default values for $CHAIN" LOAD_DEFAULT "true"
    [[ "${LOAD_DEFAULT}" == "true" ]] && load_defaults "${CONFIG_DIR}/${CHAIN}.json"
fi

save_pubkey

prompt "Enter ${CHAIN} account" ACCOUNT "$(get_default account)"

ACC_FILE="${DATA_DIR}/${CHAIN}.${ACCOUNT}.account.json"
if [ -f "$ACC_FILE" ]; then
    prompt_bool "Do you want to load values for this account from local file" LOAD_ACCOUNT_FILE "true"
    [[ "${LOAD_ACCOUNT_FILE}" == "true" ]] && load_account_settings "$ACC_FILE"
fi

prompt "Enter Producer" PRODUCER

prompt "Enter telegram bot_id" BOT_ID "$(get_default bot_id)"
prompt "Enter telegram chat_id" CHAT_ID "$(get_default chat_id)"

prompt_int "Enter time to receive daily notifications" DAILY_HOUR "$(get_default daily_hour 6)" 0 23

prompt_bool "Notify hourly" NOTIFY_HOURLY "$(get_default notify_hourly true)"
prompt_bool "Notify daily" NOTIFY_DAILY "$(get_default notify_hourly true)"
prompt_bool "Notify weekly" NOTIFY_WEEKLY "$(get_default notify_hourly true)"

prompt_bool "Enable Producer latency report" PRODUCER_LATENCY "$(get_default producer_latency true)"
prompt_bool "Enable CPU Benchmark (eosmechanics)" EOSMECHANICS_CPU "true"
if [ "${EOSMECHANICS_CPU}" == "true" ]; then
    prompt_int "CPU Benchmark (eosmechanics): Limit (in microseconds, us)" EOSMECHANICS_CPU_LIMIT 250
fi

prompt_bool "Enable Block Statistics" PRODUCER_BLOCK_STAT "$(get_default producer_block_statistics true)"
if [ "${PRODUCER_BLOCK_STAT}" == "true" ]; then
    prompt_int  "Block Statistics: Total CPU Usage (percent)" PRODUCER_BLOCK_STAT_LIMIT "$(get_default producer_block_statistics_limit_pct 80)" 0 100
    prompt_bool "Block Statistics: Enable extra statistics" PRODUCER_BLOCK_STAT_EXTRA "$(get_default producer_block_statistics_extras true)"
fi

SETTINGS_JSON=$(cat <<EOF
{
    "bot_id": "${BOT_ID}",
    "chat_id": "${CHAT_ID}",
    "api_url": "",
    "daily_hour": ${DAILY_HOUR:-6},
    "notify_hourly": ${NOTIFY_HOURLY},
    "notify_daily": ${NOTIFY_DAILY},
    "notify_weekly": ${NOTIFY_WEEKLY},
    "producer_latency": ${PRODUCER_LATENCY},
    "producer_block_statistics": ${PRODUCER_BLOCK_STAT},
    "producer_block_statistics_extras": ${PRODUCER_BLOCK_STAT_EXTRA:-false},
    "producer_block_statistics_limit_pct": ${PRODUCER_BLOCK_STAT_LIMIT:-0},
    "eosmechanics_cpu": ${EOSMECHANICS_CPU},
    "eosmechanics_cpu_limit_us": ${EOSMECHANICS_CPU_LIMIT:-0}
}
EOF
)

ENC_SETTINGS=$(echo $SETTINGS_JSON | jq \
    ".bot_id = \"$(encrypt "${BOT_ID}")\" | .chat_id = \"$(encrypt "${CHAT_ID}")\""
)

PAYLOAD=$(cat <<EOF
{
    "account": "${ACCOUNT}",
    "producer": "${PRODUCER}",
    "settings": ${ENC_SETTINGS}
}
EOF
)

echo "Action data:"
echo $PAYLOAD | jq

prompt_bool "Push transaction?" DO_PUSH "true"

# Push transaction
if [ "$DO_PUSH" == "true" ]; then

    # Always save settings on push
    save_settings

    $CLEOS -u ${API_URL} push action $CONTRACT reg $(echo $PAYLOAD | jq -Mcr) -p "${ACCOUNT}@active"
else :

    # Ask user if we should save settings.
    prompt_bool "Save account settings?" SAVE_ACC_SETTINGS
    if [ "$SAVE_ACC_SETTINGS" == "true" ]; then
        save_settings
    fi

    echo "Bailing out"
fi
